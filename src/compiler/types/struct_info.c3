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
    List{FieldInfo} fieldInfos;
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

// This map is used by the parser so the user can't define the same struct twice
HashMap{String, DeclIdx} declaredStructs;
HashMap{String, DeclIdx} declaredFunctions;

List{CompStructTypeInfo} structTypes;

fn void clean_up_struct_globals(){
    foreach(structTypeInfo : structTypes){
        foreach(fieldInfo : structTypeInfo.fieldInfos){
            fieldInfo.name.free(mem);
        }
        structTypeInfo.fieldInfos.free();
        structTypeInfo.name.free(mem);
    }
    structTypes.free();
    declaredStructs.clear();
}