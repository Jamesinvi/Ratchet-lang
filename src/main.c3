import scanner;
import compiler;
import common;
import debug;
import vm;
import log;
import std::collections;
import std::io::file;

alias Scanner = scanner::Scanner;
alias Compiler = compiler::Compiler;
alias Chunk = common::Chunk;

fn int main(String[] args)
{
    if(args.len < 2)
    {
        log::errlogn("You need to specify a file to compile");
        return 1;
    }
	String filename = args[1];
    Scanner scanner ={};
    Compiler compiler ={};

    @pool()
    {
        String? file = (String)file::load_temp(filename);
        if (catch err = file)
        {
            // Print the error
            log::errlogn("Failed to load %s: %s", filename, err);
            // We return, so that below 'file' will be unwrapped.
            return 1;
        }
        scanner.init(file);
        scanner.parse_tokens();
    };

    debug::@print_tokens(&scanner);
    compiler.init(scanner.tokens);
    ObjFunction*? entryPoint = compiler::compile(&compiler);
    if(catch err = entryPoint){
        log::errlogn("Compile error");
        return 1;
    }
    scanner.deinit();
    vm::Vm vm ={};

    vm.init(entryPoint);
    vm::run(&vm);
    vm.trackedHeap.debug_print();
    //vm.untrackedHeap.debug_print();
    compiler::print_all_struct_types();
    vm.deinit();
    return 0;
}
