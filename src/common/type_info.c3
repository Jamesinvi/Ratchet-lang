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

struct TypeInfo
{
    int structTypeIndex;        // -1 is reserved for non-structs
    ValueType type;
    ValueType refToType;        // Will be ValueType.NULL when it is not a reference
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

fn ushort get_type_size(TypeInfo info)
{
    switch (info.type) {
        case ValueType.INT:         	return int::size;
        case ValueType.FLOAT:       	return float::size;
        case ValueType.DOUBLE:      	return double::size;
        case ValueType.BOOL:        	return bool::size;
		case ValueType.STRING_LITERAL: 	return StringIdx::size;
        case ValueType.REF:      		nextcase;
        case ValueType.PTR:   			return uptr::size;
        case ValueType.STRUCT:      	return globals::structTypes[info.structTypeIndex].sizeInBytes;
        default:                    	unreachable();
    }
}

fn ushort get_type_alignment(TypeInfo info)
{
    switch (info.type) {
        case ValueType.INT:         	return int::alignment;
        case ValueType.FLOAT:      		return float::alignment;
        case ValueType.DOUBLE:      	return double::alignment;
        case ValueType.BOOL:        	return bool::alignment;
		case ValueType.STRING_LITERAL: 	return StringIdx::alignment;
        case ValueType.REF:      		nextcase;
        case ValueType.PTR:   			return uptr::alignment;
        case ValueType.STRUCT: 			return globals::structTypes[info.structTypeIndex].alignmentInBytes;
        default:                    	unreachable();
    }
}

fn TypeInfo pointee_from_ref(TypeInfo r)
{
    TypeInfo out = {};
    out.type = r.refToType;
    out.refToType = ValueType.NULL;
    out.structTypeIndex = (out.type == ValueType.STRUCT) ? r.structTypeIndex : NOT_STRUCT;
    return out;
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

macro ushort MethodInfo.arity(MethodInfo* this){
	assert(this.paramTypes.len() <= ushort::max);
	return (ushort)this.paramTypes.len();
}