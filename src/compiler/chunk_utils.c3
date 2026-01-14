module parser;
import common;

fn ushort Chunk.add_const_int(Chunk* chunk, int v){
    ushort index = chunk.constantsCount;
    ushort offset = chunk.totalConstantsBytes;
    Byte* bytes = (Byte*)&v;
    for(int i=0;i<int.sizeof;i++){
        chunk.constants.push(bytes[i]);
    }
    FrameSlotInfo info = {
        .type = ValueType.INT,
        .sizeInBytes = int.sizeof,
        .offset = offset,
        .index = index,
    };
    chunk.debugConstantsSlots.push(info);
    chunk.totalConstantsBytes += int.sizeof;
    chunk.constantsCount++;

    return offset;
}

fn ushort Chunk.add_const_float(Chunk* chunk, float f){
    ushort index = chunk.constantsCount;
    ushort offset = chunk.totalConstantsBytes;
    Byte* bytes = (Byte*)&f;
    for(int i=0;i<float.sizeof;i++){
        chunk.constants.push(bytes[i]);
    }
    FrameSlotInfo info = {
        .type = ValueType.FLOAT,
        .sizeInBytes = float.sizeof,
        .offset = offset,
        .index = index,
    };
    chunk.debugConstantsSlots.push(info);
    chunk.totalConstantsBytes += float.sizeof;
    chunk.constantsCount++;

    return offset;
}

fn ushort Chunk.add_const_double(Chunk* chunk, double d){
    ushort index = chunk.constantsCount;
    ushort offset = chunk.totalConstantsBytes;
    Byte* bytes = (Byte*)&d;
    for(int i=0;i<double.sizeof;i++){
        chunk.constants.push(bytes[i]);
    }
    FrameSlotInfo info = {
        .type = ValueType.DOUBLE,
        .sizeInBytes = double.sizeof,
        .offset = offset,
        .index = index,
    };
    chunk.debugConstantsSlots.push(info);
    chunk.totalConstantsBytes += double.sizeof;
    chunk.constantsCount++;

    return offset;
}


fn ushort Chunk.add_const_string(Chunk* chunk, String src){
    ushort index = chunk.constantsCount;
    ushort offset = chunk.totalConstantsBytes;
    ObjString* str = common::create_obj_string(src, true);

    uptr ptr = (uptr)str;
    Byte* bytes = (Byte*)&ptr;
    for(int i = 0; i < uptr.sizeof; i++){
        chunk.constants.push(bytes[i]);
    }
        
    FrameSlotInfo info = {
        .type = ValueType.REF,
        .sizeInBytes = uptr.sizeof,  // Pointer
        .offset = offset,
        .index = index,
    };
    chunk.debugConstantsSlots.push(info);
    chunk.totalConstantsBytes += uptr.sizeof;
    chunk.constantsCount++;
    common::allocatedConstants.push((Obj*)str);

    return offset;
}

fn ushort Chunk.add_const_function(Chunk* chunk, ObjFunction* function){
    ushort index = chunk.constantsCount;
    ushort offset = chunk.totalConstantsBytes;

    uptr ptr = (uptr)function;
    Byte* bytes = (Byte*)&ptr;
    for(int i = 0; i < uptr.sizeof; i++){
        chunk.constants.push(bytes[i]);
    }

    FrameSlotInfo info = {
        .type = ValueType.PTR,
        .sizeInBytes = uptr.sizeof,  // Pointer
        .offset = offset,
        .index = index,
    };
    chunk.debugConstantsSlots.push(info);
    chunk.totalConstantsBytes += uptr.sizeof;
    chunk.constantsCount++;
    common::allocatedConstants.push((Obj*)function);

    return offset;
}

fn ushort Chunk.add_const_native(Chunk* chunk, NativeFn* function){
    ushort index = chunk.constantsCount;
    ushort offset = chunk.totalConstantsBytes;

    ObjNative* nativeObj = common::create_obj_native(function);

    uptr ptr = (uptr)nativeObj;
    Byte* bytes = (Byte*)&ptr;
    for(int i = 0; i < uptr.sizeof; i++){
        chunk.constants.push(bytes[i]);
    }

    FrameSlotInfo info = {
        .type = ValueType.PTR,
        .sizeInBytes = uptr.sizeof,  // Pointer
        .offset = offset,
        .index = index,
    };
    chunk.debugConstantsSlots.push(info);
    chunk.totalConstantsBytes += uptr.sizeof;
    chunk.constantsCount++;
    common::allocatedConstants.push((Obj*)nativeObj);

    return offset;
}