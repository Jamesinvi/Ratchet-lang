module parser;
import std::collections::list;


enum ExprKind : char
{
    INT,
    FLOAT,
    DOUBLE,
    BOOL,
    NULL,
    STRING,
    VAR,        // identifier
    UNARY,      // -x, !x
    BINARY,     // x + y, x * y, ...
    CALL,       // f(a,b)
    MEMBER,      // a.b
    NEW,        // new
    GROUP,      // (x) optional; often you skip this and just use Span
}

enum BinOp : char (String asStr)
{
    ADD         = "add",
    SUB         = "sub", 
    MUL         = "mul", 
    DIV         = "div", 
    EQ          = "eq", 
    NEQ         = "noteq", 
    LESS        = "less", 
    LESS_EQ     = "lesseq", 
    GREATER     = "greater", 
    GREATER_EQ  = "greatereq", 
    AND         = "and", 
    OR          = "or",
    AS          = "as",
    ASSIGN      = "assign",
}

enum UnOp  : char (String asStr)
{ 
    NEG         = "neg",
    NOT         = "not"
}



struct ExprUnary    { UnOp op;           ExprIdx rhs; }
struct ExprBinary   { BinOp op;          ExprIdx lhs;    	ExprIdx rhs; }
struct ExprCall     { ExprIdx callee;    List{ExprIdx} args; }
struct ExprMember   { ExprIdx base;      NameIdx memberIdx; }
struct ExprNew		{ TypeAst type; }

struct Expr
{
    ExprKind kind;
    Span span;
    union
    {
        // Literals
        int         intLiteral;
        float       floatLiteral;
        double      doubleLiteral;
        bool        boolLiteral;
        NameIdx     varExpr;
        NameIdx     stringLiteral;
        // Operation expressions
        ExprUnary   unary;
        ExprBinary  binary;
        ExprCall    call;
        ExprMember  member;
		ExprNew 	new;
    }    
}

fn void ExprCall.init(ExprCall* this, Allocator allocator)
{
    this.args.init(allocator);
}
