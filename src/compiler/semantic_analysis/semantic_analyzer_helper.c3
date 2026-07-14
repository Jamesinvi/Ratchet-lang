
module compiler::analyzer;
import compiler;
import common;
import globals;
import std::collections::list;
import log;
import debug;
	
TypeInfo nullType = { .type = ValueType.NULL, .refToType = ValueType.NULL, .structTypeIndex = common::NOT_STRUCT };


fn bool SemanticAnalyzer.is_in_method(SemanticAnalyzer* this)
{
	return this.scopes.size > 0 && this.scopes.peek().insideMethod;
}

<* 
 	Helper to convert a TypeAst to a TypeResult we can use for analysis. Conversion can fail if the user program
	has incorrect type usage. This function will spit out errors to the user using stderr
*>
fn TypeResult SemanticAnalyzer.create_type_from_ast(SemanticAnalyzer* this, TypeAst* input, Span span)
{
	TypeInfo result = {.type = ValueType.NULL, .refToType = ValueType.NULL, .structTypeIndex = common::NOT_STRUCT};
	switch (input.tokenType)
	{
		case TokenType.INTEGER_T: 		result.type = ValueType.INT;
		case TokenType.FLOAT_T: 		result.type = ValueType.FLOAT;
		case TokenType.DOUBLE_T: 		result.type = ValueType.DOUBLE;
		case TokenType.BOOL_T: 			result.type = ValueType.BOOL;
		case TokenType.NULL:			result.type = ValueType.NULL;
		case TokenType.INT_REF_GC:		{ result.type = ValueType.REF; result.refToType = ValueType.INT; }
		case TokenType.FLOAT_REF_GC:	{ result.type = ValueType.REF; result.refToType = ValueType.FLOAT; }
		case TokenType.DOUBLE_REF_GC:	{ result.type = ValueType.REF; result.refToType = ValueType.DOUBLE; }
		case TokenType.BOOL_REF_GC:		{ result.type = ValueType.REF; result.refToType = ValueType.BOOL; }
		case TokenType.INT_REF_NOGC:	{ result.type = ValueType.PTR; result.refToType = ValueType.INT; }
		case TokenType.FLOAT_REF_NOGC:	{ result.type = ValueType.PTR; result.refToType = ValueType.FLOAT; }
		case TokenType.DOUBLE_REF_NOGC:	{ result.type = ValueType.PTR; result.refToType = ValueType.DOUBLE; }
		case TokenType.BOOL_REF_NOGC:	{ result.type = ValueType.PTR; result.refToType = ValueType.BOOL; }
		case TokenType.IDENTIFIER:
		{
            assert(globals::structTypes.len() < int::max);
			String typeName = this.ast.names[input.nameIdx].text();
			if (typeName.len == 0){
				return this.type_error(ErrorKind.INVALID_TYPE, nullType, nullType, span);
			} 

			char lastChar = typeName[typeName.len - 1];

			// Ref or Ptr type to structs
			if (lastChar == '&' || lastChar == '*') {
				if (typeName.len < 2) return this.type_error(ErrorKind.INVALID_TYPE, nullType, nullType, span);
				String baseName = typeName.[0 .. typeName.len - 2];
				DeclIdx? found = globals::declaredStructs.get(baseName);
				if (catch err = found) return this.type_error(ErrorKind.INVALID_TYPE, nullType, nullType, span);
				result.type = (lastChar == '&') ? ValueType.REF : ValueType.PTR;
				result.refToType = ValueType.STRUCT;
				result.structTypeIndex = get_struct_idx_bind_if_needed(baseName, this.outputAllocator);
				return type_ok(result);
			}

			// Try structs
			DeclIdx? found = globals::declaredStructs.get(typeName);
			if (catch err = found) return this.type_error(ErrorKind.INVALID_TYPE, nullType, nullType, span);
			result.type = ValueType.STRUCT;
			result.structTypeIndex = get_struct_idx_bind_if_needed(typeName, this.outputAllocator);
			return type_ok(result);
		}
		case TokenType.THIS:			
		{
            assert(globals::structTypes.len() < int::max);
			String typeName = this.ast.names[input.nameIdx].text();
			DeclIdx? found = globals::declaredStructs.get(typeName);
			if (catch err = found) return this.type_error(ErrorKind.INVALID_TYPE, nullType, nullType, span);
			result.type = ValueType.STRUCT;
			result.structTypeIndex = get_struct_idx_bind_if_needed(typeName, this.outputAllocator);
			result.refToType = ValueType.NULL;
			return type_ok(result);
		}
		default: 						return this.type_error(ErrorKind.INVALID_TYPE, nullType, nullType, span);
	}
	return type_ok(result);
}

fn TypeResult SemanticAnalyzer.fill_globals(SemanticAnalyzer* this)
{
	for (int i = 0; i < (int)this.ast.globalBlock.globalStatements.len(); i++){
		StmtIdx stmtIdx = (StmtIdx)this.ast.globalBlock.globalStatements[i];
		Stmt* stmt = &this.ast.statements[stmtIdx];
		if (stmt.kind == StmtKind.DECL) {
			TypeResult lhsType = this.create_type_from_ast(&stmt.varDecl.type, stmt.span);
			if (lhsType.hadError) {
				return lhsType;
			}
			// If type was valid, add this global declaration (+ assignment) to visible symbols to scope 0 
			SymbolIdx symbolIdx = this.symbols_len();
			Symbol symbol = { .kind = SymbolKind.GLOBAL_VAR, .idx = stmtIdx, .type = lhsType.value };
			this.symbolTable.symbols.push(symbol);
			this.symbolTable.stmtSymbols[stmtIdx] = symbolIdx;
			this.current_scope().visibleSymbols.push(symbolIdx);
			debug::@log_analysis("statement %s: %s is of type %s", stmt.kind, this.ast.names[stmt.varDecl.nameIdx].text(), lhsType.value.type);
			if (stmt.varDecl.init != parser::NO_IDX) {
				Expr* initExpr = &this.ast.expressions[stmt.varDecl.init];
				switch (initExpr.kind) {
					case ExprKind.INT: 				break;
					case ExprKind.FLOAT: 			break;
					case ExprKind.DOUBLE: 			break;
					case ExprKind.BOOL: 			break;
					case ExprKind.NULL: 			break;
					case ExprKind.STRING_LITERAL: 	break;
					default:
						return this.type_error(ErrorKind.INVALID_GLOBAL_INITIALIZER, nullType, lhsType.value, initExpr.span);
				}
				TypeResult rhsType = this.analyze_expr(stmt.varDecl.init);
				if (rhsType.hadError) {
					return rhsType;
				}
				if (!common::type_info_matches(lhsType.value, rhsType.value)){
					return this.type_error(ErrorKind.TYPE_MISMATCH, rhsType.value, lhsType.value, initExpr.span);
				}
			}
		} else {
			// If we have a global statement that is not a variable declaration, then we have a problem
			return this.type_error(ErrorKind.UNDECLARED_NAME, nullType, nullType, {});
		}
	}
	return type_ok(nullType);
}

fn TypeInfo make_type(ValueType type)
{
	TypeInfo info = { .type = type, .refToType = ValueType.NULL, .structTypeIndex = common::NOT_STRUCT };
	return info;
}

fn TypeInfo make_ref_type(ValueType refToType, int structIndex)
{
	TypeInfo info = { .type = ValueType.REF, .refToType = refToType, .structTypeIndex = structIndex };
	return info;
}

fn bool is_numeric_type(TypeInfo info)
{
	return info.type == ValueType.INT || info.type == ValueType.FLOAT || info.type == ValueType.DOUBLE;
}

<* 
	Helper to get a struct index in globals::structNamesToIdx. If not present, add a new entry and return the index at which it was added
*>
fn int get_struct_idx_bind_if_needed(String name, Allocator outputAllocator)
{
	int? structTypeIdx = globals::structNamesToIdx.get(name);
	if (catch err = structTypeIdx) {
		int nextIdx = (int)globals::structTypes.len();
		CompStructTypeInfo structInfo = {
			.typeIndex = nextIdx,
		};
		globals::structTypes.push(structInfo);
		String nameCopy = String.copy(name, outputAllocator);
		globals::structNamesToIdx[nameCopy] = nextIdx;
		return nextIdx;
	} else {
		return structTypeIdx;
	}
}

enum StructLayoutResult : char
{
	OK,
	DEFER,
	ERROR,
}

fn TypeResult SemanticAnalyzer.fill_structs_metadata(SemanticAnalyzer* this, List{DeclIdx} structDeclIndices)
{
	// Allocate a temporary list to track which structs managed to determine their metadata
	List{bool} done = {};
	done.init(&this.localAllocator, structDeclIndices.len());
	common::list_append_fill{bool}(&done, false, structDeclIndices.len());
	sz remaining = structDeclIndices.len();
	// Continue trying to loop through all structs determining their metadata. 
	// If no progress was made in an iteration it must mean there's a circular reference
	while(remaining > 0){
		bool madeProgress = false;
		for (int i = 0; i < (int)structDeclIndices.len(); i++) {
			// Already done, early out
			if (done[i]) {
				continue;
			}

			DeclIdx declIdx = structDeclIndices[i];
			Decl* decl = &this.ast.declarations[declIdx];
			StructLayoutResult result = this.try_fill_struct_field_info(decl, this.ast);

			switch (result) {
				case StructLayoutResult.OK:
					done[i] = true;
					remaining--;
					madeProgress = true;
				case StructLayoutResult.DEFER:	 continue; // Try again after other structs are laid out.
				case StructLayoutResult.ERROR:   return this.type_error(ErrorKind.INVALID_TYPE, nullType, nullType, {});
			}
		}
		// Break out. Special error for circular references
		if(!madeProgress){
			return this.type_error(ErrorKind.UNRESOLVED_STRUCT, nullType, nullType, {});
		}
	}

	// Now do all the method info
	for (int i = 0; i < (int)structDeclIndices.len(); i++) {
		DeclIdx declIdx = structDeclIndices[i];
		Decl* decl = &this.ast.declarations[declIdx];
		this.fill_struct_method_info(decl, this.ast);
	}
	return type_ok(nullType);
}

<*
	Try to fill in a specific struct field metadata. Will return an enum value based on success, error, or defer.
	If defer is returned, it means the struct contains a field of another struct that still has undefined metadata, 
	so it must be deferred to a later pass.
*>
fn StructLayoutResult SemanticAnalyzer.try_fill_struct_field_info(SemanticAnalyzer* this, Decl* decl, ProgramAst* ast)
{
	int index = get_struct_idx_bind_if_needed(this.ast.names[decl.structDecl.nameIdx].text(), this.outputAllocator);
	CompStructTypeInfo* info = &globals::structTypes[index];
	String name = ast.names[decl.structDecl.nameIdx].text();

	// First pass: check if we can actually fill in the info
	StructLayoutResult fieldsAreDefined = this.check_fields_are_defined(decl, ast);
	if (fieldsAreDefined != StructLayoutResult.OK) return fieldsAreDefined;

	// CompStructTypeInfo owns its data, so we must  init() it
	info.init();
	ushort offset   = 0;
	ushort maxAlign = 1;
	// Second pass: know we know we have all the field types declared, so fill in the info

	// Fiedls
	foreach (&field : decl.structDecl.fields) {
		TypeInfo fieldType = this.create_type_from_ast(&field.type, { }).value;
		ushort fieldAlign = fieldType.alignment();
		ushort fieldSize = fieldType.size();
		// There's some ugliness with types and sizes, so make sure these casts are safe
		always_assert(offset < short::max);
		always_assert(fieldAlign < short::max);
		offset = (ushort)common::align_offset((short)offset, (short)fieldAlign);
		// FieldInfo is type information so it should be allocated in typeInfo string interner and allocator
		FieldInfo fieldInfo = {
			.name = globals::typeInfoStrings.get_or_intern(ast.names[field.nameIdx].text()),
			.typeInfo = fieldType,
			.offset = offset,
		};

		info.fieldInfos.push(fieldInfo);

		offset += fieldSize;
		maxAlign = max(maxAlign, fieldAlign);
	}
	info.name = globals::typeInfoStrings.get_or_intern(name);

	// There's some ugliness with types and sizes, so make sure these casts are safe
	always_assert(offset < short::max);
	always_assert(maxAlign < short::max);
	info.fieldCount = (ushort)info.fieldInfos.len();
	info.alignmentInBytes = maxAlign;
	info.sizeInBytes = (ushort)common::align_offset((short)offset, (short)maxAlign);
	info.isDefined = true;
	return StructLayoutResult.OK;
}

fn void SemanticAnalyzer.fill_struct_method_info(SemanticAnalyzer* this, Decl* decl, ProgramAst* ast)
{
	int index = get_struct_idx_bind_if_needed(this.ast.names[decl.structDecl.nameIdx].text(), this.outputAllocator);
	CompStructTypeInfo* structInfo = &globals::structTypes[index];
	// Methods
	foreach (&method : decl.structDecl.methods) {
		TypeInfo fieldType = this.create_type_from_ast(&method.returnType, { }).value;
		List{TypeInfo} methodParamTypes = {};
		List{InternedString} methodParamNames = {};
		List{ParamPassMode} methodParamPassModes = {};
		methodParamTypes.init(&globals::typeInfoAllocator, method.params.len());
		methodParamNames.init(&globals::typeInfoAllocator, method.params.len());
		methodParamPassModes.init(&globals::typeInfoAllocator, method.params.len());
		foreach (&param: method.params){
			TypeInfo methodParamType = this.create_type_from_ast(&param.type, { }).value;
			InternedString methodParamName = globals::typeInfoStrings.get_or_intern(ast.names[param.nameIdx].text());
			ParamPassMode methodParamPassMode = param.passMode;
			methodParamTypes.push(methodParamType);
			methodParamNames.push(methodParamName);
			methodParamPassModes.push(methodParamPassMode);
		}
		MethodInfo methodInfo = {
			.name = globals::typeInfoStrings.get_or_intern(this.ast.names[method.nameIdx].text()),
			.returnType = fieldType,
			.paramTypes = methodParamTypes,
			.paramNames = methodParamNames,
			.paramPassModes = methodParamPassModes,
		};

		structInfo.methodInfos.push(methodInfo);
	}
}

fn StructLayoutResult SemanticAnalyzer.check_fields_are_defined(SemanticAnalyzer* this, Decl* decl, ProgramAst* ast)
{
	foreach (&field : decl.structDecl.fields)	{
		TypeResult fieldTypeResult = this.create_type_from_ast(&field.type, { });
		if (fieldTypeResult.hadError) {
			return StructLayoutResult.ERROR;
		}

		TypeInfo fieldType = fieldTypeResult.value;
		if (fieldType.type == ValueType.STRUCT)	{
			int fieldStructIndex = fieldType.structTypeIndex;
			CompStructTypeInfo* fieldStructInfo = &globals::structTypes[fieldStructIndex];

			if (!fieldStructInfo.isDefined) {
				return StructLayoutResult.DEFER;
			}
		}
	}
	return StructLayoutResult.OK;
}


macro SymbolIdx SemanticAnalyzer.symbols_len(SemanticAnalyzer* this)
{
    assert(this.symbolTable.symbols.len() < int::max);
    return (SymbolIdx)this.symbolTable.symbols.len();
}
