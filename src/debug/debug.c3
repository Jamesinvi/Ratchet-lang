module debug;
import vm;
import scanner;
import common;

const SHOW_TOKENS = false;
const SHOW_STACK = false;
const SHOW_DISASSEMBLY = true;
const DISASSMBLE_DURING_EXECUTION = false;



macro @print_instruction(Vm* vm){
    $if (DISASSMBLE_DURING_EXECUTION):
        common::dissassemble_instruction(&vm.frame.function.chunk,(int)(vm.frame.ip - &vm.frame.function.chunk.code[0]));
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
