import compiler;
import main;
import std::core::env;


fn void compile_allocation() @benchmark
{
	compile_file("./src/benchmark/ratchet_benchmarks/allocation.ratc")!!;
}

fn void compile_array_heap() @benchmark
{
	compile_file("./src/benchmark/ratchet_benchmarks/array_heap.ratc")!!;
}

fn void compile_array_inline() @benchmark
{
	compile_file("./src/benchmark/ratchet_benchmarks/array_inline.ratc")!!;
}

fn void compile_borrow_parameters() @benchmark
{
	compile_file("./src/benchmark/ratchet_benchmarks/borrow_parameters.ratc")!!;
}

fn void compile_branching() @benchmark
{
	compile_file("./src/benchmark/ratchet_benchmarks/branching.ratc")!!;
}

fn void compile_floating_point() @benchmark
{
	compile_file("./src/benchmark/ratchet_benchmarks/floating_point.ratc")!!;
}

fn void compile_function_calls() @benchmark
{
	compile_file("./src/benchmark/ratchet_benchmarks/function_calls.ratc")!!;
}

fn void compile_heat_diffusion() @benchmark
{
	compile_file("./src/benchmark/ratchet_benchmarks/heat_diffusion.ratc")!!;
}

fn void compile_integer_math() @benchmark
{
	compile_file("./src/benchmark/ratchet_benchmarks/integer_math.ratc")!!;
}

fn void compile_struct_fields() @benchmark
{
	compile_file("./src/benchmark/ratchet_benchmarks/struct_fields.ratc")!!;
}

fn void compile_struct_references() @benchmark
{
	compile_file("./src/benchmark/ratchet_benchmarks/struct_references.ratc")!!;
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

