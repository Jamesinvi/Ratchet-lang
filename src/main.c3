module main;
import log;
import vm;
import std::io;
import globals;

fn int main(String[] args)
{
	if (args.len < 2)
	{
		log::errlogn("You need to specify a file to compile");
		return 1;
	}
	String filename = args[1];

	CompilationResult result = compile_file(filename);

	if (result.outcome != CompilationOutcome.NO_ERROR)
	{
		return (int)result.outcome;
	}

	if (!KEEP_DEBUG_DATA_IN_MEMORY)
	{
		globals::cleanup_compilation_only_data();
	}
	RunResult runResult = vm::run(&result.compiledProgram, io::stdout());
	cleanup();
	return runResult == RunResult.OK ? 0 : 1;
}

