import parser;
import main;


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

fn void t_10() @test
{
    compile_and_run_file("./test/10_simple_math.ratc","5\n375\n")!!;
}

fn void t_11() @test
{
    compile_and_run_file("./test/11_long_file.ratc","4598913\n1848215163\n-1274708953\n18.870001\n-15.869999\n25.424101\n")!!;
}

fn void t_12() @test
{
    compile_and_run_file("./test/12_very_long_file.ratc","")!!;
}


fn void? compile_and_run_file(String filename, String expectedResult)
{
	defer main::cleanup();
	switch (main::compile_file(filename)) {
		case CompilationResult.NO_ERROR:
			return;
		case CompilationResult.PARSE_ERROR:
			return parser::PARSE_ERROR~;
		case CompilationResult.ANALYSIS_ERROR:
			return parser::analyzer::ANALYSIS_ERR~;
	}
}
