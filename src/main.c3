import scanner;
import compiler;
import common;
import std::io;
import std::collections;
import vm;
alias Scanner = scanner::Scanner;
alias Compiler = compiler::Compiler;
alias Chunk = common::Chunk;

fn int main(String[] args)
{
	String filename = args[1];
    Scanner scanner ={};
    Compiler compiler ={};

    @pool()
    {
        String? file = (String)file::load_temp(filename);
        if (catch err = file)
        {
            // Print the error
            io::printfn("Failed to load %s: %s", filename, err);
            // We return, so that below 'file' will be unwrapped.
            return 1;
        }
        scanner.init(file);
        scanner.parse_tokens();
    };

    scanner.print_tokens();
    compiler.init(scanner.tokens);
    compiler::compile(&compiler);

    vm::Vm vm ={};
    vm.init();
    vm::run(&vm, &compiler.chunks[0]);
    vm.trackedHeap.debug_print();
    vm.untrackedHeap.debug_print();

    vm.deinit();
    scanner.deinit();
    return 0;
}
