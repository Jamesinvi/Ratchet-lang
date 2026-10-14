import compiler;
import main;
import vm;
import runtime;
import log;


fn void t_00_empty() @test
{
	compile_and_run_file("./test/t_00_empty.ratc", "")!!;
}

fn void t_01_echo_int_match() @test
{
	compile_and_run_file("./test/t_01_echo_int_match.ratc", "7\n")!!;
}

fn void t_02_call_identity_numeric() @test
{
	compile_and_run_file("./test/t_02_call_identity_numeric.ratc", "2.300000\n2.300000\n")!!;
}

fn void t_04_if_else() @test
{
	compile_and_run_file("./test/t_04_if_else.ratc", "1\n")!!;
}

fn void t_05_struct_simple() @test
{
	compile_and_run_file("./test/t_05_struct_simple.ratc", "14.000000\n0.000000\n0.000000\n14.000000\n0.000000\n33.000000\n0.000000\n0.000000\n0.000000\n0.000000\n0.000000\n0.000000\n", true, true)!!;
}

fn void t_06_logic() @test
{
	compile_and_run_file("./test/t_06_logic.ratc", "false\ntrue\nfalse\ntrue\ntrue\n")!!;
}

fn void t_07_while_countdown() @test
{
	compile_and_run_file("./test/t_07_while_countdown.ratc", "3\n2\n1\n")!!;
}

fn void t_08_fibonacci() @test
{
	compile_and_run_file("./test/t_08_fibonacci.ratc", "377\n")!!;
}

fn void t_09_simple_casts() @test
{
	compile_and_run_file("./test/t_09_simple_casts.ratc", "15\n15.000000\n13.600000\n16.400000\n16\n16.400000\n13.600000\n13\n-3\n")!!;
}

fn void t_10_simple_math() @test
{
	compile_and_run_file("./test/t_10_simple_math.ratc", "5\n375\n")!!;
}

fn void t_11_long_file() @test
{
	// Day 4/day 8 stock, sales, receipts, fingerprint and revenue; ledger totals; 25 checks, 0 failures.
	compile_and_run_file("./test/t_11_long_file.ratc", "107\n397\n108\n17597\n734.000000\n23\n589\n216\n26548\n1135.000000\n864\n275\n49\n2161\n25\n0\n")!!;
}

fn void t_12_very_long_file() @test
{
	// Daily/final reports, snapshot/reference checks and relief planning; 0 failures in 676 checks.
	compile_and_run_file(
		"./test/t_12_very_long_file.ratc",
		"771621\n454963\n3142\n577225\n248942\n4245\n440959\n111084\n5154\n348503\n962680\n5963\n542343\n1693\n578\n447\n41\n657\n1324\n1368\n11408\n103817\n102828\n64\n64\n962680\n988121\n57\n962680\n117047\n4669\n48\n1398\n1899\n548\n238\n31511\n174\n33474\n0\n68\n87\n0\n676\n11326\n"
	)!!;
}

fn void t_13_structs_decl_order() @test
{
	compile_and_run_file("./test/t_13_structs_decl_order.ratc", "34\n")!!;
}

fn void t_14_methods() @test
{
	compile_and_run_file("./test/t_14_methods.ratc", "42\n42\n7\n")!!;
}

fn void t_15_simple_gc_tracked_vars() @test
{
	compile_and_run_file("./test/t_15_simple_gc_tracked_vars.ratc", "5\n12\n5.540000\n1.222222\nfalse\n1616\n")!!;
}

fn void t_16_borrow_params() @test
{
	compile_and_run_file("./test/t_16_borrow_params.ratc", "6\n11\n31\n17\n26\n")!!;
}

fn void t_17_struct_refs() @test
{
	compile_and_run_file("./test/t_17_struct_refs.ratc", "15\n22\n")!!;
}

fn void t_18_break_continue() @test
{
	compile_and_run_file("./test/t_18_break_continue.ratc", "1\n3\n4\n")!!;
}

fn void t_19_indexing() @test
{
	compile_and_run_file("./test/t_19_indexing.ratc", "42\n1\n42\n17\n2.500000\n13\n19\n2.500000\n13\n3.500000\n29\n31\n")!!;
}

fn void b_runtime_benchmark() @benchmark
{
	compile_and_run_file("./test/b_runtime_benchmark.ratc", "71586238\n", false)!!;
}

fn void t_20_index_negative() @test
{
	defer main::cleanup();
	main::CompilationResult result = main::compile_file("./test/t_20_index_negative.ratc");
	assert(result.outcome == main::CompilationOutcome.NO_ERROR);
	DString output = dstring::new(mem);
	defer output.free();
	assert(vm::run(&result.compiledProgram, &output) == vm::RunResult.RUNTIME_ERR);
	assert(output.len() == 0);
}

fn void t_21_index_past_end() @test
{
	defer main::cleanup();
	main::CompilationResult result = main::compile_file("./test/t_21_index_past_end.ratc");
	assert(result.outcome == main::CompilationOutcome.NO_ERROR);
	DString output = dstring::new(mem);
	defer output.free();
	assert(vm::run(&result.compiledProgram, &output) == vm::RunResult.RUNTIME_ERR);
	assert(output.len() == 0);
}

fn void t_22_array_properties() @test
{
	compile_and_run_file("./test/t_22_array_properties.ratc", "3\n3\n7\n8\n5\n5\n9\n16\n4\n4\n11\n16\n4\n4\n13\n16\n4\n16\n4\n17\n8\n15\n35\n35\n25\n37\n6\n8\n")!!;
}

fn void t_23_place_evaluation() @test
{
	compile_and_run_file("./test/t_23_place_evaluation.ratc", "3\n1\n3\n2\n6\n3\n8\n4\n12\n5\n23\n6\n3\n1\n2\n31\n42\n3\n57\n42\n4\n12\n61\n")!!;
}

fn void t_24_property_index_bounds() @test
{
	compile_and_expect_runtime_error("./test/t_24_property_index_bounds.ratc");
}

fn void t_25_null_array_length() @test
{
	compile_and_expect_runtime_error("./test/t_25_null_array_length.ratc");
}

fn void t_27_null_inline_array_property() @test
{
	compile_and_expect_runtime_error("./test/t_27_null_inline_array_property.ratc");
}
faultdef UNKNOWN_COMPILE_ERROR;
faultdef OUTPUT_DOESNT_MATCH_ERROR;
faultdef EXPECTED_ANALYSIS_ERROR;

fn void? compile_and_run_file(String filename, String expectedResult, bool printOutput = true, bool checkStaticOffsets = false)
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

	if (checkStaticOffsets)
	{
		foreach (instruction : result.compiledProgram.instructions)
		{
			assert(instruction.opCode != runtime::BCOpCode.LOCAL_ADDR);
			assert(instruction.opCode != runtime::BCOpCode.GLOBAL_ADDR);
			assert(instruction.opCode != runtime::BCOpCode.OFFSET_ADDR);
			assert(instruction.opCode != runtime::BCOpCode.INDEX_ADDR);
		}
	}

	DString output = dstring::new(mem);
	defer output.free();
	if (vm::run(&result.compiledProgram, &output) != vm::RunResult.OK) return vm::RUNTIME_ERROR~;
	if (printOutput)
	{
		log::logn("%s", output);
	}
	if (expectedResult != output.str_view())
	{
		return OUTPUT_DOESNT_MATCH_ERROR~;
	}
}

fn void compile_and_expect_runtime_error(String filename)
{
	defer main::cleanup();
	main::CompilationResult result = main::compile_file(filename);
	assert(result.outcome == main::CompilationOutcome.NO_ERROR);
	DString output = dstring::new(mem);
	defer output.free();
	assert(vm::run(&result.compiledProgram, &output) == vm::RunResult.RUNTIME_ERR);
	assert(output.len() == 0);
}

