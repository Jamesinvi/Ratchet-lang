module compiler;
import common;
import common::stack;
import std::collections::list;
import std::collections::map;
alias Byte = common::Byte;
alias TypeStack = common::stack::Stack{common::ValueType};

faultdef COMPILE_ERROR;


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
    List{Token} input;
    Token* current;
    Token* previous;
    bool hadError;
    bool panicMode;

    TypeStack typeStack; 
    ObjFunction* entryPoint;

    List{ScopeTracker} scopes;
    ScopeTracker* currentScope;
    ScopeTracker rootScope;

    HashMap{String,ValueType} functionReturnTypes;
    bool hasPendingCalleeType;
    ValueType pendingCalleeReturnType;
    ValueType currentDeclType;

    bool returnFoundInCurrentScope;
}

// ---------- Lifecycle ----------

fn void Compiler.init(Compiler* this, List{Token} tokens)
{
    this.input = tokens;
    this.hadError = false;
    this.panicMode = false;

    this.current = &this.input[0];
    this.previous = this.current;
    this.entryPoint = null;

    this.scopes.init(mem);

    // Root script function + scope
    this.rootScope.depth = 0;
    this.rootScope.localCount = 0;
    this.rootScope.enclosing  = null;
    this.rootScope.function = common::create_obj_function("script", true, ValueType.NULL);
    common::ensure_globals_init();
    common::allocatedConstants.push((Obj*)this.rootScope.function);

    // Dummy local 0
    Local* local = &this.rootScope.locals[this.rootScope.localCount++];
    local.depth = 0;
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
    this.scopes.free();
}

fn Chunk* Compiler.get_current_chunk(Compiler* this)
{
    return &this.currentScope.function.chunk;
}


// ---------- Top-level compile pipeline ----------

fn ObjFunction*? compile(Compiler* compiler)
{
    while (!compiler.match(TokenType.EOF)) {
        compiler.declaration();
    }
    
    if (compiler.entryPoint != null) {
        compiler.emit_program_call();
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
    this.emit_op(OpCode.RETURN, this.previous.line);
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
    int restorePoint = this.typeStack.size;
    this.expression();
    this.consume(TokenType.SEMICOLON, "Expected ';' after expression.");

    if (this.typeStack.size > restorePoint) {
        // Normal case: expression left one value
        ValueType type = this.typeStack.pop();
        this.emit_pop_of_type(type, this.previous.line);

        // If somehow more values are left (buggy rules), drop them too
        while (this.typeStack.size > restorePoint) {
            ValueType extra = this.typeStack.pop();
            this.emit_pop_of_type(extra, this.previous.line);
        }
    }
}

fn void Compiler.debug_statment(Compiler* this)
{
    this.expression();
    this.consume(TokenType.SEMICOLON, "Expected ';' after value.");
    ValueType type = this.typeStack.pop();
    this.emit_op_u8(OpCode.ECHO, (Byte)type, this.previous.line);
}

fn void Compiler.return_statement(Compiler* this)
{
    this.returnFoundInCurrentScope = true;

    int line = this.previous.line;

    if (this.currentScope.enclosing == null) {
        this.error("Cannot return from top-level code.");
    }

    if (this.check(TokenType.SEMICOLON)) {
        this.consume(TokenType.SEMICOLON, "Expect ';' after return.");
        this.emit_op(OpCode.RETURN, line);
        return;
    }

    this.expression();

    ValueType exprType = this.typeStack.pop();
    ValueType expected = this.currentScope.function.returnType;
    if (exprType != expected) {
         this.error("Return type mismatch");
    }


    this.consume(TokenType.SEMICOLON, "Expect ';' after return value.");
    this.emit_op(OpCode.RETURN, line);
}

fn void Compiler.if_statement(Compiler* this)
{
    this.consume(TokenType.LEFT_PAREN, "Expect '(' after 'if'.");
    this.expression();
    this.consume(TokenType.RIGHT_PAREN, "Expect ')' after condition."); 

    // Condition type
    ValueType condType = this.typeStack.pop();

    int thenJump = this.emit_jump(OpCode.JMP_IF_FALSE, this.previous.line);
    this.emit_pop_of_type(condType, this.previous.line); 

    this.consume(TokenType.LEFT_BRACE, "Expect '{' after 'if' condition.");
    this.begin_scope();
    this.block();
    this.end_scope();

    int elseJump = this.emit_jump(OpCode.JMP, this.previous.line);

    this.patch_jump(thenJump);
    // If we jumped here, condition was false and is still on the stack:
    this.emit_pop_of_type(condType, this.previous.line);

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

    ValueType condType = this.typeStack.pop();

    int exitJump = this.emit_jump(OpCode.JMP_IF_FALSE, this.previous.line);
    this.emit_pop_of_type(ValueType.BOOL, this.previous.line); // pop when condition is true

    this.statement();

    this.emit_loop(loopStart);

    this.patch_jump(exitJump);
    this.emit_pop_of_type(ValueType.BOOL, this.previous.line);
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
    this.currentScope.depth++;
}

fn void Compiler.end_scope(Compiler* this)
{
    this.currentScope.depth--;

    while (this.currentScope.localCount > 0 &&
           this.currentScope.locals[this.currentScope.localCount - 1].depth >
           this.currentScope.depth) {

        Local* local = &this.currentScope.locals[this.currentScope.localCount - 1];
        SlotInfo slot = this.currentScope.function.slots[local.slotIdx];

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
            fieldInfo.name = String.copy(this.previous.value, mem); // field name
            fieldInfo.type = fieldType;

            if(this.match(TokenType.EQUAL)){
                this.error("Default field initializers are not yet supported");
            }

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
    ushort index = this.parse_variable("Expected variable name");
    int restorePoint = this.typeStack.size;

    if (this.match(TokenType.EQUAL)) {
        this.expression();
        if(this.typeStack.size > restorePoint){
            this.typeStack.size = restorePoint;
        }
    } else {
        this.emit_op(OpCode.CONST_NULL, this.previous.line);
    }

    if(this.currentScope.depth == 0) {
        this.error("Only functions can be globally defined");
    }

    this.consume(TokenType.SEMICOLON, "Expected ';' after declaration");
    this.define_variable(index);
}

fn ushort Compiler.parse_variable(Compiler* this, String errMsg)
{
    this.consume(TokenType.IDENTIFIER, errMsg);
    Token* name = this.previous;

    this.declare_variable();
    if (this.currentScope.depth > 0) {
        return 0;
    }
    return this.identifier_constant(this.previous);
}

fn void Compiler.declare_variable(Compiler* this)
{
    if (this.currentScope.depth == 0) return;

    Token* name = this.previous;
    for (int i = this.currentScope.localCount - 1; i >= 0; i--) {
        Local* local = &this.currentScope.locals[i];
        if (local.depth != -1 && local.depth < this.currentScope.depth) {
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

    ushort slotIndex = this.currentScope.function.add_slot(this.currentDeclType);
    Local* local = &this.currentScope.locals[this.currentScope.localCount++];
    local.name  = name;
    local.depth = -1;
    local.slotIdx = slotIndex;
}

fn void Compiler.mark_initialized(Compiler* this)
{
    if (this.currentScope.depth == 0) return;
    this.currentScope.locals[this.currentScope.localCount - 1].depth =
        this.currentScope.depth;
}

fn ushort Compiler.identifier_constant(Compiler* this, Token* name)
{
    return this.ensure_constant(this.get_current_chunk().add_const_string(name.value));
}

fn void Compiler.define_variable(Compiler* this, ushort globalsIndex)
{
    if (this.currentScope.depth > 0) {
        this.mark_initialized();
        Local* local = &this.currentScope.locals[this.currentScope.localCount - 1];
        // emit SET_LOCAL with slot index
        this.emit_op_u16(OpCode.SET_LOCAL, local.slotIdx, this.previous.line);
        return;
    }
    this.emit_op_u16(OpCode.DEFINE_GLOBAL, globalsIndex, this.previous.line);
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
    OpCode getOp, setOp;

    // Check if its a local or global
    int localIdx = this.resolve_local(&name);

    if (localIdx != -1) {
        getOp = OpCode.GET_LOCAL;
        setOp = OpCode.SET_LOCAL;

        Local* local = &this.currentScope.locals[localIdx];
        ushort slotIdx = local.slotIdx;
        ValueType varType = this.currentScope.function.slots[slotIdx].type;

        if (!canAssign || !this.check(TokenType.EQUAL)) {
            this.emit_op_u16(getOp, slotIdx, this.previous.line);
            this.typeStack.push(varType);
            return;
        }

        if (this.match(TokenType.EQUAL)) {
            this.expression();
            ValueType rhsType = this.typeStack.pop();
            this.emit_op_u16(setOp, slotIdx, this.previous.line);
            this.maybe_optimize_local_inc_dec(slotIdx, this.previous.line);
        }
    } else {
        ushort arg = this.identifier_constant(&name);
        getOp = OpCode.GET_GLOBAL;
        setOp = OpCode.SET_GLOBAL;

        if (canAssign && this.match(TokenType.EQUAL)) {
            this.expression();
            ValueType rhsType = this.typeStack.pop();
            this.emit_op_u16(setOp, (ushort)arg, this.previous.line);
        } else {
            this.emit_op_u16(getOp, (ushort)arg, this.previous.line);
            this.typeStack.push(ValueType.GC_OBJ);
        }
    }
}

// ---------- Functions & calls ----------

fn void Compiler.fun_declaration(Compiler* this)
{
    ValueType returnType = this.match_type("Expected return type before function name");
    ushort globalsIndex    = this.parse_variable("Expect function name");
    Token* nameToken     = this.previous;

    this.functionReturnTypes.set(nameToken.value, returnType);

    bool isTopLevel = (this.currentScope.enclosing == null);
    bool isProgram = strings_equal(nameToken.value, "program");
    bool isEntryPoint = isTopLevel && isProgram;

    this.mark_initialized();
    this.function(returnType, isEntryPoint);
    this.define_variable(globalsIndex);
}

fn void Compiler.function(Compiler* this, ValueType returnType, bool isEntryPoint)
{
    ScopeTracker* prevScope = this.currentScope;

    // Create a new scope and get a reference to it.
    this.scopes.push({});
    ScopeTracker* newScope = &this.scopes[this.scopes.size-1];
    newScope.init(this, returnType, this.previous.value);
    // We set the enclosing scope to the current one
    newScope.enclosing  = this.currentScope;
    // Install the newly created scope as the current one
    this.currentScope = newScope;

    this.returnFoundInCurrentScope = false;
    this.begin_scope();

    if (isEntryPoint) {
        if (this.entryPoint != null){
            this.error("can only contain one \"program\" function");
        }
        if (returnType != ValueType.NULL) {
            this.error("program must have return type 'null'.");
        }
    }

    // function shape => fn <name> (<arg1>, <arg2>) {   }
    this.consume(TokenType.LEFT_PAREN, "Expect '(' after function name.");
    ushort argsSize = 0;
    // the function could have no parameters, so check
    if (!this.check(TokenType.RIGHT_PAREN)) {
        do {
            // Here we are DEFINING a function, so expressions are NOT valid
            // We expect a variable shape (type + name)
            this.currentScope.function.arity++;
            ValueType paramRetType = this.match_type("Expected parameter type");
            if (this.currentScope.function.arity > 255) {
                this.error("Can't have more than 255 parameters.");
            }
            this.currentDeclType = paramRetType;
            ushort constant = this.parse_variable("Expect parameter name.");
            this.mark_initialized();
            argsSize += common::get_type_size(paramRetType);
        } while (this.match(TokenType.COMMA));
    }
    this.currentScope.function.argsSizeInBytes = argsSize;
    // No shorthands, both ')' and '{' must be present
    this.consume(TokenType.RIGHT_PAREN, "Expect ')' after parameters");
    this.consume(TokenType.LEFT_BRACE, "Expect '{' before body.");
    this.block();

   // Return statement has to be present, for now also in the main "program" func
   if(!this.returnFoundInCurrentScope){
        this.error("No return found in function");
   }

    ObjFunction* function = this.currentScope.function;

    if (isEntryPoint) {
        if (function.arity != 0) {
            this.error("program must not take parameters.");
        }
        this.entryPoint = function;
    }

    this.currentScope = prevScope;            


    ushort offset = this.ensure_constant(this.get_current_chunk().add_const_function(function));
    this.emit_op_u16(OpCode.CONST_FUNC, offset, this.previous.line);
}

fn void Compiler.call(Compiler* this, bool canAssign)
{
    FuncCallInfo callInfo = this.call_args_info();
    this.emit_op_u8(OpCode.CALL, callInfo.argCount, this.previous.line);
    this.emit_u16(callInfo.argsSizeInBytes, this.previous.line);
    
    this.typeStack.pop();
    // If type wasn't set, then error
    // If it was, push it on the stack, and reset the global state
    // "hasPengingCalleeType"
    if (this.hasPendingCalleeType) {
        this.typeStack.push(this.pendingCalleeReturnType);
        this.hasPendingCalleeType = false;
    } else {
        this.error("unknown type for function call");
    }
}


struct FuncCallInfo
{
    Byte argCount;
    ushort argsSizeInBytes;
}

fn FuncCallInfo Compiler.call_args_info(Compiler* this)
{
    FuncCallInfo info = {};
    // We're CALLING a function, so we allow expressions as arguments
    // Consume as many as we can find.
    if (!this.check(TokenType.RIGHT_PAREN)) {
        do {
            this.expression();
            if (info.argCount >= Byte.max) {
                this.error("Can't have more than 255 arguments");
            }
            // Remove all arguments from the type stack
            info.argsSizeInBytes += common::get_type_size(this.typeStack.pop());
            info.argCount++;
        } while (this.match(TokenType.COMMA));
    }

    this.consume(TokenType.RIGHT_PAREN, "Expect ')' after arguments.");
    return info;
}

// ---------- Expressions & precedence ----------

fn void Compiler.expression(Compiler* this)
{
    this.parse_precedence(Precedence.ASSIGNMENT);
}

fn void Compiler.and(Compiler* this)
{
    int line = this.previous.line;
    int jump = this.emit_jump(OpCode.JMP_IF_FALSE, line);

    // left operand (bool) is on top
    ValueType condType = this.typeStack.pop();
    assert(condType == ValueType.BOOL);
    this.emit_pop_of_type(condType, line);

    this.parse_precedence(Precedence.AND);
    this.patch_jump(jump);
}

fn void Compiler.or(Compiler* this)
{
    int line = this.previous.line;
    int elseJump = this.emit_jump(OpCode.JMP_IF_FALSE, line);
    int endJump  = this.emit_jump(OpCode.JMP, line);

    this.patch_jump(elseJump);

    ValueType condType = this.typeStack.pop();
    this.emit_pop_of_type(condType, line);

    this.parse_precedence(Precedence.OR);
    this.patch_jump(endJump);
}

fn void Compiler.grouping(Compiler* this, bool canAssign)
{
    // If we see '(' and then a type, it must be a cast
    if (this.check_builtin_type_token()) {
        ValueType targetType = this.match_type("Expected type in cast.");
        // Ensure we really have closing ')'
        this.consume(TokenType.RIGHT_PAREN, "Expected ')' after cast type.");
        int line = this.previous.line;
        // Now parse the operand at UNARY precedence so:
        // (int)1+2 => cast applies to 1, not (1+2)
        this.parse_precedence(Precedence.UNARY);
        // We now have operand value on stack + typeStack top = operandType
        this.emit_cast(targetType, line);
        return;
    }

    this.expression();
    this.consume(TokenType.RIGHT_PAREN, "Expected ')' after expression");
}


fn void Compiler.number(Compiler* this, bool canAssign)
{
    switch (this.previous.tokenType) {
        case TokenType.INTEGER:
            int ival = common::parse_int(this.previous.value);
            ushort offset = this.get_current_chunk().add_const_int(ival);
            this.emit_op_u16(OpCode.CONST_INT, offset, this.previous.line);
            this.typeStack.push(ValueType.INT);

        case TokenType.FLOAT:
            float  fval = common::parse_float(this.previous.value);
            ushort offset = this.get_current_chunk().add_const_float(fval);
            this.emit_op_u16(OpCode.CONST_FLOAT, offset, this.previous.line);
            this.typeStack.push(ValueType.FLOAT);

        case TokenType.DOUBLE:
            double dval = common::parse_double(this.previous.value);
            ushort offset = this.get_current_chunk().add_const_double(dval);
            this.emit_op_u16(OpCode.CONST_DOUBLE, offset, this.previous.line);
            this.typeStack.push(ValueType.DOUBLE);

        default:
            this.error("Unsupported type");
    }
}

fn void Compiler.string(Compiler* this, bool canAssign)
{
    String source = this.previous.value;
    int offset = this.get_current_chunk().add_const_string(source);
    this.emit_op_u16(OpCode.CONST_STRING, this.ensure_constant(offset), this.previous.line);
    this.typeStack.push(ValueType.GC_OBJ);
}

fn void Compiler.unary(Compiler* this, bool canAssign)
{
    int operatorLine = this.previous.line;
    TokenType operatorType = this.previous.tokenType;

    this.parse_precedence(Precedence.UNARY);

    switch (operatorType) {
        case TokenType.MINUS:       this.emit_op(OpCode.NEGATE_DOUBLE, operatorLine);
        case TokenType.BANG:        this.emit_op(OpCode.NOT, operatorLine);
        default:                    this.error("Unsupported operator");
    }
}


fn void Compiler.binary(Compiler* this)
{
    TokenType   operatorType = this.previous.tokenType;
    CompileRule* rule        = get_rule(operatorType);
    this.parse_precedence((Precedence)(rule.precedence + 1));

    switch (operatorType) {
        case TokenType.PLUS:          this.emit_numeric_binary(OpCode.ADD_INT, OpCode.ADD_FLOAT, OpCode.ADD_DOUBLE, this.previous.line);
        case TokenType.MINUS:         this.emit_numeric_binary(OpCode.SUB_INT, OpCode.SUB_FLOAT, OpCode.SUB_DOUBLE, this.previous.line);
        case TokenType.STAR:          this.emit_numeric_binary(OpCode.MUL_INT, OpCode.MUL_FLOAT, OpCode.MUL_DOUBLE, this.previous.line);
        case TokenType.SLASH:         this.emit_numeric_binary(OpCode.DIV_INT, OpCode.DIV_FLOAT, OpCode.DIV_DOUBLE, this.previous.line);
        case TokenType.BANG_EQUAL:    this.emit_not_equal(this.previous.line);
        case TokenType.EQUAL_EQUAL:   this.emit_numeric_binary(OpCode.INT_EQUAL, OpCode.FLOAT_EQUAL, OpCode.DOUBLE_EQUAL, this.previous.line);
        case TokenType.GREATER:       this.emit_numeric_binary(OpCode.INT_GREATER, OpCode.FLOAT_GREATER, OpCode.DOUBLE_GREATER, this.previous.line);
        case TokenType.GREATER_EQUAL: this.emit_greater_equal(this.previous.line);
        case TokenType.LESS:          this.emit_numeric_binary(OpCode.INT_LESS, OpCode.FLOAT_LESS, OpCode.DOUBLE_LESS, this.previous.line);
        case TokenType.LESS_EQUAL:    this.emit_less_equal(this.previous.line);
        default: this.error("Unsupported token");
    }
}

fn void Compiler.literal_true(Compiler* this)
{
    this.emit_op(OpCode.CONST_TRUE, this.previous.line);
    this.typeStack.push(ValueType.BOOL);
}

fn void Compiler.literal_false(Compiler* this)
{
    this.emit_op(OpCode.CONST_FALSE, this.previous.line);
    this.typeStack.push(ValueType.BOOL);
}

fn void Compiler.literal_null(Compiler* this)
{
    this.emit_op(OpCode.CONST_NULL, this.previous.line);
    this.typeStack.push(ValueType.NULL);
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
