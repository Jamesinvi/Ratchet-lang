import compiler;
import main;
import std::core::env;


fn void b_allocation() @benchmark
{
	compile_file("./src/benchmark/compilation_benchmarks/b_allocation.ratc")!!;
}

fn void b_array_heap() @benchmark
{
	compile_file("./src/benchmark/compilation_benchmarks/b_array_heap.ratc")!!;
}

fn void b_array_inline() @benchmark
{
	compile_file("./src/benchmark/compilation_benchmarks/b_array_inline.ratc")!!;
}

fn void b_borrow_parameters() @benchmark
{
	compile_file("./src/benchmark/compilation_benchmarks/b_borrow_parameters.ratc")!!;
}

fn void b_branching() @benchmark
{
	compile_file("./src/benchmark/compilation_benchmarks/b_branching.ratc")!!;
}

fn void b_floating_point() @benchmark
{
	compile_file("./src/benchmark/compilation_benchmarks/b_floating_point.ratc")!!;
}

fn void b_function_calls() @benchmark
{
	compile_file("./src/benchmark/compilation_benchmarks/b_function_calls.ratc")!!;
}

fn void b_heat_diffusion() @benchmark
{
	compile_file("./src/benchmark/compilation_benchmarks/b_heat_diffusion.ratc")!!;
}

fn void b_integer_math() @benchmark
{
	compile_file("./src/benchmark/compilation_benchmarks/b_integer_math.ratc")!!;
}

fn void b_struct_fields() @benchmark
{
	compile_file("./src/benchmark/compilation_benchmarks/b_struct_fields.ratc")!!;
}

fn void b_struct_references() @benchmark
{
	compile_file("./src/benchmark/compilation_benchmarks/b_struct_references.ratc")!!;
}

fn void b_long_file() @benchmark
{
	compile_file("./src/benchmark/compilation_benchmarks/b_long_file.ratc")!!;
}


faultdef UNKNOWN_COMPILE_ERROR;


fn void setup_benchmarks() @init @feat(BENCHMARKING)
{
	// Do some setup
	// If we're not at max optimizations, runs 10x less iterations
	if (env::COMPILER_OPT_LEVEL < env::CompilerOptLevel.O3)
	{
		set_benchmark_max_iterations(1000);
	}
	else
	{
		set_benchmark_max_iterations(10000);
	}
}

// Measures source loading, compilation, and cleanup; the VM is never run.
fn void? compile_file(String filename)
{
	defer main::cleanup();
	main::CompilationResult result = main::compile_file(filename, true);
	switch (result.outcome)
	{
		case main::CompilationOutcome.NO_ERROR: break;
		case main::CompilationOutcome.PARSE_ERROR: return compiler::parser::PARSE_ERROR~;
		case main::CompilationOutcome.ANALYSIS_ERROR: return compiler::analyzer::ANALYSIS_ERR~;
		default: return UNKNOWN_COMPILE_ERROR~;
	}
}

