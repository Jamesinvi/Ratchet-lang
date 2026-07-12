import compiler;
import main;
import vm;
import log;


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
    compile_and_run_file("./test/06_logic.ratc","false\ntrue\nfalse\ntrue\ntrue\n")!!;
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
    compile_and_run_file("./test/09_simple_casts.ratc", "15\n15.000000\n13.600000\n16.400000\n16\n16.400000\n13.600000\n13\n-3\n")!!;
}

fn void t_10() @test
{
    compile_and_run_file("./test/10_simple_math.ratc","5\n375\n")!!;
}

fn void t_11() @test
{
    compile_and_run_file("./test/11_long_file.ratc", 
	 "4598913\n1848215163\n-1274708953\n18.870001\n-15.869999\n25.424101\n")!!;
}

fn void t_12() @test
{
    compile_and_run_file("./test/12_very_long_file.ratc",
	"4598913\n1848215163\n81242\n144625\n5.000000\n7.000000\n9.000000\n2.500000\n3.500000\n4.500000\n777.892090\n-100.336113\n724.901245\n32.000000\n-2.000000\n5.000000\n11.000000\n3.000000\nfalse\nfalse\n0.350000\n0.325000\n0.525000\n0.687500\n0.156250\n0.356250\n0.344755\n0.283634\n-11.500000\n-37.000000\n")!!;
}

fn void t_13() @test
{
    compile_and_run_file("./test/13_structs_decl_order.ratc","34\n")!!;
}

fn void t_14() @test
{
    compile_and_run_file("./test/14_methods.ratc", "42\n42\n7\n")!!;
}

fn void t_15() @test
{
    compile_and_run_file("./test/15_simple_gc_tracked_vars.ratc", "5\n12\n5.540000\n1.222222\nfalse\n1616\n")!!;
}

fn void t_16() @test
{
    compile_and_run_file("./test/16_borrow_params.ratc", "6\n11\n31\n17\n26\n")!!;
}

faultdef UNKNOWN_COMPILE_ERROR;
faultdef OUTPUT_DOESNT_MATCH_ERROR;
faultdef EXPECTED_ANALYSIS_ERROR;

fn void? compile_and_run_file(String filename, String expectedResult)
{
	defer main::cleanup();
	main::CompilationResult result = main::compile_file(filename);
	switch (result.outcome) 
	{
		case main::CompilationOutcome.NO_ERROR:			break;
		case main::CompilationOutcome.PARSE_ERROR:		return compiler::parser::PARSE_ERROR~;
		case main::CompilationOutcome.ANALYSIS_ERROR:	return compiler::analyzer::ANALYSIS_ERR~;
		default:										return UNKNOWN_COMPILE_ERROR~;
	}


	DString output = dstring::new(mem);
	defer output.free();
	vm::run(&result.compiledProgram, &output);
	log::logn("%s", output);
	if(expectedResult != output.str_view()){
		return OUTPUT_DOESNT_MATCH_ERROR~;
	}
}
