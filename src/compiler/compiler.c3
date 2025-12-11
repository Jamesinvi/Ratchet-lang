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
    ObjFunction*         entryPoint;

    List{ScopeTracker}   scopes;
    ScopeTracker*        currentScope;
    ScopeTracker         rootScope;

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

    this.scopes.init(mem);

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
    this.scopes.free();
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
    this.compile_op(OpCode.RETURN, this.previous.line);
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
        this.compile_pop_of_type(type, this.previous.line);

        // If somehow more values are left (buggy rules), drop them too
        while (this.typeStack.size > restorePoint) {
            ValueType extra = this.typeStack.pop();
            this.compile_pop_of_type(extra, this.previous.line);
        }
    }
}

fn void Compiler.debug_statment(Compiler* this)
{
    this.expression();
    this.consume(TokenType.SEMICOLON, "Expected ';' after value.");
    this.compile_op(OpCode.ECHO, this.previous.line);
}

fn void Compiler.return_statement(Compiler* this)
{
    int line = this.previous.line;

    if (this.currentScope.enclosing == null) {
        this.error("Cannot return from top-level code.");
    }

    if (this.check(TokenType.SEMICOLON)) {
        this.consume(TokenType.SEMICOLON, "Expect ';' after return.");
        this.compile_op(OpCode.RETURN, line);
        return;
    }

    this.expression();
    this.consume(TokenType.SEMICOLON, "Expect ';' after return value.");
    this.compile_op(OpCode.RETURN, line);
}

fn void Compiler.if_statement(Compiler* this)
{
    this.consume(TokenType.LEFT_PAREN, "Expect '(' after 'if'.");
    this.expression();
    this.consume(TokenType.RIGHT_PAREN, "Expect ')' after condition."); 

    // Condition type
    ValueType condType = this.typeStack.pop();

    int thenJump = this.compile_jump(OpCode.JMP_IF_FALSE, this.previous.line);
    this.compile_pop_of_type(condType, this.previous.line); 

    this.consume(TokenType.LEFT_BRACE, "Expect '{' after 'if' condition.");
    this.begin_scope();
    this.block();
    this.end_scope();

    int elseJump = this.compile_jump(OpCode.JMP, this.previous.line);

    this.patch_jump(thenJump);
    // If we jumped here, condition was false and is still on the stack:
    this.compile_pop_of_type(condType, this.previous.line);

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

    int exitJump = this.compile_jump(OpCode.JMP_IF_FALSE, this.previous.line);
    this.compile_pop_of_type(ValueType.BOOL, this.previous.line); // pop when condition is true

    this.statement();

    this.compile_loop(loopStart);

    this.patch_jump(exitJump);
    this.compile_pop_of_type(condType, this.previous.line);
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
    ushort index = this.parse_variable("Expected variable name");
    int restorePoint = this.typeStack.size;

    if (this.match(TokenType.EQUAL)) {
        this.expression();
        if(this.typeStack.size > restorePoint){
            this.typeStack.size = restorePoint;
        }
    } else {
        this.compile_op(OpCode.CONST_NULL, this.previous.line);
    }

    this.consume(TokenType.SEMICOLON, "Expected ';' after declaration");
    this.define_variable(index);
}

fn ushort Compiler.parse_variable(Compiler* this, String errMsg)
{
    this.consume(TokenType.IDENTIFIER, errMsg);
    Token* name = this.previous;

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

    ushort slotIndex = this.currentScope.function.add_slot(this.currentDeclType);
    Local* local = &this.currentScope.locals[this.currentScope.localCount++];
    local.name  = name;
    local.depth = -1;
    local.slotIdx = slotIndex;


}

fn void Compiler.mark_initialized(Compiler* this)
{
    if (this.currentScope.scopeDepth == 0) return;
    this.currentScope.locals[this.currentScope.localCount - 1].depth =
        this.currentScope.scopeDepth;
}

fn ushort Compiler.identifier_constant(Compiler* this, Token* name)
{
    return this.ensure_constant(this.get_current_chunk().add_const_string(name.value));
}

fn void Compiler.define_variable(Compiler* this, ushort globalsIndex)
{
    if (this.currentScope.scopeDepth > 0) {
        this.mark_initialized();
        Local* local = &this.currentScope.locals[this.currentScope.localCount - 1];
        // emit SET_LOCAL with slot index
        this.compile_op_u16(OpCode.SET_LOCAL, local.slotIdx, this.previous.line);
        return;
    }
    this.compile_op_u16(OpCode.DEFINE_GLOBAL, globalsIndex, this.previous.line);
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
    int localIdx = this.resolve_local(&name);

    if (localIdx != -1) {
        getOp = OpCode.GET_LOCAL;
        setOp = OpCode.SET_LOCAL;

        Local* local = &this.currentScope.locals[localIdx];
        ushort slotIdx = local.slotIdx;
        ValueType varType = this.currentScope.function.slots[slotIdx].type;

        if (!canAssign || !this.check(TokenType.EQUAL)) {
            this.compile_op_u16(getOp, slotIdx, this.previous.line);
            this.typeStack.push(varType);
            return;
        }

        if (this.match(TokenType.EQUAL)) {
            this.expression();
            ValueType rhsType = this.typeStack.pop();
            this.compile_op_u16(setOp, slotIdx, this.previous.line);
            this.maybe_optimize_local_inc_dec(slotIdx, this.previous.line);
        }
    } else {
        ushort arg = this.identifier_constant(&name);
        getOp = OpCode.GET_GLOBAL;
        setOp = OpCode.SET_GLOBAL;

        if (canAssign && this.match(TokenType.EQUAL)) {
            this.expression();
            ValueType rhsType = this.typeStack.pop();
            this.compile_op_u16(setOp, (ushort)arg, this.previous.line);
        } else {
            this.compile_op_u16(getOp, (ushort)arg, this.previous.line);
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

    bool isTopLevel           = (this.currentScope.enclosing == null);
    bool isProgram            = strings_equal(nameToken.value, "program");
    bool isEntryPointCandidate = isTopLevel && isProgram;

    this.mark_initialized();
    this.function(returnType, isEntryPointCandidate);
    this.define_variable(globalsIndex);
}

fn void Compiler.function(Compiler* this, ValueType returnType, bool isEntryPointCandidate)
{
    ScopeTracker* prevScope = this.currentScope;
    this.scopes.push({});
    ScopeTracker* newScope = &this.scopes[this.scopes.size-1];
    newScope.init(this, returnType, this.previous.value);
    
    this.begin_scope();

    this.consume(TokenType.LEFT_PAREN, "Expect '(' after function name.");
    if (!this.check(TokenType.RIGHT_PAREN)) {
        do {
            this.currentScope.function.arity++;
            ValueType paramRetType = this.match_type("Expected parameter type");
            if (this.currentScope.function.arity > 255) {
                this.error("Can't have more than 255 parameters.");
            }
            this.currentDeclType = paramRetType;
            ushort constant = this.parse_variable("Expect parameter name.");
            this.define_variable(constant);
        } while (this.match(TokenType.COMMA));
    }
    this.consume(TokenType.RIGHT_PAREN, "Expect ')' after parameters");
    this.consume(TokenType.LEFT_BRACE, "Expect '{' before body.");
    this.block();

    ObjFunction* function = this.currentScope.function; 
    this.compile_op(OpCode.RETURN, this.previous.line);  
    
    this.currentScope = prevScope;            

    if (isEntryPointCandidate) {
        if (returnType != ValueType.NULL) {
            this.error("program must have return type 'null'.");
        }
        if (function.arity != 0) {
            this.error("program must not take parameters.");
        }
        this.entryPoint = function;
    }

    ushort offset = this.ensure_constant(this.get_current_chunk().add_const_function(function));
    this.compile_op_u16(OpCode.CONST_FUNC, offset, this.previous.line);
}
fn void Compiler.call(Compiler* this, bool canAssign)
{
    Byte argCount = this.arg_list();
    this.compile_op_u8(OpCode.CALL, argCount, this.previous.line);
    
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
    int line = this.previous.line;
    int jump = this.compile_jump(OpCode.JMP_IF_FALSE, line);

    // left operand (bool) is on top
    ValueType condType = this.typeStack.pop();
    assert(condType == ValueType.BOOL);
    this.compile_pop_of_type(condType, line);

    this.parse_precedence(Precedence.AND);
    this.patch_jump(jump);
}

fn void Compiler.or(Compiler* this)
{
    int line = this.previous.line;
    int elseJump = this.compile_jump(OpCode.JMP_IF_FALSE, line);
    int endJump  = this.compile_jump(OpCode.JMP, line);

    this.patch_jump(elseJump);

    ValueType condType = this.typeStack.pop();
    this.compile_pop_of_type(condType, line);

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
            int ival = common::parse_int(this.previous.value);
            ushort offset = this.get_current_chunk().add_const_int(ival);
            this.compile_op_u16(OpCode.CONST_INT, offset, this.previous.line);
            this.typeStack.push(ValueType.INT);

        case TokenType.FLOAT:
            float  fval = common::parse_float(this.previous.value);
            ushort offset = this.get_current_chunk().add_const_float(fval);
            this.compile_op_u16(OpCode.CONST_FLOAT, offset, this.previous.line);
            this.typeStack.push(ValueType.FLOAT);

        case TokenType.DOUBLE:
            double dval = common::parse_double(this.previous.value);
            ushort offset = this.get_current_chunk().add_const_double(dval);
            this.compile_op_u16(OpCode.CONST_DOUBLE, offset, this.previous.line);
            this.typeStack.push(ValueType.DOUBLE);

        default:
            this.error("Unsupported type");
    }
}

fn void Compiler.string(Compiler* this, bool canAssign)
{
    String source = this.previous.value;
    int offset = this.get_current_chunk().add_const_string(source);
    this.compile_op_u16(OpCode.CONST_STRING, this.ensure_constant(offset), this.previous.line);
    this.typeStack.push(ValueType.GC_OBJ);
}

fn void Compiler.unary(Compiler* this, bool canAssign)
{
    int       operatorLine = this.previous.line;
    TokenType operatorType = this.previous.tokenType;

    this.parse_precedence(Precedence.UNARY);

    switch (operatorType) {
        case TokenType.MINUS:
            this.compile_op(OpCode.NEGATE_DOUBLE, operatorLine);
        case TokenType.BANG:
            this.compile_op(OpCode.NOT, operatorLine);
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
        case TokenType.BANG_EQUAL:    this.compile_not_equal(this.previous.line);
        case TokenType.EQUAL_EQUAL:   this.compile_equal(this.previous.line);
        case TokenType.GREATER:       this.compile_greater(this.previous.line);
        case TokenType.GREATER_EQUAL: this.compile_greater_equal(this.previous.line);
        case TokenType.LESS:          this.compile_less(this.previous.line);
        case TokenType.LESS_EQUAL:    this.compile_less_equal(this.previous.line);
        default: this.error("Unsupported token");
    }
}

fn void Compiler.literal_true(Compiler* this)
{
    this.compile_op(OpCode.CONST_TRUE, this.previous.line);
}

fn void Compiler.literal_false(Compiler* this)
{
    this.compile_op(OpCode.CONST_FALSE, this.previous.line);
}

fn void Compiler.literal_null(Compiler* this)
{
    this.compile_op(OpCode.CONST_NULL, this.previous.line);
}

// ---------- Type-aware arithmetic/logic codegen ----------

// ---------- Type-aware comparison codegen ----------

// a == b
fn void Compiler.compile_equal(Compiler* this, int line)
{
    ValueType right = this.typeStack.pop();
    ValueType left  = this.typeStack.pop();

    if (left != right) {
        this.error("Type mismatch in '=='.");
        return;
    }

    switch (left) {
        case ValueType.INT:
            this.compile_op(OpCode.INT_EQUAL, line);
        case ValueType.FLOAT:
            this.compile_op(OpCode.FLOAT_EQUAL, line);
        case ValueType.DOUBLE:
            this.compile_op(OpCode.DOUBLE_EQUAL, line);
        default:
            this.error("Unsupported '==' operand types");
    }

    // Comparisons always produce bool
    this.typeStack.push(ValueType.BOOL);
}

// a != b  =>  !(a == b)
fn void Compiler.compile_not_equal(Compiler* this, int line)
{
    // This pops both operands and pushes a bool
    this.compile_equal(line);
    // Now negate the bool on top of the stack
    this.compile_op(OpCode.NOT, line);
    // Type is still BOOL
}

// a < b
fn void Compiler.compile_less(Compiler* this, int line)
{
    ValueType right = this.typeStack.pop();
    ValueType left  = this.typeStack.pop();

    if (left != right) {
        this.error("Type mismatch in '<'.");
        return;
    }

    switch (left) {
        case ValueType.INT:
            this.compile_op(OpCode.INT_LESS, line);
        case ValueType.FLOAT:
            this.compile_op(OpCode.FLOAT_LESS, line);
        case ValueType.DOUBLE:
            this.compile_op(OpCode.DOUBLE_LESS, line);
        default:
            this.error("Unsupported '<' operand types");
    }

    this.typeStack.push(ValueType.BOOL);
}

// a > b
fn void Compiler.compile_greater(Compiler* this, int line)
{
    ValueType right = this.typeStack.pop();
    ValueType left  = this.typeStack.pop();

    if (left != right) {
        this.error("Type mismatch in '>'.");
        return;
    }

    switch (left) {
        case ValueType.INT:
            this.compile_op(OpCode.INT_GREATER, line);
        case ValueType.FLOAT:
            this.compile_op(OpCode.FLOAT_GREATER, line);
        case ValueType.DOUBLE:
            this.compile_op(OpCode.DOUBLE_GREATER, line);
        default:
            this.error("Unsupported '>' operand types");
    }

    this.typeStack.push(ValueType.BOOL);
}

// a <= b  =>  !(a > b)
fn void Compiler.compile_less_equal(Compiler* this, int line)
{
    ValueType right = this.typeStack.pop();
    ValueType left  = this.typeStack.pop();

    if (left != right) {
        this.error("Type mismatch in '<='.");
        return;
    }

    switch (left) {
        case ValueType.INT:
            this.compile_op(OpCode.INT_GREATER, line);
        case ValueType.FLOAT:
            this.compile_op(OpCode.FLOAT_GREATER, line);
        case ValueType.DOUBLE:
            this.compile_op(OpCode.DOUBLE_GREATER, line);
        default:
            this.error("Unsupported '<=' operand types");
    }

    this.compile_op(OpCode.NOT, line);
    this.typeStack.push(ValueType.BOOL);
}

// a >= b  =>  !(a < b)
fn void Compiler.compile_greater_equal(Compiler* this, int line)
{
    ValueType right = this.typeStack.pop();
    ValueType left  = this.typeStack.pop();

    if (left != right) {
        this.error("Type mismatch in '>='.");
        return;
    }

    switch (left) {
        case ValueType.INT:
            this.compile_op(OpCode.INT_LESS, line);
        case ValueType.FLOAT:
            this.compile_op(OpCode.FLOAT_LESS, line);
        case ValueType.DOUBLE:
            this.compile_op(OpCode.DOUBLE_LESS, line);
        default:
            this.error("Unsupported '>=' operand types");
    }

    this.compile_op(OpCode.NOT, line);
    this.typeStack.push(ValueType.BOOL);
}

fn void Compiler.compile_div(Compiler* this, int line)
{
    ValueType right = this.typeStack.pop();
    ValueType left  = this.typeStack.pop();

    switch (left) {
        case ValueType.INT:
            this.compile_op(OpCode.DIV_INT, line);
            this.typeStack.push(ValueType.INT);
        case ValueType.FLOAT:
            this.compile_op(OpCode.DIV_FLOAT, line);
            this.typeStack.push(ValueType.FLOAT);
        case ValueType.DOUBLE:
            this.compile_op(OpCode.DIV_DOUBLE, line);
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
            this.compile_op(OpCode.MUL_INT, line);
            this.typeStack.push(ValueType.INT);
        case ValueType.FLOAT:
            this.compile_op(OpCode.MUL_FLOAT, line);
            this.typeStack.push(ValueType.FLOAT);
        case ValueType.DOUBLE:
            this.compile_op(OpCode.MUL_DOUBLE, line);
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
            this.compile_op(OpCode.SUB_INT, line);
            this.typeStack.push(ValueType.INT);
        case ValueType.FLOAT:
            this.compile_op(OpCode.SUB_FLOAT, line);
            this.typeStack.push(ValueType.FLOAT);
        case ValueType.DOUBLE:
            this.compile_op(OpCode.SUB_DOUBLE, line);
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
            this.compile_op(OpCode.ADD_INT, line);
            this.typeStack.push(ValueType.INT);
        case ValueType.FLOAT:
            this.compile_op(OpCode.ADD_FLOAT, line);
            this.typeStack.push(ValueType.FLOAT);
        case ValueType.DOUBLE:
            this.compile_op(OpCode.ADD_DOUBLE, line);
            this.typeStack.push(ValueType.DOUBLE);
        case ValueType.GC_OBJ:
            this.compile_op(OpCode.CONCAT_STRING, line);
            this.typeStack.push(ValueType.NO_GC_OBJ);
        case ValueType.NO_GC_OBJ:
            this.compile_op(OpCode.CONCAT_STRING, line);
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
