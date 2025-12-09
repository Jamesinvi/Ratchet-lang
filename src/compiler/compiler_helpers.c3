module compiler;
import std::io;
import common;
import common::stack;
import std::collections::list;
import libc;

// ---------- Basic token helpers ----------

fn void Compiler.advance(Compiler* this)
{
    this.previous = this.current;
    this.current++;
}

fn void Compiler.consume(Compiler* this, TokenType type, String msg)
{
    if (this.current.tokenType == type) {
        this.advance();
        return;
    }
    this.error(msg);
}

fn bool Compiler.match(Compiler* this, TokenType... tokenTypes)
{
    foreach (type : tokenTypes) {
        if (this.current.tokenType == type) {
            this.advance();
            return true;
        }
    }
    return false;
}

fn bool Compiler.check(Compiler* this, TokenType tokenType)
{
    return this.current.tokenType == tokenType;
}

fn bool Compiler.check_struct_type_token(Compiler* this)
{
    bool typeAlreadyDeclared = common::declaredStructs.has_key(this.current.value);
    return this.check(TokenType.IDENTIFIER) && typeAlreadyDeclared;
}

fn bool Compiler.check_any_type_token(Compiler* this)
{
    return this.check_builtin_type_token() || this.check_struct_type_token();
}


fn bool Compiler.check_builtin_type_token(Compiler* this)
{
    return this.check(TokenType.NULL)      ||
           this.check(TokenType.INTEGER_T) ||
           this.check(TokenType.FLOAT_T)   ||
           this.check(TokenType.STRING_T)  ||
           this.check(TokenType.DOUBLE_T);
}

fn ValueType Compiler.match_type(Compiler* this, String errMsg)
{
    if (this.match(TokenType.NULL)) {
        return ValueType.NULL;
    } else if (this.match(TokenType.INTEGER_T)) {
        return ValueType.INT;
    } else if (this.match(TokenType.FLOAT_T)) {
        return ValueType.FLOAT;
    } else if (this.match(TokenType.DOUBLE_T)) {
        return ValueType.DOUBLE;
    } else if (this.match(TokenType.STRING_T)) {
        return ValueType.GC_OBJ;
    } else if (this.check_struct_type_token()) {
        this.advance();
        return ValueType.STRUCT;
    } else {
        this.error(errMsg);
        return ValueType.NULL;
    }
}

fn uint get_type_index(ValueType type, String name){
    if(type != ValueType.STRUCT){
        return common::NOT_STRUCT;
    }else{
        return common::declaredStructs.get(name)!!;
    }

}

// ---------- Errors ----------

fn void Compiler.error(Compiler* this, String msg)
{
    this.error_at(this.previous, msg);
}

fn void Compiler.error_at(Compiler* this, Token* token, String msg)
{
    if (this.panicMode) return;

    io::printf("[line %d] Error", token.line);
    this.hadError  = true;
    this.panicMode = true;

    if (token.tokenType == TokenType.EOF) {
        io::printf(" at end");
    } else {
        io::printf(" at '%s'", token.value);
    }
    io::printf(", %s \n", msg);
}

// ---------- Identifier helpers ----------

fn bool identifiers_equal(Token* a, Token* b) @inline
{
    return strings_equal(a.value, b.value);
}

fn bool strings_equal(String a, String b)
{
    if (a.len != b.len) return false;
    return libc::memcmp(a, b, a.len) == 0;
}

fn int resolve_local(ScopeTracker* currentScope, Token* name)
{
    for (int i = currentScope.localCount - 1; i >= 0; i--) {
        Local* local = &currentScope.locals[i];
        if (identifiers_equal(name, &local.name)) {
            if (local.depth == -1) {
                io::printfn("Can't read local var in its initializer");
            }
            return i;
        }
    }
    return -1;
}

fn int resolve_local_index(ScopeTracker* currentScope, Token* name)
{
    for (int i = currentScope.localCount - 1; i >= 0; i--) {
        Local* local = &currentScope.locals[i];
        if (identifiers_equal(name, &local.name)) {
            return i;
        }
    }
    return -1;
}

// ---------- Program entry ----------

fn void Compiler.compile_program_call(Compiler* this)
{
    Token name = {.tokenType = TokenType.IDENTIFIER, .value = "program", .line = this.previous.line};

    this.named_variable(name, false);
    this.compile_bytes((Byte)OpCode.CALL, (Byte)0, name.line);
    this.compile_byte((Byte)OpCode.POP, name.line);
}

// ---------- Bytecode helpers ----------

fn void Compiler.compile_byte(Compiler* this, Byte byte, int line)
{
    this.get_current_chunk().append_to_chunk(byte, line);
}

fn void Compiler.compile_bytes(Compiler* this, Byte byte1, Byte byte2, int line)
{
    this.compile_byte(byte1, line);
    this.compile_byte(byte2, line);
}

fn int Compiler.compile_jump(Compiler* this, OpCode opCode, int line)
{
    this.compile_byte((Byte)opCode, line);
    this.compile_byte(0xff, line);
    this.compile_byte(0xff, line);
    return (int)this.get_current_chunk().code.size - 2;
}

fn void Compiler.compile_loop(Compiler* this, int loopStart)
{
    this.compile_byte((Byte)OpCode.LOOP, this.previous.line);

    int offset = (int)this.get_current_chunk().code.size - loopStart + 2;
    if (offset > ushort.max) {
        this.error("Loop body too large.");
    }

    this.compile_byte((Byte)((offset >> 8) & 0xff), this.previous.line);
    this.compile_byte((Byte)((offset) & 0xff), this.previous.line);
}

fn void Compiler.patch_jump(Compiler* this, int offset)
{
    int jumpLen = (int)this.get_current_chunk().code.size - offset - 2;

    if (jumpLen > ushort.max) {
        this.error("Jump size too big");
        return;
    }

    this.get_current_chunk().code[offset]         = (Byte)((jumpLen >> 8) & 0xff);
    this.get_current_chunk().code[(usz)(offset+1)] = (Byte)(jumpLen & 0xff);
}

fn void Compiler.compile_cast(Compiler* this, ValueType targetType, int line)
{
    ValueType source = this.typeStack.pop();

    // No-op cast
    if (source == targetType) {
        this.typeStack.push(source);
        return;
    }

    switch (targetType) {
        case ValueType.INT:
            switch (source) {
                case ValueType.FLOAT:
                    this.compile_byte((Byte)OpCode.CAST_F_I, line);
                case ValueType.DOUBLE:
                    this.compile_byte((Byte)OpCode.CAST_D_I, line);
                case ValueType.GC_OBJ:  nextcase;
                default:
                    this.error("Unsupported cast to int.");
            }
            this.typeStack.push(ValueType.INT);
            return;

        case ValueType.FLOAT:
            switch (source) {
                case ValueType.INT:
                    this.compile_byte((Byte)OpCode.CAST_I_F, line);
                case ValueType.DOUBLE:
                    this.compile_byte((Byte)OpCode.CAST_D_F, line);
                case ValueType.GC_OBJ:  nextcase;
                default:
                    this.error("Unsupported cast to float.");
            }
            this.typeStack.push(ValueType.FLOAT);
            return;

        case ValueType.DOUBLE:
            switch (source) {
                case ValueType.INT:
                    this.compile_byte((Byte)OpCode.CAST_I_D, line);
                case ValueType.FLOAT:
                    this.compile_byte((Byte)OpCode.CAST_F_D, line);
                case ValueType.GC_OBJ:  nextcase;
                default:
                    this.error("Unsupported cast to double.");
            }
            this.typeStack.push(ValueType.DOUBLE);
            return;

        case ValueType.GC_OBJ: // string
            switch (source) {
                case ValueType.INT:
                case ValueType.FLOAT:
                case ValueType.DOUBLE:
                case ValueType.NULL:
                case ValueType.BOOL:
                case ValueType.NO_GC_OBJ:
                    // Generic "value → string" op
                    this.compile_byte((Byte)OpCode.CAST_TO_STRING, line);
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



fn Byte Compiler.ensure_constant(Compiler* this, int constantIndex)
{
    if (constantIndex > 255) {
        this.error("Too many constants in one chunk");
        return 0;
    }
    return (Byte)constantIndex;
}

// ---------- Predeclaration for functions / natives ----------

fn ValueType token_type_to_value_type(TokenType t)
{
    switch (t) {
        case TokenType.NULL:      return ValueType.NULL;
        case TokenType.INTEGER_T: return ValueType.INT;
        case TokenType.FLOAT_T:   return ValueType.FLOAT;
        case TokenType.DOUBLE_T:  return ValueType.DOUBLE;
        default:                  return ValueType.NULL;
    }
}

fn void Compiler.predeclare_functions(Compiler* this)
{
    int count = (int)this.input.len();

    // Look for patterns: FN <type> <identifier>
    for (int i = 0; i < count - 2; i++) {
        Token* t = &this.input[i];
        if (t.tokenType == TokenType.FN) {
            Token* typeTok = &this.input[(usz)i + 1];
            Token* nameTok = &this.input[(usz)i + 2];

            ValueType ret = token_type_to_value_type(typeTok.tokenType);
            this.functionReturnTypes.set(nameTok.value, ret);
        }
    }
}

fn void Compiler.predeclare_natives(Compiler* this)
{
    // Keep this in sync with VM native registrations
    this.functionReturnTypes.set("clock", ValueType.DOUBLE);
}
