module compiler;
import common;
import log;
import globals;
import std::collections::list;
import std::collections::map;

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


struct FieldInfo
{
    InternedString name;
    CompTypeInfo typeInfo;
    ushort offset;
}

struct MethodInfo
{
	InternedString name;
    CompTypeInfo returnType;
	List{CompTypeInfo} paramTypes;
	List{InternedString} paramNames;
	List{ParamPassMode} paramPassModes;
}

macro ushort MethodInfo.arity(MethodInfo* this){
	assert(this.paramTypes.len() <= ushort::max);
	return (ushort)this.paramTypes.len();
}