module compiler;
import common;
import log;
import globals;
import std::collections::list;
import std::collections::map;

struct CompStructTypeInfo
{
    String name;
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
	log::logn("struct %s [size: %s, alignment: %s, fieldCount: %s] {", this.name, this.sizeInBytes, this.alignmentInBytes, this.fieldCount);
	foreach(&fieldInfo : this.fieldInfos){
		log::logn(".   %s, %s, %s", fieldInfo.name, fieldInfo.typeInfo.type, fieldInfo.offset);
	}

	foreach(&methodInfo : this.methodInfos){
		log::logn(".   method %s, %s", methodInfo.name, methodInfo.arity);
	}

	log::logn("}");
}


struct FieldInfo
{
    String name;
    CompTypeInfo typeInfo;
    ushort offset;
}

struct MethodInfo
{
	String name;
	ushort arity;
}
