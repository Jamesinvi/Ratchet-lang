module compiler;
import common;
alias Token = common::Token;

struct Local
{
    Token name;
    int depth;
    ValueType type;
}