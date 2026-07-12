module debug;
import vm;
import compiler;
import lexer;
import common;
import log;

macro @print_tokens(lexer::Lexer* sc){
    $if ($feature(SHOW_TOKENS)):
        sc.print_tokens();
    $endif
}

macro @log_parse(String msg, args ...){
    $if ($feature(TRACE_PARSER)):
        log::logn(msg,...args);
    $endif
}

macro @log_analysis(String msg, args ...){
    $if ($feature(TRACE_ANALYSIS)):
        log::logn(msg,...args);
    $endif
}

macro @log_mir(String msg, args ...){
    $if ($feature(TRACE_MIR)):
        log::logn(msg,...args);
    $endif
}

macro @log_bytecode(String msg, args ...){
    $if ($feature(TRACE_BYTECODE)):
        log::logn(msg,...args);
    $endif
}

macro @print_type_stack(Stack{TypeInfo}* typeStack)
{
    $if ($feature(TRACE_COMPILATION)):
        log::logn("------Compilation type stack-----");
        if(typeStack.size == 0){
            log::logn("empty!\n---------------------");
        } else{
            for(usz i = (usz)typeStack.size-1; i == 0; i--){
                log::log("[%s, refTo: %s]", typeStack.items[i].type, typeStack.items[i].refToType);
            }
            log::logn("\n----------------");
        }
    $endif
}


