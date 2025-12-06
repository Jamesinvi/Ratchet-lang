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
    List{Chunk} chunks;
    TypeStack typeStack; 
    Chunk* currentChunk;
}

// ---------- Lifecycle ----------

fn void Compiler.init(Compiler* this, List{Token} tokens){
    this.input = tokens;
    this.chunks.init(mem);

    this.current = &this.input[0];
    this.previous = this.current;
    Chunk c = {};
    c.init();
    this.chunks.push(c);
    this.currentChunk = &this.chunks[0];
}

fn void Compiler.deinit(Compiler* this){
    foreach(c : this.chunks){
        c.deinit();
    }
    this.typeStack.free();
    this.chunks.free();
}

fn Chunk* Compiler.get_current_chunk(Compiler* this){
    return this.currentChunk;
}

// ---------- Top-level compile pipeline ----------

fn CompileResult compile(Compiler* compiler){
    while(!compiler.match(TokenType.EOF)){
        compiler.declaration();
    }
    compiler.compile_byte((Byte)OpCode.RETURN, compiler.previous.line);
    return CompileResult.OK;
}

fn void Compiler.declaration(Compiler* this){
    if(this.match(TokenType.INTEGER_T, TokenType.FLOAT_T, TokenType.DOUBLE_T, TokenType.STRING_T)){
        this.var_declaration();
    }else{
        this.statement();
    }
}

fn void Compiler.statement(Compiler* this){
    if(this.match(TokenType.DEBUG)){
        this.print_statement();
    }else{
        this.expression_statement();
    }
}

fn void Compiler.expression_statement(Compiler* this){
    this.expression();
    this.consume(TokenType.SEMICOLON, "Expected ';' after expression.");
    this.compile_byte((Byte)OpCode.POP, this.previous.line);
}

fn void Compiler.print_statement(Compiler* this){
    this.expression();
    this.consume(TokenType.SEMICOLON, "Expected ';' after value.");
    this.compile_byte((Byte)OpCode.DEBUG, this.previous.line);
}

fn void Compiler.expression(Compiler* this){
    this.parse_precedence(Precedence.ASSIGNMENT);
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
    return this.identifier_constant(this.previous);
}

fn Byte Compiler.identifier_constant(Compiler* this, Token* name){
    return this.ensure_constant(this.get_current_chunk().add_const_string(name.value));
}

fn void Compiler.define_variable(Compiler* this, Byte globalsIndex){
    this.compile_bytes((Byte)OpCode.DEFINE_GLOBAL, globalsIndex, this.previous.line);
}

fn void Compiler.variable(Compiler* this, bool canAssign){
    this.named_variable(*this.previous, canAssign);
}

fn void Compiler.named_variable(Compiler* this, Token name, bool canAssign){
    Byte arg = this.identifier_constant(&name);
    if(canAssign && this.match(TokenType.EQUAL)){
        this.expression();
        this.compile_bytes((Byte)OpCode.SET_GLOBAL, arg, this.previous.line);
    }else{
        this.compile_bytes((Byte)OpCode.GET_GLOBAL, arg, this.previous.line);
    }
}

// ---------- Expression parse functions ----------

fn void Compiler.number(Compiler* this){
    switch (this.previous.tokenType){
        case TokenType.INTEGER:
            int val = common::parse_int(this.previous.value);
            int constantIndex = this.currentChunk.add_const_int(val);
            this.compile_bytes((Byte)OpCode.CONSTANT, this.ensure_constant(constantIndex),this.previous.line);
            this.typeStack.push(ValueType.INT);

        case TokenType.FLOAT:
            float val = common::parse_float(this.previous.value);
            int constantIndex = this.currentChunk.add_const_float(val);
            this.compile_bytes((Byte)OpCode.CONSTANT, this.ensure_constant(constantIndex),this.previous.line);
            this.typeStack.push(ValueType.FLOAT);

        case TokenType.DOUBLE:
            double val = common::parse_double(this.previous.value);
            int constantIndex = this.currentChunk.add_const_double(val);
            this.compile_bytes((Byte)OpCode.CONSTANT, this.ensure_constant(constantIndex),this.previous.line);
            this.typeStack.push(ValueType.DOUBLE);

        default:
            this.error("Unsupported type");
    }
}

fn void Compiler.string(Compiler* this){
    String source = this.previous.value;
    int constantIndex = this.currentChunk.add_const_string(source);
    this.compile_bytes((Byte)OpCode.CONSTANT, this.ensure_constant(constantIndex),this.previous.line);
    this.typeStack.push(ValueType.GC_OBJ);
}

fn void Compiler.grouping(Compiler* this){
    this.expression();
    this.consume(TokenType.RIGHT_PAREN, "Expected ')' after expression");
}

fn void Compiler.unary(Compiler* this){
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
    prefixRule(this);

    while (precedence <= get_rule(this.current.tokenType).precedence) {
        this.advance();
        ParseFn infixRule = get_rule(this.previous.tokenType).infix;
        infixRule(this);
    }

    if(canAssign && this.match(TokenType.EQUAL)){
        this.error("Invalid assignment target");
    }
}
