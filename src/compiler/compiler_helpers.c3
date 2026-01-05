module compiler;
import common;
import common::stack;
import std::collections::list;
import libc;
import debug;
import log;


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
    return token_matches(this.current ,tokenType);
}

fn bool token_matches(Token* t1, TokenType toCheck) @inline
{
    return t1.tokenType == toCheck;
}

fn bool Compiler.check_struct_type_token(Compiler* this)
{
    bool typeAlreadyDeclared = declaredStructs.has_key(this.current.value);
    return this.check(TokenType.IDENTIFIER) && typeAlreadyDeclared;
}

fn bool Compiler.check_any_type_token(Compiler* this)
{
    return  this.check_builtin_type_token()         ||
            this.check_struct_type_token()          ||
            this.check_builtin_type_tracked_refs()  ||
            this.check_builtin_type_untracked_refs()||
            this.check_struct_type_refs('&')        ||
            this.check_struct_type_refs('*');
    }

fn bool Compiler.check_builtin_type_token(Compiler* this)
{
    return this.check(TokenType.NULL)      ||
           this.check(TokenType.INTEGER_T) ||
           this.check(TokenType.FLOAT_T)   ||
           this.check(TokenType.DOUBLE_T)  ||
           this.check(TokenType.BOOL_T)    ||
           this.check(TokenType.STRING_T);
}

fn bool Compiler.check_builtin_type_tracked_refs(Compiler* this)
{
    return this.check(TokenType.INT_REF_GC)     ||
           this.check(TokenType.FLOAT_REF_GC)   ||
           this.check(TokenType.DOUBLE_REF_GC)  ||
           this.check(TokenType.BOOL_REF_GC);
}

fn bool Compiler.check_builtin_type_untracked_refs(Compiler* this)
{
    return this.check(TokenType.INT_REF_NOGC)     ||
           this.check(TokenType.FLOAT_REF_NOGC)   ||
           this.check(TokenType.DOUBLE_REF_NOGC)  ||
           this.check(TokenType.BOOL_REF_NOGC);
}

fn ValueType builtin_ref_to_type(Token* tok) {
    if (tok.tokenType == INT_REF_GC     || tok.tokenType == INT_REF_NOGC)   return ValueType.INT;
    if (tok.tokenType == FLOAT_REF_GC   || tok.tokenType == FLOAT_REF_NOGC) return ValueType.FLOAT;
    if (tok.tokenType == DOUBLE_REF_GC  || tok.tokenType == DOUBLE_REF_NOGC)   return ValueType.DOUBLE;
    if (tok.tokenType == BOOL_REF_GC    || tok.tokenType == BOOL_REF_NOGC)  return ValueType.BOOL;
    // if (tok.tokenType == STRING_REF_GC || tok.tokenType == STRING_REF_NOGC)  return ValueType.GC_OBJ;
    return ValueType.NULL;
}


fn bool Compiler.check_struct_type_refs(Compiler* this, char trailingChar)
{
    bool anyMatch = false;
    @pool()
    {
        foreach(structType : structTypes){
            String trailingString = {trailingChar};
            String refStructname = structType.name.tconcat(trailingString);
            if(strings_equal(this.current.value, refStructname) ){
                return true;
            }
        }
    };
    return false;
}

fn CompTypeInfo Compiler.match_type(Compiler* this, String errMsg)
{
    debug::@log_compilation("searching for a matching type for '%s'", this.current.value);
    CompTypeInfo result = {};
    result.structTypeIndex = uint.max;
    if (this.match(TokenType.NULL))             { result.type = ValueType.NULL;}
    else if (this.match(TokenType.INTEGER_T))   { result.type = ValueType.INT;}
    else if (this.match(TokenType.FLOAT_T))     { result.type = ValueType.FLOAT;}
    else if (this.match(TokenType.DOUBLE_T))    { result.type = ValueType.DOUBLE;}
    else if (this.match(TokenType.BOOL_T))      { result.type = ValueType.BOOL;}
    else if (this.match(TokenType.STRING_T))    { result.type = ValueType.GC_OBJ;}
    else if (this.check_struct_type_token()) {
        this.advance();
        result.type = ValueType.STRUCT;
        result.structTypeIndex = declaredStructs[this.previous.value]!!;
    }   
    else if (this.check_builtin_type_tracked_refs()) {
        this.advance();
        result.type = ValueType.GC_OBJ;
        result.structTypeIndex = uint.max;
        result.refToType = builtin_ref_to_type(this.previous);
    }   
    else if (this.check_builtin_type_untracked_refs()) {
        this.advance();
        result.type = ValueType.NO_GC_OBJ;
        result.structTypeIndex = uint.max;
        result.refToType = builtin_ref_to_type(this.previous);
    } 
    else if (this.check_struct_type_refs('&')) {
        this.advance();
        result.type = ValueType.GC_OBJ;
        result.refToType = ValueType.STRUCT;
        result.structTypeIndex = declaredStructs[this.previous.value[0..this.previous.value.len-2]]!!;
    } 
    else if (this.check_struct_type_refs('*')) {
        this.advance();
        result.type = ValueType.NO_GC_OBJ;
        result.refToType = ValueType.STRUCT;
        result.structTypeIndex = declaredStructs[this.previous.value[0..this.previous.value.len-2]]!!;
    }  else {
        this.error(errMsg);
        result.type = ValueType.NULL;
    }
    return result;
}

fn uint get_type_index(ValueType type, String name){
    if(type != ValueType.STRUCT){
        return NOT_STRUCT;
    }else{
        return declaredStructs.get(name)!!;
    }

}

// ---------- Errors / Debug ----------

fn void Compiler.warning(Compiler* this, String msg)
{
    this.warning_at(this.previous, msg);
}

fn void Compiler.warning_at(Compiler* this, Token* token, String msg)
{
    if (this.panicMode) return;

    log::errlog("[line %d] Warning", token.line);
    log::errlog(" at '%s'", token.value);
    log::errlog(", %s \n", msg);
}

fn void Compiler.error(Compiler* this, String msg, args ...)
{
    this.error_at(this.previous, msg, ...args);
}

fn void Compiler.error_at(Compiler* this, Token* token, String msg, args ...)
{
    if (this.panicMode) return;

    log::errlog("[line %d] Error", token.line);
    this.hadError  = true;
    this.panicMode = true;

    if (token.tokenType == TokenType.EOF) {
        log::errlog(" at end, ");
    } else {
        log::errlog(" at '%s', ", token.value);
    }

    log::errlogn(msg, ...args);

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
    this.emit_u16(0, name.line);
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

// ---------- Predeclaration for functions / structs / natives ----------

fn CompTypeInfo token_to_value_type_info(Token* t)
{
    CompTypeInfo result = {};
    result.structTypeIndex = uint.max;
    switch (t.tokenType) {
        case TokenType.NULL:            result.type = ValueType.NULL;
        case TokenType.INTEGER_T:       result.type = ValueType.INT;
        case TokenType.FLOAT_T:         result.type = ValueType.FLOAT;
        case TokenType.DOUBLE_T:        result.type = ValueType.DOUBLE;
        case TokenType.BOOL_T:          result.type = ValueType.BOOL;
        case TokenType.STRING:          result.type = ValueType.GC_OBJ;
        case TokenType.INT_REF_GC:      nextcase;
        case TokenType.INT_REF_NOGC:    result.type = ValueType.GC_OBJ; result.refToType = ValueType.INT;
        case TokenType.FLOAT_REF_GC:    nextcase;
        case TokenType.FLOAT_REF_NOGC:  result.type = ValueType.GC_OBJ; result.refToType = ValueType.FLOAT;
        case TokenType.DOUBLE_REF_GC:   nextcase;
        case TokenType.DOUBLE_REF_NOGC: result.type = ValueType.GC_OBJ; result.refToType = ValueType.DOUBLE;
        case TokenType.BOOL_REF_GC:     nextcase;
        case TokenType.BOOL_REF_NOGC:   result.type = ValueType.GC_OBJ; result.refToType = ValueType.BOOL;
        default:{
            // Try structs:
            uint? index = declaredStructs.get(t.value);
            if(catch notFound = index){
                // Structs not found, try references to structs
                char lastChar = t.value[t.value.len-1];
                if(!common::is_ref_char(lastChar)){
                    log::errlogn("Didn't find any type matching for %s", t.value);
                    break;
                }
                String tokenTypeToLastChar = t.value[0 .. t.value.len-2];
                uint? indexWithoutLastChar = declaredStructs.get(tokenTypeToLastChar);
                if(catch refTypeNotFound = indexWithoutLastChar){
                    log::errlogn("Didn't find any type matching for %s", t.value);
                    break;
                }
                result.type = lastChar == '&' ? ValueType.GC_OBJ : ValueType.NO_GC_OBJ;
                result.refToType = ValueType.STRUCT;
                result.structTypeIndex = indexWithoutLastChar;
                return result;
            }
            result.type = ValueType.STRUCT;
            result.structTypeIndex = index;
        }
    }
    return result;
}

fn void Compiler.predeclare_struct_names(Compiler* this)
{
    // Look for patterns: STRUCT <identifier>
    for (usz i = 0; i < this.input.len(); i++) {
        if (this.input[i].tokenType != TokenType.STRUCT_T) {
            continue;
        }
        if (i + 1 >= this.input.size){
            break;
        } 

        Token nameTok = this.input[i + 1];
        if (nameTok.tokenType != TokenType.IDENTIFIER) {
            continue;
        }

        String name = nameTok.value;

        if (!declaredStructs.has_key(name)) {
            // reserve an index so function signatures can refer to it
            uint idx = (uint)structTypes.size;

            CompStructTypeInfo placeholder = {};
            placeholder.init();
            placeholder.name = String.copy(name, mem);
            placeholder.sizeInBytes = 0;
            placeholder.fieldCount = 0;

            structTypes.push(placeholder);
            declaredStructs.set(name, idx);
        }
    }
}

fn void Compiler.predeclare_functions(Compiler* this)
{
    // Look for patterns: FN <type> <identifier>
    for (usz i = 0; i < this.input.len() - 2; i++) {
        Token* t = &this.input[i];
        if (t.tokenType == TokenType.FN) {
            Token* typeTok = &this.input[i + 1];
            Token* nameTok = &this.input[i + 2];

            CompTypeInfo ret = token_to_value_type_info(typeTok);
            this.functionReturnTypes.set(nameTok.value, ret);
            debug::@log_compilation("pre-declaring function '%s' with return type {%s, (ref to)%s}", nameTok.value, ret.type, ret.refToType);
        }
    }
}

fn void Compiler.predeclare_natives(Compiler* this)
{
    // Keep this in sync with VM native registrations
    this.functionReturnTypes.set("clock", {.type = ValueType.DOUBLE, .structTypeIndex = uint.max});
}
