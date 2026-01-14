module parser;
import common;
import common::stack;
import log;
import debug;
import std::collections::list;
import std::collections::map;
alias Byte = common::Byte;

faultdef PARSE_ERROR;

struct Parser
{
    List{Token} input;
    Token* current;
    Token* previous;
    ProgramAst outputAst;
    TrackingAllocator allocator;
    bool hadError;
    bool panicMode;
}

// ---------- Lifecycle ----------

fn void Parser.init(Parser* this, List{Token} tokens)
{
    this.input = tokens;
    this.hadError = false;
    this.panicMode = false;

    this.current = &(this.input[0]);
    this.previous = this.current;

    this.allocator = {};
    this.allocator.init(mem);

    this.outputAst = {};
    this.outputAst.init(&this.allocator);

    common::ensure_globals_init();
    this.predeclare_structs();
    this.predeclare_functions();
}

fn void Parser.deinit(Parser* this)
{
    this.allocator.free();
    clean_up_struct_globals();
}

// ---------- Top-level compile pipeline ----------

fn void? Parser.parse(Parser* parser)
{
    while (!parser.match(TokenType.EOF)) {
        parser.declaration();
    }
}

// ---------- Declarations & statements ----------

fn void Parser.declaration(Parser* this)
{
    if (this.match(TokenType.FN)) {
        this.fun_declaration();
    } else if (this.match(TokenType.STRUCT_T)) {
        this.struct_declaration();
    } else {
        this.error("Only function/struct declarations are allowed at top level.");
        this.advance();
    }
}

fn StmtIdx Parser.statement(Parser* this)
{
    if (this.match(TokenType.ECHO)) {
        return this.echo_statement();
    } else if (this.match(TokenType.LEFT_BRACE)) {
        return this.block();
    } else if (this.match(TokenType.IF)) {
        return this.if_statement();
    } else if (this.match(TokenType.WHILE)) {
        return this.while_statement();
    } else if (this.match(TokenType.RETURN)) {
        return this.return_statement();
    } else {
        return this.expression_statement();
    }
}

fn StmtIdx Parser.expression_statement(Parser* this)
{
    debug::@log_compilation("expression_statement at %s", (this.previous-1).value);
    int line = this.current.line;
    ExprIdx exprIdx = this.expression();
    this.consume(TokenType.SEMICOLON, "Expected ';' after statement.");

    Stmt stmt = {.kind = StmtKind.EXPR};
    stmt.span = {.line = line};
    stmt.exprStmt = exprIdx;
    return this.push_stmt_get_idx(&stmt);
}

fn StmtIdx Parser.echo_statement(Parser* this)
{
    debug::@log_compilation("echo_statement at %s", (this.previous-1).value);
    int line = this.previous.line;
    ExprIdx exprIdx = this.expression();
    this.consume(TokenType.SEMICOLON, "Expected ';' after statement.");

    Stmt stmt = {.kind = StmtKind.ECHO};
    stmt.span = {.line = line};
    stmt.echoStmt = exprIdx;
    return this.push_stmt_get_idx(&stmt);
}

fn StmtIdx Parser.return_statement(Parser* this)
{
    debug::@log_compilation("return_statement at %s at %s", this.previous.value, this.current.value);
    int line = this.previous.line;

    Stmt stmt = {.kind = StmtKind.RETURN};
    stmt.span = {.line = line};

    if (this.check(TokenType.SEMICOLON)) {
        this.consume(TokenType.SEMICOLON, "Expect ';' after return.");
        stmt.retStmt = {.value = NO_IDX};
        return this.push_stmt_get_idx(&stmt);
    }

    ExprIdx value = this.expression();
    this.consume(TokenType.SEMICOLON, "Expect ';' after return.");
    stmt.retStmt = {.value = value};
    return this.push_stmt_get_idx(&stmt);
}

fn StmtIdx Parser.if_statement(Parser* this)
{
    debug::@log_compilation("if_statement at %s", this.current.value);
    int line = this.previous.line;

    this.consume(TokenType.LEFT_PAREN, "Expect '(' after 'if'.");
    ExprIdx condIdx = this.expression();
    this.consume(TokenType.RIGHT_PAREN, "Expect ')' after condition."); 

    this.consume(TokenType.LEFT_BRACE, "Expect '{' after 'if' condition.");
    StmtIdx thenIdx = this.block();

    StmtIdx elseIdx = NO_IDX;
    if (this.match(TokenType.ELSE)) {
        this.consume(TokenType.LEFT_BRACE, "Expect '{' after 'else'.");
        elseIdx = this.block();
    }

    Stmt stmt = {.kind = StmtKind.IF};
    stmt.span = {.line = line};
    stmt.ifStmt = {.cond = condIdx, .thenBlock = thenIdx, .elseBlock = elseIdx};
    return this.push_stmt_get_idx(&stmt);
}


fn StmtIdx Parser.while_statement(Parser* this)
{
    debug::@log_compilation("while_statement at %s", this.current.value);
    int line = this.previous.line;

    this.consume(TokenType.LEFT_PAREN, "Expect '(' after 'while'.");
    ExprIdx condIdx = this.expression();
    this.consume(TokenType.RIGHT_PAREN, "Expect ')' after condition."); 

    this.consume(TokenType.LEFT_BRACE, "Expect '{' after 'while'");
    StmtIdx bodyIdx = this.block();

    Stmt stmt = {.kind = StmtKind.WHILE};
    stmt.span = {.line = line};
    stmt.whileStmt = {.cond = condIdx, .body = bodyIdx};
    return this.push_stmt_get_idx(&stmt);
}

fn StmtIdx Parser.block(Parser* this)
{
    // assumes '{' was already consumed by the caller
    Stmt stmt = {.kind = StmtKind.BLOCK};
    stmt.span = {.line = this.previous.line};

    BlockStmt blockStmt = {};
    blockStmt.stmts.init(&this.allocator);

    while (!this.check(TokenType.RIGHT_BRACE) && !this.check(TokenType.EOF)) {
        StmtIdx child = this.statement_or_vardecl_in_block();
        if (child != NO_IDX) {
            blockStmt.stmts.push(child);
        }
    }

    this.consume(TokenType.RIGHT_BRACE, "Expected '}' after block");
    stmt.blockStmt = blockStmt;
    return this.push_stmt_get_idx(&stmt);
}

fn StmtIdx Parser.statement_or_vardecl_in_block(Parser* this)
{
    if (this.check_any_type_token()) {
        return this.var_declaration();
    }
    if (this.match(TokenType.FN) || this.match(TokenType.STRUCT_T)) {
        this.error("Functions/structs are not allowed inside blocks (top-level only).");
        return NO_IDX;
    }
    return this.statement();
}


// ---------- Struct declarations ----------

fn DeclIdx Parser.struct_declaration(Parser* this)
{
    debug::@log_compilation("struct_declaration at %s", this.current.value);

    // struct <name> { <fields> }
    this.consume(TokenType.IDENTIFIER, "Expected struct name after 'struct'");
    String name = this.previous.value;

    // Find the predeclared struct entry (or create one if missing)
    DeclIdx declIdx;
    DeclIdx? found = declaredStructs.get(name);
    if (catch notFound = found) {
        // Not predeclared (unexpected), create a fresh one
        Decl decl = {.kind = DeclKind.STRUCT};
        decl.structDecl = {};
        decl.structDecl.nameIdx = this.push_name_get_idx(name);
        decl.structDecl.fields.init(&this.allocator);
        declIdx = this.push_decl_get_idx(&decl);
        declaredStructs.set(name, declIdx);
    } else {
        declIdx = found;
    }

    Decl* decl = &this.outputAst.declarations[declIdx];
    if (decl.kind != DeclKind.STRUCT) {
        this.error("Internal error: struct declaration slot already used by a non-struct.");
        return declIdx;
    }
    // Ensure fields list is initialized
    decl.structDecl.nameIdx = this.push_name_get_idx(name);
    decl.structDecl.fields.init(&this.allocator);

    this.consume(TokenType.LEFT_BRACE, "Expected '{' after struct name");
    while (!this.check(TokenType.RIGHT_BRACE) && !this.check(TokenType.EOF)) {
        // Parse field: <type> <name> ;
        TypeAst fieldType = this.parse_type_ast();
        this.consume(TokenType.IDENTIFIER, "Expected field name.");
        NameIdx fieldNameIdx = this.push_name_get_idx(this.previous.value);
        FieldAst field = {.type = fieldType, .nameIdx = fieldNameIdx};
        decl.structDecl.fields.push(field);
        this.consume(TokenType.SEMICOLON, "Expected ';' after field");
    }
    this.consume(TokenType.RIGHT_BRACE, "Expected '}' after struct fields");
    return declIdx;
}

fn ExprIdx Parser.dot(Parser* this, ExprIdx lhs)
{
    debug::@log_compilation("dot at %s at %s", this.previous.value, this.current.value);

    String fieldName = this.current.value;

    this.consume(TokenType.IDENTIFIER, "Expect property name after '.'.");
    
    NameIdx nameIdx = this.push_name_get_idx(fieldName);

    Expr expr = {.kind = ExprKind.FIELD};
    expr.span = {.line = this.previous.line};
    expr.field = {.base = lhs, .field = nameIdx};
    ExprIdx index = this.push_expr_get_idx(&expr);
    return index;
}

// ---------- Variable declarations & access ----------

fn StmtIdx Parser.var_declaration(Parser* this)
{
    debug::@log_compilation("var_declaration at %s", this.current.value);
    int line = this.current.line;

    TypeAst type = this.parse_type_ast();
    this.consume(TokenType.IDENTIFIER, "Expected variable name");
    NameIdx nameIdx = this.push_name_get_idx(this.previous.value);

    ExprIdx initIdx = NO_IDX;
    if (this.match(TokenType.EQUAL)) {
        initIdx = this.expression();
    }

    this.consume(TokenType.SEMICOLON, "Expected ';' after declaration");

    Stmt stmt = {.kind = StmtKind.DECL};
    stmt.span = {.line = line};
    stmt.varDecl = {.type = type, .nameIdx = nameIdx, .init = initIdx};
    return this.push_stmt_get_idx(&stmt);
}

fn ushort Parser.parse_variable(Parser* this, String errMsg)
{
    this.consume(TokenType.IDENTIFIER, errMsg);
    Token* name = this.previous;

    this.declare_variable();
    return this.identifier_constant(this.previous);
}

fn void Parser.declare_variable(Parser* this)
{
    Token* name = this.previous;
    this.add_local(*name);
}

fn void Parser.add_local(Parser* this, Token name)
{
}

fn void Parser.mark_initialized(Parser* this)
{
}

fn ushort Parser.identifier_constant(Parser* this, Token* name)
{
    return 0;
}

fn void Parser.define_variable(Parser* this, ushort globalsIndex)
{
}

fn ExprIdx Parser.variable(Parser* this)
{
    debug::@log_compilation("variable at %s", this.previous.value);
    NameIdx nameIdx = this.push_name_get_idx(this.previous.value);
    Expr expr = {.kind = ExprKind.VAR, .varExpr = nameIdx};
    expr.span = {.line = this.previous.line};
    return this.push_expr_get_idx(&expr);
}

fn void Parser.named_variable(Parser* this, Token name)
{
}

// ---------- Functions & calls ----------

fn DeclIdx Parser.fun_declaration(Parser* this)
{
    debug::@log_compilation("fun_declaration at %s", this.current.value);

    // return type
    TypeAst ret = this.parse_type_ast(); // consumes it

    // function name
    this.consume(TokenType.IDENTIFIER, "Expected function name after return type");
    String fnName = this.previous.value;

    // must exist from predeclaration
    DeclIdx? declIdxOpt = declaredFunctions.get(fnName);
    if (catch notFound = declIdxOpt) {
        this.error("No function pre-declared with name at %s", fnName);
        return NO_IDX;
    }

    DeclIdx declIdx = declIdxOpt;
    Decl* decl = &this.outputAst.declarations[declIdx];

    // sanity
    if (decl.kind != DeclKind.FUNCTION) {
        this.error("Internal error: predecl for at %s isn't a function decl", fnName);
        return NO_IDX;
    }

    // fill missing pieces
    decl.fnDecl.returnType = ret;

    // parse params + body
    this.consume(TokenType.LEFT_PAREN, "Expected '(' after function name");
    this.fill_fun_params(&decl.fnDecl);

    this.consume(TokenType.LEFT_BRACE, "Expected '{' before function body");
    StmtIdx bodyIdx = this.block(); // block consumes the closing '}'
    decl.fnDecl.body = bodyIdx;

    return declIdx;
}


fn void Parser.fill_fun_params(Parser* this, FnDeclAst* declFn)
{
    // assumes '(' has already been consumed
    // ensure list is initialized
    declFn.params.init(&this.allocator);

    if (!this.check(TokenType.RIGHT_PAREN))
    {
        do {
            ParamAst p = this.fun_param();
            if (declFn.params.len() >= Byte.max) {
                this.error("Can't have more than 255 parameters");
                break;
            }
            declFn.params.push(p);
        } while (this.match(TokenType.COMMA));
    }

    this.consume(TokenType.RIGHT_PAREN, "Expect ')' after parameters");
}


fn ParamAst Parser.fun_param(Parser* this)
{
    ParamAst param = {};
    TypeAst type = this.parse_type_ast();
    
    this.consume(TokenType.IDENTIFIER, "Expected parameter name");
    
    NameIdx nameIdx = this.push_name_get_idx(this.previous.value);
    param.type = type;
    param.nameIdx = nameIdx;
    param.span = {.line = this.previous.line};

    return param;
}


fn TypeAst Parser.parse_type_ast(Parser* this)
{
    // expects current token is some type token
    if (!this.match_any_type_token())
    {
        this.error("Expected type");
        return {.tokenType = TokenType.NULL, .nameIdx = 0};
    }

    // match_any_type_token advanced, so `previous` is the type token
    NameIdx typeNameIdx = this.push_name_get_idx(this.previous.value);
    return {.tokenType = this.previous.tokenType, .nameIdx = typeNameIdx};
}

fn ExprIdx Parser.call(Parser* this, ExprIdx lhs)
{
    Expr expr = {.kind = ExprKind.CALL};
    expr.call = {};
    expr.call.init(&this.allocator);
    expr.call.callee = lhs;
    this.fill_call_args(&expr.call);
    ExprIdx exprIdx = this.push_expr_get_idx(&expr);
    return exprIdx;
}

fn void Parser.fill_call_args(Parser* this, ExprCall* exprCall)
{
    // We're CALLING a function, so we allow expressions as arguments
    // Consume as many as we can find.
    if (!this.check(TokenType.RIGHT_PAREN)) {
        do {
            ExprIdx argExprIdx = this.expression();
            if (exprCall.args.len() >= Byte.max) {
                this.error("Can't have more than 255 arguments");
            }
            exprCall.args.push(argExprIdx);
            // Remove all arguments from the type stack
        } while (this.match(TokenType.COMMA));
    }

    this.consume(TokenType.RIGHT_PAREN, "Expect ')' after arguments.");
}

// ---------- Expressions & precedence ----------

fn ExprIdx Parser.expression(Parser* this)
{
    return this.parse_precedence(Precedence.ASSIGNMENT);
}

fn ExprIdx Parser.new_expr(Parser* this)
{
    debug::@log_compilation("new_expr at %s", this.previous.value);
	TypeAst targetType = this.parse_type_ast();
    Expr expr = { .kind = ExprKind.NEW};
    expr.span = {.line = this.previous.line};
	expr.new = {.type = targetType};
    ExprIdx index = this.push_expr_get_idx(&expr);
    return index;

}

fn ExprIdx Parser.as(Parser* this, ExprIdx lhs)
{
    // Parse a type on the RHS of `as` (e.g., expr as string)
    TypeAst targetType = this.parse_type_ast();
    // Represent the type as a synthetic VAR node holding the type name for now.
    Expr typeExpr = {.kind = ExprKind.VAR, .varExpr = targetType.nameIdx};
    typeExpr.span = {.line = this.previous.line};
    ExprIdx rhs = this.push_expr_get_idx(&typeExpr);

    Expr expr = { .kind = ExprKind.BINARY};
    expr.span = { .line = this.previous.line};
    expr.binary = { .op = BinOp.AS, .lhs = lhs, .rhs = rhs};
    return this.push_expr_get_idx(&expr);
}

fn ExprIdx Parser.and(Parser* this, ExprIdx lhs)
{
    ExprIdx rhs = this.parse_precedence(Precedence.AND);
    Expr expr = { .kind = ExprKind.BINARY};
    expr.span = { .line = this.previous.line};
    expr.binary = { .op = BinOp.AND, .lhs = lhs, .rhs = rhs};
    ExprIdx index = this.push_expr_get_idx(&expr);
    return index;
}

fn ExprIdx Parser.or(Parser* this, ExprIdx lhs)
{
    // left operand (bool) is on top
    ExprIdx rhs = this.parse_precedence(Precedence.OR);
    Expr expr = { .kind = ExprKind.BINARY};
    expr.span = { .line = this.previous.line};
    expr.binary = { .op = BinOp.OR, .lhs = lhs, .rhs = rhs};
    ExprIdx index = this.push_expr_get_idx(&expr);
    return index;
}

fn ExprIdx Parser.grouping(Parser* this)
{
    ExprIdx rhs = this.expression();
    this.consume(TokenType.RIGHT_PAREN, "Expected ')' after expression");
    return rhs;
}


fn ExprIdx Parser.number(Parser* this)
{
    debug::@log_compilation("number at %s", this.previous.value);
    Expr expr;
    switch (this.previous.tokenType) {
        case TokenType.INTEGER:
            int? ival = String.to_int(this.previous.value);
			if(catch notParsable = ival) {
				this.error("%s is not an valid int", this.previous.value);
				return NO_IDX;
			}
            expr = {.kind = ExprKind.INT, .intLiteral = ival};
        case TokenType.FLOAT:
            float? fval = String.to_float(this.previous.value);
			if(catch notParsable = fval) {
				this.error("%s is not an valid float", this.previous.value);
				return NO_IDX;
			}
            expr = {.kind = ExprKind.FLOAT, .floatLiteral = fval};
        case TokenType.DOUBLE:
            double? dval = String.to_double(this.previous.value);
			if(catch notParsable = dval) {
				this.error("%s is not an valid double", this.previous.value);
				return NO_IDX;
			}
            expr = {.kind = ExprKind.DOUBLE, .doubleLiteral = dval};
        default:
            this.error("Unknown type at %s", this.previous.value);
    }
    expr.span = {.line = this.previous.line};
    return this.push_expr_get_idx(&expr);
}

fn ExprIdx Parser.string(Parser* this)
{
    String source = this.previous.value;
    NameIdx nameIdx = this.push_name_get_idx(source);
    Expr expr = {.kind = ExprKind.STRING, .stringLiteral = nameIdx};
    ExprIdx exprIdx = this.push_expr_get_idx(&expr);
    return exprIdx;
}

fn ExprIdx Parser.unary(Parser* this)
{
    int operatorLine = this.previous.line;
    TokenType opTokType = this.previous.tokenType;

    ExprIdx rhsIdx = this.parse_precedence(Precedence.UNARY);
    UnOp opType;

    switch (opTokType) {
        case TokenType.MINUS:       opType = UnOp.NEG;
        case TokenType.BANG:        opType = UnOp.NOT;
        default:                    this.error("Unsupported operator");
    }
    Expr expr = {.kind = ExprKind.UNARY};
    expr.span = {.line = operatorLine };
    expr.unary = {.op = opType, .rhs = rhsIdx};
    return this.push_expr_get_idx(&expr);
}


fn ExprIdx Parser.binary(Parser* this, ExprIdx lhs)
{
    TokenType   operatorType = this.previous.tokenType;
    ParseRule* rule = get_rule(operatorType);
    ExprIdx rhs = this.parse_precedence((Precedence)(rule.precedence + 1));
    BinOp op;

    switch (operatorType) {
        case TokenType.PLUS:          op = BinOp.ADD;
        case TokenType.MINUS:         op = BinOp.SUB;
        case TokenType.STAR:          op = BinOp.MUL;
        case TokenType.SLASH:         op = BinOp.DIV;
        case TokenType.BANG_EQUAL:    op = BinOp.NEQ;
        case TokenType.EQUAL_EQUAL:   op = BinOp.EQ;
        case TokenType.GREATER:       op = BinOp.GREATER;
        case TokenType.GREATER_EQUAL: op = BinOp.GREATER_EQ;
        case TokenType.LESS:          op = BinOp.LESS;
        case TokenType.LESS_EQUAL:    op = BinOp.LESS_EQ;
        case TokenType.EQUAL:         op = BinOp.ASSIGN;
        default:                      op = BinOp.AS;
    }
    Expr expr = {.kind = ExprKind.BINARY};
    expr.span = {.line = this.previous.line};
    expr.binary = {.op = op, .lhs = lhs, .rhs = rhs };
    ExprIdx index = this.push_expr_get_idx(&expr);
    return index;
}

fn ExprIdx Parser.literal_true(Parser* this)
{
    Expr expr = {.kind = ExprKind.BOOL, .boolLiteral = true };
    expr.span.line = this.previous.line;
    return this.push_expr_get_idx(&expr);
}

fn ExprIdx Parser.literal_false(Parser* this)
{
    Expr expr = {.kind = ExprKind.BOOL, .boolLiteral = false };
    expr.span.line = this.previous.line;
    return this.push_expr_get_idx(&expr);;
}

fn ExprIdx Parser.literal_null(Parser* this)
{
    Expr expr = {.kind = ExprKind.NULL};
    expr.span.line = this.previous.line;
    return this.push_expr_get_idx(&expr);
}

// ---------- Precedence engine ----------

fn ExprIdx Parser.parse_precedence(Parser* this, Precedence precedence)
{
    this.advance();
    PrefixFn prefixRule = get_rule(this.previous.tokenType).prefix;
    if (prefixRule == null) {
        this.error("Expected expression");
        return NO_IDX;
    }

    ExprIdx lastIdx = prefixRule(this);

    while (precedence <= get_rule(this.current.tokenType).precedence) {
        this.advance();
        InfixFn infixRule = get_rule(this.previous.tokenType).infix;
        lastIdx = infixRule(this, lastIdx);
    }

    return lastIdx;
}
