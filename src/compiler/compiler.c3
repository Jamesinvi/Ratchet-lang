module compiler;
import std::io;
import common;
import common::stack;
import std::collections::list;
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
    ASSIGNMENT,  // =
    OR,          // or
    AND,         // and
    EQUALITY,    // == !=
    COMPARISON,  // < > <= >=
    TERM,        // + -
    FACTOR,      // * /
    UNARY,       // ! -
    CALL,        // . ()
    PRIMARY
}

struct Compiler
{
    List{Token} input;
    Token* current;
    Token* previous;
    bool hadError;
    bool panicMode;
    TypeStack typeStack; 
    ScopeTracker* currentScope;
    ScopeTracker rootScope;
    ObjFunction* entryPoint;
}

// ---------- Lifecycle ----------

fn void Compiler.init(Compiler* this, List{Token} tokens){
    this.input     = tokens;
    this.hadError  = false;
    this.panicMode = false;

    this.current  = &this.input[0];
    this.previous = this.current;
    this.entryPoint = null;

    // Initialize root scope tracker
    this.rootScope.scopeDepth = 0;
    this.rootScope.localCount = 0;
    this.rootScope.enclosing  = null;
    this.rootScope.function   = common::create_obj_function("script",true);

    // Dummy local 0 for the script function
    Local* local = &this.rootScope.locals[this.rootScope.localCount++];
    local.depth      = 0;
    local.name.value = ""; 

    this.currentScope = &this.rootScope;
}

fn void Compiler.deinit(Compiler* this){
    this.typeStack.free();
}

fn Chunk* Compiler.get_current_chunk(Compiler* this){
    return &this.currentScope.function.chunk;
}

faultdef COMPILE_ERROR;

// ---------- Top-level compile pipeline ----------
fn ObjFunction*? compile(Compiler* compiler){
    while(!compiler.match(TokenType.EOF)){
        compiler.declaration();
    }
    
    if(compiler.entryPoint !=null ){
        compiler.compile_program_call();
    }else{
        compiler.error("program function not defined. All programs must define a fn null program()");
    }

    ObjFunction* script = compiler.end();
    if(compiler.hadError){
        return COMPILE_ERROR?;
    }
    return script;
}

fn ObjFunction* Compiler.end(Compiler* this){
    this.compile_byte((Byte)OpCode.RETURN, this.previous.line);
    ObjFunction* function = this.currentScope.function;
    if(this.hadError){
        // SHOULD PRINT THE CURRENT FUNCTION NAME 
    }
    return function;
}

fn void Compiler.declaration(Compiler* this){
    if(this.match(TokenType.INTEGER_T, TokenType.FLOAT_T, TokenType.DOUBLE_T, TokenType.STRING_T)){
        this.var_declaration();
    }else if(this.match(TokenType.FN)){
        this.fun_declaration();
    }else{
        this.statement();
    }
}

fn ValueType Compiler.match_return_type(Compiler* this){
    if (this.match(TokenType.NULL)) {
        return ValueType.NULL;
    } else if (this.match(TokenType.INTEGER_T)) {
        return ValueType.INT;
    } else if (this.match(TokenType.FLOAT_T)) {
        return ValueType.FLOAT;
    } else if (this.match(TokenType.DOUBLE_T)) {
        return ValueType.DOUBLE;
    } else {
        this.error("Expect return type before function name.");
        return ValueType.NULL;
    }
}
fn void Compiler.fun_declaration(Compiler* this){

     // 1) Parse return type
    ValueType returnType = this.match_return_type();
    Byte globalsIndex = this.parse_variable("Expect function name");
    Token* nameToken = this.previous;
    bool isTopLevel = (this.currentScope.enclosing == null);
    bool isProgram  = strings_equal(nameToken.value, "program");
    bool isEntryPointCandidate = isTopLevel && isProgram;
    this.mark_initialized();
    this.function(returnType, isEntryPointCandidate);
    this.define_variable(globalsIndex);

}

fn void Compiler.function(Compiler* this, ValueType returnType, bool isEntryPointCandidate){
    ScopeTracker tracker={};
    Token* nameToken = this.previous;

    tracker.init(this, returnType, nameToken.value);
    this.begin_scope();

    this.consume(TokenType.LEFT_PAREN, "Epect '(' after function name.");
    if(!this.check(TokenType.RIGHT_PAREN)){
        do {
            this.currentScope.function.arity++;
            ValueType paramRetType = this.match_return_type();
            if (this.currentScope.function.arity > 255) {
                this.error("Can't have more than 255 parameters.");
            }
            Byte constant = this.parse_variable("Expect parameter name.");
            this.define_variable(constant);
        } while (this.match(TokenType.COMMA));
    }
    this.consume(TokenType.RIGHT_PAREN, "Epect ')' after parameters");
    this.consume(TokenType.LEFT_BRACE, "Expect '{' before function body.");
    this.block();


    ObjFunction* function = this.end();

    this.currentScope = this.currentScope.enclosing;

    if(isEntryPointCandidate){
        if (returnType != ValueType.NULL){
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

fn void Compiler.call(Compiler* this, bool canAssign){
    Byte argCount = this.arg_list();
    this.compile_bytes((Byte)OpCode.CALL, argCount, this.previous.line);
}

fn Byte Compiler.arg_list(Compiler* this){
    Byte count =0;

    if(!this.check(TokenType.RIGHT_PAREN)){
        do{
            this.expression();
            if(count>=Byte.max){
                this.error("Can't have more than 255 arguments");
            }
            count++;
        }   while(this.match(TokenType.COMMA));
    }
    this.consume(TokenType.RIGHT_PAREN, "Expect ')' after arguments.");
    return count;

}

fn void Compiler.statement(Compiler* this){
    if(this.match(TokenType.DEBUG)){
        this.debug_statment();
    }else if (this.match(TokenType.LEFT_BRACE)){
        this.begin_scope();
        this.block();
        this.end_scope();
    }else if (this.match(TokenType.IF)){
        this.if_statement();
    }else if(this.match(TokenType.WHILE)){
        this.while_statement();
    }else if(this.match(TokenType.RETURN)){
        this.return_statement();
    }else{
        this.expression_statement();
    }
}
fn void Compiler.return_statement(Compiler* this){
    int line = this.previous.line;
    if (this.currentScope.enclosing == null) {
        this.error("Cannot return from top-level code.");
    }
    // `return;` – no value
    if (this.check(TokenType.SEMICOLON)) {
        this.consume(TokenType.SEMICOLON, "Expect ';' after return.");
        this.compile_byte((Byte)OpCode.RETURN, line);
        return;
    }

    // `return <expr>;`
    this.expression();
    this.consume(TokenType.SEMICOLON, "Expect ';' after return value.");
    this.compile_byte((Byte)OpCode.RETURN, line);
}

fn void Compiler.debug_statment(Compiler* this){
    this.expression();
    this.consume(TokenType.SEMICOLON, "Expected ';' after value.");
    this.compile_byte((Byte)OpCode.DEBUG, this.previous.line);
}

fn void Compiler.begin_scope(Compiler* this){
    this.currentScope.scopeDepth++;
}

fn void Compiler.block(Compiler* this){
    while (!this.check(TokenType.RIGHT_BRACE) && !this.check(TokenType.EOF)){
        this.declaration();
    }
    this.consume(TokenType.RIGHT_BRACE, "Epxected '}' after block");
}

fn void Compiler.end_scope(Compiler* this){
    this.currentScope.scopeDepth--;
    while (this.currentScope.localCount > 0 && this.currentScope.locals[this.currentScope.localCount - 1].depth >this.currentScope.scopeDepth) {
        this.compile_byte((Byte)OpCode.POP, this.previous.line);
        this.currentScope.localCount--;
    }
}

fn void Compiler.if_statement(Compiler* this) {
    this.consume(TokenType.LEFT_PAREN, "Expect '(' after 'if'.");
    this.expression();
    this.consume(TokenType.RIGHT_PAREN, "Expect ')' after condition."); 

    int thenJump = this.compile_jump(OpCode.JMP_IF_FALSE, this.previous.line);
    this.compile_byte((Byte)OpCode.POP, this.previous.line);

    // require block for then
    this.consume(TokenType.LEFT_BRACE, "Expect '{' after 'if' condition.");
    this.begin_scope();
    this.block();  // will consume until RIGHT_BRACE
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

fn void Compiler.while_statement(Compiler* this){
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

fn void Compiler.expression_statement(Compiler* this){
    this.expression();
    this.consume(TokenType.SEMICOLON, "Expected ';' after expression.");
    this.compile_byte((Byte)OpCode.POP, this.previous.line);
}


fn void Compiler.expression(Compiler* this){
    this.parse_precedence(Precedence.ASSIGNMENT);
}

fn void Compiler.and(Compiler* this){
    int jump = this.compile_jump(OpCode.JMP_IF_FALSE, this.previous.line);

    this.compile_byte((Byte)OpCode.POP, this.previous.line);
    this.parse_precedence(Precedence.AND);

    this.patch_jump(jump);
}

fn void Compiler.or(Compiler* this){
    int elseJump = this.compile_jump(OpCode.JMP_IF_FALSE, this.previous.line);
    int endJump = this.compile_jump(OpCode.JMP, this.previous.line);

    this.patch_jump(elseJump);
    this.compile_byte((Byte)OpCode.POP, this.previous.line);

    this.parse_precedence(Precedence.OR);
    this.patch_jump(endJump);
}

// ---------- Variable declarations & access ----------

fn void Compiler.var_declaration(Compiler* this){
    Byte globalsIndex = this.parse_variable("Expected variable name");
    if(this.match(TokenType.EQUAL)){
        this.expression();
    }else{
        this.compile_byte((Byte)OpCode.CONST_NULL,this.previous.line);
    }

    this.consume(TokenType.SEMICOLON, "Expected ';' after declaration");
    this.define_variable(globalsIndex);
}

fn Byte Compiler.parse_variable(Compiler* this, String errMsg){
    this.consume(TokenType.IDENTIFIER, errMsg);

    this.declare_variable();
    if(this.currentScope.scopeDepth > 0){
        return 0;
    }
    return this.identifier_constant(this.previous);
}

fn void Compiler.declare_variable(Compiler* this){
    if(this.currentScope.scopeDepth==0) return;
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

fn Byte Compiler.identifier_constant(Compiler* this, Token* name){
    return this.ensure_constant(this.get_current_chunk().add_const_string(name.value));
}

fn void Compiler.define_variable(Compiler* this, Byte globalsIndex){
    if(this.currentScope.scopeDepth>0){
        this.mark_initialized();
        return;
    }
    this.compile_bytes((Byte)OpCode.DEFINE_GLOBAL, globalsIndex, this.previous.line);
}

fn void Compiler.mark_initialized(Compiler* this){
    if(this.currentScope.scopeDepth == 0){
        return;
    }
    this.currentScope.locals[this.currentScope.localCount -1 ].depth = this.currentScope.scopeDepth;
}
fn void Compiler.add_local(Compiler* this, Token name){
    if(this.currentScope.localCount == Byte.max){
        this.error("Too many local variables in this block");
        return;
    }
    Local* local = &this.currentScope.locals[this.currentScope.localCount++];
    local.name = name;
    local.depth = -1;
}

fn void Compiler.variable(Compiler* this, bool canAssign){
    this.named_variable(*this.previous, canAssign);
}

fn void Compiler.named_variable(Compiler* this, Token name, bool canAssign){
    Byte getOp, setOp;
    int arg = resolve_local(this.currentScope, &name);

    if(arg != -1){
        getOp = (Byte)OpCode.GET_LOCAL;
        setOp = (Byte)OpCode.SET_LOCAL;
    }else{
        arg = this.identifier_constant(&name);
        getOp = (Byte)OpCode.GET_GLOBAL;
        setOp = (Byte)OpCode.SET_GLOBAL;
    }
    if(canAssign && this.match(TokenType.EQUAL)){
        this.expression();
        this.compile_bytes((Byte)setOp, (Byte)arg, this.previous.line);
    }else{
        this.compile_bytes((Byte)getOp, (Byte)arg, this.previous.line);
    }
}

// ---------- Expression parse functions ----------

fn void Compiler.number(Compiler* this, bool canAssign){
    switch (this.previous.tokenType){
        case TokenType.INTEGER:
            int val = common::parse_int(this.previous.value);
            int constantIndex = this.get_current_chunk().add_const_int(val);
            this.compile_bytes((Byte)OpCode.CONSTANT, this.ensure_constant(constantIndex),this.previous.line);
            this.typeStack.push(ValueType.INT);

        case TokenType.FLOAT:
            float val = common::parse_float(this.previous.value);
            int constantIndex = this.get_current_chunk().add_const_float(val);
            this.compile_bytes((Byte)OpCode.CONSTANT, this.ensure_constant(constantIndex),this.previous.line);
            this.typeStack.push(ValueType.FLOAT);

        case TokenType.DOUBLE:
            double val = common::parse_double(this.previous.value);
            int constantIndex = this.get_current_chunk().add_const_double(val);
            this.compile_bytes((Byte)OpCode.CONSTANT, this.ensure_constant(constantIndex),this.previous.line);
            this.typeStack.push(ValueType.DOUBLE);

        default:
            this.error("Unsupported type");
    }
}

fn void Compiler.string(Compiler* this, bool canAssign){
    String source = this.previous.value;
    int constantIndex = this.get_current_chunk().add_const_string(source);
    this.compile_bytes((Byte)OpCode.CONSTANT, this.ensure_constant(constantIndex),this.previous.line);
    this.typeStack.push(ValueType.GC_OBJ);
}

fn void Compiler.grouping(Compiler* this){
    this.expression();
    this.consume(TokenType.RIGHT_PAREN, "Expected ')' after expression");
}

fn void Compiler.unary(Compiler* this, bool canAssign){
    int operatorLine = this.previous.line;
    TokenType operatorType = this.previous.tokenType;

    this.parse_precedence(Precedence.UNARY);

    switch (operatorType){
        case TokenType.MINUS:
            this.compile_byte((Byte)OpCode.NEGATE_DOUBLE, operatorLine);
        case TokenType.BANG:
            this.compile_byte((Byte)OpCode.NOT, operatorLine);
        default:
            break;
    }
}

fn void Compiler.binary(Compiler* this){
    TokenType operatorType = this.previous.tokenType;
    CompileRule* rule = get_rule(operatorType);
    this.parse_precedence((Precedence)(rule.precedence +1));

    switch(operatorType){
        case TokenType.PLUS:            this.compile_add(this.previous.line);
        case TokenType.MINUS:           this.compile_sub(this.previous.line);
        case TokenType.STAR:            this.compile_mul(this.previous.line);
        case TokenType.SLASH:           this.compile_div(this.previous.line);
        case TokenType.BANG_EQUAL:      this.compile_bytes((Byte)OpCode.EQUAL, (Byte)OpCode.NOT, this.previous.line);
        case TokenType.EQUAL_EQUAL:     this.compile_byte((Byte)OpCode.EQUAL, this.previous.line);
        case TokenType.GREATER:         this.compile_byte((Byte)OpCode.GREATER, this.previous.line);
        case TokenType.GREATER_EQUAL:   this.compile_bytes((Byte)OpCode.LESS, (Byte)OpCode.NOT, this.previous.line);
        case TokenType.LESS:            this.compile_byte((Byte)OpCode.LESS, this.previous.line);
        case TokenType.LESS_EQUAL:      this.compile_bytes((Byte)OpCode.GREATER, (Byte)OpCode.NOT, this.previous.line);
        default: this.error("Unsupported token");
    }
}

fn void Compiler.literal_true(Compiler* this){
    this.compile_byte((Byte)OpCode.CONST_TRUE, this.previous.line);
}

fn void Compiler.literal_false(Compiler*this){
    this.compile_byte((Byte)OpCode.CONST_FALSE, this.previous.line);
}

fn void Compiler.literal_null(Compiler*this){
    this.compile_byte((Byte)OpCode.CONST_NULL, this.previous.line);
}

// ---------- Type-aware arithmetic codegen ----------

fn void Compiler.compile_div(Compiler* this, int line){
    ValueType right = this.typeStack.pop();
    ValueType left = this.typeStack.pop();

    switch (left){
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

fn void Compiler.compile_mul(Compiler* this, int line){
    ValueType right = this.typeStack.pop();
    ValueType left = this.typeStack.pop();

    switch (left){
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

fn void Compiler.compile_sub(Compiler* this, int line){
    ValueType right = this.typeStack.pop();
    ValueType left = this.typeStack.pop();

    switch (left){
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

fn void Compiler.compile_add(Compiler* this, int line){
    ValueType right = this.typeStack.pop();
    ValueType left = this.typeStack.pop();

    switch (left){
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

fn void Compiler.parse_precedence(Compiler* this, Precedence precedence){
    this.advance();
    ParseFn prefixRule = get_rule(this.previous.tokenType).prefix;
    if(prefixRule==null){
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

    if(canAssign && this.match(TokenType.EQUAL)){
        this.error("Invalid assignment target");
    }
}
