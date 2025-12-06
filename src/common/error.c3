module common;
import std::io;

faultdef INVALID_TOKEN;

fn void error_lin(int l, int c, String msg) {
    io::printfn("Error on line: %d:%d, %s", l, c, msg);
}

fn void error_tok(Token token, String message) {
    if (token.tokenType == TokenType.EOF) {
        io::printfn("%d, at end, %s",token.line, message);
    } else {
        io::printfn("%d, at '%s' %s",token.line, token.value, message);
    }
}