module compiler::analyzer;
import common;
import compiler;
import debug;
import std::collections::list;
import std::collections::map;
import common::stack;
import log;
import globals;

faultdef ANALYSIS_ERR;

fn List{TypeResult} analyze(ProgramAst* ast, SymbolTable* symbolTable, Allocator outputAllocator)
{
	SemanticAnalyzer analyzer = { };
	analyzer.init(ast, symbolTable, outputAllocator);
	analyzer.run();
	defer analyzer.deinit();
	return analyzer.errors;
}

struct SemanticAnalyzer
{
	ProgramAst* ast; // input
	SymbolTable* symbolTable; // output (inout)
	List{TypeResult} errors; // ouput
	Stack{Scope} scopes; // temp
	DynamicArenaAllocator localAllocator;
	Allocator outputAllocator;
	Expr* currentExpr;
	TypeInfo currentReturnType;
	DeclIdx currentStructDeclIdx;
	SymbolIdx currentReceiverSymbolIdx;
	int currentScopeIdx;
	int currentLoopDepth; // how many nested loops are we in?
	bool returnFound;
}


fn void SemanticAnalyzer.init(SemanticAnalyzer* this, ProgramAst* ast, SymbolTable* symbolTable, Allocator outputAllocator)
{
	this.ast = ast;
	this.symbolTable = symbolTable;
	this.outputAllocator = outputAllocator;
	this.scopes = { };
	this.errors.init(outputAllocator);
	this.localAllocator = { };
	this.localAllocator.init(mem, 64 * 1024);

	sz exprLen = this.ast.expressions.len();
	sz stmtLen = this.ast.statements.len();
	sz declLen = this.ast.declarations.len();
	this.symbolTable.symbols.init(outputAllocator, exprLen + stmtLen + declLen);
	this.symbolTable.exprSymbols.init(outputAllocator, exprLen);
	this.symbolTable.exprTypes.init(outputAllocator, exprLen);
	this.symbolTable.stmtSymbols.init(outputAllocator, stmtLen);
	this.symbolTable.declSymbols.init(outputAllocator, declLen);
	this.symbolTable.functions.init(outputAllocator);
	// Hashmaps
	this.symbolTable.memberFieldIndices.init(outputAllocator, 64);
	this.symbolTable.callTargets.init(outputAllocator, 64);

	// Fill lists with defaults
	common::list_append_fill{SymbolIdx}(&this.symbolTable.stmtSymbols, NO_SYMBOL, stmtLen);
	common::list_append_fill{SymbolIdx}(&this.symbolTable.declSymbols, NO_SYMBOL, declLen);
	common::list_append_fill{SymbolIdx}(&this.symbolTable.exprSymbols, NO_SYMBOL, exprLen);
	common::list_append_fill{TypeInfo}(&this.symbolTable.exprTypes, nullType, exprLen);


	this.currentReturnType = make_type(ValueType.NULL);
	this.returnFound = false;
	this.currentScopeIdx = 0;
	this.currentStructDeclIdx = parser::NO_IDX;
	this.currentReceiverSymbolIdx = NO_SYMBOL;
}

fn void SemanticAnalyzer.deinit(SemanticAnalyzer* this)
{
	for (sz i = 0; i < this.scopes.size; i++)
	{
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
	List{DeclIdx} structDeclIndices = { };
	structDeclIndices.init(&this.localAllocator, this.ast.declarations.len() / 2);
	// Register struct names before resolving callable signatures.
	foreach (declIdx : this.ast.globalBlock.globalDeclarations)
	{
		Decl* decl = &this.ast.declarations[declIdx];
		if (decl.kind != DeclKind.STRUCT) continue;
		get_struct_idx_bind_if_needed(this.ast.names[decl.nameIdx].text(), this.outputAllocator);
		structDeclIndices.push(declIdx);
	}
	TypeResult metaDataResult = this.fill_structs_metadata(structDeclIndices);
	if (metaDataResult.hadError) return metaDataResult;

	// Complete every signature before analyzing any body, including forward calls.
	foreach (declIdx : this.ast.globalBlock.globalDeclarations)
	{
		Decl* decl = &this.ast.declarations[declIdx];
		if (decl.kind == DeclKind.FUNCTION)
		{
			Span span             = this.ast.statements[decl.fnDecl.body].span;
			TypeResult returnType = this.create_type_from_ast(&decl.fnDecl.returnType, span);
			if (returnType.hadError) return returnType;
			FunctionAnalysisInfo info = {
				.kind = CallTargetKind.FREE_FUN,
				.fnDeclIdx = declIdx,
				.returnType = returnType.value,
				.receiverSymbolIdx = NO_SYMBOL,
			};
			SymbolIdx symbolIdx = this.declare_function(this.ast.names[decl.nameIdx], info, true);
			this.symbolTable.declSymbols[declIdx] = symbolIdx;
			TypeResult paramsType = this.declare_params(symbolIdx, &decl.fnDecl.params, NO_SYMBOL);
			if (paramsType.hadError) return paramsType;
		}
		else if (decl.kind == DeclKind.STRUCT)
		{
			foreach (methodIdx, &method : decl.structDecl.methods)
			{
				TypeResult result = this.declare_method(declIdx, (int)methodIdx, method);
				if (result.hadError) return result;
			}
		}
	}
	// Declare all native functions
	foreach (idx, &nativeFn : common::nativeFunctions)
	{
		if (nativeFn.targetKind == CallTargetKind.NATIVE_METHOD) continue;
		InternedString name = globals::internedSourceStrings.get_or_intern(nativeFn.name);
		SymbolIdx alreadyDeclaredFn;
		// If the user has declared a function with this name, error!
		if (this.try_resolve_visible_symbol(name, &alreadyDeclaredFn))
		{
			FuncIdx funcIdx = this.symbolTable.symbols[alreadyDeclaredFn].funcIdx;
			Decl* funcDecl  = &this.ast.declarations[this.symbolTable.functions[funcIdx].fnDeclIdx];
			return this.type_error(ErrorKind.FUNC_NAME_CLASHES_NATIVE, nullType, nullType, funcDecl.span);
		}

		FunctionAnalysisInfo info = {
			.kind = CallTargetKind.NATIVE_FUN,
			.nativeFnIdx = (NativeFnIdx)idx,
			.returnType = nativeFn.returnType,
			.receiverSymbolIdx = NO_SYMBOL,
		};
		SymbolIdx symbolIdx = this.declare_function(name, info, true);
		sz nextFreeIdx      = 0;
		SymbolIdx[] params  = mem::alloc::alloc_array(this.outputAllocator, SymbolIdx, nativeFn.params.len);
		foreach (param : nativeFn.params)
		{
			// Each native-function parameter gets a generated symbol (not from source)
			params[nextFreeIdx++] = this.symbols_len();
			Symbol syntheticSymbol = {
				.kind = SymbolKind.PARAM,
				.type = param.type,
				.passMode = param.passMode,
			};
			this.symbolTable.symbols.push(syntheticSymbol);
		}
		FuncIdx funcIdx = this.symbolTable.symbols[symbolIdx].funcIdx;
		this.symbolTable.functions[funcIdx].params = params;
	}

	// Global symbols
	TypeResult globalsResult = this.fill_globals();
	if (globalsResult.hadError)
	{
		return globalsResult;
	}

	for (int i = 0; i < (int)this.ast.declarations.len(); i++)
	{
		Decl* decl = &this.ast.declarations[i];
		switch (decl.kind)
		{
			case DeclKind.FUNCTION:
				TypeResult declType = this.analyze_fn(decl, i);
				if (declType.hadError)
				{
					return declType;
				}
			case DeclKind.STRUCT:
				foreach (methodIdx, &method : decl.structDecl.methods)
				{
					assert(methodIdx < int::max);
					TypeResult declType = this.analyze_method(method, (int)methodIdx);
					if (declType.hadError)
					{
						return declType;
					}
				}
			default: return this.type_error(ErrorKind.INVALID_TYPE, nullType, nullType, { });
		}
	}
	return type_ok(make_type(ValueType.NULL));
}

fn SymbolIdx SemanticAnalyzer.declare_function(SemanticAnalyzer* this, InternedString name, FunctionAnalysisInfo info, bool visible)
{
	SymbolIdx symbolIdx = this.symbols_len();
	Symbol symbol = {
		.kind = SymbolKind.FUNCTION,
		.name = name,
		.type = info.returnType,
		.funcIdx = (FuncIdx)this.symbolTable.functions.len(),
	};
	info.symbolIdx = symbolIdx;
	this.symbolTable.symbols.push(symbol);
	this.symbolTable.functions.push(info);
	if (visible) this.current_scope().visibleSymbols.push(symbolIdx);
	return symbolIdx;
}

fn TypeResult SemanticAnalyzer.declare_params(SemanticAnalyzer* this, SymbolIdx functionSymbolIdx, List{ParamAst}* params, SymbolIdx receiverSymbolIdx)
{
	// If it's a method (has a reciever), add 1 to the params since the receiver is the first in the param list
	sz allocationSize        = receiverSymbolIdx != NO_SYMBOL ? params.len() + 1 : params.len();
	SymbolIdx[] paramSymbols = mem::alloc::alloc_array(this.outputAllocator, SymbolIdx, allocationSize);
	sz nextFreeIdx           = 0;
	if (receiverSymbolIdx != NO_SYMBOL) paramSymbols[nextFreeIdx++] = receiverSymbolIdx;
	foreach (&param : *params)
	{
		TypeResult paramType = this.create_type_from_ast(&param.type, param.span);
		if (paramType.hadError) return paramType;
		paramSymbols[nextFreeIdx++] = this.symbols_len();
		Symbol paramSymbol = {
			.kind = SymbolKind.PARAM,
			.name = this.ast.names[param.nameIdx],
			.type = paramType.value,
			.passMode = param.passMode,
		};
		this.symbolTable.symbols.push(paramSymbol);
	}
	FuncIdx funcIdx = this.symbolTable.symbols[functionSymbolIdx].funcIdx;
	this.symbolTable.functions[funcIdx].params = paramSymbols;
	return type_ok(nullType);
}

fn TypeResult SemanticAnalyzer.declare_method(SemanticAnalyzer* this, DeclIdx structDeclIdx, int methodIdx, MethodDeclAst* method)
{
	Span span             = this.ast.statements[method.body].span;
	TypeResult returnType = this.create_type_from_ast(&method.returnType, span);
	if (returnType.hadError) return returnType;
	TypeAst receiverTypeAst = {
		.tokenType = TokenType.IDENTIFIER,
		.arraySize = common::NO_LENGTH,
		.nameIdx = this.ast.declarations[structDeclIdx].nameIdx,
	};
	TypeResult receiverType = this.create_type_from_ast(&receiverTypeAst, span);
	if (receiverType.hadError) return receiverType;
	SymbolIdx receiverSymbolIdx = this.symbols_len();
	this.symbolTable.symbols.push(
		{
			.kind = SymbolKind.RECEIVER,
			.type = receiverType.value,
			.passMode = ParamPassMode.INOUT,
		}
	);
	FunctionAnalysisInfo info = {
		.kind = CallTargetKind.METHOD,
		.methodId = { .structDeclIdx = structDeclIdx, .methodIdx = methodIdx },
		.returnType = returnType.value,
		.receiverSymbolIdx = receiverSymbolIdx,
	};
	SymbolIdx symbolIdx = this.declare_function(this.ast.names[method.nameIdx], info, false);
	return this.declare_params(symbolIdx, &method.params, receiverSymbolIdx);
}

fn void SemanticAnalyzer.bind_params(SemanticAnalyzer* this, SymbolIdx functionSymbolIdx)
{
	FuncIdx funcIdx    = this.symbolTable.symbols[functionSymbolIdx].funcIdx;
	SymbolIdx[] params = this.symbolTable.functions[funcIdx].params;
	foreach (symbolIdx : params)
	{
		// The receiver is resolved through `this`, not through a parameter name.
		if (this.symbolTable.symbols[symbolIdx].kind == SymbolKind.RECEIVER) continue;
		this.current_scope().visibleSymbols.push(symbolIdx);
	}
}

fn void SemanticAnalyzer.begin_scope(SemanticAnalyzer* this, TypeResult returnType, bool insideMethod)
{
	int enclosingIdx = 0;
	if (this.scopes.size > 0)
	{
		enclosingIdx = this.currentScopeIdx;
	}
	assert(this.scopes.size < int::max);
	Scope scope = { .depth = (int)this.scopes.size, .enclosingIdx = enclosingIdx };
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
	if (this.scopes.size > 0)
	{
		this.currentScopeIdx = (int)this.scopes.size - 1;
	}
}

fn bool SemanticAnalyzer.try_resolve_method_call(SemanticAnalyzer* this, DeclIdx structDeclIdx, InternedString methodName, ExprIdx callExprIdx, ExprIdx receiverExprIdx, TypeResult* out)
{
	if (structDeclIdx == parser::NO_IDX) return false;
	Decl* structDecl = &this.ast.declarations[structDeclIdx];
	if (structDecl.kind != DeclKind.STRUCT) return false;
	int methodIdx = this.find_method_idx(&structDecl.structDecl, methodName);
	if (methodIdx == parser::NO_IDX) return false;
	FunctionAnalysisInfo* method = this.symbolTable.find_method({ .structDeclIdx = structDeclIdx, .methodIdx = methodIdx });
	assert(method != null);
	*out = this.analyze_call_arguments(callExprIdx, method.symbolIdx, receiverExprIdx);
	return true;
}

fn bool SemanticAnalyzer.try_resolve_native_method_call(SemanticAnalyzer* this, TypeInfo baseType, InternedString methodName, ExprIdx callExprIdx, ExprIdx receiverExprIdx, TypeResult* out)
{
	assert(baseType.is_heap_array());
	foreach (methodIdx, &native : common::nativeFunctions)
	{
		if (native.targetKind != CallTargetKind.NATIVE_METHOD) continue;
		assert(native.params.len > 0);
		if (native.name != methodName.text() || baseType.type != native.params[0].type.type) continue;

		assert(methodIdx < int::max);
		NativeFnIdx nativeFnIdx = (NativeFnIdx)methodIdx;

		// Look for the analysed method
		FunctionAnalysisInfo* method = this.symbolTable.find_native_method(nativeFnIdx, baseType);
		SymbolIdx symbolIdx;
		// If present, use that, otherwise, generate a new one
		if (method != null)
		{
			symbolIdx = method.symbolIdx;
		}
		else
		{
			// Resolve the template once per complete receiver type.
			SymbolIdx receiverSymbolIdx = this.symbols_len();
			Symbol receiverSymbol       = { .kind = SymbolKind.RECEIVER, .type = baseType, .passMode = native.params[0].passMode };
			this.symbolTable.symbols.push(receiverSymbol);
			// Params array (including the receiver)
			SymbolIdx[] params = mem::alloc::alloc_array(this.outputAllocator, SymbolIdx, native.params.len);
			params[0] = receiverSymbolIdx;
			foreach (paramIdx, param : native.params)
			{
				if (paramIdx == 0) continue; // first is receiver, skip
				TypeInfo paramType = param.type;
				switch (param.flags)
				{
					case FunctionParameterFlags.NONE: break;
					case FunctionParameterFlags.PARAMETER_TYPE_MATCHES_RECEIVER: paramType = baseType;
					case FunctionParameterFlags.PARAMETER_TYPE_MATCHES_RECEIVER_ELEMENT: paramType = baseType.element_type();
					default: unreachable();
				}
				params[paramIdx] = this.symbols_len();
				Symbol paramSymbol = { .kind = SymbolKind.PARAM, .type = paramType, .passMode = param.passMode };
				this.symbolTable.symbols.push(paramSymbol);
			}
			FunctionAnalysisInfo info = {
				.kind = CallTargetKind.NATIVE_METHOD,
				.nativeFnIdx = nativeFnIdx,
				.returnType = native.returnType,
				.receiverSymbolIdx = receiverSymbolIdx,
				.params = params,
			};
			symbolIdx = this.declare_function(methodName, info, false);
		}
		*out = this.analyze_call_arguments(callExprIdx, symbolIdx, receiverExprIdx);
		return true;
	}
	return false;
}


fn TypeResult SemanticAnalyzer.analyze_fn(SemanticAnalyzer* this, Decl* decl, DeclIdx ownerDeclIdx)
{
	FnDeclAst* fnDecl          = &decl.fnDecl;
	Span fnSpan                = this.ast.statements[fnDecl.body].span;
	TypeResult expectedRetType = this.create_type_from_ast(&fnDecl.returnType, fnSpan);
	if (expectedRetType.hadError)
	{
		return expectedRetType;
	}
	debug::@log_analysis("fn '%s', expects '%s' return type", this.ast.names[decl.nameIdx].text(), expectedRetType.value.type);
	List{StmtIdx}* stmtsIndices = &this.ast.statements[fnDecl.body].blockStmt.stmts;

	this.begin_scope(expectedRetType, false);
	DeclIdx prevStructDeclIdx       = this.currentStructDeclIdx;
	SymbolIdx prevReceiverSymbolIdx = this.currentReceiverSymbolIdx;
	this.currentStructDeclIdx = parser::NO_IDX;
	this.currentReceiverSymbolIdx = NO_SYMBOL;
	this.bind_params(this.symbolTable.declSymbols[ownerDeclIdx]);
	// Scan and analyze all statments in the function
	this.currentReturnType = expectedRetType.value;
	this.returnFound = false;
	foreach (stmtIdx : stmtsIndices)
	{
		TypeResult resultType = this.analyze_stmt(stmtIdx);

		if (resultType.hadError)
		{
			return resultType;
		}
	}

	if (expectedRetType.value.type != ValueType.NULL && !this.returnFound)
	{
		return this.type_error(ErrorKind.NO_RETURN, nullType, expectedRetType.value, fnSpan);
	}
	this.end_scope();
	this.currentStructDeclIdx = prevStructDeclIdx;
	this.currentReceiverSymbolIdx = prevReceiverSymbolIdx;
	return type_ok(expectedRetType.value);
}

fn TypeResult SemanticAnalyzer.analyze_method(SemanticAnalyzer* this, MethodDeclAst* methodDecl, int methodIdx)
{
	Span methodSpan            = this.ast.statements[methodDecl.body].span;
	TypeResult expectedRetType = this.create_type_from_ast(&methodDecl.returnType, methodSpan);
	if (expectedRetType.hadError)
	{
		return expectedRetType;
	}
	debug::@log_analysis("method '%s', expects '%s' return type", this.ast.names[methodDecl.nameIdx].text(), expectedRetType.value.type);
	List{StmtIdx}* stmtsIndices = &this.ast.statements[methodDecl.body].blockStmt.stmts;

	this.begin_scope(expectedRetType, true);
	DeclIdx prevStructDeclIdx       = this.currentStructDeclIdx;
	SymbolIdx prevReceiverSymbolIdx = this.currentReceiverSymbolIdx;
	this.currentStructDeclIdx = methodDecl.structIdx;

	FunctionAnalysisInfo* methodInfo = this.symbolTable.find_method({ .structDeclIdx = methodDecl.structIdx, .methodIdx = methodIdx });
	assert(methodInfo != null);
	this.currentReceiverSymbolIdx = methodInfo.receiverSymbolIdx;
	this.bind_params(methodInfo.symbolIdx);

	this.currentReturnType = expectedRetType.value;
	this.returnFound = false;

	foreach (stmtIdx : stmtsIndices)
	{
		TypeResult resultType = this.analyze_stmt(stmtIdx);
		if (resultType.hadError)
		{
			return resultType;
		}
	}

	if (expectedRetType.value.type != ValueType.NULL && !this.returnFound)
	{
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
	foreach (idx, &decl : this.ast.declarations)
	{
		int index = (int)idx;
		if (decl.kind != DeclKind.STRUCT) continue;
		String structName = this.ast.names[decl.nameIdx].text();
		if (!globals::structNamesToIdx.has_key(structName)) continue;
		int? indexInStructNames = globals::structNamesToIdx.get(structName);
		if (catch err = indexInStructNames) continue;
		if (indexInStructNames == structTypeIndex) return index;
	}
	return parser::NO_IDX;
}

fn int SemanticAnalyzer.find_method_idx(SemanticAnalyzer* this, StructDeclAst* structDecl, InternedString name)
{
	for (sz i = 0; i < structDecl.methods.len(); i++)
	{
		MethodDeclAst* method     = &structDecl.methods[i];
		InternedString methodName = this.ast.names[method.nameIdx];
		if (methodName.id == name.id)
		{
			assert(i < int::max);
			return (int)i;
		}
	}
	return parser::NO_IDX;
}

fn TypeResult SemanticAnalyzer.analyze_stmt(SemanticAnalyzer* this, StmtIdx stmtIdx)
{
	Stmt* stmt = &this.ast.statements[stmtIdx];
	debug::@log_analysis("starting analysis on statement %s", stmt.kind);
	switch (stmt.kind)
	{
		case StmtKind.EXPR: return this.analyze_expr(stmt.exprStmt);
		case StmtKind.ECHO: return this.analyze_expr(stmt.echoStmt);
		case StmtKind.DECL:
			TypeResult lhsType = this.create_type_from_ast(&stmt.varDecl.type, stmt.span);
			if (lhsType.hadError) return lhsType;
			SymbolIdx symbolIdx = this.symbols_len();
			Symbol symbol = { .kind = SymbolKind.LOCAL, .name = this.ast.names[stmt.varDecl.nameIdx], .stmtIdx = stmtIdx, .type = lhsType.value };
			this.symbolTable.symbols.push(symbol);
			this.symbolTable.stmtSymbols[stmtIdx] = symbolIdx;
			this.current_scope().visibleSymbols.push(symbolIdx);
			debug::@log_analysis("statement %s: %s is of type %s", stmt.kind, this.ast.names[stmt.varDecl.nameIdx].text(), lhsType.value.type);
			if (stmt.varDecl.init != parser::NO_IDX)
			{
				Expr* initExpr     = &this.ast.expressions[stmt.varDecl.init];
				TypeResult rhsType = this.analyze_expr(stmt.varDecl.init);
				if (rhsType.hadError)
				{
					return rhsType;
				}
				if (common::type_info_matches(lhsType.value, rhsType.value))
				{
					return type_ok(lhsType.value);
				}

				return this.type_error(ErrorKind.TYPE_MISMATCH, rhsType.value, lhsType.value, initExpr.span);
			}
			return type_ok(lhsType.value);
		case StmtKind.BLOCK:
			// Same as function, scan and analyze all statements
			bool insideMethod = this.is_in_method();
			TypeResult scopeReturnType = type_ok(this.currentReturnType);
			this.begin_scope(scopeReturnType, insideMethod);
			foreach (childIdx : stmt.blockStmt.stmts)
			{
				TypeResult result = this.analyze_stmt(childIdx);

				if (result.hadError)
				{
					return result;
				}
			}
			this.end_scope();
			return type_ok(make_type(ValueType.NULL));
		case StmtKind.IF:
			TypeInfo boolType = make_type(ValueType.BOOL);
			Expr* condExpr = &this.ast.expressions[stmt.ifStmt.cond];
			TypeResult condType = this.analyze_expr(stmt.ifStmt.cond);
			if (condType.hadError) return condType;
			if (condType.value.type != ValueType.BOOL)
			{
				return this.type_error(ErrorKind.TYPE_MISMATCH, condType.value, boolType, condExpr.span);
			}
			TypeResult thenType = this.analyze_stmt(stmt.ifStmt.thenBlock);
			if (thenType.hadError) return thenType;
			if (stmt.ifStmt.elseBlock != parser::NO_IDX)
			{
				TypeResult elseType = this.analyze_stmt(stmt.ifStmt.elseBlock);
				if (elseType.hadError) return elseType;
			}
			return type_ok(make_type(ValueType.NULL));
		case StmtKind.WHILE:
			TypeInfo boolType = make_type(ValueType.BOOL);
			Expr* condExpr = &this.ast.expressions[stmt.whileStmt.cond];
			TypeResult condType = this.analyze_expr(stmt.whileStmt.cond);
			if (condType.hadError) return condType;
			if (condType.value.type != ValueType.BOOL)
			{
				return this.type_error(ErrorKind.TYPE_MISMATCH, condType.value, boolType, condExpr.span);
			}
			this.currentLoopDepth++;
			TypeResult bodyTypeResult = this.analyze_stmt(stmt.whileStmt.body);
			this.currentLoopDepth--;
			return bodyTypeResult;
		case StmtKind.RETURN:
			this.returnFound = true;
			if (stmt.retStmt.value == parser::NO_IDX)
			{
				if (this.currentReturnType.type != ValueType.NULL)
				{
					return this.type_error(ErrorKind.TYPE_MISMATCH, nullType, this.currentReturnType, stmt.span);
				}
				return type_ok(nullType);
			}
			TypeResult valueType = this.analyze_expr(stmt.retStmt.value);
			if (valueType.hadError)
			{
				return valueType;
			}
			if (!common::type_info_matches(this.currentReturnType, valueType.value))
			{
				return this.type_error(ErrorKind.TYPE_MISMATCH, valueType.value, this.currentReturnType, stmt.span);
			}
			return type_ok(valueType.value);
		case StmtKind.BREAK:
			if (this.currentLoopDepth == 0)
			{
				return this.type_error(ErrorKind.BREAK_WITHOUT_LOOP, nullType, nullType, stmt.span);
			}
			return type_ok(nullType);
		case StmtKind.CONTINUE:
			if (this.currentLoopDepth == 0)
			{
				return this.type_error(ErrorKind.CONTINUE_WITHOUT_LOOP, nullType, nullType, stmt.span);
			}
			return type_ok(nullType);
		default:
			return type_ok(make_type(ValueType.NULL));
	}
}

fn TypeResult SemanticAnalyzer.analyze_expr(SemanticAnalyzer* this, ExprIdx exprIdx)
{
	if (exprIdx == parser::NO_IDX)
	{
		return type_ok(make_type(ValueType.NULL));
	}
	Expr* expr = &this.ast.expressions[exprIdx];
	debug::@log_analysis(
		"starting analysis on expressions %s",
		expr.kind,
	);
	TypeResult result = { };
	switch (expr.kind)
	{
		case ExprKind.VAR: result = this.analyze_expr_var(exprIdx);
		case ExprKind.INT: result = type_ok(make_type(ValueType.INT));
		case ExprKind.FLOAT: result = type_ok(make_type(ValueType.FLOAT));
		case ExprKind.DOUBLE: result = type_ok(make_type(ValueType.DOUBLE));
		case ExprKind.BOOL: result = type_ok(make_type(ValueType.BOOL));
		case ExprKind.NULL: result = type_ok(make_type(ValueType.NULL));
		case ExprKind.STRING_LITERAL: result = type_ok(make_type(ValueType.STRING_LITERAL));
		case ExprKind.UNARY: result = this.analyze_expr_unary(exprIdx);
		case ExprKind.BINARY: result = this.analyze_expr_binary(exprIdx);
		case ExprKind.NEW: result = this.analyze_expr_new(exprIdx);
		case ExprKind.THIS: result = this.analyze_expr_this(exprIdx);
		case ExprKind.CALL: result = this.analyze_expr_call(exprIdx);
		case ExprKind.MEMBER: result = this.analyze_expr_member(exprIdx);
		case ExprKind.CAST: result = this.analyze_expr_cast(exprIdx);
		case ExprKind.INDEXER: result = this.analyze_expr_indexer(exprIdx);
		default: result = type_ok(make_type(ValueType.NULL));
	}
	if (!result.hadError)
	{
		this.symbolTable.exprTypes[exprIdx] = result.value;
	}
	return result;
}

fn TypeResult SemanticAnalyzer.analyze_expr_new(SemanticAnalyzer* this, ExprIdx exprIdx)
{
	Expr* expr            = &this.ast.expressions[exprIdx];
	TypeResult targetType = this.create_type_from_ast(&expr.new.type, expr.span);
	// if we had an error return it. If instead we're allocating a non-ref lke value with new,
	// it's a mistake:
	// int& a = new int { 5 } <- invalid
	// int& a = new int& { 5 } <- valid
	if (targetType.hadError || !targetType.value.is_ref_like())
	{
		return targetType.hadError ? targetType : this.type_error(ErrorKind.INVALID_TYPE, targetType.value, targetType.value, expr.span);
	}
	if (targetType.value.type == ValueType.ARR_REF_GC || targetType.value.type == ValueType.ARR_REF_NOGC)
	{
		TypeResult initArrSize = this.analyze_expr(expr.new.arraySize);
		if (initArrSize.hadError) return initArrSize;
		if (initArrSize.value.type != ValueType.INT)
		{
			return this.type_error(ErrorKind.TYPE_MISMATCH, initArrSize.value, make_type(ValueType.INT), expr.span);
		}
	}
	else
	{
		TypeResult initType = this.analyze_expr(expr.new.init);
		if (initType.hadError) return initType;
		TypeInfo pointeeType = targetType.value.pointee_type();
		if (!common::type_info_matches(initType.value, pointeeType))
		{
			return this.type_error(ErrorKind.TYPE_MISMATCH, initType.value, pointeeType, expr.span);
		}
	}
	return targetType;
}

fn bool SemanticAnalyzer.try_resolve_visible_symbol(SemanticAnalyzer* this, InternedString name, SymbolIdx* outSymbolIdx)
{
	sz scopeIdx = this.currentScopeIdx;
	// Start from the current scope's visible symbols and traverse upwards, looking for a match
	while (scopeIdx != 0)
	{
		Stack{SymbolIdx}* visibleSymbols = &this.scopes.items[scopeIdx].visibleSymbols;
		for (sz i = (sz)visibleSymbols.size - 1; i >= 0; i--)
		{
			SymbolIdx symbolIdx       = visibleSymbols.items[i];
			Symbol* symbol            = &this.symbolTable.symbols[symbolIdx];
			InternedString symbolName = symbol.name;
			*outSymbolIdx = symbolIdx;
			if (symbolName.id == name.id) return true;
		}
		scopeIdx = this.scopes.items[scopeIdx].enclosingIdx;
	}
	Stack{SymbolIdx}* globalScopeSymbols = &this.scopes.items[0].visibleSymbols;
	for (sz i = (sz)globalScopeSymbols.size - 1; i >= 0; i--)
	{
		SymbolIdx symbolIdx       = globalScopeSymbols.items[i];
		Symbol* symbol            = &this.symbolTable.symbols[symbolIdx];
		InternedString symbolName = symbol.name;
		*outSymbolIdx = symbolIdx;
		if (symbolName.id == name.id) return true;
	}
	return false;
}

fn TypeResult SemanticAnalyzer.analyze_expr_var(SemanticAnalyzer* this, ExprIdx exprIdx)
{
	Expr* expr          = &this.ast.expressions[exprIdx];
	InternedString name = this.ast.names[expr.varExpr];
	SymbolIdx symbolIdx = NO_SYMBOL;
	debug::@log_analysis("analyzing expr_var '%s'", name.text());
	if (this.try_resolve_visible_symbol(name, &symbolIdx))
	{
		this.symbolTable.exprSymbols[exprIdx] = symbolIdx;
		return type_ok(this.symbolTable.symbols[symbolIdx].type);
	}
	return this.type_error(ErrorKind.UNDECLARED_NAME, nullType, nullType, expr.span);
}

fn TypeResult SemanticAnalyzer.analyze_expr_unary(SemanticAnalyzer* this, ExprIdx exprIdx)
{
	Expr* expr         = &this.ast.expressions[exprIdx];
	TypeResult rhsType = this.analyze_expr(expr.unary.rhs);
	if (rhsType.hadError) return rhsType;
	switch (expr.unary.op)
	{
		case UnOp.NEG:
			if (!is_numeric_type(rhsType.value)) return this.type_error(ErrorKind.TYPE_MISMATCH, rhsType.value, rhsType.value, expr.span);
			return type_ok(rhsType.value);
		case UnOp.NOT:
			if (rhsType.value.type != ValueType.BOOL) return this.type_error(ErrorKind.TYPE_MISMATCH, rhsType.value, make_type(ValueType.BOOL), expr.span);
			return type_ok(make_type(ValueType.BOOL));
		default:
			return type_ok(rhsType.value);
	}
}

fn TypeResult SemanticAnalyzer.analyze_expr_cast(SemanticAnalyzer* this, ExprIdx exprIdx)
{
	Expr* expr = &this.ast.expressions[exprIdx];

	TypeResult source = this.analyze_expr(expr.cast.value);
	if (source.hadError) return source;

	TypeResult target = this.create_type_from_ast(&expr.cast.targetType, expr.span);
	if (target.hadError) return target;

	if (!is_numeric_type(source.value) || !is_numeric_type(target.value)) return this.type_error(ErrorKind.TYPE_MISMATCH, source.value, target.value, expr.span);

	return type_ok(target.value);
}

fn TypeResult SemanticAnalyzer.analyze_expr_indexer(SemanticAnalyzer* this, ExprIdx exprIdx)
{
	Expr* expr           = &this.ast.expressions[exprIdx];
	// Analyze the array base
	TypeResult arrayType = this.analyze_expr(expr.indexer.base);
	if (arrayType.hadError) return arrayType;
	// Not an array? indexing on non-arrays is not valid
	if (!arrayType.value.is_array())
	{
		return this.type_error(ErrorKind.NOT_INDEXABLE, arrayType.value, nullType, this.ast.expressions[expr.indexer.base].span);
	}
	// Analyze the index expression
	TypeResult indexType = this.analyze_expr(expr.indexer.index);
	if (indexType.hadError) return indexType;
	// Used a non-integer index? error
	if (indexType.value.type != ValueType.INT)
	{
		return this.type_error(ErrorKind.TYPE_MISMATCH, indexType.value, make_type(ValueType.INT), this.ast.expressions[expr.indexer.index].span);
	}
	return type_ok(arrayType.value.element_type());
}

fn TypeResult SemanticAnalyzer.analyze_expr_binary(SemanticAnalyzer* this, ExprIdx exprIdx)
{
	Expr* expr         = &this.ast.expressions[exprIdx];
	TypeResult lhsType = this.analyze_expr(expr.binary.lhs);

	if (lhsType.hadError)
	{
		return lhsType;
	}

	TypeResult rhsType = this.analyze_expr(expr.binary.rhs);
	if (rhsType.hadError)
	{
		return rhsType;
	}

	debug::@log_analysis("analysis on binary going forward: left %s, right %s", lhsType.value.type, rhsType.value.type);

	switch (expr.binary.op)
	{
		case BinOp.ADD: nextcase;
		case BinOp.SUB: nextcase;
		case BinOp.MUL: nextcase;
		case BinOp.DIV:

			{
				if (!is_numeric_type(lhsType.value) || !common::type_info_matches(lhsType.value, rhsType.value))
				{
					return this.type_error(ErrorKind.TYPE_MISMATCH, rhsType.value, lhsType.value, expr.span);
				}
				return type_ok(lhsType.value);
			}
		case BinOp.EQ: nextcase;
		case BinOp.NEQ:
			if (!common::type_info_matches(lhsType.value, rhsType.value))
			{
				return this.type_error(ErrorKind.TYPE_MISMATCH, rhsType.value, lhsType.value, expr.span);
			}
			return type_ok(make_type(ValueType.BOOL));
		case BinOp.LESS: nextcase;
		case BinOp.LESS_EQ: nextcase;
		case BinOp.GREATER: nextcase;
		case BinOp.GREATER_EQ:
			if (!is_numeric_type(lhsType.value) || !common::type_info_matches(lhsType.value, rhsType.value))
			{
				return this.type_error(ErrorKind.TYPE_MISMATCH, rhsType.value, lhsType.value, expr.span);
			}
			return type_ok(make_type(ValueType.BOOL));
		case BinOp.AND: nextcase;
		case BinOp.OR:
			if (lhsType.value.type != ValueType.BOOL)
			{
				return this.type_error(ErrorKind.TYPE_MISMATCH, lhsType.value, make_type(ValueType.BOOL), expr.span);
			}
			if (rhsType.value.type != ValueType.BOOL)
			{
				return this.type_error(ErrorKind.TYPE_MISMATCH, rhsType.value, make_type(ValueType.BOOL), expr.span);
			}
			return type_ok(make_type(ValueType.BOOL));
		case BinOp.STORE:
			ExprKind lhsKind = this.ast.expressions[expr.binary.lhs].kind;
			if (lhsKind == ExprKind.THIS)
			{
				return this.type_error(ErrorKind.INVALID_LVALUE, lhsType.value, lhsType.value, expr.span);
			}
			if (!common::type_info_matches(lhsType.value, rhsType.value))
			{
				return this.type_error(ErrorKind.TYPE_MISMATCH, rhsType.value, lhsType.value, expr.span);
			}
			// Assigning to a readonly variable is not allowed
			if (this.is_expression_readonly(expr.binary.lhs))
			{
				return this.type_error(ErrorKind.MEMBER_IS_READONLY, lhsType.value, lhsType.value, expr.span);
			}
			return type_ok(lhsType.value);
		default:
			return type_ok(lhsType.value);
	}
}

fn TypeResult SemanticAnalyzer.analyze_expr_this(SemanticAnalyzer* this, ExprIdx exprIdx)
{
	Expr* expr = &this.ast.expressions[exprIdx];
	if (!this.is_in_method())
	{
		return this.type_error(ErrorKind.UNDECLARED_NAME, nullType, nullType, expr.span);
	}
	if (this.currentStructDeclIdx == parser::NO_IDX || this.currentReceiverSymbolIdx == NO_SYMBOL)
	{
		return this.type_error(ErrorKind.INVALID_TYPE, nullType, nullType, expr.span);
	}
	this.symbolTable.exprSymbols[exprIdx] = this.currentReceiverSymbolIdx;
	return type_ok(this.symbolTable.symbols[this.currentReceiverSymbolIdx].type);
}

fn bool SemanticAnalyzer.is_place_expr(SemanticAnalyzer* this, ExprIdx exprIdx)
{
	Expr* expr = &this.ast.expressions[exprIdx];
	switch (expr.kind)
	{
		case ExprKind.VAR: return true;
		case ExprKind.THIS: return true;
		case ExprKind.MEMBER: return this.is_place_expr(expr.member.base);
		default: return false;
	}
}

fn TypeResult SemanticAnalyzer.analyze_expr_call(SemanticAnalyzer* this, ExprIdx exprIdx)
{
	Expr* expr       = &this.ast.expressions[exprIdx];
	// Method calls: resolve against struct methods before treating as free function calls.
	Expr* calleeExpr = &this.ast.expressions[expr.call.callee];
	if (calleeExpr.kind == ExprKind.MEMBER)
	{
		TypeResult baseType = this.analyze_expr(calleeExpr.member.base);

		if (baseType.hadError)
		{
			return baseType;
		}
		TypeInfo baseInfo = baseType.value;
		bool isStruct     = baseInfo.type == ValueType.STRUCT;
		bool isArray      = baseInfo.is_heap_array();
		if (isStruct)
		{
			DeclIdx structDeclIdx     = this.find_struct_decl_idx(baseInfo.structTypeIndex);
			InternedString methodName = this.ast.names[calleeExpr.member.memberIdx];
			TypeResult resolved       = { };
			if (this.try_resolve_method_call(structDeclIdx, methodName, exprIdx, calleeExpr.member.base, &resolved))
			{
				if (!resolved.hadError && !this.is_place_expr(calleeExpr.member.base))
				{
					return this.type_error(ErrorKind.INVALID_METHOD_RECEIVER, baseInfo, baseInfo, expr.span);
				}
				return resolved;
			}
		}
		else if (isArray)
		{
			InternedString methodName = this.ast.names[calleeExpr.member.memberIdx];
			TypeResult resolved       = { };

			if (this.try_resolve_native_method_call(baseInfo, methodName, exprIdx, calleeExpr.member.base, &resolved))
			{
				return resolved;
			}
		}
	}
	if (calleeExpr.kind == ExprKind.VAR && this.currentStructDeclIdx != parser::NO_IDX)
	{
		InternedString methodName = this.ast.names[calleeExpr.varExpr];
		TypeResult resolved       = { };
		if (this.try_resolve_method_call(this.currentStructDeclIdx, methodName, exprIdx, parser::NO_IDX, &resolved))
		{
			return resolved;
		}
	}

	TypeResult calleeType = this.analyze_expr(expr.call.callee);

	if (calleeType.hadError)
	{
		return calleeType;
	}

	SymbolIdx symbolIdx = this.symbolTable.exprSymbols[expr.call.callee];
	if (symbolIdx == NO_SYMBOL || this.symbolTable.symbols[symbolIdx].kind != SymbolKind.FUNCTION)
	{
		return this.type_error(ErrorKind.INVALID_CALL, nullType, nullType, expr.span);
	}
	return this.analyze_call_arguments(exprIdx, symbolIdx, parser::NO_IDX);
}

fn TypeResult SemanticAnalyzer.analyze_call_arguments(SemanticAnalyzer* this, ExprIdx callExprIdx, SymbolIdx functionSymbolIdx, ExprIdx receiverExprIdx)
{
	Expr* expr                = &this.ast.expressions[callExprIdx];
	Symbol functionSymbol     = this.symbolTable.symbols[functionSymbolIdx];
	FunctionAnalysisInfo info = this.symbolTable.functions[functionSymbol.funcIdx];
	SymbolIdx[] params        = info.params;
	int paramOffset           = (info.kind == CallTargetKind.METHOD || info.kind == CallTargetKind.NATIVE_METHOD) ? 1 : 0;
	int argCount              = expr.call.argsEnd - expr.call.argsStart;
	if (argCount != (int)params.len - paramOffset)
	{
		return this.type_error(ErrorKind.INVALID_ARITY, nullType, nullType, expr.span);
	}
	for (int i = 0; i < argCount; i++)
	{
		Symbol param       = this.symbolTable.symbols[params[(sz)(i + paramOffset)]];
		ExprIdx argListIdx = expr.call.argsStart + i;
		TypeResult result;
		if (this.analyze_function_argument(param.type, this.ast.args[argListIdx].exprIdx, this.ast.args[argListIdx].passMode, param.passMode, &result)) return result;
	}
	this.symbolTable.callTargets[callExprIdx] = {
		.functionSymbolIdx = functionSymbolIdx,
		.receiverExprIdx = receiverExprIdx,
	};
	return type_ok(info.returnType);
}

faultdef NO_TYPE_ERROR;
fn bool SemanticAnalyzer.analyze_function_argument(SemanticAnalyzer* this, TypeInfo expectedType, ExprIdx argExprIdx, ParamPassMode argPassMode, ParamPassMode paramPassMode, TypeResult* result)
{
	*result = this.analyze_expr(argExprIdx);

	if (result.hadError)
	{
		return true;
	}
	// Expected type and real type doens't match
	if (!common::type_info_matches(expectedType, result.value))
	{
		*result = this.type_error(ErrorKind.TYPE_MISMATCH, result.value, expectedType, this.ast.expressions[argExprIdx].span);
		return true;
	}
	// In/inout must match between the declaration and call
	if (paramPassMode != argPassMode)
	{
		*result = this.type_error(ErrorKind.PASS_MODE_MISMATCH, result.value, result.expected, this.ast.expressions[argExprIdx].span);
		return true;
	}
	// If it was passed as inout but was readonly, error
	if (paramPassMode == ParamPassMode.INOUT && this.is_expression_readonly(argExprIdx))
	{
		*result = this.type_error(ErrorKind.MEMBER_IS_READONLY, result.value, result.expected, this.ast.expressions[argExprIdx].span);
		return true;
	}

	return false;
}

fn TypeResult SemanticAnalyzer.analyze_expr_member(SemanticAnalyzer* this, ExprIdx exprIdx)
{
	Expr* expr          = &this.ast.expressions[exprIdx];
	TypeResult baseType = this.analyze_expr(expr.member.base);
	if (baseType.hadError)
	{
		return baseType;
	}
	TypeInfo baseInfo = baseType.value;

	// If we're analyzing a member of a (for example) int&
	// We only accept the built-in .value property, reject anything else
	if (baseInfo.is_builtin_ref_like())
	{
		InternedString fieldName = this.ast.names[expr.member.memberIdx];
		TypeInfo builtinPointee  = baseInfo.pointee_type();
		if (fieldName.text() == "value")
		{
			return type_ok(builtinPointee);
		}
		else
		{
			return this.type_error(ErrorKind.UNDECLARED_NAME, nullType, builtinPointee, expr.span);
		}
	}

	// Array handling for .length and .capacity properties
	bool isArray = baseInfo.is_array();
	if (isArray)
	{
		InternedString fieldName = this.ast.names[expr.member.memberIdx];
		String fieldString       = fieldName.text();
		if (fieldString == "length" || fieldString == "capacity")
		{
			return type_ok(make_type(ValueType.INT));
		}
	}

	// struct handling for generic fields
	bool isStruct = baseInfo.type == ValueType.STRUCT;
	if (!isStruct && !baseInfo.is_struct_ref_like())
	{
		return this.type_error(ErrorKind.INVALID_TYPE, baseInfo, baseInfo, expr.span);
	}
	if (baseInfo.structTypeIndex == common::NOT_STRUCT)
	{
		return this.type_error(ErrorKind.INVALID_TYPE, baseInfo, baseInfo, expr.span);
	}

	DeclIdx structDeclIdx = this.find_struct_decl_idx(baseInfo.structTypeIndex);
	if (structDeclIdx == parser::NO_IDX)
	{
		return this.type_error(ErrorKind.INVALID_TYPE, baseInfo, baseInfo, expr.span);
	}

	Decl* structDecl         = &this.ast.declarations[structDeclIdx];
	InternedString fieldName = this.ast.names[expr.member.memberIdx];
	MemberIdx fieldIdx       = 0;
	foreach (&field : structDecl.structDecl.fields)
	{
		InternedString declName = this.ast.names[field.nameIdx];
		if (declName.id == fieldName.id)
		{
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

