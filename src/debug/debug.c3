module debug;
import vm;
import scanner;
import common;

const SHOW_TOKENS = false;
const SHOW_STACK = false;
const SHOW_DISASSEMBLY = false;
const DISASSMBLE_DURING_EXECUTION = false;



macro @print_instruction(Vm* vm){
    $if (DISASSMBLE_DURING_EXECUTION):
        int offset = (int)(vm.frame.ip - &vm.frame.function.chunk.code[0]) - 1;
        common::dissassemble_instruction(&vm.frame.function.chunk, offset);  
  $endif
}
macro @print_stack(Vm* vm){
    $if (SHOW_STACK):
        vm.print_stack();
    $endif
}
macro @print_disassembly(Vm* vm){
    $if (SHOW_DISASSEMBLY):
        vm.print_disassembly();
    $endif
}

macro @print_tokens(Scanner* sc){
    $if (SHOW_TOKENS):
        sc.print_tokens();
    $endif
}
