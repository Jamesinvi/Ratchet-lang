module common;
import std::collections::list;
import std::collections::map;
import std::io;

struct StructTypeInfo
{
    String name;
    ushort fieldCount;
    List{FieldInfo} fieldInfos;
}

fn void StructTypeInfo.init(StructTypeInfo* this){
    this.fieldInfos.init(mem);
}

fn void StructTypeInfo.free(StructTypeInfo* this){
    foreach (info : this.fieldInfos){
        info.name.free(mem);
    }
    this.fieldInfos.free();
}

struct FieldInfo
{
    ValueMetadata metadata;
    ValueType type;
    String name;
}

// This map is used by the compiler so the user can't define the same struct twice
HashMap{String, uint} declaredStructs;

List{StructTypeInfo} structTypes;

fn void print_all_struct_types(){
    foreach (typeInfo : structTypes){
        io::printf("[name: %s, fieldCount: %s]{\n", typeInfo.name, typeInfo.fieldCount);
        foreach(field : typeInfo.fieldInfos){
            if(field.metadata.typeIndex == NOT_STRUCT){
                io::printfn("   %s, %s, idx: NOT STRUCT", ValueType.names[field.type.ordinal], field.name);
            }else{
                io::printfn("   %s, %s, idx: %d", ValueType.names[field.type.ordinal], field.name,  field.metadata.typeIndex);
            }
        }
        io::printf("}\n");
    }
}