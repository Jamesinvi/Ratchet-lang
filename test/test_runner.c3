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


fn void t_00() @test
{
    compile_and_run_file("./test/00_empty.ratc")!!;
}

fn void t_01() @test
{
    compile_and_run_file("./test/01_echo_int_match.ratc")!!;
}

fn void t_02() @test
{
    compile_and_run_file("./test/02_call_identity_double.ratc")!!;
}

fn void t_03() @test
{
    compile_and_run_file("./test/03_call_identity_float.ratc")!!;
}

fn void t_04() @test
{
    compile_and_run_file("./test/04_if_else.ratc")!!;
}

fn void t_05() @test
{
    compile_and_run_file("./test/05_native_clock.ratc")!!;
}

fn void t_06() @test
{
    compile_and_run_file("./test/06_logic.ratc")!!;
}

fn void t_07() @test
{
    compile_and_run_file("./test/07_while_countdown.ratc")!!;
}


fn void t_08() @test
{
    compile_and_run_file("./test/08_fibonacci.ratc")!!;
}


fn void? compile_and_run_file(String filename)
{
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
            return io::FILE_NOT_FOUND?;
        }
        scanner.init(file);
        scanner.parse_tokens();
    };

    debug::@print_tokens(&scanner);
    compiler.init(scanner.tokens);
    ObjFunction*? entryPoint = compiler::compile(&compiler);
    if(catch err = entryPoint){
        scanner.deinit();
        return compiler::COMPILE_ERROR?;
    }
    scanner.deinit();

    vm::Vm vm ={};
    vm.init(entryPoint);
    RunResult res = vm::run(&vm);
    assert(res == RunResult.OK);
    vm.deinit();
    compiler.deinit();
}