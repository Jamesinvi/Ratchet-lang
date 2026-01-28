module parser;
import common;
import std::collections::list;
import std::collections::map;
import std::io;

struct CompStructTypeInfo
{
    String name;
    bool isDefined;
    ushort sizeInBytes;
    ushort fieldCount;
    uint typeIndex;                 //index in structTypes
    List{FieldInfo} 	fieldInfos;
	List{MethodInfo}	methodsInfos;
}

fn void CompStructTypeInfo.init(CompStructTypeInfo* this){
    this.fieldInfos.init(mem);
}

fn void CompStructTypeInfo.free(CompStructTypeInfo* this){
    foreach (info : this.fieldInfos){
        info.name.free(mem);
    }
    this.fieldInfos.free();
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
