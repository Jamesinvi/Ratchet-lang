module compiler;
import std::io;
import common;
import common::stack;
import std::collections::list;
import std::collections::map;
alias Byte = common::Byte;
alias TypeStack = common::stack::Stack{common::ValueType};

enum CompileResult
{
    OK,
    ERROR,
}

enum Precedence 
{
    NONE,
    ASSIGNMENT, // =
    OR,         // ||
    AND,        // &&
    EQUALITY,   
    COMPARISON, // ==
    TERM,       
    FACTOR,
    UNARY,
    CALL,
    PRIMARY
}

struct Compiler
{
    List{Token}          input;
    Token*               current;
    Token*               previous;
    bool                 hadError;
    bool                 panicMode;

    TypeStack            typeStack; 
    ScopeTracker*        currentScope;
    ScopeTracker         rootScope;
    ObjFunction*         entryPoint;

    HashMap{String,ValueType} functionReturnTypes;
    bool                 hasPendingCalleeType;
    ValueType            pendingCalleeReturnType;
    ValueType            currentDeclType;
}

// ---------- Lifecycle ----------

fn void Compiler.init(Compiler* this, List{Token} tokens)
{
    this.input     = tokens;
    this.hadError  = false;
    this.panicMode = false;

    this.current   = &this.input[0];
    this.previous  = this.current;
    this.entryPoint = null;

    // Root script function + scope
    this.rootScope.scopeDepth = 0;
    this.rootScope.localCount = 0;
    this.rootScope.enclosing  = null;
    this.rootScope.function   = common::create_obj_function("script", true);

    // Dummy local 0
    Local* local  = &this.rootScope.locals[this.rootScope.localCount++];
    local.depth   = 0;
    local.name.value = "";

    this.currentScope = &this.rootScope;

    this.functionReturnTypes.init(mem);
    this.hasPendingCalleeType = false;

    // First pass: discover all functions + return types
    this.predeclare_functions();
    this.predeclare_natives();
}

fn void Compiler.deinit(Compiler* this)
{
    this.typeStack.free();
    this.functionReturnTypes.free();
}

fn Chunk* Compiler.get_current_chunk(Compiler* this)
{
    return &this.currentScope.function.chunk;
}

faultdef COMPILE_ERROR;

// ---------- Top-level compile pipeline ----------

fn ObjFunction*? compile(Compiler* compiler)
{
    while (!compiler.match(TokenType.EOF)) {
        compiler.declaration();
    }
    
    if (compiler.entryPoint != null) {
        compiler.compile_program_call();
    } else {
        compiler.error("program function not defined. All programs must define a fn null program()");
    }

    ObjFunction* script = compiler.end();
    if (compiler.hadError) {
        return COMPILE_ERROR?;
    }
    return script;
}

fn ObjFunction* Compiler.end(Compiler* this)
{
    this.compile_byte((Byte)OpCode.RETURN, this.previous.line);
    ObjFunction* function = this.currentScope.function;
    return function;
}

// ---------- Declarations & statements ----------

fn void Compiler.declaration(Compiler* this)
{
    if (this.check_any_type_token()) {
        ValueType declType = this.match_type("Expected type before variable name");
        this.currentDeclType = declType;
        this.var_declaration();
    } else if (this.match(TokenType.FN)) {
        this.fun_declaration();
    } else if (this.match(TokenType.STRUCT_T)) {
        this.struct_definition();
    } else {
        this.statement();
    }
}

fn void Compiler.statement(Compiler* this)
{
    if (this.match(TokenType.ECHO)) {
        this.debug_statment();
    } else if (this.match(TokenType.LEFT_BRACE)) {
        this.begin_scope();
        this.block();
        this.end_scope();
    } else if (this.match(TokenType.IF)) {
        this.if_statement();
    } else if (this.match(TokenType.WHILE)) {
        this.while_statement();
    } else if (this.match(TokenType.RETURN)) {
        this.return_statement();
    } else {
        this.expression_statement();
    }
}

fn void Compiler.expression_statement(Compiler* this)
{
    this.expression();
    this.consume(TokenType.SEMICOLON, "Expected ';' after expression.");
    this.compile_byte((Byte)OpCode.POP, this.previous.line);
}

fn void Compiler.debug_statment(Compiler* this)
{
    this.expression();
    this.consume(TokenType.SEMICOLON, "Expected ';' after value.");
    this.compile_byte((Byte)OpCode.ECHO, this.previous.line);
}

fn void Compiler.return_statement(Compiler* this)
{
    int line = this.previous.line;

    if (this.currentScope.enclosing == null) {
        this.error("Cannot return from top-level code.");
    }

    if (this.check(TokenType.SEMICOLON)) {
        this.consume(TokenType.SEMICOLON, "Expect ';' after return.");
        this.compile_byte((Byte)OpCode.RETURN, line);
        return;
    }

    this.expression();
    this.consume(TokenType.SEMICOLON, "Expect ';' after return value.");
    this.compile_byte((Byte)OpCode.RETURN, line);
}

fn void Compiler.if_statement(Compiler* this)
{
    this.consume(TokenType.LEFT_PAREN, "Expect '(' after 'if'.");
    this.expression();
    this.consume(TokenType.RIGHT_PAREN, "Expect ')' after condition."); 

    int thenJump = this.compile_jump(OpCode.JMP_IF_FALSE, this.previous.line);
    this.compile_byte((Byte)OpCode.POP, this.previous.line);

    this.consume(TokenType.LEFT_BRACE, "Expect '{' after 'if' condition.");
    this.begin_scope();
    this.block();
    this.end_scope();

    int elseJump = this.compile_jump(OpCode.JMP, this.previous.line);

    this.patch_jump(thenJump);
    this.compile_byte((Byte)OpCode.POP, this.previous.line);

    if (this.match(TokenType.ELSE)) {
        this.consume(TokenType.LEFT_BRACE, "Expect '{' after 'else'.");
        this.begin_scope();
        this.block();
        this.end_scope();
    }

    this.patch_jump(elseJump);
}

fn void Compiler.while_statement(Compiler* this)
{
    int loopStart = (int)this.get_current_chunk().code.size;

    this.consume(TokenType.LEFT_PAREN, "Expect '(' after 'while'.");
    this.expression();
    this.consume(TokenType.RIGHT_PAREN, "Expect ')' after condition.");

    int exitJump = this.compile_jump(OpCode.JMP_IF_FALSE, this.previous.line);
    this.compile_byte((Byte)OpCode.POP, this.previous.line);

    this.statement();
    this.compile_loop(loopStart);

    this.patch_jump(exitJump);
    this.compile_byte((Byte)OpCode.POP, this.previous.line);
}

fn void Compiler.block(Compiler* this)
{
    while (!this.check(TokenType.RIGHT_BRACE) && !this.check(TokenType.EOF)) {
        this.declaration();
    }
    this.consume(TokenType.RIGHT_BRACE, "Epxected '}' after block");
}

fn void Compiler.begin_scope(Compiler* this)
{
    this.currentScope.scopeDepth++;
}

fn void Compiler.end_scope(Compiler* this)
{
    this.currentScope.scopeDepth--;
    while (this.currentScope.localCount > 0 &&
           this.currentScope.locals[this.currentScope.localCount - 1].depth >
           this.currentScope.scopeDepth) {
        this.compile_byte((Byte)OpCode.POP, this.previous.line);
        this.currentScope.localCount--;
    }
}

// ---------- Struct declarations & access ----------

fn void Compiler.struct_definition(Compiler* this){
    this.consume(TokenType.IDENTIFIER, "Expected struct name after 'struct'");
    String name = this.previous.value;
    this.consume(TokenType.LEFT_BRACE, "Expected '{' after struct name'}");

    if(common::declaredStructs.has_key(name)){
        this.error("This struct has already been defined elsewhere");
        return;
    }
    StructTypeInfo structInfo = {};
    structInfo.init();
    ushort fieldCounter = 0;
    structInfo.name = String.copy(name, mem);

    while (!this.check(TokenType.RIGHT_BRACE) && !this.check(TokenType.EOF)) {
        if (this.check_any_type_token()) {
            FieldInfo fieldInfo = {};
            ValueType fieldType = this.match_type("Expected type before field name");

            // If it was a struct type, `this.previous` holds the type identifier (e.g. "Vec2")
            String typeName = this.previous.value;

            this.consume(TokenType.IDENTIFIER, "Expected field name.");

            ValueMetadata fieldMetadata = {};
            fieldMetadata.typeIndex = get_type_index(fieldType, typeName);

            fieldInfo.metadata = fieldMetadata;
            fieldInfo.name     = String.copy(this.previous.value, mem); // field name
            fieldInfo.type     = fieldType;

            this.consume(TokenType.SEMICOLON, "Expected ';' after field declaration.");

            structInfo.fieldInfos.push(fieldInfo);
            fieldCounter++;
        } else if (this.check(TokenType.METHOD)) {
            // TODO
        } else {
            this.error("Unsupported declaration inside struct (for now).");
            this.advance(); // crude resync
        }
    }
    this.consume(TokenType.RIGHT_BRACE, "Expected '}' to close struct body");
    structInfo.fieldCount = fieldCounter;
    uint structTypesLen =(uint) common::structTypes.size;
    common::structTypes.push(structInfo);
    common::declaredStructs.set(structInfo.name, structTypesLen);
}

// ---------- Variable declarations & access ----------

fn void Compiler.var_declaration(Compiler* this)
{
    Byte index = this.parse_variable("Expected variable name");

    if (this.match(TokenType.EQUAL)) {
        this.expression();
    } else {
        this.compile_byte((Byte)OpCode.CONST_NULL, this.previous.line);
    }

    this.consume(TokenType.SEMICOLON, "Expected ';' after declaration");
    this.define_variable(index);
}

fn Byte Compiler.parse_variable(Compiler* this, String errMsg)
{
    this.consume(TokenType.IDENTIFIER, errMsg);

    this.declare_variable();
    if (this.currentScope.scopeDepth > 0) {
        return 0;
    }
    return this.identifier_constant(this.previous);
}

fn void Compiler.declare_variable(Compiler* this)
{
    if (this.currentScope.scopeDepth == 0) return;

    Token* name = this.previous;
    for (int i = this.currentScope.localCount - 1; i >= 0; i--) {
        Local* local = &this.currentScope.locals[i];
        if (local.depth != -1 && local.depth < this.currentScope.scopeDepth) {
            break; 
        }
        if (identifiers_equal(name, &local.name)) {
            this.error("Already a variable with this name in this scope.");
        }
    }
    this.add_local(*name);
}

fn void Compiler.add_local(Compiler* this, Token name)
{
    if (this.currentScope.localCount == Byte.max) {
        this.error("Too many local variables in this block");
        return;
    }

    Local* local = &this.currentScope.locals[this.currentScope.localCount++];
    local.type  = this.currentDeclType;
    local.name  = name;
    local.depth = -1;
}

fn void Compiler.mark_initialized(Compiler* this)
{
    if (this.currentScope.scopeDepth == 0) return;
    this.currentScope.locals[this.currentScope.localCount - 1].depth =
        this.currentScope.scopeDepth;
}

fn Byte Compiler.identifier_constant(Compiler* this, Token* name)
{
    return this.ensure_constant(this.get_current_chunk().add_const_string(name.value));
}

fn void Compiler.define_variable(Compiler* this, Byte globalsIndex)
{
    if (this.currentScope.scopeDepth > 0) {
        this.mark_initialized();
        return;
    }
    this.compile_bytes((Byte)OpCode.DEFINE_GLOBAL, globalsIndex, this.previous.line);
}

fn void Compiler.variable(Compiler* this, bool canAssign)
{
    Token* tokenName = this.previous;

    bool isCallSite = (this.current.tokenType == TokenType.LEFT_PAREN);
    this.named_variable(*this.previous, canAssign);

    if (isCallSite) {
        ValueType returnType = ValueType.NULL;
        ValueType? stored = this.functionReturnTypes.get(tokenName.value);
        if (catch err = stored) {
            this.error("Error with function type");
            return;
        }
        returnType = stored;
        this.pendingCalleeReturnType = returnType;
        this.hasPendingCalleeType    = true;
        return;
    }
}

fn void Compiler.named_variable(Compiler* this, Token name, bool canAssign)
{
    Byte getOp, setOp;
    int arg = resolve_local(this.currentScope, &name);

    if (arg != -1) {
        getOp = (Byte)OpCode.GET_LOCAL;
        setOp = (Byte)OpCode.SET_LOCAL;

        Local* local = &this.currentScope.locals[arg];
        ValueType varType = local.type;

        if (!canAssign || !this.check(TokenType.EQUAL)) {
            this.compile_bytes(getOp, (Byte)arg, this.previous.line);
            this.typeStack.push(varType);
            return;
        }
    } else {
        arg   = this.identifier_constant(&name);
        getOp = (Byte)OpCode.GET_GLOBAL;
        setOp = (Byte)OpCode.SET_GLOBAL;
    }

    if (canAssign && this.match(TokenType.EQUAL)) {
        this.expression();
        int line = this.previous.line;
        this.compile_bytes((Byte)setOp, (Byte)arg, this.previous.line);
        // try peephole optimize: i = i + 1 / i = i - 1
        if (setOp == (Byte)OpCode.SET_LOCAL) {
            this.maybe_optimize_local_inc_dec(arg, line);
        }
    } else {
        this.compile_bytes((Byte)getOp, (Byte)arg, this.previous.line);
    }
}

// ---------- Functions & calls ----------

fn void Compiler.fun_declaration(Compiler* this)
{
    ValueType returnType = this.match_type("Expected return type before function name");
    Byte globalsIndex    = this.parse_variable("Expect function name");
    Token* nameToken     = this.previous;

    this.functionReturnTypes.set(nameToken.value, returnType);

    bool isTopLevel           = (this.currentScope.enclosing == null);
    bool isProgram            = strings_equal(nameToken.value, "program");
    bool isEntryPointCandidate = isTopLevel && isProgram;

    this.mark_initialized();
    this.function(returnType, isEntryPointCandidate);
    this.define_variable(globalsIndex);
}

fn void Compiler.function(Compiler* this, ValueType returnType, bool isEntryPointCandidate)
{
    ScopeTracker tracker = {};
    Token* nameToken     = this.previous;

    tracker.init(this, returnType, nameToken.value);
    this.begin_scope();

    this.consume(TokenType.LEFT_PAREN, "Epect '(' after function name.");
    if (!this.check(TokenType.RIGHT_PAREN)) {
        do {
            this.currentScope.function.arity++;
            ValueType paramRetType = this.match_type("Expected parameter type");
            if (this.currentScope.function.arity > 255) {
                this.error("Can't have more than 255 parameters.");
            }
            this.currentDeclType = paramRetType;
            Byte constant = this.parse_variable("Expect parameter name.");
            this.define_variable(constant);
        } while (this.match(TokenType.COMMA));
    }
    this.consume(TokenType.RIGHT_PAREN, "Epect ')' after parameters");
    this.consume(TokenType.LEFT_BRACE, "Expect '{' before body.");
    this.block();

    ObjFunction* function = this.end();
    this.currentScope     = this.currentScope.enclosing;

    if (isEntryPointCandidate) {
        if (returnType != ValueType.NULL) {
            this.error("program must have return type 'null'.");
        }
        if (function.arity != 0) {
            this.error("program must not take parameters.");
        }
        this.entryPoint = function;
    }

    Byte index = this.ensure_constant(this.get_current_chunk().add_const_function(function));
    this.compile_bytes((Byte)OpCode.CONSTANT, index, this.previous.line);
}

fn void Compiler.call(Compiler* this, bool canAssign)
{
    Byte argCount = this.arg_list();
    this.compile_bytes((Byte)OpCode.CALL, argCount, this.previous.line);
    
    for (int i = 0; i < argCount; i++) {
        this.typeStack.pop();
    }

    if (this.hasPendingCalleeType) {
        this.typeStack.push(this.pendingCalleeReturnType);
        this.hasPendingCalleeType = false;
    } else {
        this.error("unknown type for function call");
    }
}

fn Byte Compiler.arg_list(Compiler* this)
{
    Byte count = 0;

    if (!this.check(TokenType.RIGHT_PAREN)) {
        do {
            this.expression();
            if (count >= Byte.max) {
                this.error("Can't have more than 255 arguments");
            }
            count++;
        } while (this.match(TokenType.COMMA));
    }

    this.consume(TokenType.RIGHT_PAREN, "Expect ')' after arguments.");
    return count;
}

// ---------- Expressions & precedence ----------

fn void Compiler.expression(Compiler* this)
{
    this.parse_precedence(Precedence.ASSIGNMENT);
}

fn void Compiler.and(Compiler* this)
{
    int jump = this.compile_jump(OpCode.JMP_IF_FALSE, this.previous.line);
    this.compile_byte((Byte)OpCode.POP, this.previous.line);
    this.parse_precedence(Precedence.AND);
    this.patch_jump(jump);
}

fn void Compiler.or(Compiler* this)
{
    int elseJump = this.compile_jump(OpCode.JMP_IF_FALSE, this.previous.line);
    int endJump  = this.compile_jump(OpCode.JMP, this.previous.line);

    this.patch_jump(elseJump);
    this.compile_byte((Byte)OpCode.POP, this.previous.line);

    this.parse_precedence(Precedence.OR);
    this.patch_jump(endJump);
}

fn void Compiler.grouping(Compiler* this, bool canAssign)
{
    // We are right after seeing '(' as a prefix.
    if (this.check_builtin_type_token()) {
        // --- CAST: (type) unaryExpression ---
        ValueType targetType = this.match_type("Expected type in cast.");
        // Ensure we really have "( type )"
        this.consume(TokenType.RIGHT_PAREN, "Expected ')' after cast type.");
        int line = this.previous.line;

        // Now parse the operand at UNARY precedence so:
        // (int)1+2 => cast applies to 1, not (1+2)
        this.parse_precedence(Precedence.UNARY);

        // We now have operand value on stack + typeStack top = operandType
        this.compile_cast(targetType, line);
        return;
    }

    this.expression();
    this.consume(TokenType.RIGHT_PAREN, "Expected ')' after expression");
}


fn void Compiler.number(Compiler* this, bool canAssign)
{
    switch (this.previous.tokenType) {
        case TokenType.INTEGER:
            int    ival = common::parse_int(this.previous.value);
            int    ic   = this.get_current_chunk().add_const_int(ival);
            this.compile_bytes((Byte)OpCode.CONSTANT, this.ensure_constant(ic), this.previous.line);
            this.typeStack.push(ValueType.INT);

        case TokenType.FLOAT:
            float  fval = common::parse_float(this.previous.value);
            int    fc   = this.get_current_chunk().add_const_float(fval);
            this.compile_bytes((Byte)OpCode.CONSTANT, this.ensure_constant(fc), this.previous.line);
            this.typeStack.push(ValueType.FLOAT);

        case TokenType.DOUBLE:
            double dval = common::parse_double(this.previous.value);
            int    dc   = this.get_current_chunk().add_const_double(dval);
            this.compile_bytes((Byte)OpCode.CONSTANT, this.ensure_constant(dc), this.previous.line);
            this.typeStack.push(ValueType.DOUBLE);

        default:
            this.error("Unsupported type");
    }
}

fn void Compiler.string(Compiler* this, bool canAssign)
{
    String source      = this.previous.value;
    int    constantIdx = this.get_current_chunk().add_const_string(source);
    this.compile_bytes((Byte)OpCode.CONSTANT, this.ensure_constant(constantIdx), this.previous.line);
    this.typeStack.push(ValueType.GC_OBJ);
}

fn void Compiler.unary(Compiler* this, bool canAssign)
{
    int       operatorLine = this.previous.line;
    TokenType operatorType = this.previous.tokenType;

    this.parse_precedence(Precedence.UNARY);

    switch (operatorType) {
        case TokenType.MINUS:
            this.compile_byte((Byte)OpCode.NEGATE_DOUBLE, operatorLine);
        case TokenType.BANG:
            this.compile_byte((Byte)OpCode.NOT, operatorLine);
        default:
            break;
    }
}

fn void Compiler.binary(Compiler* this)
{
    TokenType   operatorType = this.previous.tokenType;
    CompileRule* rule        = get_rule(operatorType);
    this.parse_precedence((Precedence)(rule.precedence + 1));

    switch (operatorType) {
        case TokenType.PLUS:          this.compile_add(this.previous.line);
        case TokenType.MINUS:         this.compile_sub(this.previous.line);
        case TokenType.STAR:          this.compile_mul(this.previous.line);
        case TokenType.SLASH:         this.compile_div(this.previous.line);
        case TokenType.BANG_EQUAL:    this.compile_bytes((Byte)OpCode.EQUAL, (Byte)OpCode.NOT, this.previous.line);
        case TokenType.EQUAL_EQUAL:   this.compile_byte((Byte)OpCode.EQUAL, this.previous.line);
        case TokenType.GREATER:       this.compile_byte((Byte)OpCode.GREATER, this.previous.line);
        case TokenType.GREATER_EQUAL: this.compile_bytes((Byte)OpCode.LESS, (Byte)OpCode.NOT, this.previous.line);
        case TokenType.LESS:          this.compile_less(this.previous.line);
        case TokenType.LESS_EQUAL:    this.compile_bytes((Byte)OpCode.GREATER, (Byte)OpCode.NOT, this.previous.line);
        default: this.error("Unsupported token");
    }
}

fn void Compiler.literal_true(Compiler* this)
{
    this.compile_byte((Byte)OpCode.CONST_TRUE, this.previous.line);
}

fn void Compiler.literal_false(Compiler* this)
{
    this.compile_byte((Byte)OpCode.CONST_FALSE, this.previous.line);
}

fn void Compiler.literal_null(Compiler* this)
{
    this.compile_byte((Byte)OpCode.CONST_NULL, this.previous.line);
}

// ---------- Type-aware arithmetic/logic codegen ----------

fn void Compiler.compile_less(Compiler* this, int line)
{
    ValueType right = this.typeStack.peek();
    ValueType left  = this.typeStack.peek_at(1);

    if(right==ValueType.INT && right==left){
        this.compile_byte((Byte)OpCode.INT_LESS, line);
    } else {
        this.compile_byte((Byte)OpCode.LESS, this.previous.line);
    }

}

fn void Compiler.compile_div(Compiler* this, int line)
{
    ValueType right = this.typeStack.pop();
    ValueType left  = this.typeStack.pop();

    switch (left) {
        case ValueType.INT:
            this.compile_byte((Byte)OpCode.DIV_INT, line);
            this.typeStack.push(ValueType.INT);
        case ValueType.FLOAT:
            this.compile_byte((Byte)OpCode.DIV_FLOAT, line);
            this.typeStack.push(ValueType.FLOAT);
        case ValueType.DOUBLE:
            this.compile_byte((Byte)OpCode.DIV_DOUBLE, line);
            this.typeStack.push(ValueType.DOUBLE);
        default:
            this.error("Unsupported divide");
    }
}

fn void Compiler.compile_mul(Compiler* this, int line)
{
    ValueType right = this.typeStack.pop();
    ValueType left  = this.typeStack.pop();

    switch (left) {
        case ValueType.INT:
            this.compile_byte((Byte)OpCode.MUL_INT, line);
            this.typeStack.push(ValueType.INT);
        case ValueType.FLOAT:
            this.compile_byte((Byte)OpCode.MUL_FLOAT, line);
            this.typeStack.push(ValueType.FLOAT);
        case ValueType.DOUBLE:
            this.compile_byte((Byte)OpCode.MUL_DOUBLE, line);
            this.typeStack.push(ValueType.DOUBLE);
        default:
            this.error("Unsupported multiply");
    }
}

fn void Compiler.compile_sub(Compiler* this, int line)
{
    ValueType right = this.typeStack.pop();
    ValueType left  = this.typeStack.pop();

    switch (left) {
        case ValueType.INT:
            this.compile_byte((Byte)OpCode.SUB_INT, line);
            this.typeStack.push(ValueType.INT);
        case ValueType.FLOAT:
            this.compile_byte((Byte)OpCode.SUB_FLOAT, line);
            this.typeStack.push(ValueType.FLOAT);
        case ValueType.DOUBLE:
            this.compile_byte((Byte)OpCode.SUB_DOUBLE, line);
            this.typeStack.push(ValueType.DOUBLE);
        default:
            this.error("Unsupported subtraction");
    }
}

fn void Compiler.compile_add(Compiler* this, int line)
{
    ValueType right = this.typeStack.pop();
    ValueType left  = this.typeStack.pop();

    switch (left) {
        case ValueType.INT:
            this.compile_byte((Byte)OpCode.ADD_INT, line);
            this.typeStack.push(ValueType.INT);
        case ValueType.FLOAT:
            this.compile_byte((Byte)OpCode.ADD_FLOAT, line);
            this.typeStack.push(ValueType.FLOAT);
        case ValueType.DOUBLE:
            this.compile_byte((Byte)OpCode.ADD_DOUBLE, line);
            this.typeStack.push(ValueType.DOUBLE);
        case ValueType.GC_OBJ:
            this.compile_byte((Byte)OpCode.CONCAT_STRING, line);
            this.typeStack.push(ValueType.NO_GC_OBJ);
        case ValueType.NO_GC_OBJ:
            this.compile_byte((Byte)OpCode.CONCAT_STRING, line);
            this.typeStack.push(ValueType.GC_OBJ);
        default:
            this.error("Unsupported add");
    }
}

// ---------- Precedence engine ----------

fn void Compiler.parse_precedence(Compiler* this, Precedence precedence)
{
    this.advance();
    ParseFn prefixRule = get_rule(this.previous.tokenType).prefix;
    if (prefixRule == null) {
        this.error("Expected expression");
        return;
    }

    bool canAssign = precedence.ordinal <= (Precedence.ASSIGNMENT.ordinal);
    prefixRule(this, canAssign);

    while (precedence <= get_rule(this.current.tokenType).precedence) {
        this.advance();
        ParseFn infixRule = get_rule(this.previous.tokenType).infix;
        infixRule(this, canAssign);
    }

    if (canAssign && this.match(TokenType.EQUAL)) {
        this.error("Invalid assignment target");
    }
}
