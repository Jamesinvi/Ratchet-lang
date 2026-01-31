module parser::analyzer;
import common;
import debug;
import std::collections::list;
import common::stack;
import log;
import globals;

faultdef ANALYSIS_ERR;


struct SemanticAnalyzer
{
	ProgramAst* ast;
	Expr* currentExpr;
	SymbolTable symbolTable;
	CompTypeInfo currentReturnType;
	List{TypeResult} errors;
	Stack{Scope} scopes;
	bool returnFound;
	usz currentScopeIdx;
	DeclIdx currentStructDeclIdx;
	DynamicArenaAllocator allocator;

}

fn void SemanticAnalyzer.init(SemanticAnalyzer* this, ProgramAst* ast)
{
	this.ast = ast;
	this.symbolTable = {};
	this.allocator = {};
	this.allocator.init(mem, 64 * 1024);

	this.errors.init(&this.allocator);
	usz exprLen = this.ast.expressions.len();
	usz stmtLen = this.ast.statements.len();
	usz declLen = this.ast.declarations.len();
	this.symbolTable.symbols.init(&this.allocator, exprLen + stmtLen + declLen);
	this.symbolTable.exprSymbols.init(&this.allocator, exprLen);
	this.symbolTable.stmtSymbols.init(&this.allocator, stmtLen);
	this.symbolTable.declSymbols.init(&this.allocator, declLen);

	// Fill lists with NO_SYMBOL
	for (usz i = 0; i < exprLen; i++) {
		this.symbolTable.exprSymbols.push(NO_SYMBOL);
	}

	for (usz i = 0; i < stmtLen; i++) {
		this.symbolTable.stmtSymbols.push(NO_SYMBOL);
	}
	
	for (usz i = 0; i < declLen; i++) {
		this.symbolTable.declSymbols.push(NO_SYMBOL);
	}
	this.currentReturnType = make_type(ValueType.NULL);
	this.returnFound = false;
	this.currentScopeIdx = 0;
	this.currentStructDeclIdx = parser::NO_IDX;
}

fn void SemanticAnalyzer.deinit(SemanticAnalyzer* this)
{
	for(usz i = 0; i < this.scopes.size; i++){
		this.scopes.items[i].deinit();
	}
	this.scopes.free();
	this.allocator.free();
}

// ---- Entry point ----
fn TypeResult SemanticAnalyzer.run(SemanticAnalyzer* this)
{
	TypeResult globalReturnType = type_ok(make_type(ValueType.NULL));
	this.begin_scope(globalReturnType, false);

	// Predeclare function symbols with return types.
	for (usz i = 0; i < this.ast.declarations.len(); i++){
		Decl* decl = &this.ast.declarations[i];
		if (decl.kind == DeclKind.FUNCTION) {
			Span declSpan = this.ast.statements[decl.fnDecl.body].span;
			TypeResult returnType = this.create_type_from_ast(&decl.fnDecl.returnType, declSpan);
			if (returnType.hadError) {
				return returnType;
			}
			SymbolIdx symbolIdx = this.symbolTable.symbols.len();
			Symbol symbol = { .kind = SymbolKind.FUNCTION, .idx = i, .type = returnType.value };
			this.symbolTable.symbols.push(symbol);
			this.symbolTable.declSymbols[i] = symbolIdx;
			this.current_scope().visibleSymbols.push(symbolIdx);
		}
	}


	for (usz i = 0; i < this.ast.declarations.len(); i++){
		Decl* decl = &this.ast.declarations[i];
		switch (decl.kind)
		{
			case DeclKind.FUNCTION:
			{
				TypeResult declType = this.analyze_fn(&decl.fnDecl);
				if (declType.hadError) {
					return declType;
				}
			}
			case DeclKind.STRUCT:
			{
				foreach (method : decl.structDecl.methods){
					TypeResult declType = this.analyze_method(&method);
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
		SymbolIdx symbolIdx = this.symbolTable.symbols.len();
		Symbol symbol = { .kind = SymbolKind.PARAM, .idx = (SymbolIdx)param.nameIdx, .type = paramType.value };
		this.symbolTable.symbols.push(symbol);
		this.current_scope().visibleSymbols.push(symbolIdx);
	}
	return type_ok(make_type(ValueType.NULL));
}

fn void SemanticAnalyzer.begin_scope(SemanticAnalyzer* this, TypeResult returnType, bool insideMethod)
{
	usz enclosingIdx = 0;
	if (this.scopes.size > 0) {
		enclosingIdx = this.currentScopeIdx;
	}
	Scope scope = {.depth = this.scopes.size, .enclosingIdx = enclosingIdx };
	scope.init(returnType, insideMethod);
	this.scopes.push(scope);
	this.currentScopeIdx = (usz)this.scopes.size - 1;
}

fn void SemanticAnalyzer.end_scope(SemanticAnalyzer* this)
{
	Scope popped = this.scopes.pop();
	popped.visibleSymbols.free();
	debug::@log_analysis("exiting scope");
	if (this.scopes.size > 0) {
		this.currentScopeIdx = (usz)this.scopes.size - 1;
	}
}

fn bool SemanticAnalyzer.try_resolve_method_call(SemanticAnalyzer* this, DeclIdx structDeclIdx, String methodName, ExprCall* call, Span span, TypeResult* out)
{
	if (structDeclIdx == parser::NO_IDX) {
		return false;
	}

	Decl* structDecl = &this.ast.declarations[structDeclIdx];
	if (structDecl.kind != DeclKind.STRUCT) {
		return false;
	}
	
	usz methodIdx = this.find_method_idx(&structDecl.structDecl, methodName);
	if (methodIdx == parser::NO_IDX) {
		return false;
	}

	for(usz i = call.argsStart; i < call.argsEnd; i++) {
		ExprIdx argExprIdx = this.ast.args[i];
		TypeResult argType = this.analyze_expr(argExprIdx);
		if (argType.hadError) {
			*out = argType;
			return true;
		}
	}

	MethodDeclAst* methodDecl = &structDecl.structDecl.methods[methodIdx];
	*out = this.create_type_from_ast(&methodDecl.returnType, span);
	return true;
}

fn TypeResult SemanticAnalyzer.analyze_fn(SemanticAnalyzer* this, FnDeclAst* fnDecl)
{
	Span fnSpan = this.ast.statements[fnDecl.body].span;
	TypeResult expectedRetType = this.create_type_from_ast(&fnDecl.returnType, fnSpan);
	if (expectedRetType.hadError) {
		return expectedRetType;
	}
	debug::@log_analysis("fn '%s', expects '%s' return type", this.ast.names[fnDecl.nameIdx], expectedRetType.value.type);
	List{StmtIdx}* stmtsIndices = &this.ast.statements[fnDecl.body].blockStmt.stmts;

	this.begin_scope(expectedRetType, false);
	DeclIdx prevStructDeclIdx = this.currentStructDeclIdx;
	this.currentStructDeclIdx = parser::NO_IDX;
	TypeResult paramsType = this.declare_params(&fnDecl.params);
	if (paramsType.hadError) {
		return paramsType;
	}
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
	return type_ok(expectedRetType.value);
}

fn TypeResult SemanticAnalyzer.analyze_method(SemanticAnalyzer* this, MethodDeclAst* methodDecl)
{
	
	Span methodSpan = this.ast.statements[methodDecl.body].span;
	TypeResult expectedRetType = this.create_type_from_ast(&methodDecl.returnType, methodSpan);
	if (expectedRetType.hadError) {
		return expectedRetType;
	}
	debug::@log_analysis("method '%s', expects '%s' return type", this.ast.names[methodDecl.nameIdx], expectedRetType.value.type);
	List{StmtIdx}* stmtsIndices = &this.ast.statements[methodDecl.body].blockStmt.stmts;

	this.begin_scope(expectedRetType, true);
	DeclIdx prevStructDeclIdx = this.currentStructDeclIdx;
	this.currentStructDeclIdx = methodDecl.structIdx;
	TypeResult paramsType = this.declare_params(&methodDecl.params);

	if (paramsType.hadError) {
		return paramsType;
	}
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
	return type_ok(expectedRetType.value);
}

fn DeclIdx SemanticAnalyzer.find_struct_decl_idx(SemanticAnalyzer* this, uint structTypeIndex)
{
	// Search for a struct that has the same structTypeIndex 
	foreach(idx, &decl : this.ast.declarations){
		if (decl.kind != DeclKind.STRUCT) {
			continue;
		}
		String structName = this.ast.names[decl.structDecl.nameIdx];
		if (!globals::structNamesToIdx.has_key(structName)) {
			continue;
		}
		usz? indexInStructNames = globals::structNamesToIdx.get(structName);
		if (catch err = indexInStructNames) {
			continue;
		}
		if ((uint)indexInStructNames == structTypeIndex) {
			return idx;
		}
	}
	return parser::NO_IDX;
}

fn usz SemanticAnalyzer.find_method_idx(SemanticAnalyzer* this, StructDeclAst* structDecl, String name)
{
	for (usz i = 0; i < structDecl.methods.len(); i++){
		MethodDeclAst* method = &structDecl.methods[i];
		String methodName = this.ast.names[method.nameIdx];
		if (common::string_equals(methodName, name)) {
			return i;
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
			SymbolIdx symbolIdx = this.symbolTable.symbols.len();
			Symbol symbol = { .kind = SymbolKind.LOCAL, .idx = stmtIdx, .type = lhsType.value };
			this.symbolTable.symbols.push(symbol);
			this.symbolTable.stmtSymbols[stmtIdx] = symbolIdx;
			this.current_scope().visibleSymbols.push(symbolIdx);
			debug::@log_analysis("statement %s: %s is of type %s", stmt.kind, this.ast.names[stmt.varDecl.nameIdx], lhsType.value.type);
			if (stmt.varDecl.init != parser::NO_IDX) {
				Expr* initExpr = &this.ast.expressions[stmt.varDecl.init];
				TypeResult rhsType = this.analyze_expr(stmt.varDecl.init);
				if (rhsType.hadError) {
					return rhsType;
				}
				if (parser::type_info_matches(lhsType.value, rhsType.value)){
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
			CompTypeInfo boolType = make_type(ValueType.BOOL);
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
			CompTypeInfo boolType = make_type(ValueType.BOOL);
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
			if (!parser::type_info_matches(this.currentReturnType, valueType.value)){
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

	switch(expr.kind)
	{
		case ExprKind.VAR:			return this.analyze_expr_var(exprIdx, expr);
		case ExprKind.INT:			return type_ok(make_type(ValueType.INT));
		case ExprKind.FLOAT:		return type_ok(make_type(ValueType.FLOAT));
		case ExprKind.DOUBLE:		return type_ok(make_type(ValueType.DOUBLE));
		case ExprKind.BOOL:			return type_ok(make_type(ValueType.BOOL));
		case ExprKind.NULL:			return type_ok(make_type(ValueType.NULL));
		case ExprKind.STRING:		return type_ok(make_ref_type(ValueType.NULL, parser::NOT_STRUCT));
		case ExprKind.UNARY:		return this.analyze_expr_unary(expr);
		case ExprKind.BINARY:		return this.analyze_expr_binary(expr);
		case ExprKind.NEW:			return this.create_type_from_ast(&expr.new.type, expr.span);
		case ExprKind.THIS:			return this.analyze_expr_this(expr);
		case ExprKind.CALL:			return this.analyze_expr_call(expr);
		case ExprKind.MEMBER:		return this.analyze_expr_member(expr);
		default:					return type_ok(make_type(ValueType.NULL));
	}

}

fn bool SemanticAnalyzer.is_struct_ref_like(SemanticAnalyzer* this, CompTypeInfo info)
{
	return (info.type == ValueType.REF ||
			info.type == ValueType.PTR ||
			info.type == ValueType.BORROW_REF) &&
			info.refToType == ValueType.STRUCT;
}

fn bool SemanticAnalyzer.try_resolve_visible_symbol(SemanticAnalyzer* this, String name, SymbolIdx* outSymbolIdx)
{
	usz scopeIdx = this.currentScopeIdx;
	
	// Start from the current scope's visible symbols and traverse upwards, looking for a match
	while (scopeIdx!=0){
		Stack{SymbolIdx}* visibleSymbols = &this.scopes.items[scopeIdx].visibleSymbols;
		for (isz i = (isz)visibleSymbols.size - 1; i >= 0; i--){
			SymbolIdx symbolIdx = visibleSymbols.items[i];
			Symbol* symbol = &this.symbolTable.symbols[symbolIdx];
			if (symbol.kind == SymbolKind.LOCAL) {
				Stmt* declStmt = &this.ast.statements[(StmtIdx)symbol.idx];
				if (declStmt.kind != StmtKind.DECL) {
					continue;
				}
				String declName = this.ast.names[declStmt.varDecl.nameIdx];
				if (common::string_equals(declName, name)){
					*outSymbolIdx = symbolIdx;
					return true;
				}
			} else if (symbol.kind == SymbolKind.PARAM){
				String declName = this.ast.names[(usz)symbol.idx];
				if (common::string_equals(declName, name)){
					*outSymbolIdx = symbolIdx;
					return true;
				}
			}
		}
		scopeIdx = this.scopes.items[scopeIdx].enclosingIdx;
	}
	Stack{SymbolIdx}* globalScopeSymbols = &this.scopes.items[0].visibleSymbols;
	for (isz i = (isz)globalScopeSymbols.size - 1; i >= 0; i--){
		SymbolIdx symbolIdx = globalScopeSymbols.items[i];
		Symbol* symbol = &this.symbolTable.symbols[symbolIdx];
		if (symbol.kind == SymbolKind.FUNCTION) {
			Decl* decl = &this.ast.declarations[(DeclIdx)symbol.idx];
			String declName = this.ast.names[decl.fnDecl.nameIdx];
			if (common::string_equals(declName, name)){
				*outSymbolIdx = symbolIdx;
				return true;
			}
		}
	}

	return false;
}

fn TypeResult SemanticAnalyzer.analyze_expr_var(SemanticAnalyzer* this, ExprIdx exprIdx, Expr* expr)
{
	String name = this.ast.names[expr.varExpr];
	SymbolIdx symbolIdx = NO_SYMBOL;
	if (this.try_resolve_visible_symbol(name, &symbolIdx)){
		this.symbolTable.exprSymbols[exprIdx] = symbolIdx;
		return type_ok(this.symbolTable.symbols[symbolIdx].type);
	}
	return this.type_error(ErrorKind.UNDECLARED_NAME, nullType, nullType, expr.span);
}

fn TypeResult SemanticAnalyzer.analyze_expr_unary(SemanticAnalyzer* this, Expr* expr)
{
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

fn TypeResult SemanticAnalyzer.analyze_expr_binary(SemanticAnalyzer* this, Expr* expr)
{
	TypeResult lhsType = this.analyze_expr(expr.binary.lhs);
	if (lhsType.hadError) {
		return lhsType;
	}
	if (expr.binary.op == BinOp.AS) {
		return type_ok(lhsType.value);
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
			if (!is_numeric_type(lhsType.value) || !parser::type_info_matches(lhsType.value, rhsType.value)) {
				return this.type_error(ErrorKind.TYPE_MISMATCH, rhsType.value, lhsType.value, expr.span);
			}
			return type_ok(lhsType.value);
		}
		case BinOp.EQ:			nextcase;
		case BinOp.NEQ:
			if (!parser::type_info_matches(lhsType.value, rhsType.value)) {
				return this.type_error(ErrorKind.TYPE_MISMATCH, rhsType.value, lhsType.value, expr.span);
			}
			return type_ok(make_type(ValueType.BOOL));
		case BinOp.LESS:		nextcase;
		case BinOp.LESS_EQ:		nextcase;
		case BinOp.GREATER:		nextcase;
		case BinOp.GREATER_EQ:
			if (!is_numeric_type(lhsType.value) || !parser::type_info_matches(lhsType.value, rhsType.value)) {
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
		case BinOp.ASSIGN:
			if (!parser::type_info_matches(lhsType.value, rhsType.value)) {
				return this.type_error(ErrorKind.TYPE_MISMATCH, rhsType.value, lhsType.value, expr.span);
			}
			return type_ok(lhsType.value);
		default:
			return type_ok(lhsType.value);
	}
}

fn TypeResult SemanticAnalyzer.analyze_expr_this(SemanticAnalyzer* this, Expr* expr)
{
	if (!this.is_in_method()){
		return this.type_error(ErrorKind.UNDECLARED_NAME, nullType, nullType, expr.span);
	}
	if (this.currentStructDeclIdx == parser::NO_IDX) {
		return this.type_error(ErrorKind.INVALID_TYPE, nullType, nullType, expr.span);
	}
	NameIdx structNameIdx = this.ast.declarations[this.currentStructDeclIdx].structDecl.nameIdx;
	TypeAst thisTypeAst = {.tokenType = TokenType.THIS, .nameIdx = structNameIdx};
	return this.create_type_from_ast(&thisTypeAst, expr.span);
}

fn TypeResult SemanticAnalyzer.analyze_expr_call(SemanticAnalyzer* this, Expr* expr)
{
	// Method calls: resolve against struct methods before treating as free function calls.
	Expr* calleeExpr = &this.ast.expressions[expr.call.callee];
	if (calleeExpr.kind == ExprKind.MEMBER) {
		TypeResult baseType = this.analyze_expr(calleeExpr.member.base);
		if (baseType.hadError) {
			return baseType;
		}
		CompTypeInfo baseInfo = baseType.value;
		bool isStruct = baseInfo.type == ValueType.STRUCT;
		if (isStruct || this.is_struct_ref_like(baseInfo)) {
			DeclIdx structDeclIdx = this.find_struct_decl_idx(baseInfo.structTypeIndex);
			String methodName = this.ast.names[calleeExpr.member.memberIdx];
			TypeResult resolved = {};
			if (this.try_resolve_method_call(structDeclIdx, methodName, &expr.call, expr.span, &resolved)) {
				return resolved;
			}
		}
	}
	if (calleeExpr.kind == ExprKind.VAR && this.currentStructDeclIdx != parser::NO_IDX) {
		String methodName = this.ast.names[calleeExpr.varExpr];
		TypeResult resolved = {};
		if (this.try_resolve_method_call(this.currentStructDeclIdx, methodName, &expr.call, expr.span, &resolved)) {
			return resolved;
		}
	}

	TypeResult calleeType = this.analyze_expr(expr.call.callee);
	if (calleeType.hadError) {
		return calleeType;
	}

	for(usz i = expr.call.argsStart; i < expr.call.argsEnd; i++) {
		ExprIdx argExprIdx = this.ast.args[i];
		TypeResult argType = this.analyze_expr(argExprIdx);
		if (argType.hadError) {
			return argType;
		}
	}

	SymbolIdx symbolIdx = this.symbolTable.exprSymbols[expr.call.callee];
	if (symbolIdx != NO_SYMBOL && this.symbolTable.symbols[symbolIdx].kind == SymbolKind.FUNCTION) {
		return type_ok(this.symbolTable.symbols[symbolIdx].type);
	}
	return type_ok(calleeType.value);
}

fn TypeResult SemanticAnalyzer.analyze_expr_member(SemanticAnalyzer* this, Expr* expr)
{
	TypeResult baseType = this.analyze_expr(expr.member.base);
	if (baseType.hadError) {
		return baseType;
	}
	CompTypeInfo baseInfo = baseType.value;
	bool isStruct = baseInfo.type == ValueType.STRUCT;
	if (!isStruct && !this.is_struct_ref_like(baseInfo)) {
		return this.type_error(ErrorKind.INVALID_TYPE, baseInfo, baseInfo, expr.span);
	}
	if (baseInfo.structTypeIndex == parser::NOT_STRUCT) {
		return this.type_error(ErrorKind.INVALID_TYPE, baseInfo, baseInfo, expr.span);
	}

	DeclIdx structDeclIdx = this.find_struct_decl_idx(baseInfo.structTypeIndex);
	if (structDeclIdx == parser::NO_IDX) {
		return this.type_error(ErrorKind.INVALID_TYPE, baseInfo, baseInfo, expr.span);
	}

	Decl* structDecl = &this.ast.declarations[structDeclIdx];
	String fieldName = this.ast.names[expr.member.memberIdx];
	foreach (&field : structDecl.structDecl.fields){
		String declName = this.ast.names[field.nameIdx];
		if (common::string_equals(declName, fieldName)){
			return this.create_type_from_ast(&field.type, expr.span);
		}
	}
	return this.type_error(ErrorKind.UNDECLARED_NAME, nullType, nullType, expr.span);
}


fn Scope* SemanticAnalyzer.current_scope(SemanticAnalyzer* this)
{
	return &this.scopes.items[this.currentScopeIdx];
}
