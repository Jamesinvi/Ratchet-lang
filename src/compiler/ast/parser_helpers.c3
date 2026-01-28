module parser;
import common;
import globals;
import common::stack;
import std::collections::list;
import libc;
import debug;
import log;


// ---------- Basic token helpers ----------

fn void Parser.advance(Parser* this)
{
    this.previous = this.current;
    this.current++;
}

fn void Parser.consume(Parser* this, TokenType type, String msg)
{
    if (this.current.tokenType == type) {
        this.advance();
        return;
    }
    this.error(msg);
}

fn bool Parser.match(Parser* this, TokenType... tokenTypes)
{
    foreach (type : tokenTypes) {
        if (this.current.tokenType == type) {
            this.advance();
            return true;
        }
    }
    return false;
}

fn bool Parser.check(Parser* this, TokenType tokenType)
{
    return this.current.matches_type(tokenType);
}

fn bool Parser.match_any_type_token(Parser* this)
{
    if(this.check_any_type_token()){
        this.advance();
        return true;
    }
    return false;
}

fn bool Parser.check_any_type_token(Parser* this) @inline
{
    return  this.current.is_any_type();
}

// ---------- Errors / Debug ----------

fn void Parser.warning(Parser* this, String msg)
{
    this.warning_at(this.previous, msg);
}

fn void Parser.warning_at(Parser* this, Token* token, String msg)
{
    if (this.panicMode) return;

    log::errlog("[line %d] Warning", token.line);
    log::errlog(" at '%s'", token.value());
    log::errlog(", %s \n", msg);
}

fn void Parser.error(Parser* this, String msg, args ...)
{
    this.error_at(this.previous, msg, ...args);
}

fn void Parser.error_at(Parser* this, Token* token, String msg, args ...)
{
    if (this.panicMode) return;

    log::errlog("[line %d] Error", token.line);
    this.hadError  = true;
    this.panicMode = true;

    if (token.tokenType == TokenType.EOF) {
        log::errlog(" at end, ");
    } else {
        log::errlog(" at '%s', ", token.value());
    }

    log::errlogn(msg, ...args);

}

// ---------- Identifier helpers ----------

fn bool identifiers_equal(Token* a, Token* b) @inline
{
    return strings_equal(a.value(), b.value());
}

fn bool strings_equal(String a, String b)
{
    if (a.len != b.len) return false;
    return libc::memcmp(a, b, a.len) == 0;
}


// ---------- Program entry ----------

fn void Parser.emit_program_call(Parser* this)
{
}

// ---------- Bytecode helpers ----------

fn ushort Parser.ensure_constant(Parser* this, int constantIndex)
{
    if (constantIndex > ushort.max) {
        this.error("Too many constants in one chunk");
        return 0;
    }
    return (ushort)constantIndex;
}

// ---------- Predeclaration for functions / structs / natives ----------

fn void Parser.predeclare_structs(Parser* this)
{
	assert(globals::declaredStructs.is_initialized());
	assert(globals::declaredStructs.table.len > 0);

    // Look for patterns: struct <name>
    for (usz i = 0; i < this.input.len() - 2; i++) {
        Token* t = &this.input[i];
        if (t.tokenType == TokenType.STRUCT_T) {
			int scopeCloseExpected = 1;
            Token* nameTok = &this.input[i + 1];
            // We push a temporary declaration that will have to be filled in later
            Decl decl = {.kind = DeclKind.STRUCT};
            decl.structDecl = {};
            NameIdx nameIdx = this.push_name_get_idx(nameTok.value());
            decl.structDecl.nameIdx = nameIdx;
            DeclIdx declIdx = this.push_decl_get_idx(&decl);

            // Also register ref/pointer spellings so type checks succeed on tokens like "vec3*" / "vec3&".
            String starName = nameTok.value().concat(&globals::allocator, "*");
            String ampName = nameTok.value().concat(&globals::allocator, "&");

            debug::@log_compilation("pre-declaring struct with names '%s' %s, and %s", nameTok.value(), starName, ampName);
            globals::declaredStructs.set(nameTok.value(), declIdx);
            globals::declaredStructs.set(starName, declIdx);
            globals::declaredStructs.set(ampName, declIdx);
		}
    }
}

fn void Parser.predeclare_functions(Parser* this)
{
    // Look for patterns: fn <type> <identifier>
    for (usz i = 0; i < this.input.len() - 2; i++) {
        Token* t = &this.input[i];
        if (t.tokenType == TokenType.FN) {
            Token* typeTok = &this.input[i + 1];
            Token* nameTok = &this.input[i + 2];
            // We push a temporary declaration that will have to be filled in later
            Decl decl = {.kind = DeclKind.FUNCTION};
            decl.fnDecl = {};
            NameIdx returnTypeNameIdx = this.push_name_get_idx(typeTok.value());
            TypeAst returnTypeAst = {.tokenType = typeTok.tokenType, .nameIdx = returnTypeNameIdx};
            NameIdx nameIdx = this.push_name_get_idx(nameTok.value());
            decl.fnDecl.returnType = returnTypeAst;
            decl.fnDecl.nameIdx = nameIdx;
            debug::@log_compilation("pre-declaring function '%s' with return type {%s} (at index %s)", nameTok.value(), typeTok.value(), nameIdx);
            DeclIdx declIdx = this.push_decl_get_idx(&decl);
            globals::declaredFunctions.set(nameTok.value(), declIdx);
        }
    }
}



fn void Parser.predeclare_natives(Parser* this)
{
}

fn ExprIdx Parser.push_expr_get_idx(Parser* this, Expr* expr){
    ExprIdx index = this.outputAst.expressions.len();
    this.outputAst.expressions.push(*expr);
    return index;
}

fn DeclIdx Parser.push_decl_get_idx(Parser* this, Decl* decl){
    DeclIdx index = this.outputAst.declarations.len();
    this.outputAst.declarations.push(*decl);
    return index;
}

fn NameIdx Parser.push_name_get_idx(Parser* this, String toCopy){
    NameIdx index = this.outputAst.names.len();
    String copy = String.copy(toCopy, &this.allocator);
    this.outputAst.names.push(copy);
	assert(this.outputAst.names.len() == index + 1);
    return index;
}

fn StmtIdx Parser.push_stmt_get_idx(Parser* this, Stmt* stmt)
{
    StmtIdx idx = this.outputAst.statements.len();
    this.outputAst.statements.push(*stmt);
    return idx;
}
