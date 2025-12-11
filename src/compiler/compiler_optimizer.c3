module compiler;
import common;


fn void Compiler.maybe_optimize_local_inc_dec(Compiler* this, int slot, int line)
{
    // Chunk* chunk = this.get_current_chunk();

    // // Pattern:
    // //   GET_LOCAL <slot>
    // //   CONSTANT  <cIndex>
    // //   ADD_INT / SUB_INT
    // //   SET_LOCAL <slot>
    // //
    // // bytes: [0] GET_LOCAL
    // //        [1] slot
    // //        [2] CONSTANT
    // //        [3] constIndex
    // //        [4] ADD_INT / SUB_INT
    // //        [5] SET_LOCAL
    // //        [6] slot

    // if (chunk.code.size < 7) return;

    // usz base = (usz)chunk.code.size - 7;
    // Byte op0 = chunk.code[base + 0];
    // Byte s0  = chunk.code[base + 1];
    // Byte op1 = chunk.code[base + 2];
    // Byte cIx = chunk.code[base + 3];
    // Byte op2 = chunk.code[base + 4];
    // Byte op3 = chunk.code[base + 5];
    // Byte s1  = chunk.code[base + 6];

    // // Check shape
    // if (op0 != (Byte)OpCode.GET_LOCAL)   return;
    // if (s0  != (Byte)slot)               return;
    // if (op1 != (Byte)OpCode.CONSTANT)    return;
    // if (op3 != (Byte)OpCode.SET_LOCAL)   return;
    // if (s1  != (Byte)slot)               return;

    // // Const must be integer 1
    // Value constVal = chunk.constants[cIx];
    // if (constVal.type != ValueType.INT)  return;
    // if (constVal.as.intNum != 1)         return;

    // // Decide INC or DEC
    // Byte incOp;
    // if (op2 == (Byte)OpCode.ADD_INT) {
    //     incOp = (Byte)OpCode.INC_LOCAL;
    // } else if (op2 == (Byte)OpCode.SUB_INT) {
    //     incOp = (Byte)OpCode.DEC_LOCAL;
    // } else {
    //     return;
    // }

    // // Rewrite: nuke 7-byte sequence, replace with INC_LOCAL/DEC_LOCAL + slot
    // chunk.code.size = base; // truncate
    // this.compile_bytes(incOp, (Byte)slot, line);
}
