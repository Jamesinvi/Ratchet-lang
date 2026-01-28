module lexer;
import common;
import globals;
import std::collections;
import libc;
import log;

faultdef INVALID_TOKEN;

struct Lexer
{
    String input;
    int line;
    int current;
    int column;
    int start;
}

fn void Lexer.init(Lexer* this, String inputString) {
	this.input = inputString;
    this.line = 1;
    this.current = 0;
    this.column = 0;
    this.start = 0;
}

fn void Lexer.print_tokens(Lexer* this){
    foreach (t : globals::tokens){
		log::logn("[%s: \"%s\"]", t.tokenType, t.value());
    }
}

fn void Lexer.parse_tokens(Lexer* this) {
    while (!this.is_at_end()) {
        this.parse_token();
    }
    this.add_token(TokenType.EOF);

}

fn void Lexer.parse_token(Lexer* this) {
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

fn char Lexer.advance(Lexer* this) {
    return this.input[this.current++];
}

fn bool Lexer.is_at_end(Lexer* this) {
    return this.current >= this.input.len;
}

fn bool Lexer.match_c(Lexer* this, char c) {
    if (this.is_at_end()) return false;
    if (this.peek() == c) {
        this.advance();
        return true;
    }
    return false;
}

fn bool Lexer.match_s(Lexer* this, String str) {
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

fn char Lexer.peek(Lexer* this) {
    if (this.is_at_end()) return '\0';
    return this.input[this.current];
}

fn char Lexer.peek_at(Lexer* this, int distance) {
    if (this.is_at_end()) return '\0';
    return this.input[this.current + distance];
}


fn void Lexer.add_token(Lexer* this, TokenType tokenType) {
    String lexeme = "";
	lexeme = String.copy(this.input[this.start .. this.current -1], &globals::allocator);
	usz tokenValueIdx = globals::tokenValues.len();
	assert(this.start <= this.current);
	assert(this.current <= this.input.len);
	globals::tokenValues.push(lexeme);
    Token token = { tokenType, this.line, tokenValueIdx };
    globals::tokens.push(token);
}


fn void Lexer.string(Lexer* this) {
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

fn void Lexer.number(Lexer* this) {
    bool isDecimal = false;
    bool isFloat   = false;

    while ((common::is_digit(this.peek()) || this.peek() == '.' || this.peek() == 'f') && !this.is_at_end()) {
        if (this.peek() == '.'|| this.peek() == 'f') {
            isDecimal = true;
			if(this.peek() == 'f'){
				isFloat = true;
			}
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

    if (isDecimal) {
        if (isFloat) {this.add_token( TokenType.FLOAT);}
        else{         this.add_token(TokenType.DOUBLE);}
    } else {
        this.add_token(TokenType.INTEGER);
    }
}

fn void Lexer.keyword(Lexer* this) {
    foreach (k : common::keywords) {
        if (this.match_s(k.string)) {
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

fn void error_tok(Token token,  String message) {
    if (token.tokenType == TokenType.EOF) {
        log::errlogn("%d, at end, %s",token.line, message);
    } else {
        log::errlogn("%d, at '%s' %s",token.line, token.value(), message);
    }
}
