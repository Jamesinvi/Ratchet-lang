module compiler::analyzer;
import common;
import compiler;
import debug;
import std::collections::list;
import common::stack;
import log;
import globals;

faultdef ANALYSIS_ERR;

fn List{TypeResult} analyze(ProgramAst* ast, SymbolTable* symbolTable, Allocator outputAllocator)
{
	SemanticAnalyzer analyzer = {};
	analyzer.init(ast, symbolTable, outputAllocator);
	analyzer.run();
	defer analyzer.deinit();
	return analyzer.errors;
}

struct SemanticAnalyzer
{
	ProgramAst* ast;					// input
	SymbolTable* symbolTable;			// output (inout)
	List{TypeResult} errors;			// ouput
	Stack{Scope} scopes;				// temp
	DynamicArenaAllocator localAllocator;
	Allocator outputAllocator;
	Expr* currentExpr;		
	TypeInfo currentReturnType;		
	DeclIdx currentStructDeclIdx;
	SymbolIdx currentReceiverSymbolIdx;
	int currentScopeIdx;
	bool returnFound;
}


fn void SemanticAnalyzer.init(SemanticAnalyzer* this, ProgramAst* ast, SymbolTable* symbolTable, Allocator outputAllocator)
{
	this.ast = ast;
	this.symbolTable = symbolTable;
	this.outputAllocator = outputAllocator;
	this.scopes = {};
	this.errors.init(outputAllocator);
	this.localAllocator = {};
	this.localAllocator.init(mem, 64 * 1024);

	sz exprLen = this.ast.expressions.len();
	sz stmtLen = this.ast.statements.len();
	sz declLen = this.ast.declarations.len();
	this.symbolTable.symbols.init(outputAllocator, exprLen + stmtLen + declLen);
	this.symbolTable.exprSymbols.init(outputAllocator, exprLen);
	this.symbolTable.exprTypes.init(outputAllocator, exprLen);
	this.symbolTable.stmtSymbols.init(outputAllocator, stmtLen);
	this.symbolTable.declSymbols.init(outputAllocator, declLen);
	this.symbolTable.declParamRanges.init(outputAllocator, declLen);
	this.symbolTable.declParamSymbols.init(outputAllocator, exprLen + stmtLen + declLen);
	this.symbolTable.callTargets.init(outputAllocator, exprLen);
	this.symbolTable.callReceiverExpr.init(outputAllocator, exprLen);
	this.symbolTable.memberFieldIndices.init(outputAllocator, exprLen);
	this.symbolTable.methods.init(outputAllocator);

	// Fill lists with defaults
	common::list_append_fill{SymbolIdx}(&this.symbolTable.stmtSymbols, NO_SYMBOL, stmtLen);
	common::list_append_fill{SymbolIdx}(&this.symbolTable.declSymbols, NO_SYMBOL, declLen);
	common::list_append_fill{DeclParamRange}(&this.symbolTable.declParamRanges, {}, declLen);
	common::list_append_fill{MemberIdx}(&this.symbolTable.memberFieldIndices, -1, exprLen);
	for (sz i = 0; i < exprLen; i++) {
		this.symbolTable.exprSymbols.push(NO_SYMBOL);
		this.symbolTable.exprTypes.push(nullType);
		this.symbolTable.callTargets.push({});
		this.symbolTable.callReceiverExpr.push(parser::NO_IDX);
	}


	this.currentReturnType = make_type(ValueType.NULL);
	this.returnFound = false;
	this.currentScopeIdx = 0;
	this.currentStructDeclIdx = parser::NO_IDX;
	this.currentReceiverSymbolIdx = NO_SYMBOL;
}

fn void SemanticAnalyzer.deinit(SemanticAnalyzer* this)
{
	for(sz i = 0; i < this.scopes.size; i++){
		this.scopes.items[i].deinit();
	}
	this.scopes.free();
	this.localAllocator.free();
}

// ---- Entry point ----
fn TypeResult SemanticAnalyzer.run(SemanticAnalyzer* this)
{
	TypeResult globalReturnType = type_ok(make_type(ValueType.NULL));
	this.begin_scope(globalReturnType, false);

	// Create a temporary list in which we will store all decl indices for structs
    assert(this.ast.declarations.len() < int::max);
	List{DeclIdx} structDeclIndices = {};
	structDeclIndices.init(&this.localAllocator, this.ast.declarations.len() / 2);
	// Predeclare function symbols with return types.
	for (int i = 0; i < (int)this.ast.declarations.len(); i++){
		Decl* decl = &this.ast.declarations[i];
		if (decl.kind == DeclKind.FUNCTION) {
			Span declSpan = this.ast.statements[decl.fnDecl.body].span;
			TypeResult returnType = this.create_type_from_ast(&decl.fnDecl.returnType, declSpan);
			if (returnType.hadError) {
				return returnType;
			}
			SymbolIdx symbolIdx = this.symbols_len();
			Symbol symbol = { .kind = SymbolKind.FUNCTION, .idx = i, .type = returnType.value };
			this.symbolTable.symbols.push(symbol);
			this.symbolTable.declSymbols[i] = symbolIdx;
			this.current_scope().visibleSymbols.push(symbolIdx);
		} else if (decl.kind == DeclKind.STRUCT) {
			get_struct_idx_bind_if_needed(this.ast.names[decl.structDecl.nameIdx].text(), this.outputAllocator);
			structDeclIndices.push(i);
		}
	}
	
	TypeResult metaDataResult = this.fill_structs_metadata(structDeclIndices);
	if(metaDataResult.hadError){
		return metaDataResult;
	}

	for (int i = 0; i < (int)this.ast.declarations.len(); i++){
		Decl* decl = &this.ast.declarations[i];
		switch (decl.kind)
		{
			case DeclKind.FUNCTION:
			{
				TypeResult declType = this.analyze_fn(&decl.fnDecl, i);
				if (declType.hadError) {
					return declType;
				}
			}
			case DeclKind.STRUCT:
			{
				foreach (methodIdx, &method : decl.structDecl.methods){
					assert(methodIdx < int::max);
					TypeResult declType = this.analyze_method(method, (int)methodIdx);
					if (declType.hadError) {
						return declType;
					}
				}
			}
			default: return this.type_error(ErrorKind.INVALID_TYPE, nullType, nullType, {});
		}
	}
	return type_ok(make_type(ValueType.NULL));
}

fn TypeResult SemanticAnalyzer.declare_params(SemanticAnalyzer* this, List{ParamAst}* params)
{
	foreach (&param : *params){
		TypeResult paramType = this.create_type_from_ast(&param.type, param.span);
		if (paramType.hadError) {
			return paramType;
		}
		SymbolIdx symbolIdx = this.symbols_len();
		Symbol symbol = {
			.kind = SymbolKind.PARAM,
			.idx = (SymbolIdx)param.nameIdx,
			.type = paramType.value,
			.passMode = param.passMode,
		};
		this.symbolTable.symbols.push(symbol);
		this.symbolTable.declParamSymbols.push(symbolIdx);
		this.current_scope().visibleSymbols.push(symbolIdx);
	}
	return type_ok(make_type(ValueType.NULL));
}

fn void SemanticAnalyzer.begin_scope(SemanticAnalyzer* this, TypeResult returnType, bool insideMethod)
{
	int enclosingIdx = 0;
	if (this.scopes.size > 0) {
		enclosingIdx = this.currentScopeIdx;
	}
	assert(this.scopes.size < int::max);
	Scope scope = {.depth = (int)this.scopes.size, .enclosingIdx = enclosingIdx };
	scope.init(returnType, insideMethod);
	this.scopes.push(scope);
	this.currentScopeIdx = (int)this.scopes.size - 1;
}

fn void SemanticAnalyzer.end_scope(SemanticAnalyzer* this)
{
	Scope popped = this.scopes.pop();
	popped.visibleSymbols.free();
	debug::@log_analysis("exiting scope");
	assert(this.scopes.size < int::max);
	if (this.scopes.size > 0) {
		this.currentScopeIdx = (int)this.scopes.size - 1;
	}
}

fn bool SemanticAnalyzer.try_resolve_method_call(SemanticAnalyzer* this,
 DeclIdx structDeclIdx, 
 InternedString methodName,
 ExprCall* call,
 ExprIdx callExprIdx,
 Span span,
 TypeResult* out)
{
	if (structDeclIdx == parser::NO_IDX) {
		return false;
	}

	Decl* structDecl = &this.ast.declarations[structDeclIdx];
	if (structDecl.kind != DeclKind.STRUCT) {
		return false;
	}
	
	int methodIdx = this.find_method_idx(&structDecl.structDecl, methodName);
	if (methodIdx == parser::NO_IDX) {
		return false;
	}

	MethodDeclAst* method = &structDecl.structDecl.methods[methodIdx];
	int argCount = call.argsEnd - call.argsStart;
	if (argCount != (int)method.params.len()) {
		*out = this.type_error(ErrorKind.INVALID_ARITY, nullType, nullType, span);
		return true;
	}

	for(int i = 0; i < argCount; i++) {
		ExprIdx argListIdx = call.argsStart + i;
		ExprIdx argExprIdx = this.ast.args[argListIdx];
		TypeResult argType = this.analyze_expr(argExprIdx);
		if (argType.hadError) {
			*out = argType;
			return true;
		}
		TypeResult expectedType = this.create_type_from_ast(&method.params[i].type, span);
		if (expectedType.hadError) {
			*out = expectedType;
			return true;
		}
		if (!common::type_info_matches(argType.value, expectedType.value)) {
			*out = this.type_error(ErrorKind.TYPE_MISMATCH, argType.value, expectedType.value, span);
			return true;
		}
	}

	this.symbolTable.callTargets[callExprIdx].kind = CallTargetKind.METHOD;
	this.symbolTable.callTargets[callExprIdx].methodId = {
		.structDeclIdx = structDeclIdx,
		.methodIdx = methodIdx,
	};

	*out = this.create_type_from_ast(&method.returnType, span);
	return true;
}

fn TypeResult SemanticAnalyzer.analyze_fn(SemanticAnalyzer* this, FnDeclAst* fnDecl, DeclIdx ownerDeclIdx)
{
	Span fnSpan = this.ast.statements[fnDecl.body].span;
	TypeResult expectedRetType = this.create_type_from_ast(&fnDecl.returnType, fnSpan);
	if (expectedRetType.hadError) {
		return expectedRetType;
	}
	debug::@log_analysis("fn '%s', expects '%s' return type", this.ast.names[fnDecl.nameIdx].text(), expectedRetType.value.type);
	List{StmtIdx}* stmtsIndices = &this.ast.statements[fnDecl.body].blockStmt.stmts;

	this.begin_scope(expectedRetType, false);
	DeclIdx prevStructDeclIdx = this.currentStructDeclIdx;
	SymbolIdx prevReceiverSymbolIdx = this.currentReceiverSymbolIdx;
	this.currentStructDeclIdx = parser::NO_IDX;
	this.currentReceiverSymbolIdx = NO_SYMBOL;
	int paramsStart = (int)this.symbolTable.declParamSymbols.len();
	TypeResult paramsType = this.declare_params(&fnDecl.params);
	if (paramsType.hadError) {
		return paramsType;
	}
	this.symbolTable.declParamRanges[ownerDeclIdx] = {
		.start = paramsStart,
		.end = (int)this.symbolTable.declParamSymbols.len(),
	};
	// Scan and analyze all statments in the function
	this.currentReturnType = expectedRetType.value;
	this.returnFound = false;
	foreach (stmtIdx : stmtsIndices){
		TypeResult resultType = this.analyze_stmt(stmtIdx);
		if (resultType.hadError) {
			return resultType;
		}
	}

	if (expectedRetType.value.type != ValueType.NULL && !this.returnFound) {
		return this.type_error(ErrorKind.NO_RETURN, nullType, expectedRetType.value, fnSpan);
	}
	this.end_scope();
	this.currentStructDeclIdx = prevStructDeclIdx;
	this.currentReceiverSymbolIdx = prevReceiverSymbolIdx;
	return type_ok(expectedRetType.value);
}

fn TypeResult SemanticAnalyzer.analyze_method(SemanticAnalyzer* this, MethodDeclAst* methodDecl, int methodIdx)
{
	
	Span methodSpan = this.ast.statements[methodDecl.body].span;
	TypeResult expectedRetType = this.create_type_from_ast(&methodDecl.returnType, methodSpan);
	if (expectedRetType.hadError) {
		return expectedRetType;
	}
	debug::@log_analysis("method '%s', expects '%s' return type", this.ast.names[methodDecl.nameIdx].text(), expectedRetType.value.type);
	List{StmtIdx}* stmtsIndices = &this.ast.statements[methodDecl.body].blockStmt.stmts;

	this.begin_scope(expectedRetType, true);
	DeclIdx prevStructDeclIdx = this.currentStructDeclIdx;
	SymbolIdx prevReceiverSymbolIdx = this.currentReceiverSymbolIdx;
	this.currentStructDeclIdx = methodDecl.structIdx;

	Decl* structDecl = &this.ast.declarations[methodDecl.structIdx];
	TypeAst receiverTypeAst = {
		.tokenType = TokenType.IDENTIFIER,
		.nameIdx = structDecl.structDecl.nameIdx,
	};
	TypeResult receiverType = this.create_type_from_ast(&receiverTypeAst, methodSpan);
	if (receiverType.hadError) {
		return receiverType;
	}

	int paramsStart = (int)this.symbolTable.declParamSymbols.len();
	SymbolIdx receiverSymbolIdx = this.symbols_len();
	Symbol receiverSymbol = {
		.kind = SymbolKind.RECEIVER,
		.idx = NO_SYMBOL,
		.type = receiverType.value,
		.passMode = ParamPassMode.INOUT,
	};
	this.symbolTable.symbols.push(receiverSymbol);
	this.symbolTable.declParamSymbols.push(receiverSymbolIdx);
	this.currentReceiverSymbolIdx = receiverSymbolIdx;

	TypeResult paramsType = this.declare_params(&methodDecl.params);

	if (paramsType.hadError) {
		return paramsType;
	}
	MethodAnalysisInfo methodInfo = {
		.id = {
			.structDeclIdx = methodDecl.structIdx,
			.methodIdx = methodIdx,
		},
		.paramRange = {
			.start = paramsStart,
			.end = (int)this.symbolTable.declParamSymbols.len(),
		},
		.receiverSymbolIdx = receiverSymbolIdx,
		.returnType = expectedRetType.value,
	};
	this.symbolTable.methods.push(methodInfo);
	this.currentReturnType = expectedRetType.value;
	this.returnFound = false;

	foreach (stmtIdx : stmtsIndices){
		TypeResult resultType = this.analyze_stmt(stmtIdx);
		if (resultType.hadError) {
			return resultType;
		}
	}

	if (expectedRetType.value.type != ValueType.NULL && !this.returnFound) {
		return this.type_error(ErrorKind.NO_RETURN, nullType, expectedRetType.value, methodSpan);
	}
	this.end_scope();
	this.currentStructDeclIdx = prevStructDeclIdx;
	this.currentReceiverSymbolIdx = prevReceiverSymbolIdx;
	return type_ok(expectedRetType.value);
}

fn DeclIdx SemanticAnalyzer.find_struct_decl_idx(SemanticAnalyzer* this, int structTypeIndex)
{
	// Search for a struct that has the same structTypeIndex 
	assert(this.ast.declarations.len() < int::max);
	foreach(idx, &decl : this.ast.declarations){
	    int index = (int)idx;
		if (decl.kind != DeclKind.STRUCT) {
			continue;
		}
		String structName = this.ast.names[decl.structDecl.nameIdx].text();
		if (!globals::structNamesToIdx.has_key(structName)) {
			continue;
		}
		int? indexInStructNames = globals::structNamesToIdx.get(structName);
		if (catch err = indexInStructNames) {
			continue;
		}
		if (indexInStructNames == structTypeIndex) {
			return index;
		}
	}
	return parser::NO_IDX;
}

fn int SemanticAnalyzer.find_method_idx(SemanticAnalyzer* this, StructDeclAst* structDecl, InternedString name)
{
	for (sz i = 0; i < structDecl.methods.len(); i++){
		MethodDeclAst* method = &structDecl.methods[i];
		InternedString methodName = this.ast.names[method.nameIdx];
		if (methodName.id == name.id) {
			assert(i < int::max);
			return (int)i;
		}
	}
	return parser::NO_IDX;
}

fn TypeResult SemanticAnalyzer.analyze_stmt(SemanticAnalyzer* this, StmtIdx stmtIdx)
{
	Stmt* stmt = &this.ast.statements[stmtIdx];
	switch (stmt.kind)
	{
		case StmtKind.EXPR:					return this.analyze_expr(stmt.exprStmt);
		case StmtKind.ECHO:					return this.analyze_expr(stmt.echoStmt);
		case StmtKind.DECL:
		{
			TypeResult lhsType = this.create_type_from_ast(&stmt.varDecl.type, stmt.span);
			if (lhsType.hadError) {
				return lhsType;
			}
			SymbolIdx symbolIdx = this.symbols_len();
			Symbol symbol = { .kind = SymbolKind.LOCAL, .idx = stmtIdx, .type = lhsType.value };
			this.symbolTable.symbols.push(symbol);
			this.symbolTable.stmtSymbols[stmtIdx] = symbolIdx;
			this.current_scope().visibleSymbols.push(symbolIdx);
			debug::@log_analysis("statement %s: %s is of type %s", stmt.kind, this.ast.names[stmt.varDecl.nameIdx].text(), lhsType.value.type);
			if (stmt.varDecl.init != parser::NO_IDX) {
				Expr* initExpr = &this.ast.expressions[stmt.varDecl.init];
				TypeResult rhsType = this.analyze_expr(stmt.varDecl.init);
				if (rhsType.hadError) {
					return rhsType;
				}
				if (common::type_info_matches(lhsType.value, rhsType.value)){
					return type_ok(lhsType.value);
				}
				return this.type_error(ErrorKind.TYPE_MISMATCH, rhsType.value, lhsType.value, initExpr.span);
			}
			return type_ok(lhsType.value);
		}
		case StmtKind.BLOCK:
		{
			// Same as function, scan and analyze all statements
			bool insideMethod = this.is_in_method();
			TypeResult scopeReturnType = type_ok(this.currentReturnType);
			this.begin_scope(scopeReturnType, insideMethod);
			foreach (childIdx : stmt.blockStmt.stmts){
				TypeResult result = this.analyze_stmt(childIdx);
				if (result.hadError) {
					return result;
				}
			}
			this.end_scope();
			return type_ok(make_type(ValueType.NULL));
		}
		case StmtKind.IF:
		{
			TypeInfo boolType = make_type(ValueType.BOOL);
			Expr* condExpr = &this.ast.expressions[stmt.ifStmt.cond];
			TypeResult condType = this.analyze_expr(stmt.ifStmt.cond);
			if (condType.hadError) {
				return condType;
			}
			if (condType.value.type != ValueType.BOOL) {
				return this.type_error(ErrorKind.TYPE_MISMATCH, condType.value, boolType, condExpr.span);
			}
			TypeResult thenType = this.analyze_stmt(stmt.ifStmt.thenBlock);
			if (thenType.hadError) {
				return thenType;
			}
			if (stmt.ifStmt.elseBlock != parser::NO_IDX) {
				TypeResult elseType = this.analyze_stmt(stmt.ifStmt.elseBlock);
				if (elseType.hadError) {
					return elseType;
				}
			}
			return type_ok(make_type(ValueType.NULL));
		}
		case StmtKind.WHILE:
		{
			TypeInfo boolType = make_type(ValueType.BOOL);
			Expr* condExpr = &this.ast.expressions[stmt.whileStmt.cond];
			TypeResult condType = this.analyze_expr(stmt.whileStmt.cond);
			if (condType.hadError) {
				return condType;
			}
			if (condType.value.type != ValueType.BOOL) {
				return this.type_error(ErrorKind.TYPE_MISMATCH, condType.value, boolType, condExpr.span);
			}
			return this.analyze_stmt(stmt.whileStmt.body);
		}
		case StmtKind.RETURN:
		{
			this.returnFound = true;
			if (stmt.retStmt.value == parser::NO_IDX) {
				if (this.currentReturnType.type != ValueType.NULL) {
					return this.type_error(ErrorKind.TYPE_MISMATCH, nullType, this.currentReturnType, stmt.span);
				}
				return type_ok(nullType);
			}
			TypeResult valueType = this.analyze_expr(stmt.retStmt.value);
			if (valueType.hadError) {
				return valueType;
			}
			if (!common::type_info_matches(this.currentReturnType, valueType.value)){
				return this.type_error(ErrorKind.TYPE_MISMATCH, valueType.value, this.currentReturnType, stmt.span);
			}
			return type_ok(valueType.value);
		}
		default:
			return type_ok(make_type(ValueType.NULL));
	}
}

fn TypeResult SemanticAnalyzer.analyze_expr(SemanticAnalyzer* this, ExprIdx exprIdx)
{
	if (exprIdx == parser::NO_IDX) {
		return type_ok(make_type(ValueType.NULL));
	}
	Expr* expr = &this.ast.expressions[exprIdx];
	TypeResult result = {};
	switch(expr.kind)
	{
		case ExprKind.VAR:				result = this.analyze_expr_var(exprIdx);
		case ExprKind.INT:				result = type_ok(make_type(ValueType.INT));
		case ExprKind.FLOAT:			result = type_ok(make_type(ValueType.FLOAT));
		case ExprKind.DOUBLE:			result = type_ok(make_type(ValueType.DOUBLE));
		case ExprKind.BOOL:				result = type_ok(make_type(ValueType.BOOL));
		case ExprKind.NULL:				result = type_ok(make_type(ValueType.NULL));
		case ExprKind.STRING_LITERAL:	result = type_ok(make_type(ValueType.STRING_LITERAL));
		case ExprKind.UNARY:			result = this.analyze_expr_unary(exprIdx);
		case ExprKind.BINARY:			result = this.analyze_expr_binary(exprIdx);
		case ExprKind.NEW:				result = this.create_type_from_ast(&expr.new.type, expr.span);
		case ExprKind.THIS:				result = this.analyze_expr_this(exprIdx);
		case ExprKind.CALL:				result = this.analyze_expr_call(exprIdx);
		case ExprKind.MEMBER:			result = this.analyze_expr_member(exprIdx);
		case ExprKind.CAST:				result = this.analyze_expr_cast(exprIdx);
		default:						result = type_ok(make_type(ValueType.NULL));
	}
	if (!result.hadError) {
		this.symbolTable.exprTypes[exprIdx] = result.value;
	}
	return result;
}

fn bool SemanticAnalyzer.is_struct_ref_like(SemanticAnalyzer* this, TypeInfo info)
{
	return (info.type == ValueType.REF ||
			info.type == ValueType.PTR) &&
			info.refToType == ValueType.STRUCT;
}

fn bool SemanticAnalyzer.try_resolve_visible_symbol(SemanticAnalyzer* this, InternedString name, SymbolIdx* outSymbolIdx)
{
	sz scopeIdx = this.currentScopeIdx;
	
	// Start from the current scope's visible symbols and traverse upwards, looking for a match
	while (scopeIdx!=0){
		Stack{SymbolIdx}* visibleSymbols = &this.scopes.items[scopeIdx].visibleSymbols;
		for (sz i = (sz)visibleSymbols.size - 1; i >= 0; i--){
			SymbolIdx symbolIdx = visibleSymbols.items[i];
			Symbol* symbol = &this.symbolTable.symbols[symbolIdx];
			if (symbol.kind == SymbolKind.LOCAL) {
				Stmt* declStmt = &this.ast.statements[(StmtIdx)symbol.idx];
				if (declStmt.kind != StmtKind.DECL) {
					continue;
				}
				InternedString declName = this.ast.names[declStmt.varDecl.nameIdx];
				if (declName.id == name.id){
					*outSymbolIdx = symbolIdx;
					return true;
				}
			} else if (symbol.kind == SymbolKind.PARAM){
				InternedString declName = this.ast.names[symbol.idx];
				if (declName.id == name.id){
					*outSymbolIdx = symbolIdx;
					return true;
				}
			}
		}
		scopeIdx = this.scopes.items[scopeIdx].enclosingIdx;
	}
	Stack{SymbolIdx}* globalScopeSymbols = &this.scopes.items[0].visibleSymbols;
	for (sz i = (sz)globalScopeSymbols.size - 1; i >= 0; i--){
		SymbolIdx symbolIdx = globalScopeSymbols.items[i];
		Symbol* symbol = &this.symbolTable.symbols[symbolIdx];
		if (symbol.kind == SymbolKind.FUNCTION) {
			Decl* decl = &this.ast.declarations[(DeclIdx)symbol.idx];
			InternedString declName = this.ast.names[decl.fnDecl.nameIdx];
			if (declName.id == name.id){
				*outSymbolIdx = symbolIdx;
				return true;
			}
		}
	}

	return false;
}

fn TypeResult SemanticAnalyzer.analyze_expr_var(SemanticAnalyzer* this, ExprIdx exprIdx)
{
	Expr* expr = &this.ast.expressions[exprIdx];
	InternedString name = this.ast.names[expr.varExpr];
	SymbolIdx symbolIdx = NO_SYMBOL;
	if (this.try_resolve_visible_symbol(name, &symbolIdx)){
		this.symbolTable.exprSymbols[exprIdx] = symbolIdx;
		return type_ok(this.symbolTable.symbols[symbolIdx].type);
	}
	return this.type_error(ErrorKind.UNDECLARED_NAME, nullType, nullType, expr.span);
}

fn TypeResult SemanticAnalyzer.analyze_expr_unary(SemanticAnalyzer* this, ExprIdx exprIdx)
{
	Expr* expr = &this.ast.expressions[exprIdx];
	TypeResult rhsType = this.analyze_expr(expr.unary.rhs);
	if (rhsType.hadError) {
		return rhsType;
	}
	switch (expr.unary.op){
		case UnOp.NEG:
			if (!is_numeric_type(rhsType.value)) {
				return this.type_error(ErrorKind.TYPE_MISMATCH, rhsType.value, rhsType.value, expr.span);
			}
			return type_ok(rhsType.value);
		case UnOp.NOT:
			if (rhsType.value.type != ValueType.BOOL) {
				return this.type_error(ErrorKind.TYPE_MISMATCH, rhsType.value, make_type(ValueType.BOOL), expr.span);
			}
			return type_ok(make_type(ValueType.BOOL));
		default:
			return type_ok(rhsType.value);
	}
}

fn TypeResult SemanticAnalyzer.analyze_expr_cast( SemanticAnalyzer* this,ExprIdx exprIdx)
 {
    Expr* expr = &this.ast.expressions[exprIdx];

    TypeResult source = this.analyze_expr(expr.cast.value);
    if (source.hadError) {
		return source;
	}

    TypeResult target = this.create_type_from_ast(&expr.cast.targetType, expr.span);
    if (target.hadError){
		return target;
	} 

    if (!is_numeric_type(source.value) || !is_numeric_type(target.value)) {
        return this.type_error( ErrorKind.TYPE_MISMATCH, source.value, target.value, expr.span);
    }

    return type_ok(target.value);
}

fn TypeResult SemanticAnalyzer.analyze_expr_binary(SemanticAnalyzer* this, ExprIdx exprIdx)
{
	Expr* expr = &this.ast.expressions[exprIdx];
	TypeResult lhsType = this.analyze_expr(expr.binary.lhs);
	if (lhsType.hadError) {
		return lhsType;
	}
	TypeResult rhsType = this.analyze_expr(expr.binary.rhs);
	if (rhsType.hadError) {
		return rhsType;
	}

	switch (expr.binary.op)
	{
		case BinOp.ADD:			nextcase;
		case BinOp.SUB:			nextcase;
		case BinOp.MUL:			nextcase;
		case BinOp.DIV:
		{
			if (!is_numeric_type(lhsType.value) || !common::type_info_matches(lhsType.value, rhsType.value)) {
				return this.type_error(ErrorKind.TYPE_MISMATCH, rhsType.value, lhsType.value, expr.span);
			}
			return type_ok(lhsType.value);
		}
		case BinOp.EQ:			nextcase;
		case BinOp.NEQ:
			if (!common::type_info_matches(lhsType.value, rhsType.value)) {
				return this.type_error(ErrorKind.TYPE_MISMATCH, rhsType.value, lhsType.value, expr.span);
			}
			return type_ok(make_type(ValueType.BOOL));
		case BinOp.LESS:		nextcase;
		case BinOp.LESS_EQ:		nextcase;
		case BinOp.GREATER:		nextcase;
		case BinOp.GREATER_EQ:
			if (!is_numeric_type(lhsType.value) || !common::type_info_matches(lhsType.value, rhsType.value)) {
				return this.type_error(ErrorKind.TYPE_MISMATCH, rhsType.value, lhsType.value, expr.span);
			}
			return type_ok(make_type(ValueType.BOOL));
		case BinOp.AND:			nextcase;
		case BinOp.OR:
			if (lhsType.value.type != ValueType.BOOL) {
				return this.type_error(ErrorKind.TYPE_MISMATCH, lhsType.value, make_type(ValueType.BOOL), expr.span);
			}
			if (rhsType.value.type != ValueType.BOOL) {
				return this.type_error(ErrorKind.TYPE_MISMATCH, rhsType.value, make_type(ValueType.BOOL), expr.span);
			}
			return type_ok(make_type(ValueType.BOOL));
		case BinOp.STORE:
			if (this.ast.expressions[expr.binary.lhs].kind == ExprKind.THIS) {
				return this.type_error(ErrorKind.INVALID_LVALUE, lhsType.value, lhsType.value, expr.span);
			}
			if (!common::type_info_matches(lhsType.value, rhsType.value)) {
				return this.type_error(ErrorKind.TYPE_MISMATCH, rhsType.value, lhsType.value, expr.span);
			}
			return type_ok(lhsType.value);
		default:
			return type_ok(lhsType.value);
	}
}

fn TypeResult SemanticAnalyzer.analyze_expr_this(SemanticAnalyzer* this, ExprIdx exprIdx)
{
	Expr* expr = &this.ast.expressions[exprIdx];
	if (!this.is_in_method()){
		return this.type_error(ErrorKind.UNDECLARED_NAME, nullType, nullType, expr.span);
	}
	if (this.currentStructDeclIdx == parser::NO_IDX || this.currentReceiverSymbolIdx == NO_SYMBOL) {
		return this.type_error(ErrorKind.INVALID_TYPE, nullType, nullType, expr.span);
	}
	this.symbolTable.exprSymbols[exprIdx] = this.currentReceiverSymbolIdx;
	return type_ok(this.symbolTable.symbols[this.currentReceiverSymbolIdx].type);
}

fn bool SemanticAnalyzer.is_place_expr(SemanticAnalyzer* this, ExprIdx exprIdx)
{
	Expr* expr = &this.ast.expressions[exprIdx];
	switch (expr.kind) {
		case ExprKind.VAR: return true;
		case ExprKind.THIS: return true;
		case ExprKind.MEMBER: return this.is_place_expr(expr.member.base);
		default: return false;
	}
}

fn TypeResult SemanticAnalyzer.analyze_expr_call(SemanticAnalyzer* this, ExprIdx exprIdx)
{
	Expr* expr = &this.ast.expressions[exprIdx];
	this.symbolTable.callReceiverExpr[exprIdx] = parser::NO_IDX;
	// Method calls: resolve against struct methods before treating as free function calls.
	Expr* calleeExpr = &this.ast.expressions[expr.call.callee];
	if (calleeExpr.kind == ExprKind.MEMBER) {
		TypeResult baseType = this.analyze_expr(calleeExpr.member.base);
		if (baseType.hadError) {
			return baseType;
		}
		TypeInfo baseInfo = baseType.value;
		bool isStruct = baseInfo.type == ValueType.STRUCT;
		if (isStruct) {
			DeclIdx structDeclIdx = this.find_struct_decl_idx(baseInfo.structTypeIndex);
			InternedString methodName = this.ast.names[calleeExpr.member.memberIdx];
			TypeResult resolved = {};
			if (this.try_resolve_method_call(structDeclIdx, methodName, &expr.call, exprIdx, expr.span, &resolved)) {
				if (!resolved.hadError && !this.is_place_expr(calleeExpr.member.base)) {
					return this.type_error(ErrorKind.INVALID_LVALUE, baseInfo, baseInfo, expr.span);
				}
				this.symbolTable.callReceiverExpr[exprIdx] = calleeExpr.member.base;
				return resolved;
			}
		}
	}
	if (calleeExpr.kind == ExprKind.VAR && this.currentStructDeclIdx != parser::NO_IDX) {
		InternedString methodName = this.ast.names[calleeExpr.varExpr];
		TypeResult resolved = {};
		if (this.try_resolve_method_call(this.currentStructDeclIdx, methodName, &expr.call, exprIdx, expr.span, &resolved)) {
			this.symbolTable.callReceiverExpr[exprIdx] = parser::NO_IDX;
			return resolved;
		}
	}

	TypeResult calleeType = this.analyze_expr(expr.call.callee);
	if (calleeType.hadError) {
		return calleeType;
	}

	for(sz i = expr.call.argsStart; i < expr.call.argsEnd; i++) {
		ExprIdx argExprIdx = this.ast.args[i];
		TypeResult argType = this.analyze_expr(argExprIdx);
		if (argType.hadError) {
			return argType;
		}
	}

	SymbolIdx symbolIdx = this.symbolTable.exprSymbols[expr.call.callee];
	if (symbolIdx != NO_SYMBOL && this.symbolTable.symbols[symbolIdx].kind == SymbolKind.FUNCTION) {
		// Add extra info to the symbol table, useful in later passes
		this.symbolTable.callTargets[exprIdx].kind = CallTargetKind.FREE_FUN;
		this.symbolTable.callTargets[exprIdx].fnDeclIdx = this.symbolTable.symbols[symbolIdx].idx;
		this.symbolTable.callReceiverExpr[exprIdx] = parser::NO_IDX;

		return type_ok(this.symbolTable.symbols[symbolIdx].type);
	}
	return type_ok(calleeType.value);
}

fn TypeResult SemanticAnalyzer.analyze_expr_member(SemanticAnalyzer* this, ExprIdx exprIdx)
{
	Expr* expr = &this.ast.expressions[exprIdx];
	TypeResult baseType = this.analyze_expr(expr.member.base);
	if (baseType.hadError) {
		return baseType;
	}
	TypeInfo baseInfo = baseType.value;
	bool isStruct = baseInfo.type == ValueType.STRUCT;
	if (!isStruct && !this.is_struct_ref_like(baseInfo)) {
		return this.type_error(ErrorKind.INVALID_TYPE, baseInfo, baseInfo, expr.span);
	}
	if (baseInfo.structTypeIndex == common::NOT_STRUCT) {
		return this.type_error(ErrorKind.INVALID_TYPE, baseInfo, baseInfo, expr.span);
	}

	DeclIdx structDeclIdx = this.find_struct_decl_idx(baseInfo.structTypeIndex);
	if (structDeclIdx == parser::NO_IDX) {
		return this.type_error(ErrorKind.INVALID_TYPE, baseInfo, baseInfo, expr.span);
	}

	Decl* structDecl = &this.ast.declarations[structDeclIdx];
	InternedString fieldName = this.ast.names[expr.member.memberIdx];
	MemberIdx fieldIdx = 0;
	foreach (&field : structDecl.structDecl.fields){
		InternedString declName = this.ast.names[field.nameIdx];
		if (declName.id == fieldName.id){
			this.symbolTable.memberFieldIndices[exprIdx] = fieldIdx;
			return this.create_type_from_ast(&field.type, expr.span);
		}
		fieldIdx++;
	}
	return this.type_error(ErrorKind.UNDECLARED_NAME, nullType, nullType, expr.span);
}


fn Scope* SemanticAnalyzer.current_scope(SemanticAnalyzer* this)
{
	return &this.scopes.items[this.currentScopeIdx];
}
