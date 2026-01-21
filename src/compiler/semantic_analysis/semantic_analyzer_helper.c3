
module parser::analyzer;
import common;
import std::collections::list;
import log;
	
CompTypeInfo nullType = { .type = ValueType.NULL, .refToType = ValueType.NULL, .structTypeIndex = parser::NOT_STRUCT };


fn bool SemanticAnalyzer.is_in_method(SemanticAnalyzer* this)
{
	return this.scopes.size > 0 && this.scopes.peek().insideMethod;
}


fn TypeResult SemanticAnalyzer.create_type_from_ast(SemanticAnalyzer* this, TypeAst* input, Span span)
{
	CompTypeInfo result = {.type = ValueType.NULL, .refToType = ValueType.NULL, .structTypeIndex = parser::NOT_STRUCT};
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
			String typeName = this.ast.names[input.nameIdx];
			if (typeName.len == 0){
				return this.type_error(ErrorKind.INVALID_TYPE, nullType, nullType, span);
			} 

			char lastChar = typeName[typeName.len - 1];

			// Ref or Ptr type to structs
			if (lastChar == '&' || lastChar == '*') {
				if (typeName.len < 2) return this.type_error(ErrorKind.INVALID_TYPE, nullType, nullType, span);
				String baseName = typeName.[0 .. typeName.len - 1];
				DeclIdx? found = parser::declaredStructs.get(baseName);
				if (catch err = found) return this.type_error(ErrorKind.INVALID_TYPE, nullType, nullType, span);
				result.type = (lastChar == '&') ? ValueType.REF : ValueType.PTR;
				result.refToType = ValueType.STRUCT;
				if(!parser::structNamesToIdx.has_key(baseName)){
					usz nextIdx = parser::structTypes.len();
					CompStructTypeInfo structInfo = {};
					parser::structTypes.push(structInfo);
					String nameCopy = String.copy(baseName, mem);
					parser::structNamesToIdx[nameCopy] = nextIdx;
				}
				usz? structTypeIdx = parser::structNamesToIdx.get(baseName);
				if (catch err = structTypeIdx) return this.type_error(ErrorKind.INVALID_TYPE, nullType, nullType, span);
				result.structTypeIndex = (uint)structTypeIdx;
				return type_ok(result);
			}

			// Try structs
			DeclIdx? found = parser::declaredStructs.get(typeName);
			if (catch err = found) return this.type_error(ErrorKind.INVALID_TYPE, nullType, nullType, span);
			result.type = ValueType.STRUCT;
			if(!parser::structNamesToIdx.has_key(typeName)){
				usz nextIdx = parser::structTypes.len();
				CompStructTypeInfo structInfo = {};
				parser::structTypes.push(structInfo);
				String nameCopy = String.copy(typeName, mem);
				parser::structNamesToIdx[nameCopy] = nextIdx;
			}
			usz? structTypeIdx = parser::structNamesToIdx.get(typeName);
			if (catch err = structTypeIdx) return this.type_error(ErrorKind.INVALID_TYPE, nullType, nullType, span);
			result.structTypeIndex = (uint)structTypeIdx;
			return type_ok(result);
		}
		case TokenType.THIS:			
		{
			String typeName = this.ast.names[input.nameIdx];
			DeclIdx? found = parser::declaredStructs.get(typeName);
			if (catch err = found) return this.type_error(ErrorKind.INVALID_TYPE, nullType, nullType, span);
			result.type = ValueType.BORROW_REF;
			
			if(!parser::structNamesToIdx.has_key(typeName)){
				usz nextIdx = parser::structTypes.len();
				CompStructTypeInfo structInfo = {};
				parser::structTypes.push(structInfo);
				String nameCopy = String.copy(typeName, mem);
				parser::structNamesToIdx[nameCopy] = nextIdx;
			}
			usz? structTypeIdx = parser::structNamesToIdx.get(typeName);
			if (catch err = structTypeIdx) return this.type_error(ErrorKind.INVALID_TYPE, nullType, nullType, span);
			result.refToType = ValueType.STRUCT;
			result.structTypeIndex = (uint)structTypeIdx;
			return type_ok(result);
		}
		default: 						return this.type_error(ErrorKind.INVALID_TYPE, nullType, nullType, span);
	}
	return type_ok(result);
}

fn CompTypeInfo make_type(ValueType type)
{
	CompTypeInfo info = { .type = type, .refToType = ValueType.NULL, .structTypeIndex = parser::NOT_STRUCT };
	return info;
}

fn CompTypeInfo make_ref_type(ValueType refToType, uint structIndex)
{
	CompTypeInfo info = { .type = ValueType.REF, .refToType = refToType, .structTypeIndex = structIndex };
	return info;
}

fn bool is_numeric_type(CompTypeInfo info)
{
	return info.type == ValueType.INT || info.type == ValueType.FLOAT || info.type == ValueType.DOUBLE;
}
