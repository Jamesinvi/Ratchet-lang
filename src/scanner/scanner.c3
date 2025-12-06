module scanner;
import common;
import std::io;
import std::collections;
import libc;

struct Scanner
{
    String input;
    int line;
    int current;
    int column;
    int start;
    List{Token} tokens;

    TrackingAllocator allocator;
}

fn void Scanner.init(Scanner* this, String inputString) {
    this.allocator.init(mem);
    this.input = String.copy(inputString, &this.allocator);
    this.line = 1;
    this.current = 0;
    this.column = 0;
    this.start = 0;
    this.tokens.init(&this.allocator);
}

fn void Scanner.print_tokens(Scanner* this){
    foreach (t : this.tokens){
        t.debug_print();
    }
}
fn void Scanner.deinit(Scanner* this){
    this.tokens.free();
    this.allocator.free();
}
fn void Scanner.parse_tokens(Scanner* this) {
    while (!this.is_at_end()) {
        this.parse_token();
    }
    this.add_token(TokenType.EOF);
}

fn void Scanner.parse_token(Scanner* this) {
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
            } else if (common::is_alpha_ascii(character)) {
                this.keyword();
            } else {
                common::error_lin(this.line, this.column, "unsupported character");
            }
    }

}

fn char Scanner.advance(Scanner* this) {
    return this.input[this.current++];
}

fn bool Scanner.is_at_end(Scanner* this) {
    return this.current >= this.input.len;
}

fn bool Scanner.match_c(Scanner* this, char c) {
    if (this.is_at_end()) return false;
    if (this.peek() == c) {
        this.advance();
        return true;
    }
    return false;
}

fn bool Scanner.match_s(Scanner* this, String str) {
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

fn char Scanner.peek(Scanner* this) {
    if (this.is_at_end()) return '\0';
    return this.input[this.current];
}

fn void Scanner.add_token(Scanner* this, TokenType tokenType) {
    String lexeme = String.copy(this.input[this.start .. this.current-1], &this.allocator);
    Token token = { tokenType, this.line, lexeme };
    this.tokens.push(token);
}


fn void Scanner.string(Scanner* this) {
    this.start=this.current;
    while (this.peek() != '"' && !this.is_at_end()) {
        if (this.peek() == '\n') {
            this.line += 1;
        }
        this.advance();
    }

    if (this.is_at_end()) {
        common::error_lin(this.line, this.column, "Unterminated string.");
        return;
    }

    this.add_token(TokenType.STRING);
    this.advance();

}

fn void Scanner.number(Scanner* this) {
    bool isDecimal = false;
    bool isFloat   = false;

    while ((common::is_digit(this.peek()) || this.peek() == '.') && !this.is_at_end()) {
        if (this.peek() == '.') {
            isDecimal = true;
        }
        this.advance();
    }

    if (this.is_at_end()) {
        common::error_lin(this.line, this.column, "Unterminated number");
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

fn void Scanner.keyword(Scanner* this) {
    foreach (k : common::keywords) {
        if (this.match_s(k.value)) {
            this.add_token(k.tokenType);
            return;
        }
    }

    while (common::is_alpha_ascii(this.peek())) {
        this.advance();
    }
    this.add_token(TokenType.IDENTIFIER);
}

fn void discard_token() {
}
