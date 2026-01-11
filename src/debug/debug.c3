module debug;
import vm;
import tokenizer;
import common;
import parser;
import log;

macro @print_instruction(Vm* vm){
    $if ($feature(DISASSMBLE_DURING_EXECUTION)):
        int offset = (int)(vm.frame.ip - &vm.frame.function.chunk.code[0]) - 1;
        common::dissassemble_instruction(&vm.frame.function.chunk, offset);  
  $endif
}

macro @print_disassembly(Vm* vm){
    $if ($feature(SHOW_DISASSEMBLY)):
        vm.print_disassembly();
    $endif
}

macro @print_tokens(tokenizer::Tokenizer* sc){
    $if ($feature(SHOW_TOKENS)):
        sc.print_tokens();
    $endif
}

macro @log_compilation(String msg, args ...){
    $if ($feature(TRACE_COMPILATION)):
        log::logn(msg,...args);
    $endif
}


macro @print_type_stack(Stack{CompTypeInfo}* typeStack)
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


