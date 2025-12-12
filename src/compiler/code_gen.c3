module compiler;
import common;


fn void Compiler.emit_numeric_binary(Compiler* this, OpCode intOp, OpCode floatOp, OpCode doubleOp, int line)
{
    ValueType right = this.typeStack.pop();
    ValueType left  = this.typeStack.pop();

    if (left != right) {
        this.error("Type mismatch in numeric operator.");
        return;
    }

    switch (left) {
        case ValueType.INT:         this.emit_op(intOp, line);
        case ValueType.FLOAT:       this.emit_op(floatOp, line);
        case ValueType.DOUBLE:      this.emit_op(doubleOp, line);
        default:                    this.error("Unsupported numeric operand type");
    }

    this.typeStack.push(left);
}

fn void Compiler.emit_not_equal(Compiler* this, int line)
{
    this.emit_numeric_binary(OpCode.INT_EQUAL, OpCode.FLOAT_EQUAL, OpCode.DOUBLE_EQUAL, line);
    this.emit_op(OpCode.NOT, line);
    this.typeStack.push(ValueType.BOOL);
}

fn void Compiler.emit_less_equal(Compiler* this, int line)
{
    this.emit_numeric_binary(OpCode.INT_GREATER, OpCode.FLOAT_GREATER, OpCode.DOUBLE_GREATER, line);
    this.emit_op(OpCode.NOT, line);
    this.typeStack.push(ValueType.BOOL);
}

fn void Compiler.emit_greater_equal(Compiler* this, int line)
{
    this.emit_numeric_binary(OpCode.INT_LESS, OpCode.FLOAT_LESS, OpCode.DOUBLE_LESS, line);
    this.emit_op(OpCode.NOT, line);
    this.typeStack.push(ValueType.BOOL);
}

fn void Compiler.emit_byte(Compiler* this, Byte byte, int line)
{
    this.get_current_chunk().append_to_chunk(byte, line);
}

fn void Compiler.emit_ops(Compiler* this, OpCode op1, OpCode op2, int line)
{
    this.emit_byte((Byte)op1, line);
    this.emit_byte((Byte)op2, line);
}

fn void Compiler.emit_op(Compiler* this, OpCode op1, int line)
{
    this.emit_byte((Byte)op1, line);
}

fn void Compiler.emit_op_u16(Compiler* this, OpCode opCode, ushort operandIndex, int line)
{
    this.emit_byte((Byte)opCode, line);
    this.emit_u16(operandIndex, line);
}

fn void Compiler.emit_u16(Compiler* this, ushort val, int line)
{
    this.emit_byte((Byte)val >> 8, line);   // High byte
    this.emit_byte((Byte)val & 0xFF, line); // Low byte
}

fn void Compiler.emit_op_u8(Compiler* this, OpCode opCode, Byte byte, int line)
{
    this.emit_byte((Byte)opCode, line);
    this.emit_byte(byte, line);
}


fn int Compiler.emit_jump(Compiler* this, OpCode opCode, int line)
{
    this.emit_byte((Byte)opCode, line);
    // Temporary offset, will need to be patched.
    this.emit_byte(0xff, line);
    this.emit_byte(0xff, line);
    return (int)this.get_current_chunk().code.size - 2;
}

fn void Compiler.emit_loop(Compiler* this, int loopStart)
{
    // Loop BACK to specified point. 3 is the size of this instruction
    int offset = (int)this.get_current_chunk().code.size + 3 - loopStart; 

    if (offset > ushort.max) {
        this.error("Loop body too large.");
    }
    this.emit_op_u16(OpCode.LOOP, (ushort)offset, this.previous.line);
}

fn void Compiler.patch_jump(Compiler* this, int offset)
{
    int jumpLen = (int)this.get_current_chunk().code.size - offset - 2;

    if (jumpLen > ushort.max) {
        this.error("Jump size too big");
        return;
    }

    // High byte
    this.get_current_chunk().code[offset] = (Byte)((jumpLen >> 8) & 0xff);
    // Low byte
    this.get_current_chunk().code[(usz)(offset+1)] = (Byte)(jumpLen & 0xff);
}

fn void Compiler.emit_cast(Compiler* this, ValueType targetType, int line)
{
    ValueType source = this.typeStack.pop();

    // No-op cast
    if (source == targetType) {
        this.warning("Specified cast is between two identical types.");
        this.typeStack.push(source);
        return;
    }

    switch (targetType) {
        case ValueType.INT:
            switch (source) {
                case ValueType.FLOAT:       this.emit_byte((Byte)OpCode.CAST_F_I, line);
                case ValueType.DOUBLE:      this.emit_byte((Byte)OpCode.CAST_D_I, line);
                default:                    this.error("Unsupported cast to int.");
            }
            this.typeStack.push(ValueType.INT);
            return;

        case ValueType.FLOAT:
            switch (source) {
                case ValueType.INT:         this.emit_byte((Byte)OpCode.CAST_I_F, line);
                case ValueType.DOUBLE:      this.emit_byte((Byte)OpCode.CAST_D_F, line);
                default:                    this.error("Unsupported cast to float.");
            }
            this.typeStack.push(ValueType.FLOAT);
            return;

        case ValueType.DOUBLE:
            switch (source) {
                case ValueType.INT:         this.emit_byte((Byte)OpCode.CAST_I_D, line);
                case ValueType.FLOAT:       this.emit_byte((Byte)OpCode.CAST_F_D, line);
                default:                    this.error("Unsupported cast to double.");
            }
            this.typeStack.push(ValueType.DOUBLE);
            return;

        case ValueType.GC_OBJ:
            switch (source) {
                case ValueType.INT:         nextcase;
                case ValueType.FLOAT:       nextcase;
                case ValueType.DOUBLE:      nextcase;
                case ValueType.NULL:        nextcase;
                case ValueType.BOOL:        nextcase;
                case ValueType.NO_GC_OBJ:
                    this.emit_byte((Byte)OpCode.CAST_TO_STRING, line);
                    this.emit_byte((Byte)source, line);
                    this.typeStack.push(ValueType.GC_OBJ);
                    return;

                case ValueType.GC_OBJ:
                    // string -> string is handled above as no-op
                    this.typeStack.push(ValueType.GC_OBJ);
                    return;

                default:
                    this.error("Unsupported cast to string.");
                    this.typeStack.push(targetType); // keep stack balanced after error
                    return;
            }

        default:
            this.error("Unsupported cast target type.");
            this.typeStack.push(targetType);
            return;
    }
}


fn void Compiler.emit_pop_of_type(Compiler* this, ValueType t, int line)
{
    Byte size = 0;
    switch (t) {
        case ValueType.INT:         size = (Byte)int.sizeof;
        case ValueType.FLOAT:       size = (Byte)float.sizeof;
        case ValueType.DOUBLE:      size = (Byte)double.sizeof;
        case ValueType.BOOL:        size = (Byte)bool.sizeof;
        case ValueType.GC_OBJ:      nextcase;
        case ValueType.NO_GC_OBJ:   size = (Byte)uptr.sizeof;
        case ValueType.NULL:        size = 1;
        default:    this.error("emit_pop_of_type: unsupported type");
    }

    this.emit_op_u8(OpCode.POP, size, line);
}
