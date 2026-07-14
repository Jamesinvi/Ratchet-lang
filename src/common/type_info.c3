module common;
import globals;
import log;
import std::collections::list;
import std::collections::map;

const NOT_STRUCT = -1;

enum ParamPassMode : char (String asStr)
{
    VALUE		{ "value" },
    IN			{ "in" },
    INOUT		{ "inout" },
}

enum ValueType : char
{
	INT, 
	FLOAT,
	DOUBLE,
	BOOL,
	STRUCT,
	REF,
	PTR,
	STRING_LITERAL,
	NULL,
}

struct TypeInfo
{
    int structTypeIndex;        // -1 is reserved for non-structs
    ValueType type;
    ValueType refToType;        // Will be ValueType.NULL when it is not a reference
}

fn ushort TypeInfo.size(TypeInfo* this)
{
    switch (this.type) {
        case ValueType.INT:         	return int::size;
        case ValueType.FLOAT:       	return float::size;
        case ValueType.DOUBLE:      	return double::size;
        case ValueType.BOOL:        	return bool::size;
		case ValueType.STRING_LITERAL: 	return StringIdx::size;
        case ValueType.REF:      		nextcase;
        case ValueType.PTR:   			return uptr::size;
        case ValueType.STRUCT:      	return globals::structTypes[this.structTypeIndex].sizeInBytes;
        default:                    	unreachable();
    }
}

fn ushort TypeInfo.alignment(TypeInfo* this)
{
    switch (this.type) {
        case ValueType.INT:         	return int::alignment;
        case ValueType.FLOAT:      		return float::alignment;
        case ValueType.DOUBLE:      	return double::alignment;
        case ValueType.BOOL:        	return bool::alignment;
		case ValueType.STRING_LITERAL: 	return StringIdx::alignment;
        case ValueType.REF:      		nextcase;
        case ValueType.PTR:   			return uptr::alignment;
        case ValueType.STRUCT: 			return globals::structTypes[this.structTypeIndex].alignmentInBytes;
        default:                    	unreachable();
    }
}

fn bool TypeInfo.is_builtin_ref_like(TypeInfo* this) @inline
{
	return this.is_ref_like() && this.pointee_type().is_builtin();
}

fn bool TypeInfo.is_ref_like(TypeInfo* this) @inline
{
	return this.type == ValueType.REF || this.type == ValueType.PTR;
}

fn bool TypeInfo.is_builtin(TypeInfo* this) @inline
{
    switch (this.type) {
        case ValueType.INT:         	return true;
        case ValueType.FLOAT:      		return true;
        case ValueType.DOUBLE:      	return true;
        case ValueType.BOOL:        	return true;
        case ValueType.NULL:        	return true;
		case ValueType.STRING_LITERAL: 	return true;
        case ValueType.REF:      		return false;
        case ValueType.PTR:   			return false;
        case ValueType.STRUCT: 			return false;
        default:                    	unreachable();
    }
}

fn TypeInfo TypeInfo.pointee_type(TypeInfo* this)
{
    TypeInfo out = {};
    out.type = this.refToType;
    out.refToType = ValueType.NULL;
    out.structTypeIndex = (out.type == ValueType.STRUCT) ? this.structTypeIndex : NOT_STRUCT;
    return out;
}

fn bool TypeInfo.is_struct_ref_like(TypeInfo* this) @inline
{
	return this.is_ref_like() && this.refToType == ValueType.STRUCT;
}


fn bool type_info_matches(TypeInfo a, TypeInfo b) 
{
    if (a.type != b.type) {
        return false;
    }

    if (a.refToType != b.refToType) {
        return false;
    }

    if (a.type == ValueType.STRUCT || a.refToType == ValueType.STRUCT) {
        return a.structTypeIndex == b.structTypeIndex;
    }

    return true;
}


struct CompStructTypeInfo
{
    InternedString name;
    int typeIndex;                 //index in structTypes
    bool isDefined;
    ushort sizeInBytes;
	ushort alignmentInBytes;
    ushort fieldCount;
    List{FieldInfo} 	fieldInfos;
	List{MethodInfo}	methodInfos;
}

struct FieldInfo
{
    InternedString name;
    TypeInfo typeInfo;
    ushort offset;
}

struct MethodInfo
{
	InternedString name;
    TypeInfo returnType;
	List{TypeInfo} paramTypes;
	List{InternedString} paramNames;
	List{ParamPassMode} paramPassModes;
}


fn void CompStructTypeInfo.init(CompStructTypeInfo* this){
    this.fieldInfos.init(&globals::typeInfoAllocator);
    this.methodInfos.init(&globals::typeInfoAllocator);
}

fn void CompStructTypeInfo.print(CompStructTypeInfo* this)
{
	log::logn("struct %s [size: %s, align: %s, fields: %s] {", this.name.text(), this.sizeInBytes, this.alignmentInBytes, this.fieldCount);
	foreach(&fieldInfo : this.fieldInfos){
		log::logn(".   %s, %s, %s", fieldInfo.name.text(), fieldInfo.typeInfo.type, fieldInfo.offset);
	}

	foreach(&methodInfo : this.methodInfos){
		log::log(".   method %s, [arity: %s] => [", methodInfo.name.text(), methodInfo.arity());
		for(int i = 0; i < (int)methodInfo.paramTypes.len(); i++){
			log::log("(", methodInfo.paramTypes[i].type, methodInfo.paramNames[i].text());
			if(methodInfo.paramPassModes[i] != ParamPassMode.VALUE){
				log::log("%s", methodInfo.paramPassModes[i].asStr);
			}

			log::log("<%s> %s)", methodInfo.paramTypes[i].type, methodInfo.paramNames[i].text());
			if(i< methodInfo.paramTypes.len() -1){
				log::logn(", ");
			}
		}
		log::logn("]");
	}

	log::logn("}");
}

fn ushort MethodInfo.arity(MethodInfo* this) @inline
{
	assert(this.paramTypes.len() <= ushort::max);
	return (ushort)this.paramTypes.len();
}