module debug;
import vm;
import scanner;
import common;
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

macro @print_tokens(scanner::Scanner* sc){
    $if ($feature(SHOW_TOKENS)):
        sc.print_tokens();
    $endif
}

macro @log_compilation(String msg, args ...){
    $if ($feature(TRACE_COMPILATION)):
        log::logn(msg,...args);
    $endif
}

