
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
		case TokenType.STRING_T:		result.type = ValueType.REF;
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
				int? structTypeIdx = globals::structNamesToIdx.get(baseName);
				if (catch err = structTypeIdx) {
					int nextIdx = (int)globals::structTypes.len();
					CompStructTypeInfo structInfo = {};
					globals::structTypes.push(structInfo);
					String nameCopy = String.copy(baseName, &globals::compAllocator);
					globals::structNamesToIdx[nameCopy] = nextIdx;
					result.structTypeIndex = nextIdx;
				} else {
					result.structTypeIndex = structTypeIdx;
				}
				return type_ok(result);
			}

			// Try structs
			DeclIdx? found = globals::declaredStructs.get(typeName);
			if (catch err = found) return this.type_error(ErrorKind.INVALID_TYPE, nullType, nullType, span);
			result.type = ValueType.STRUCT;
			int? structTypeIdx = globals::structNamesToIdx.get(typeName);
			if (catch err = structTypeIdx) {
				int nextIdx = (int)globals::structTypes.len();
				CompStructTypeInfo structInfo = {};
				globals::structTypes.push(structInfo);
				String nameCopy = String.copy(typeName, &globals::compAllocator);
				globals::structNamesToIdx[nameCopy] = nextIdx;
				result.structTypeIndex = nextIdx;
			} else {
				result.structTypeIndex = structTypeIdx;
			}
			return type_ok(result);
		}
		case TokenType.THIS:			
		{
            assert(globals::structTypes.len() < int::max);
			String typeName = this.ast.names[input.nameIdx].text();
			DeclIdx? found = globals::declaredStructs.get(typeName);
			if (catch err = found) return this.type_error(ErrorKind.INVALID_TYPE, nullType, nullType, span);
			result.type = ValueType.REF;
			
			int? structTypeIdx = globals::structNamesToIdx.get(typeName);
			if (catch err = structTypeIdx) {
				int nextIdx = (int)globals::structTypes.len();
				CompStructTypeInfo structInfo = {};
				globals::structTypes.push(structInfo);
				String nameCopy = String.copy(typeName, &globals::compAllocator);
				globals::structNamesToIdx[nameCopy] = nextIdx;
				result.structTypeIndex = nextIdx;
			}else{
				result.structTypeIndex = structTypeIdx;
			}
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

macro SymbolIdx SemanticAnalyzer.symbols_len(SemanticAnalyzer* this)
{
    assert(this.symbolTable.symbols.len() < int::max);
    return (SymbolIdx)this.symbolTable.symbols.len();
}
