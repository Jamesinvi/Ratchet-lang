import scanner;
import compiler;
import common;
import debug;
import vm;
import log;
import libc;
import std::collections;
import std::io::file;

alias Scanner = scanner::Scanner;
alias Compiler = compiler::Compiler;


fn void t_00() @test
{
    compile_and_run_file("./test/00_empty.ratc", "")!!;
}

fn void t_01() @test
{
    compile_and_run_file("./test/01_echo_int_match.ratc", "7\n")!!;
}

fn void t_02() @test
{
    compile_and_run_file("./test/02_call_identity_double.ratc","2.300000\n")!!;
}

fn void t_03() @test
{
    compile_and_run_file("./test/03_call_identity_float.ratc","2.300000\n")!!;
}

fn void t_04() @test
{
    compile_and_run_file("./test/04_if_else.ratc","1\n")!!;
}

fn void t_05() @test
{
    compile_and_run_file("./test/05_struct_simple.ratc","14.000000\n0.000000\n0.000000\n14.000000\n0.000000\n33.000000\n")!!;
}

fn void t_06() @test
{
    compile_and_run_file("./test/06_logic.ratc","false\ntrue\n")!!;
}

fn void t_07() @test
{
    compile_and_run_file("./test/07_while_countdown.ratc","3\n2\n1\n")!!;
}

fn void t_08() @test
{
    compile_and_run_file("./test/08_fibonacci.ratc","377\n")!!;
}

fn void t_09() @test
{
    compile_and_run_file("./test/09_cast_string.ratc","hello\n15\n")!!;
}


fn void? compile_and_run_file(String filename, String expectedResult)
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
    DString output;
    output.init(mem);
    vm.init(entryPoint, &output);
    RunResult res = vm::run(&vm);
    assert(res == RunResult.OK);
    assert(output.str_view() == expectedResult);
    vm.deinit();
    compiler.deinit();
    output.free();
}