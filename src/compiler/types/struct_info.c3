module compiler;
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

// This map is used by the compiler so the user can't define the same struct twice
HashMap{String, uint} declaredStructs;

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

fn void print_all_struct_types(){
    foreach (typeInfo : structTypes){
        io::printf("[name: %s, fieldCount: %s]{\n", typeInfo.name, typeInfo.fieldCount);
        foreach(field : typeInfo.fieldInfos){
            if(field.typeInfo.structTypeIndex == NOT_STRUCT){
                io::printfn("   %s, %s, idx: NOT STRUCT", field.typeInfo.type, field.name);
            }else{
                io::printfn("   %s, %s, idx: %d", field.typeInfo.type, field.name,  field.typeInfo.structTypeIndex);
            }
        }
        io::printf("}\n");
    }
}