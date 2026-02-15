module parser;
import common;
import log;
import std::collections::list;

alias NameIdx = usz;
alias ExprIdx = usz;
alias DeclIdx = usz;
alias StmtIdx = usz;

const NO_IDX = usz.max;

enum DeclKind : char
{
    FUNCTION,
    STRUCT,
}

struct ProgramAst
{
    List{Decl}      declarations;
    List{Stmt}      statements;      // global statement list indexed by nodes
    List{Expr}      expressions;     // global expression list indexed by nodes
    List{String}    names;           // global name list indexed by nodes
	List{ExprIdx}	args;			 // global function argument list, indices into expression list
}

struct ParamAst
{
    TypeAst type;
    NameIdx nameIdx;
    Span span;
}

struct FieldAst
{
    TypeAst type;
    NameIdx nameIdx;
	usz idxInFields;		// index in the StructDeclAst field list
}

struct TypeAst
{
    TokenType tokenType;    // INTEGER_T, INT_REF_GC, IDENTIFIER(for struct type)...
    NameIdx nameIdx;
}

struct FnDeclAst 
{
    TypeAst returnType;
    NameIdx nameIdx;
    List{ParamAst} params;
    StmtIdx body;
}

struct MethodDeclAst 
{
    TypeAst returnType;
    NameIdx nameIdx;
	DeclIdx structIdx;
    List{ParamAst} params;
    StmtIdx body;
}


struct StructDeclAst
{
    NameIdx nameIdx;
    List{FieldAst} fields;
    List{MethodDeclAst} methods;
}

struct Decl
{
    DeclKind kind;
    union
    {
        FnDeclAst       fnDecl;
        StructDeclAst   structDecl;
    }
}


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
    MEMBER,     // a.b
    NEW,        // new
    GROUP,      // (x) optional; often you skip this and just use Span
    THIS,       // used in methods to get borrowed ref
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
struct ExprBinary   { BinOp op;          ExprIdx lhs;    		ExprIdx rhs; }
struct ExprCall     { ExprIdx callee;    ExprIdx argsStart;		ExprIdx argsEnd;  ExprIdx memberCaller;}
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


fn void ProgramAst.init(ProgramAst* this, Allocator allocator)
{
    this.declarations.init(allocator, 1024);
    this.statements.init(allocator, 1024);
    this.expressions.init(allocator, 1024);
    this.names.init(allocator, 1024);
	this.args.init(allocator, 1024);
}

fn void ProgramAst.free(ProgramAst* this, Allocator allocator)
{
	foreach(name : this.names){
		name.free(allocator);
	}
	foreach(decl : this.declarations){
		if(decl.kind == DeclKind.STRUCT){
			foreach(method : decl.structDecl.methods){
				method.params.free();
			}
			decl.structDecl.methods.free();
			decl.structDecl.fields.free();
		}else if (decl.kind == FUNCTION){
			decl.fnDecl.params.free();
		}
	}

	foreach(stmt : this.statements){
		if(stmt.kind == StmtKind.BLOCK){
			stmt.blockStmt.stmts.free();
		}
	}
	
	this.names.free();
	this.declarations.free();
    this.statements.free();
    this.expressions.free();
	this.args.free();
}

fn void ProgramAst.print_indent(ProgramAst* this, int indent)
{
    log::log("%*s", indent, " ");
}

fn void ProgramAst.print(ProgramAst* this)
{
    log::logn("------------Printing Generated AST------------");
    foreach(&declaration : this.declarations){
        this.print_declaration(declaration, 0);
    }
    log::logn("-----------------------------------");
}

fn void ProgramAst.print_declaration(ProgramAst* this, Decl* decl, int indent)
{
	switch(decl.kind)
	{
		case DeclKind.FUNCTION:
		{
			String funcName = this.names[decl.fnDecl.nameIdx];
			String retType = this.names[decl.fnDecl.returnType.nameIdx];
			this.print_indent(indent);
			log::log("fn %s(", funcName);
			foreach(&param : decl.fnDecl.params){
				String paramName = this.names[param.nameIdx];
				String paramType = this.names[param.type.nameIdx];
				log::log("<%s> %s", paramType, paramName);
			}
			log::logn(") returns <%s>", retType);

			Stmt* stmt = &this.statements[decl.fnDecl.body];
			this.print_statement(stmt, indent + 2);
		}
				
		case DeclKind.STRUCT:
		{
			String structName = this.names[decl.structDecl.nameIdx];
			this.print_indent(indent);
			log::logn("struct %s \n{", structName);
			foreach(&field : decl.structDecl.fields){
				String fieldName = this.names[field.nameIdx];
				String fieldType = this.names[field.type.nameIdx];
				this.print_indent(indent+2);
				log::logn("<%s> %s", fieldType, fieldName);
			}
			foreach(&method : decl.structDecl.methods){
				String methodName = this.names[method.nameIdx];
				String retType = this.names[method.returnType.nameIdx];
				Decl structAtIdx = this.declarations[method.structIdx];
				this.print_indent(indent+2);
				log::log("method <%s> %s (", retType, methodName);
				foreach(idx, &param : method.params){
					if(idx > 0) log::log(", ");
					String paramName = this.names[param.nameIdx];
					String paramType = this.names[param.type.nameIdx];
					log::log("<%s> %s", paramType, paramName);
				}
				log::logn(") returns <%s>", retType);
				Stmt* stmt = &this.statements[method.body];
				this.print_statement(stmt, indent + 2);
			}


			log::logn("}");
		}
	}
}

fn void ProgramAst.print_statement(ProgramAst* this, Stmt* stmt, int indent)
{
    switch (stmt.kind)
    {
        case StmtKind.ECHO:
        {
            this.print_indent(indent);
            log::log("echo ");
            this.print_expression(&this.expressions[stmt.echoStmt]);
            log::logn(";");
        }
        case StmtKind.EXPR:
        {
            this.print_indent(indent);
            this.print_expression(&this.expressions[stmt.exprStmt]);
            log::logn(";");
        }
        case StmtKind.RETURN:
        {
            this.print_indent(indent);
            log::log("return");
            if (stmt.retStmt.value != NO_IDX) {
                log::log(" ");
                this.print_expression(&this.expressions[stmt.retStmt.value]);
            }
            log::logn(";");
        }
        case StmtKind.DECL:
        {
            this.print_indent(indent);
            String typeName = this.names[stmt.varDecl.type.nameIdx];
            String name = this.names[stmt.varDecl.nameIdx];
            log::log("<%s> %s", typeName, name);
            if (stmt.varDecl.init != NO_IDX) {
                log::log(" = ");
                this.print_expression(&this.expressions[stmt.varDecl.init]);
            }
            log::logn(";");
        }
        case StmtKind.IF:
        {
            this.print_indent(indent);
            log::log("if (");
            this.print_expression(&this.expressions[stmt.ifStmt.cond]);
            log::logn(") {");
            this.print_statement(&this.statements[stmt.ifStmt.thenBlock], indent + 2);
            this.print_indent(indent);
            log::logn("}");
            if (stmt.ifStmt.elseBlock != NO_IDX) {
                this.print_indent(indent);
                log::logn("else {");
                this.print_statement(&this.statements[stmt.ifStmt.elseBlock], indent + 2);
                this.print_indent(indent);
                log::logn("}");
            }
        }
        case StmtKind.WHILE:
        {
            this.print_indent(indent);
            log::log("while (");
            this.print_expression(&this.expressions[stmt.whileStmt.cond]);
            log::logn(") {");
            this.print_statement(&this.statements[stmt.whileStmt.body], indent + 2);
            this.print_indent(indent);
            log::logn("}");
        }
        case StmtKind.BLOCK:
        {
            this.print_indent(indent);
            log::logn("{");
            foreach(childIdx : stmt.blockStmt.stmts){
                this.print_statement(&this.statements[childIdx], indent + 2);
            }
            this.print_indent(indent);
            log::logn("}");
        }
        default:
        {
            this.print_indent(indent);
            log::logn("// stmt not implemented");
        }
    }
}

fn void ProgramAst.print_expression(ProgramAst* this, Expr* expr)
{
    switch (expr.kind)
    {
        case ExprKind.INT:              log::log("<int> %s", expr.intLiteral);
        case ExprKind.FLOAT:            log::log("<float> %s", expr.floatLiteral);
        case ExprKind.DOUBLE:           log::log("<double> %s", expr.doubleLiteral);
        case ExprKind.BOOL:             log::log("<bool> %s", expr.boolLiteral);
        case ExprKind.NULL:             log::log("<null>");
        case ExprKind.STRING:           log::log("\"%s\"", this.names[expr.stringLiteral]);
		case ExprKind.THIS:             log::log("@this");
        case ExprKind.VAR:              log::log("%s", this.names[expr.varExpr]);
        case ExprKind.UNARY:
        {
            log::log("%s", expr.unary.op.asStr);
            this.print_expression(&this.expressions[expr.unary.rhs]);
        }
        case ExprKind.BINARY:
        {
            log::log("(");
            this.print_expression(&this.expressions[expr.binary.lhs]);
            log::log(" %s ", (expr.binary.op.asStr));
            this.print_expression(&this.expressions[expr.binary.rhs]);
            log::log(")");
        }
        case ExprKind.CALL:
        {
			log::log("call ");
            this.print_expression(&this.expressions[expr.call.callee]);
            log::log("(");
			int counter = 0;
			for(usz i = expr.call.argsStart; i < expr.call.argsEnd; i++) {
                if (counter > 0) log::log(", ");
				ExprIdx argExprIdx = this.args[i];
                this.print_expression(&this.expressions[argExprIdx]);
				counter++;
            }
            log::log(")");
        }
        case ExprKind.MEMBER:
        {
            this.print_expression(&this.expressions[expr.member.base]);
            String member = this.names[expr.member.memberIdx];
            log::log(".%s", member);
        }
        case ExprKind.NEW:
        {
            log::log("new");
			String typeName = this.names[expr.new.type.nameIdx];
			log::log("<%s>", typeName);
        }
        case ExprKind.GROUP:            log::log("(<group>)");
        default:                        log::log("<?expr?>");
    }
}
