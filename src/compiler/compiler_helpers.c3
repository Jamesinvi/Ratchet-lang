module compiler;
import std::io;
import common;
import common::stack;
import std::collections::list;


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

fn void Compiler.error(Compiler* this, String msg){
    this.error_at(this.previous, msg);
}

fn void Compiler.error_at(Compiler* this, Token* token, String msg){
    if(this.panicMode){
        return;
    }
    io::printf("[line %d] Error", token.line);
    this.panicMode=true;

    if(token.tokenType==TokenType.EOF){
        io::printf(" at end");
    }else{
        io::printf(" at '%s'", token.value);
    }
    io::printf(", %s \n", msg);
}

fn void Compiler.compile_byte(Compiler* this, Byte byte, int line){
    this.get_current_chunk().append_to_chunk(byte, line);
}

fn void Compiler.compile_bytes(Compiler* this, Byte byte1, Byte byte2, int line) {
    this.compile_byte(byte1,line);
    this.compile_byte(byte2,line);
}

fn Byte Compiler.ensure_constant(Compiler* this, int constantIndex){
    if(constantIndex > 255){
        this.error("Too many constants in one chunk");
        return 0;
    }
    return (Byte)constantIndex;
}
