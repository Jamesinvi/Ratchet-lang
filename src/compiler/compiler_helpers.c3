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

fn void Compiler.warning(Compiler* this, String msg)
{
    this.warning_at(this.previous, msg);
}

fn void Compiler.warning_at(Compiler* this, Token* token, String msg)
{
    if (this.panicMode) return;

    io::eprintf("[line %d] Warning", token.line);
    io::eprintf(" at '%s'", token.value);
    io::eprintf(", %s \n", msg);
}


fn void Compiler.error(Compiler* this, String msg)
{
    this.error_at(this.previous, msg);
}

fn void Compiler.error_at(Compiler* this, Token* token, String msg)
{
    if (this.panicMode) return;

    io::eprintf("[line %d] Error", token.line);
    this.hadError  = true;
    this.panicMode = true;

    if (token.tokenType == TokenType.EOF) {
        io::eprintf(" at end");
    } else {
        io::eprintf(" at '%s'", token.value);
    }
    io::eprintf(", %s \n", msg);
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

fn int Compiler.resolve_local(Compiler* this, Token* name)
{
    for (int i = this.currentScope.localCount - 1; i >= 0; i--) {
        Local* local = &this.currentScope.locals[i];
        if (identifiers_equal(name, &local.name)) {
            if (local.depth == -1) {
                this.error("Can't read local var in its initializer");
                return -1;
            }
            return i;
        }
    }
    return -1;
}

// ---------- Program entry ----------

fn void Compiler.emit_program_call(Compiler* this)
{
    Token name = {.tokenType = TokenType.IDENTIFIER, .value = "program", .line = this.previous.line};

    this.named_variable(name, false);
    this.emit_op_u8(OpCode.CALL, 0, name.line);
}

// ---------- Bytecode helpers ----------

fn ushort Compiler.ensure_constant(Compiler* this, int constantIndex)
{
    if (constantIndex > ushort.max) {
        this.error("Too many constants in one chunk");
        return 0;
    }
    return (ushort)constantIndex;
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
