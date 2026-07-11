module main;
import log;
import vm;
import std::io;

fn int main(String[] args)
{
    if(args.len < 2)
    {
        log::errlogn("You need to specify a file to compile");
        return 1;
    }
	String filename = args[1];

	CompilationResult result = compile_file(filename);

	if(result.outcome != CompilationOutcome.NO_ERROR){
		return (int)result.outcome;
	}
	RunResult runResult = vm::run(&result.compiledProgram, io::stdout());
	cleanup();
    return (int)result.outcome;
}
