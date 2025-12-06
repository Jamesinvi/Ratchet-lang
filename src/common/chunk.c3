module common;
import std::collections::list;
import std::io;
alias Byte = char;

struct Chunk (DebugPrintable)
{
    List{Byte} code;
    List{Value} constants;
    List{int} lines;
}

fn void Chunk.init(Chunk* chunk){
    chunk.code.init(mem);
    chunk.lines.init(mem);
    chunk.constants.init(mem);
}


fn void Chunk.deinit(Chunk* chunk){
    chunk.code.free();
    chunk.constants.free();
    chunk.lines.free();
}


fn void Chunk.append_to_chunk( Chunk* chunk, Byte toWrite, int line){
    chunk.code.push(toWrite);
    chunk.lines.push(line);
}

fn void Chunk.debug_print(Chunk* chunk) @dynamic{
    io::printfn("======DISASSEMBLY======");
    io::printfn("BYTE|LINE |OPCODE              |EXTRA INFO");
    for (int offset = 0;offset<chunk.code.len();){
        offset = dissassemble_instruction(chunk, offset);
    }
    io::printfn("======END======");
}

fn int Chunk.add_const_int(Chunk* chunk, int v){
    int index = (int)chunk.constants.len();
    Value val = make_int(v);
    chunk.constants.push(val);
    return index;
}
fn int Chunk.add_const_float(Chunk* chunk, float v){
    int index = (int)chunk.constants.len();
    Value val = make_float(v);
    chunk.constants.push(val);
    return index;
}
fn int Chunk.add_const_double(Chunk* chunk, double v){
    int index = (int)chunk.constants.len();
    Value val = make_double(v);
    chunk.constants.push(val);
    return index;
}
fn int Chunk.add_const_string(Chunk* chunk, String src){
    int index = (int)chunk.constants.len();
    Value val = make_string(src, true);
    chunk.constants.push(val);
    return index;
}



fn int dissassemble_instruction (Chunk* chunk, int currentOffset){
    io::printf("%04d|%5d|", currentOffset, chunk.lines[currentOffset]);

    Byte instruction = chunk.code[currentOffset];

    switch(instruction){
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
        case OpCode.GREATER.ordinal:        nextcase;
        case OpCode.EQUAL.ordinal:          nextcase;
        case OpCode.CONST_FALSE.ordinal:    nextcase;
        case OpCode.CONST_TRUE.ordinal:     nextcase;
        case OpCode.CONST_NULL.ordinal:     nextcase;
        case OpCode.LESS.ordinal:           nextcase;
        case OpCode.CONCAT_STRING.ordinal:  nextcase;
        case OpCode.POP.ordinal:            nextcase;
        case OpCode.DEBUG.ordinal:          nextcase;
        case OpCode.RETURN.ordinal:     
            return single_byte_instruction(OpCode.names[instruction], currentOffset);
        case OpCode.CONSTANT.ordinal:
            return constant_instruction(OpCode.names[instruction], chunk, currentOffset);
        case OpCode.DEFINE_GLOBAL.ordinal:
        case OpCode.SET_GLOBAL.ordinal:
        case OpCode.GET_GLOBAL.ordinal:
            return constant_instruction(OpCode.names[instruction], chunk, currentOffset);
        default:
            io::printfn("Unknown opCode: %d", instruction);
            return currentOffset+1;
    }

}

fn int single_byte_instruction(String name, int currentOffset){
    io::printf("%s\n", name);
    return currentOffset + 1;
}

fn int constant_instruction(String name, Chunk* chunk, int currentOffset){
    Byte constantIndex = chunk.code[(usz)currentOffset+1];
    io::printf("%s, idx:%d      | val: ",name, constantIndex);
    chunk.print_constant(constantIndex);
    io::printf("\n");
    return currentOffset+2;
}

fn void Chunk.print_constant(Chunk* this, int index){
    Value* v = &this.constants[index];
    v.debug_print();
}
