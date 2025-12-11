module compiler;
import common;
import libc;


fn void Compiler.maybe_optimize_local_inc_dec(Compiler* this, int slot, int line)
{
    Chunk* chunk = this.get_current_chunk();

    const int SEQ_LEN = 10; // 3 + 3 + 1 + 3

    if (chunk.code.size < SEQ_LEN) return;

    usz base = (usz)chunk.code.size - SEQ_LEN;

    // Decode pattern:
    // [0] GET_LOCAL, [1..2] slot
    // [3] CONST_INT, [4..5] constOffset
    // [6] ADD_INT/SUB_INT
    // [7] SET_LOCAL, [8..9] slot

    Byte opGet   = chunk.code.[base + 0];
    Byte opConst = chunk.code.[base + 3];
    Byte opMath  = chunk.code.[base + 6];
    Byte opSet   = chunk.code.[base + 7];

    if (opGet   != (Byte)OpCode.GET_LOCAL)  return;
    if (opConst != (Byte)OpCode.CONST_INT)  return;
    if (opSet   != (Byte)OpCode.SET_LOCAL)  return;
    if (opMath  != (Byte)OpCode.ADD_INT)    return;

    ushort slotGet = (ushort) ((chunk.code.[base + 1] << 8) | chunk.code.[base + 2]);
    ushort slotSet = (ushort) ((chunk.code.[base + 8] << 8) | chunk.code.[base + 9]);

    if (slotGet != slot || slotSet != slot) return;

    ushort constOffset = (ushort) ((chunk.code.[base + 4] << 8) | chunk.code[base + 5]);

    // Now read the int value at chunk.constants[constOffset]
    // assuming add_const_int stores a 4-byte int there.
    int value;
    libc::memcpy(&value, &chunk.constants[constOffset], int.sizeof);

    if (value != 1) return;

    // OK, we have "local = local +/- 1;"
    // Truncate the original sequence
    chunk.code.size = base;
    OpCode newOp;

    if(opMath == (Byte)OpCode.ADD_INT){
        newOp = OpCode.INC_LOCAL;
    }else{
        newOp = OpCode.DEC_LOCAL;
    }
        
    this.compile_op_u16(newOp, (ushort)slot, line);
}
