module compiler;
import common;


fn void Compiler.emit_numeric_binary(Compiler* this, OpCode intOp, OpCode floatOp, OpCode doubleOp, int line)
{
    CompTypeInfo right = this.typeStack.pop();
    CompTypeInfo left  = this.typeStack.pop();

    if (left.type != right.type) {
        this.error("Type mismatch in numeric operator.");
        return;
    }

    switch (left.type) {
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
    this.typeStack.push({.type = ValueType.BOOL, .structTypeIndex = uint.max});
}

fn void Compiler.emit_less_equal(Compiler* this, int line)
{
    this.emit_numeric_binary(OpCode.INT_GREATER, OpCode.FLOAT_GREATER, OpCode.DOUBLE_GREATER, line);
    this.emit_op(OpCode.NOT, line);
    this.typeStack.push({.type = ValueType.BOOL, .structTypeIndex = uint.max});
}

fn void Compiler.emit_greater_equal(Compiler* this, int line)
{
    this.emit_numeric_binary(OpCode.INT_LESS, OpCode.FLOAT_LESS, OpCode.DOUBLE_LESS, line);
    this.emit_op(OpCode.NOT, line);
    this.typeStack.push({.type = ValueType.BOOL, .structTypeIndex = uint.max});
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

fn void Compiler.emit_op_u16(Compiler* this, OpCode opCode, ushort opData1, int line)
{
    this.emit_byte((Byte)opCode, line);
    this.emit_u16(opData1, line);
}

fn void Compiler.emit_op_u8_u8_u16(Compiler* this, OpCode opCode, Byte data1, Byte data2, ushort data3, int line)
{
    this.emit_byte((Byte)opCode, line);
    this.emit_byte(data1, line);
    this.emit_byte(data2, line);
    this.emit_u16(data3, line);
}
fn void Compiler.emit_op_u16_u16_u8(Compiler* this, OpCode opCode, ushort data1, ushort data2, Byte data3, int line)
{
    this.emit_byte((Byte)opCode, line);
    this.emit_u16(data1, line);
    this.emit_u16(data2, line);
    this.emit_byte(data3, line);
}

fn void Compiler.emit_op_u16_u16_u16_u8(Compiler* this, OpCode opCode, ushort data1, ushort data2, ushort data3, Byte data4, int line)
{
    this.emit_byte((Byte)opCode, line);
    this.emit_u16(data1, line);
    this.emit_u16(data2, line);
    this.emit_u16(data3, line);
    this.emit_byte(data4, line);
}


fn void Compiler.emit_u16(Compiler* this, ushort val, int line)
{
    this.emit_byte((Byte)(val >> 8), line);   // High byte
    this.emit_byte((Byte)(val & 0xFF), line); // Low byte
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
    CompTypeInfo source = this.typeStack.pop();

    // No-op cast
    if (source.type == targetType) {
        this.warning("Specified cast is between two identical types.");
        this.typeStack.push(source);
        return;
    }

    switch (targetType) {
        case ValueType.INT:
            switch (source.type) {
                case ValueType.FLOAT:       this.emit_byte((Byte)OpCode.CAST_F_I, line);
                case ValueType.DOUBLE:      this.emit_byte((Byte)OpCode.CAST_D_I, line);
                default:                    this.error("Unsupported cast to int.");
            }
            this.typeStack.push({.type = ValueType.INT, .structTypeIndex = uint.max});
            return;

        case ValueType.FLOAT:
            switch (source.type) {
                case ValueType.INT:         this.emit_byte((Byte)OpCode.CAST_I_F, line);
                case ValueType.DOUBLE:      this.emit_byte((Byte)OpCode.CAST_D_F, line);
                default:                    this.error("Unsupported cast to float.");
            }
            this.typeStack.push({.type = ValueType.FLOAT, .structTypeIndex = uint.max});
            return;

        case ValueType.DOUBLE:
            switch (source.type) {
                case ValueType.INT:         this.emit_byte((Byte)OpCode.CAST_I_D, line);
                case ValueType.FLOAT:       this.emit_byte((Byte)OpCode.CAST_F_D, line);
                default:                    this.error("Unsupported cast to double.");
            }
            this.typeStack.push({.type = ValueType.DOUBLE, .structTypeIndex = uint.max});
            return;

        case ValueType.GC_OBJ:
            switch (source.type) {
                case ValueType.INT:         nextcase;
                case ValueType.FLOAT:       nextcase;
                case ValueType.DOUBLE:      nextcase;
                case ValueType.NULL:        nextcase;
                case ValueType.BOOL:        nextcase;
                case ValueType.NO_GC_OBJ:
                    this.emit_byte((Byte)OpCode.CAST_TO_STRING, line);
                    this.emit_byte((Byte)source.type, line);
                    this.typeStack.push({.type = ValueType.GC_OBJ, .structTypeIndex = uint.max});
                    return;

                case ValueType.GC_OBJ:
                    // string -> string is handled above as no-op
                    this.typeStack.push({.type = ValueType.GC_OBJ, .structTypeIndex = uint.max});
                    return;

                default:
                    this.error("Unsupported cast to string.");
                    this.typeStack.push({.type = targetType, .structTypeIndex = uint.max}); // keep stack balanced after error
                    return;
            }

        default:
            this.error("Unsupported cast target type.");
            this.typeStack.push({.type = targetType, .structTypeIndex = uint.max}); 
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
        case ValueType.NULL:        size = 0;
        default:    this.error("emit_pop_of_type: unsupported type");
    }

    this.emit_op_u8(OpCode.POP, size, line);
}
