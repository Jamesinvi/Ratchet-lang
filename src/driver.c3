module main;

import lexer;
import runtime;
import compiler;
import common;
import debug;
import vm;
import log;
import globals;
import libc;
import std::collections;
import std::io::file;

alias Lexer = lexer::Lexer;
alias Parser = parser::Parser;
alias compilationCtx = globals::compilationCtx;

const PRINT_COMP_PIPELINE = false;

enum CompilationOutcome : int
{
	NO_ERROR,
	PARSE_ERROR,
	ANALYSIS_ERROR,
	MIR_ERROR,
}

struct CompilationResult
{
	CompilationOutcome outcome;
	BCProgram*		   compiledProgram;
}

struct CompilationContext
{
	Lexer 				lexer;
	Parser 				parser;
	SemanticAnalyzer	analyzer;
	MirGenerator		mirGen;
	BCGenerator 		byteCodeGen;
	BCProgram			compiledProgram;
}

fn void CompilationContext.deinit(CompilationContext* this)
{
	this.parser.deinit();
	this.analyzer.deinit();
	this.mirGen.deinit();
	this.byteCodeGen.deinit();
}


fn CompilationResult compile_file(String path)
{
	CompilationResult result;
	result.compiledProgram = null;
	String? file = (String)file::load(mem,path);
	if (catch err = file) {
		// Print the error
		log::errlogn("Failed to load %s: %s", path, err);
		// We return, so that below 'file' will be unwrapped.
		result.outcome = CompilationOutcome.PARSE_ERROR;
		return result;
	}

	globals::initialize_globals();

	compilationCtx.lexer.init(file);
	compilationCtx.lexer.parse_tokens();
	free(file);

	// ------------ Parse, AST ------------
    compilationCtx.parser.init();
    if(catch err = compilationCtx.parser.parse()){
        log::errlogn("Parse error");
		result.outcome = CompilationOutcome.PARSE_ERROR;
		return result;
    }
	if(PRINT_COMP_PIPELINE){
		compilationCtx.parser.outputAst.print();
	}
	// ------------ Analyze, Type-Check --
	compilationCtx.analyzer.init(&compilationCtx.parser.outputAst);
	TypeResult typeResult = compilationCtx.analyzer.run();
	
	foreach(err : compilationCtx.analyzer.errors){
		log::errlogn("Type error: %s at line %s, expected %s, got %s", err.errKind.asStr, err.errSpan.line, err.expected.type, err.value.type);
	}

	if(PRINT_COMP_PIPELINE){
		globals::print_struct_types();
	}

	if (typeResult.hadError || compilationCtx.analyzer.errors.len() > 0) {
		result.outcome = CompilationOutcome.ANALYSIS_ERROR;
		return result;
	}else{
		log::logn("Compiled successfully");
	}

	// ------------ Lower, MIR -----------
	compilationCtx.mirGen.init(&compilationCtx.parser.outputAst, &compilationCtx.analyzer.symbolTable);
	MirGenResult mirResult = compilationCtx.mirGen.run();

	if(PRINT_COMP_PIPELINE){
		compilationCtx.mirGen.output.print(compilationCtx.mirGen.inputAst, compilationCtx.mirGen.symbolTable);
	}

	if(mirResult != MirGenResult.OK){
		result.outcome = CompilationOutcome.MIR_ERROR;
		return result;
	}else{
		log::logn("Lowered to mir successfully");
	}

	result.outcome = CompilationOutcome.NO_ERROR;
	// Lower, Bytecode (WIP)
	compilationCtx.byteCodeGen.init(&compilationCtx);
	compilationCtx.byteCodeGen.run();
	
	if(PRINT_COMP_PIPELINE){
		compilationCtx.byteCodeGen.bcOutput.print();
	}
	
	result.compiledProgram = &compilationCtx.compiledProgram;
	result.outcome = CompilationOutcome.NO_ERROR;
	return result;

}

fn RunResult run(BCProgram* program)
{
	Vm vm = {};
    vm.init(program, io::stdout());
	return vm::run(&vm);
}


fn void cleanup()
{
	globals::cleanup_globals();
}

