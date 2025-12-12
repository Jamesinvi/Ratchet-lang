module common;
import std::collections::list;
import log;
alias Byte = char;

struct Chunk (DebugPrintable)
{
    List{Byte} code;
    List{Byte} constants;
    List{SlotInfo} debugConstantsSlots;
    List{int} lines;
    ushort constantsCount;
    ushort totalConstantsBytes;
}

fn void Chunk.init(Chunk* chunk){  
    ensure_globals_init();
    chunk.code.init(mem);
    chunk.lines.init(mem);
    chunk.constants.init(mem);
    chunk.debugConstantsSlots.init(mem);
}


fn void Chunk.deinit(Chunk* chunk){
    chunk.code.free();
    chunk.constants.free();
    chunk.debugConstantsSlots.free();
    chunk.lines.free();
}


fn void Chunk.append_to_chunk( Chunk* chunk, Byte toWrite, int line){
    chunk.code.push(toWrite);
    chunk.lines.push(line);
}

fn void Chunk.debug_print(Chunk* chunk) @dynamic{
    log::log("Constants: [");
    foreach (idx, constant : chunk.debugConstantsSlots){
        if(idx>0){
            log::log(", ");
        }
        log::log("slot %d: ",idx);
        chunk.print_constant(constant.offset);
    }
    log::log("]\n");

    log::logn("======DISASSEMBLY======");
    log::logn("BYTE|LINE |OPCODE              |EXTRA INFO");
    for (int offset = 0;offset<chunk.code.len();){
        offset = dissassemble_instruction(chunk, offset);
    }
    log::logn("======END======");
}

fn ushort Chunk.add_const_int(Chunk* chunk, int v){
    ushort index = chunk.constantsCount;
    ushort offset = chunk.totalConstantsBytes;
    Byte* bytes = (Byte*)&v;
    for(int i=0;i<int.sizeof;i++){
        chunk.constants.push(bytes[i]);
    }
    SlotInfo info = {
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
    SlotInfo info = {
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
    SlotInfo info = {
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
    ObjString* str = create_obj_string(src, true);

    uptr ptr = (uptr)str;
    Byte* bytes = (Byte*)&ptr;
    for(int i = 0; i < uptr.sizeof; i++){
        chunk.constants.push(bytes[i]);
    }
        
    SlotInfo info = {
        .type = ValueType.GC_OBJ,
        .sizeInBytes = uptr.sizeof,  // Pointer
        .offset = offset,
        .index = index,
    };
    chunk.debugConstantsSlots.push(info);
    chunk.totalConstantsBytes += uptr.sizeof;
    chunk.constantsCount++;
    allocatedConstants.push((Obj*)str);

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

    SlotInfo info = {
        .type = ValueType.NO_GC_OBJ,
        .sizeInBytes = uptr.sizeof,  // Pointer
        .offset = offset,
        .index = index,
    };
    chunk.debugConstantsSlots.push(info);
    chunk.totalConstantsBytes += uptr.sizeof;
    chunk.constantsCount++;
    allocatedConstants.push((Obj*)function);

    return offset;
}

fn ushort Chunk.add_const_native(Chunk* chunk, NativeFn* function){
    ushort index = chunk.constantsCount;
    ushort offset = chunk.totalConstantsBytes;

    ObjNative* nativeObj = create_obj_native(function);

    uptr ptr = (uptr)nativeObj;
    Byte* bytes = (Byte*)&ptr;
    for(int i = 0; i < uptr.sizeof; i++){
        chunk.constants.push(bytes[i]);
    }

    SlotInfo info = {
        .type = ValueType.NO_GC_OBJ,
        .sizeInBytes = uptr.sizeof,  // Pointer
        .offset = offset,
        .index = index,
    };
    chunk.debugConstantsSlots.push(info);
    chunk.totalConstantsBytes += uptr.sizeof;
    chunk.constantsCount++;
    allocatedConstants.push((Obj*)nativeObj);

    return offset;
}



fn int dissassemble_instruction (Chunk* chunk, int currentOffset){
    log::log("%04d|%5d|", currentOffset, chunk.lines[currentOffset]);

    Byte instruction = chunk.code[currentOffset];

    switch(instruction){
        // Math
        case OpCode.ADD_INT.ordinal:        nextcase;
        case OpCode.ADD_FLOAT.ordinal:      nextcase;
        case OpCode.ADD_DOUBLE.ordinal:     nextcase;
        case OpCode.SUB_INT.ordinal:        nextcase;
        case OpCode.SUB_FLOAT.ordinal:      nextcase;
        case OpCode.SUB_DOUBLE.ordinal:     nextcase;
        case OpCode.MUL_INT.ordinal:        nextcase;
        case OpCode.MUL_FLOAT.ordinal:      nextcase;
        case OpCode.MUL_DOUBLE.ordinal:     nextcase;
        case OpCode.DIV_INT.ordinal:        nextcase;
        case OpCode.DIV_FLOAT.ordinal:      nextcase;
        case OpCode.DIV_DOUBLE.ordinal:     nextcase;

        case OpCode.NEGATE_INT.ordinal:     nextcase;
        case OpCode.NEGATE_FLOAT.ordinal:   nextcase;
        case OpCode.NEGATE_DOUBLE.ordinal:  nextcase;
        case OpCode.NOT.ordinal:            nextcase;
         // Comparison
        case OpCode.INT_GREATER.ordinal:    nextcase;
        case OpCode.INT_EQUAL.ordinal:    nextcase;
        case OpCode.INT_LESS.ordinal:    nextcase;
        case OpCode.FLOAT_GREATER.ordinal:    nextcase;
        case OpCode.FLOAT_EQUAL.ordinal:    nextcase;
        case OpCode.FLOAT_LESS.ordinal:    nextcase;
        case OpCode.DOUBLE_GREATER.ordinal:    nextcase;
        case OpCode.DOUBLE_EQUAL.ordinal:    nextcase;

        case OpCode.CONST_FALSE.ordinal:    nextcase;
        case OpCode.CONST_TRUE.ordinal:     nextcase;
        case OpCode.CONST_NULL.ordinal:     nextcase;
        case OpCode.CONCAT_STRING.ordinal:  nextcase;
        case OpCode.CAST_F_I.ordinal:       nextcase;
        case OpCode.CAST_D_I.ordinal:       nextcase;
        case OpCode.CAST_I_F.ordinal:       nextcase;
        case OpCode.CAST_D_F.ordinal:       nextcase;
        case OpCode.CAST_I_D.ordinal:       nextcase;
        case OpCode.CAST_F_D.ordinal:       nextcase;
        case OpCode.RETURN.ordinal:     
            return single_byte_instruction(OpCode.names[instruction], currentOffset);
        case OpCode.ECHO.ordinal:           nextcase;
        case OpCode.CAST_TO_STRING.ordinal:
            return single_and_type_instruction(OpCode.names[instruction], chunk, currentOffset);
        case OpCode.POP.ordinal:            
            return pop_instruction(OpCode.names[instruction], chunk, currentOffset);
        case OpCode.CONST_INT.ordinal:      nextcase;
        case OpCode.CONST_FLOAT.ordinal:    nextcase;
        case OpCode.CONST_DOUBLE.ordinal:   nextcase;
        case OpCode.CONST_FUNC.ordinal:     nextcase;
        case OpCode.CONST_STRING.ordinal:   
            return constant_instruction(OpCode.names[instruction], chunk, currentOffset);
        case OpCode.INC_LOCAL.ordinal:      nextcase;
        case OpCode.DEC_LOCAL.ordinal:      
            return increment_instruction(OpCode.names[instruction], chunk, currentOffset);
        case OpCode.DEFINE_GLOBAL.ordinal:  nextcase;
        case OpCode.GET_GLOBAL.ordinal:     nextcase;
        case OpCode.SET_GLOBAL.ordinal:
            return constant_instruction(OpCode.names[instruction], chunk, currentOffset);
        case OpCode.JMP.ordinal:            nextcase;
        case OpCode.JMP_IF_FALSE.ordinal:
            return jump_instruction(OpCode.names[instruction], chunk, 1, currentOffset);
        case OpCode.LOOP.ordinal:
            return jump_instruction(OpCode.names[instruction], chunk, -1, currentOffset);
        case OpCode.SET_LOCAL.ordinal:      nextcase;
        case OpCode.GET_LOCAL.ordinal:      
            return local_instruction(OpCode.names[instruction], chunk, currentOffset);
        case OpCode.CALL.ordinal:           
            return call_instruction(OpCode.names[instruction], chunk, currentOffset);
        default:
            log::logn("Unknown opCode: %d", instruction);
            return currentOffset+1;
    }

}

fn int single_byte_instruction(String name, int currentOffset){
    log::log("%s\n", name);
    return currentOffset + 1;
}

fn int pop_instruction(String name, Chunk* chunk, int currentOffset){
    Byte typeSize = chunk.code[(usz)currentOffset+1];
    log::log("%s, %s\n", name, typeSize);
    return currentOffset + 2;
}
fn int constant_instruction(String name, Chunk* chunk, int currentOffset){
    ushort offset = ((chunk.code[(usz)currentOffset+1] << 8) | chunk.code[(usz)currentOffset+2]);
    log::log("%s, offset:%d      | val: ", name, offset);
    chunk.print_constant(offset);
    log::log("\n");

    return currentOffset + 3;
}

fn int increment_instruction(String name, Chunk* chunk, int currentOffset){
    Byte constantIndex = chunk.code[(usz)currentOffset+1];
    log::log("%s, idx:%d",name, constantIndex);
    log::log("\n");
    return currentOffset+2;
}

fn int local_instruction(String name, Chunk* chunk, int currentOffset){
    ushort constantIndex = ((chunk.code[(usz)currentOffset+1]<< 8) | chunk.code[(usz)currentOffset+2]);
    log::log("%s, idx:%d\n",name, constantIndex);
    return currentOffset+3;
}

fn int call_instruction(String name, Chunk* chunk, int currentOffset){
    Byte argCount = chunk.code[(usz)currentOffset+1];
    ushort argsLength = ((chunk.code[(usz)currentOffset+2]<< 8) | chunk.code[(usz)currentOffset+3]);
    log::log("%s, argc:%d, arglen:%s\n", name, argCount, argsLength);
    return currentOffset + 4; // opcode + arg count + args length
}

fn int single_and_type_instruction(String name, Chunk* chunk, int currentOffset){
    ValueType type = (ValueType)(chunk.code[(usz)currentOffset+1]);
    log::log("%s, from:%s\n", name, ValueType.names[type.ordinal]);
    return currentOffset + 2; // opcode + type
}

fn int jump_instruction(String name, Chunk* chunk, int sign, int currentOffset){
    ushort jump = (ushort)(chunk.code[(usz)currentOffset + 1] << 8);
    jump |= chunk.code[(usz)currentOffset + 2];
    log::log("%s, from:%d    | to: %d\n", name, currentOffset,currentOffset + 3 + sign * jump);
    return currentOffset + 3;
}


fn void Chunk.print_constant(Chunk* this, int offset){
   int slotIdx = -1;
    foreach (idx, info : this.debugConstantsSlots) {
        if ((int)info.offset == offset) {
            slotIdx = (int)idx;
            break;
        }
    }
    SlotInfo info = this.debugConstantsSlots[slotIdx];
    Byte* bytes = &this.constants[info.offset];
    
    switch(info.type){
        case ValueType.INT:         log::log("%d", @as(int, bytes));  
        case ValueType.FLOAT:       log::log("%f", @as(float, bytes,));  
        case ValueType.DOUBLE:      log::log("%f", @as(double, bytes,));  
        case ValueType.BOOL:        log::log("%s", @as(bool, bytes,));  
        case ValueType.STRUCT:      log::log("struct, change to print");
        case ValueType.NULL:        log::log("NULL");
        case ValueType.GC_OBJ:      nextcase;
        case ValueType.NO_GC_OBJ:   {
            switch (@as(Obj*, bytes).type)
            {
                case ObjType.STRING: log::log("\"%s\"", @as(ObjString*, bytes).str);
                case ObjType.FUNCTION: log::log("fn %s", @as(ObjFunction*, bytes).name.str);
                case ObjType.NATIVE_FUNCTION: log::log("<native_fn>");
            }
        }
    }
}
