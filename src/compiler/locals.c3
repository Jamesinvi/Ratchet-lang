module parser;
import common;
alias Token = common::Token;

struct Local
{
    Token name;
    int depth;
    ushort slotIdx;
    CompTypeInfo typeInfo;
}