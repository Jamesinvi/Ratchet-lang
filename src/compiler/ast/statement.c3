module parser;
import std::collections::list;


enum StmtKind : char
{
    EXPR,   // x;
    ECHO,   // echo(x);
    DECL,   // T x = expr;
    WHILE, 
    IF,
    BLOCK,
    RETURN,
    FOR,    // for(DECL,expr,expr)
}

struct VarDeclStmt  { TypeAst type; NameIdx nameIdx;    ExprIdx init;}
struct IfStmt       { ExprIdx cond; StmtIdx thenBlock;  StmtIdx elseBlock; }
struct WhileStmt    { ExprIdx cond; StmtIdx body; }
struct BlockStmt    { List{StmtIdx} stmts; }
struct RetStmt      { ExprIdx value;}


struct Stmt
{
    StmtKind kind;
    Span span;
    union
    {
        ExprIdx     exprStmt;
        ExprIdx     echoStmt;
        VarDeclStmt varDecl;    // init may be no NO_IDX
        IfStmt      ifStmt;     // else block might NO_IDX (only if exists)
        WhileStmt   whileStmt;  
        BlockStmt   blockStmt;
        RetStmt     retStmt;    // value might be NO_IDX ("return;")
    }
}