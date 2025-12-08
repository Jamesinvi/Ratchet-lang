module compiler;
import std::io;
import common;
import common::stack;
import std::collections::list;
import libc;


fn void Compiler.advance(Compiler* this) {
    this.previous = this.current;
    this.current++;
}

fn void Compiler.consume(Compiler* this, TokenType type, String msg){
    if(this.current.tokenType == type){
        this.advance();
        return;
    }
    this.error(msg);
}

fn bool Compiler.match(Compiler* this, TokenType... tokenTypes){
    foreach (type : tokenTypes){
        if(this.current.tokenType == type){
            this.advance();
            return true;
        }
    }
    return false;
}

fn bool Compiler.check(Compiler* this, TokenType tokenType){
    return this.current.tokenType == tokenType;
}

fn void Compiler.error(Compiler* this, String msg){
    this.error_at(this.previous, msg);
}

fn bool identifiers_equal(Token* a, Token* b)  @inline{
    return strings_equal(a.value,b.value);
}

fn bool strings_equal(String a, String b) {
  if (a.len != b.len) return false;
  return libc::memcmp(a, b, a.len) == 0;
}

fn int resolve_local(ScopeTracker* currentScope, Token* name){
    for (int i = currentScope.localCount - 1; i >= 0; i--) {
        Local* local = &currentScope.locals[i];
        if (identifiers_equal(name, &local.name)) {
            if(local.depth == -1){
                io::printfn("Can't read local var in its initializer");
            }
            return i;
        }
    }

    return -1;
}

fn void Compiler.error_at(Compiler* this, Token* token, String msg){
    if(this.panicMode){
        return;
    }
    io::printf("[line %d] Error", token.line);
    this.hadError=true;
    this.panicMode=true;

    if(token.tokenType==TokenType.EOF){
        io::printf(" at end");
    }else{
        io::printf(" at '%s'", token.value);
    }
    io::printf(", %s \n", msg);
}

fn void Compiler.compile_program_call(Compiler* this){
    // Fake identifier token "program"
    Token name = {.tokenType = TokenType.IDENTIFIER, .value = "program", .line = this.previous.line};
    // Generate `program` as a variable read (global)
    this.named_variable(name, false); // emit GET_GLOBAL "program"

    // CALL with 0 arguments
    this.compile_bytes((Byte)OpCode.CALL, (Byte)0, name.line);

    // Pop the return value (program returns null for now)
    this.compile_byte((Byte)OpCode.POP, name.line);
}

fn void Compiler.compile_byte(Compiler* this, Byte byte, int line){
    this.get_current_chunk().append_to_chunk(byte, line);
}

fn void Compiler.compile_bytes(Compiler* this, Byte byte1, Byte byte2, int line) {
    this.compile_byte(byte1,line);
    this.compile_byte(byte2,line);
}

fn int Compiler.compile_jump(Compiler* this, OpCode opCode, int line) {
    this.compile_byte((Byte)opCode, line);
    this.compile_byte(0xff, line);
    this.compile_byte(0xff, line);
    return (int)this.get_current_chunk().code.size - 2;
}

fn void Compiler.compile_loop(Compiler* this, int loopStart) {
  this.compile_byte((Byte)OpCode.LOOP, this.previous.line);

  int offset = (int)this.get_current_chunk().code.size - loopStart + 2;
  if (offset > ushort.max){
    this.error("Loop body too large.");
  }

  this.compile_byte((Byte)((offset >> 8) & 0xff), this.previous.line);
  this.compile_byte((Byte)((offset) & 0xff), this.previous.line);
}

fn void Compiler.patch_jump(Compiler* this, int offset){
    int jumpLen = (int)this.get_current_chunk().code.size - offset -2;

    if(jumpLen > ushort.max){
        this.error("Jump size too big");
        return;
    }

    this.get_current_chunk().code[offset] = (Byte)(jumpLen >> 8) & 0xff;
    this.get_current_chunk().code[(usz)(offset + 1)] = (Byte)jumpLen & 0xff;
}

fn Byte Compiler.ensure_constant(Compiler* this, int constantIndex){
    if(constantIndex > 255){
        this.error("Too many constants in one chunk");
        return 0;
    }
    return (Byte)constantIndex;
}
