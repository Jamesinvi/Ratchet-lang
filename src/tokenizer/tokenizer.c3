module tokenizer;
import common;
import std::collections;
import libc;
import log;

faultdef INVALID_TOKEN;

struct Tokenizer
{
    String input;
    int line;
    int current;
    int column;
    int start;
    List{Token} tokens;

    TrackingAllocator allocator;
}

fn void Tokenizer.init(Tokenizer* this, String inputString) {
    this.allocator.init(mem);
    this.input = String.copy(inputString, &this.allocator);
    this.line = 1;
    this.current = 0;
    this.column = 0;
    this.start = 0;
    this.tokens.init(&this.allocator);
}

fn void Tokenizer.print_tokens(Tokenizer* this){
    foreach (t : this.tokens){
        t.debug_print();
    }
}
fn void Tokenizer.deinit(Tokenizer* this)
{
    foreach (t : this.tokens) {
        t.value.free(&this.allocator);
    }
    this.tokens.free();
    this.input.free(&this.allocator);
    this.allocator.free();
}

fn void Tokenizer.parse_tokens(Tokenizer* this) {
    while (!this.is_at_end()) {
        this.parse_token();
    }
    this.add_token(TokenType.EOF);
}

fn void Tokenizer.parse_token(Tokenizer* this) {
    this.start = this.current;
    char character = this.advance();
    this.column += 1;

    switch (character) {
        case ' '  : discard_token();
        case '\r' : discard_token();
        case '\t' : discard_token();
        case '('  : this.add_token(TokenType.LEFT_PAREN);
        case ')'  : this.add_token(TokenType.RIGHT_PAREN);
        case '+'  : this.add_token(TokenType.PLUS);
        case '-'  : this.add_token(TokenType.MINUS);
        case '*'  : this.add_token(TokenType.STAR);
        case ';'  : this.add_token(TokenType.SEMICOLON);
        case '{'  : this.add_token(TokenType.LEFT_BRACE);
        case '}'  : this.add_token(TokenType.RIGHT_BRACE);
        case ','  : this.add_token(TokenType.COMMA);
        case '.'  : this.add_token(TokenType.DOT);
        case '<'  : this.add_token(this.match_c('=') ? TokenType.LESS_EQUAL    : TokenType.LESS);
        case '>'  : this.add_token(this.match_c('=') ? TokenType.GREATER_EQUAL : TokenType.GREATER);
        case '!'  : this.add_token(this.match_c('=') ? TokenType.BANG_EQUAL    : TokenType.BANG);
        case '='  : this.add_token(this.match_c('=') ? TokenType.EQUAL_EQUAL   : TokenType.EQUAL);
        case '"'  : this.string();
        case '/'  :
            if (this.match_c('/')) {
                while (this.peek() != '\n' && !this.is_at_end()) {
                    this.advance();
                }
            } else {
                this.add_token(TokenType.SLASH);
            }
            return;

        case '\n' :
            this.line += 1;
            this.column = 0;
            discard_token();

        default:
            if (common::is_digit(character)) {
                this.number();
            } else if (common::is_alpha_ascii(character) || common::is_ref_char(character)) {
                this.keyword();
            } else {
                error_lin(this.line, this.column, "unsupported character");
            }
    }

}

fn char Tokenizer.advance(Tokenizer* this) {
    return this.input[this.current++];
}

fn bool Tokenizer.is_at_end(Tokenizer* this) {
    return this.current >= this.input.len;
}

fn bool Tokenizer.match_c(Tokenizer* this, char c) {
    if (this.is_at_end()) return false;
    if (this.peek() == c) {
        this.advance();
        return true;
    }
    return false;
}

fn bool Tokenizer.match_s(Tokenizer* this, String str) {
    if (this.is_at_end()) return false;

    int indexBeforeMatch = this.current;
    this.current--;
    foreach (letter : str) {
        if (this.peek() != letter) {
            this.current = indexBeforeMatch;
            return false;
        }
        this.advance();
    }


    char nextChar = this.peek();
    if (nextChar != '\0' && common::is_alpha_ascii(nextChar)) {
        this.current = indexBeforeMatch;
        return false;
    }

    return true;
}

fn char Tokenizer.peek(Tokenizer* this) {
    if (this.is_at_end()) return '\0';
    return this.input[this.current];
}

fn char Tokenizer.peek_at(Tokenizer* this, int distance) {
    if (this.is_at_end()) return '\0';
    return this.input[this.current + distance];
}


fn void Tokenizer.add_token(Tokenizer* this, TokenType tokenType) {
    String lexeme = String.copy(this.input[this.start .. this.current-1], &this.allocator);
    Token token = { tokenType, this.line, lexeme };
    this.tokens.push(token);
}


fn void Tokenizer.string(Tokenizer* this) {
    this.start=this.current;
    while (this.peek() != '"' && !this.is_at_end()) {
        if (this.peek() == '\n') {
            this.line += 1;
        }
        this.advance();
    }

    if (this.is_at_end()) {
        error_lin(this.line, this.column, "Unterminated string.");
        return;
    }

    this.add_token(TokenType.STRING);
    this.advance();

}

fn void Tokenizer.number(Tokenizer* this) {
    bool isDecimal = false;
    bool isFloat   = false;

    while ((common::is_digit(this.peek()) || this.peek() == '.') && !this.is_at_end()) {
        if (this.peek() == '.') {
            isDecimal = true;
        }
        this.advance();
    }

    // If a letter immediately follows a number literal: 123abc → error
    if (common::is_alpha_ascii(this.peek()) && this.peek()!='f') {
        error_lin(this.line, this.column, "Number literal cannot be immediately followed by letters");
        return;
    }

    if (this.is_at_end()) {
        error_lin(this.line, this.column, "Unterminated number");
        return;
    }

    if (this.peek() == 'f') {
        isFloat = true;
        this.advance();
    }

    if (isDecimal) {
        if (isFloat) {this.add_token( TokenType.FLOAT);}
        else{         this.add_token(TokenType.DOUBLE);}
    } else {
        this.add_token(TokenType.INTEGER);
    }
}

fn void Tokenizer.keyword(Tokenizer* this) {
    foreach (k : common::keywords) {
        if (this.match_s(k.value)) {
            this.add_token(k.tokenType);
            return;
        }
    }

    while (common::is_alpha_ascii(this.peek()) || common::is_digit(this.peek()) || common::is_ref_char(this.peek())) {
        this.advance();
    }
    this.add_token(TokenType.IDENTIFIER);
}

fn void discard_token() {
}


fn void error_lin(int l, int c, String msg) {
    log::errlogn("Error on line: %d:%d, %s", l, c, msg);
}

fn void error_tok(Token token, String message) {
    if (token.tokenType == TokenType.EOF) {
        log::errlogn("%d, at end, %s",token.line, message);
    } else {
        log::errlogn("%d, at '%s' %s",token.line, token.value, message);
    }
}