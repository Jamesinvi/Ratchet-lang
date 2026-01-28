module common;
import std::collections::list;
import log;
alias Byte = char;

struct Chunk
{
    ushort constantsCount;
    ushort totalConstantsBytes;
    List{Byte} code;
    List{Byte} constants;
    List{FrameSlotInfo} debugConstantsSlots;
    List{int} lines;
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


fn void Chunk.append_to_chunk(Chunk* chunk, Byte toWrite, int line){
    chunk.code.push(toWrite);
    chunk.lines.push(line);
}

fn void Chunk.debug_print(Chunk* chunk) {
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
    for (usz offset = 0;offset<chunk.code.len();){
        offset = dissassemble_instruction(chunk, offset);
    }
    log::logn("======END======");
}


fn Byte read_u8(Chunk* chunk, usz currentOffset)
{
    return chunk.code[currentOffset+1];
}

fn ushort read_u16(Chunk* chunk, usz currentOffset)
{
    ushort hi = (ushort)chunk.code[currentOffset+1];
    ushort lo = (ushort)chunk.code[currentOffset+2];
    return (ushort)((hi << 8) | lo);
}

fn usz dissassemble_instruction (Chunk* chunk, usz currentOffset){
    log::log("%04d|%5d|", currentOffset, chunk.lines[currentOffset]);

    OpCode instruction = (OpCode)chunk.code[currentOffset];

    switch(instruction){
        // Math
        case OpCode.ADD_INT:        nextcase;
        case OpCode.ADD_FLOAT:      nextcase;
        case OpCode.ADD_DOUBLE:     nextcase;
        case OpCode.SUB_INT:        nextcase;
        case OpCode.SUB_FLOAT:      nextcase;
        case OpCode.SUB_DOUBLE:     nextcase;
        case OpCode.MUL_INT:        nextcase;
        case OpCode.MUL_FLOAT:      nextcase;
        case OpCode.MUL_DOUBLE:     nextcase;
        case OpCode.DIV_INT:        nextcase;
        case OpCode.DIV_FLOAT:      nextcase;
        case OpCode.DIV_DOUBLE:     nextcase;

        case OpCode.NEGATE_INT:     nextcase;
        case OpCode.NEGATE_FLOAT:   nextcase;
        case OpCode.NEGATE_DOUBLE:  nextcase;
        case OpCode.NOT:            nextcase;
         // Comparison
        case OpCode.INT_GREATER:    nextcase;
        case OpCode.INT_EQUAL:    nextcase;
        case OpCode.INT_LESS:    nextcase;
        case OpCode.FLOAT_GREATER:    nextcase;
        case OpCode.FLOAT_EQUAL:    nextcase;
        case OpCode.FLOAT_LESS:    nextcase;
        case OpCode.DOUBLE_GREATER:    nextcase;
        case OpCode.DOUBLE_EQUAL:    nextcase;

        case OpCode.CONST_FALSE:    nextcase;
        case OpCode.CONST_TRUE:     nextcase;
        case OpCode.CONST_NULL:     nextcase;
        case OpCode.CONCAT_STRING:  nextcase;
        case OpCode.CAST_F_I:       nextcase;
        case OpCode.CAST_D_I:       nextcase;
        case OpCode.CAST_I_F:       nextcase;
        case OpCode.CAST_D_F:       nextcase;
        case OpCode.CAST_I_D:       nextcase;
        case OpCode.CAST_F_D:       nextcase;
        case OpCode.RETURN:     
            return single_byte_instruction(instruction, currentOffset);
        case OpCode.ECHO:           nextcase;
        case OpCode.CAST_TO_STRING:
            return single_and_type_instruction(instruction, chunk, currentOffset);
        case OpCode.POP:            
            return pop_instruction(instruction, chunk, currentOffset);
        case OpCode.CONST_INT:      nextcase;
        case OpCode.CONST_FLOAT:    nextcase;
        case OpCode.CONST_DOUBLE:   nextcase;
        case OpCode.CONST_FUNC:     nextcase;
        case OpCode.CONST_STRING:   
            return constant_instruction(instruction, chunk, currentOffset);
        case OpCode.INC_LOCAL:      nextcase;
        case OpCode.DEC_LOCAL:      
            return increment_instruction(instruction, chunk, currentOffset);
        case OpCode.DEFINE_GLOBAL:  nextcase;
        case OpCode.GET_GLOBAL:     nextcase;
        case OpCode.SET_GLOBAL:
            return constant_instruction(instruction, chunk, currentOffset);
        case OpCode.JMP:            nextcase;
        case OpCode.JMP_IF_FALSE:
            return jump_instruction(instruction, chunk, 1, currentOffset);
        case OpCode.LOOP:
            return jump_instruction(instruction, chunk, -1, currentOffset);
        case OpCode.SET_LOCAL:      nextcase;
        case OpCode.GET_LOCAL:      
            return local_instruction(instruction, chunk, currentOffset);
        case OpCode.CALL:           
            return call_instruction(instruction, chunk, currentOffset);
        case OpCode.NEW_REF:        
            return alloc_ref_instruction(instruction, chunk, currentOffset);
        case OpCode.GET_PROP_REF:   nextcase;
        case OpCode.SET_PROP_REF:   nextcase;
        case OpCode.GET_PROP_LOC:   nextcase;
        case OpCode.SET_PROP_LOC:
            return property_instruction(instruction, chunk, currentOffset);
        default:
            log::logn("Unknown opCode: %d", instruction);
            return currentOffset+1;
    }

}

fn usz single_byte_instruction(OpCode instruction, usz currentOffset){
    log::log("%s\n", instruction);
    return currentOffset + 1;
}

fn usz pop_instruction(OpCode instruction, Chunk* chunk, usz currentOffset){
    Byte typeSize = read_u8(chunk,currentOffset);
    log::log("%s, %s\n", instruction, typeSize);
    return currentOffset + 2; // opcode + type
}

fn usz constant_instruction(OpCode instruction, Chunk* chunk, usz currentOffset){
    ushort offset = read_u16(chunk, currentOffset);
    log::log("%s, offset:%d      | val: ", instruction, offset);
    chunk.print_constant(offset);
    log::log("\n");

    return currentOffset + 3; // opcode + offset
}

fn usz increment_instruction(OpCode instruction, Chunk* chunk, usz currentOffset){
    ushort idx = read_u16(chunk, currentOffset);
    log::log("%s, idx:%d\n", instruction, idx);
    return currentOffset + 3; // opcode + index
}

fn usz local_instruction(OpCode instruction, Chunk* chunk, usz currentOffset){
    ushort constantIndex = read_u16(chunk, currentOffset);
    log::log("%s, idx:%d\n",instruction, constantIndex);
    return currentOffset+3; //opcode + index
}

fn usz call_instruction(OpCode instruction, Chunk* chunk, usz currentOffset){
    Byte argCount = read_u8(chunk, currentOffset);
    ushort argsLength = read_u16(chunk, currentOffset + 1);
    log::log("%s, argc:%d, arglen:%s\n", instruction, argCount, argsLength);
    return currentOffset + 4; // opcode + arg count + args length
}

fn usz single_and_type_instruction(OpCode instruction, Chunk* chunk, usz currentOffset){
    ValueType type = (ValueType) read_u8(chunk, currentOffset);
    log::log("%s, from:%s\n", instruction, type);
    return currentOffset + 2; // opcode + type
}

fn usz jump_instruction(OpCode instruction, Chunk* chunk, int sign, usz currentOffset){
    ushort jump = read_u16(chunk, currentOffset);
    log::log("%s, from:%d    | to: %d\n", instruction, currentOffset,currentOffset + 3 + (long)sign * jump);
    return currentOffset + 3;  // opcode + jumplen
}

fn usz property_instruction(OpCode instruction, Chunk* chunk, usz currentOffset){
    ushort structIndex = read_u16(chunk, currentOffset);
    ushort localOffset = read_u16(chunk, currentOffset + 2);
    ushort fieldSize = read_u16(chunk, currentOffset+ 4);
    ValueType type = (ValueType) read_u8(chunk, currentOffset +6);
    log::log("%s, idx:%d    | localOff: %d, fieldSize: %s, type: %s\n", instruction, structIndex,localOffset, fieldSize, type);
    return currentOffset + 8; // opcode + indx + offset + fieldsize + type
}

fn usz alloc_ref_instruction(OpCode instruction, Chunk* chunk, usz currentOffset){
    Byte tracked = read_u8(chunk, currentOffset);
    ValueType type = (ValueType) read_u8(chunk, currentOffset + 1);
    ushort size = read_u16(chunk, currentOffset +2);
    log::log("%s,     | tracked?: %d, allocSize: %s, type: %s\n", instruction, tracked,size, type);
    return currentOffset + 5; // opcode + fieldsize + tracked? + type
}



fn void Chunk.print_constant(Chunk* this, int offset){
   int slotIdx = -1;
    foreach (idx, info : this.debugConstantsSlots) {
        if ((int)info.offset == offset) {
            slotIdx = (int)idx;
            break;
        }
    }
    FrameSlotInfo info = this.debugConstantsSlots[slotIdx];
    Byte* bytes = &this.constants[info.offset];
    
    switch(info.type){
        case ValueType.INT:         log::log("%d", @as(int, bytes));  
        case ValueType.FLOAT:       log::log("%f", @as(float, bytes,));  
        case ValueType.DOUBLE:      log::log("%f", @as(double, bytes,));  
        case ValueType.BOOL:        log::log("%s", @as(bool, bytes,));
		case ValueType.BORROW_REF:log::log("struct, change to print");  
        case ValueType.STRUCT:      log::log("struct, change to print");
        case ValueType.NULL:        log::log("NULL");
        case ValueType.REF:      nextcase;
        case ValueType.PTR:   {
            switch (@as(Obj*, bytes).type)
            {
                case ObjType.STRING:            log::log("\"%s\"", @as(ObjString*, bytes).str);
                case ObjType.FUNCTION:          log::log("fn %s",  @as(ObjFunction*, bytes).name.str);
                case ObjType.REF:               log::log("ref %s", @as(ObjRef*, bytes).refTo);
                case ObjType.NATIVE_FUNCTION:   log::log("<native_fn>");
            }
        }
    }
}
