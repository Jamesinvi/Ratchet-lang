
module compiler::analyzer;
import compiler;
import common;
import globals;
import std::collections::list;
import log;
	
CompTypeInfo nullType = { .type = ValueType.NULL, .refToType = ValueType.NULL, .structTypeIndex = compiler::NOT_STRUCT };


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
	CompTypeInfo result = {.type = ValueType.NULL, .refToType = ValueType.NULL, .structTypeIndex = compiler::NOT_STRUCT};
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
			String typeName = this.ast.names[input.nameIdx].src_text();
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
				result.structTypeIndex = get_struct_idx_bind_if_needed(baseName);
				return type_ok(result);
			}

			// Try structs
			DeclIdx? found = globals::declaredStructs.get(typeName);
			if (catch err = found) return this.type_error(ErrorKind.INVALID_TYPE, nullType, nullType, span);
			result.type = ValueType.STRUCT;
			result.structTypeIndex = get_struct_idx_bind_if_needed(typeName);
			return type_ok(result);
		}
		case TokenType.THIS:			
		{
            assert(globals::structTypes.len() < int::max);
			String typeName = this.ast.names[input.nameIdx].src_text();
			DeclIdx? found = globals::declaredStructs.get(typeName);
			if (catch err = found) return this.type_error(ErrorKind.INVALID_TYPE, nullType, nullType, span);
			result.type = ValueType.REF;
			result.structTypeIndex = get_struct_idx_bind_if_needed(typeName);
			result.refToType = ValueType.STRUCT;
			return type_ok(result);
		}
		default: 						return this.type_error(ErrorKind.INVALID_TYPE, nullType, nullType, span);
	}
	return type_ok(result);
}

fn CompTypeInfo make_type(ValueType type)
{
	CompTypeInfo info = { .type = type, .refToType = ValueType.NULL, .structTypeIndex = compiler::NOT_STRUCT };
	return info;
}

fn CompTypeInfo make_ref_type(ValueType refToType, int structIndex)
{
	CompTypeInfo info = { .type = ValueType.REF, .refToType = refToType, .structTypeIndex = structIndex };
	return info;
}

fn bool is_numeric_type(CompTypeInfo info)
{
	return info.type == ValueType.INT || info.type == ValueType.FLOAT || info.type == ValueType.DOUBLE;
}

<* 
	Helper to get a struct index in globals::structNamesToIdx. If not present, add a new entry and return the index at which it was added
*>
fn int get_struct_idx_bind_if_needed(String name)
{
	int? structTypeIdx = globals::structNamesToIdx.get(name);
	if (catch err = structTypeIdx) {
		int nextIdx = (int)globals::structTypes.len();
		CompStructTypeInfo structInfo = {
			.typeIndex = nextIdx,
		};
		globals::structTypes.push(structInfo);
		String nameCopy = String.copy(name, &globals::compAllocator);
		globals::structNamesToIdx[nameCopy] = nextIdx;
		return nextIdx;
	} else {
		return structTypeIdx;
	}
}

enum StructLayoutResult : char
{
	DONE,
	DEFER,
	ERROR,
}
<*
	Fills in all details of a struct declaration. This is done just before the program is fully analyzed. 
	All types however, should be already declared in a previous pass.
*>
fn StructLayoutResult SemanticAnalyzer.try_fill_struct_info(SemanticAnalyzer* this, Decl* decl, ProgramAst* ast)
{
	int index = get_struct_idx_bind_if_needed(this.ast.names[decl.structDecl.nameIdx].src_text());
	CompStructTypeInfo* info = &globals::structTypes[index];
	String name = ast.names[decl.structDecl.nameIdx].src_text();

	// CompStructTypeInfo owns its data, so we must  init() it
	info.init();
    ushort offset = 0;
    ushort maxAlign = 1;
	// First pass: check if we can actually fill in the info
	foreach (&field : decl.structDecl.fields) {
        TypeResult fieldTypeResult = this.create_type_from_ast(&field.type, {});
        if (fieldTypeResult.hadError){
			return StructLayoutResult.ERROR;
		} 
        CompTypeInfo fieldType = fieldTypeResult.value;
		if (fieldType.type == ValueType.STRUCT) {
			int fieldStructIndex = fieldType.structTypeIndex;
			CompStructTypeInfo* fieldStructInfo = &globals::structTypes[fieldStructIndex];

			if (!fieldStructInfo.isDefined) {
				return StructLayoutResult.DEFER;
			}
		}
    }
	// Second pass: know we know we have all the field types declared, so fill in the info
    foreach (&field : decl.structDecl.fields) {
        CompTypeInfo fieldType = this.create_type_from_ast(&field.type, {}).value;
        ushort fieldAlign = compiler::get_type_alignment(fieldType);
        ushort fieldSize = compiler::get_type_size(fieldType);
		// There's some ugliness with types and sizes, so make sure these casts are safe
		always_assert(offset < short::max);
		always_assert(fieldAlign < short::max);
        offset = (ushort)common::align_offset((short)offset, (short)fieldAlign);
		// FieldInfo also owns its data, so we copy the string, instead of storing an interned string
        FieldInfo fieldInfo = {
            .name = String.copy(ast.names[field.nameIdx].src_text(), &globals::typeInfoAllocator),
            .typeInfo = fieldType,
            .offset = offset,
        };

        info.fieldInfos.push(fieldInfo);

        offset += fieldSize;
        maxAlign = max(maxAlign, fieldAlign);
    }

	info.name = String.copy(name, &globals::typeInfoAllocator);

	// There's some ugliness with types and sizes, so make sure these casts are safe
	always_assert(offset < short::max);
	always_assert(maxAlign < short::max);
    info.fieldCount = (ushort)info.fieldInfos.len();
    info.alignmentInBytes = maxAlign;
    info.sizeInBytes = (ushort)common::align_offset((short)offset, (short)maxAlign);
	info.isDefined = true;
	return StructLayoutResult.DONE;
}


macro SymbolIdx SemanticAnalyzer.symbols_len(SemanticAnalyzer* this)
{
    assert(this.symbolTable.symbols.len() < int::max);
    return (SymbolIdx)this.symbolTable.symbols.len();
}
