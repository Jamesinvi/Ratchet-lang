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
alias ctx = globals::compilationCtx;

const PRINT_COMP_PIPELINE = true;

enum CompilationOutcome : int
{
	NO_ERROR,
	PARSE_ERROR,
	ANALYSIS_ERROR,
	MIR_ERROR,
	BYTECODE_ERROR,
}

struct CompilationResult
{
	CompilationOutcome outcome;
	BCProgram		   compiledProgram;
}

struct CompilationContext
{
	ProgramAst 			ast;
	SymbolTable 		symbolTable;
	MirProgram			mirProgram;
	BCProgram			bcProgram;

	bool 				hadParseError;
	List{TypeResult}	analysisErrors;
	bool 				hadMirError;
	bool 				hadBytecodeError;
}

fn CompilationResult compile_file(String path)
{
	CompilationResult result;
	String? file = (String)file::load(mem,path);
	if (catch err = file) {
		// Print the error
		log::errlogn("Failed to load %s: %s", path, err);
		// We return, so that below 'file' will be unwrapped.
		result.outcome = CompilationOutcome.PARSE_ERROR;
		return result;
	}

	globals::initialize_globals();

	globals::tokens = lexer::run_lexer(file, &globals::compAllocator);
	free(file);

	// ------------ Parse, AST ------------
	ProgramAst? parseResult = parser::run_parser(globals::tokens, &globals::compAllocator);
    if(catch err = parseResult){
        log::errlogn("Parse error");
		ctx.hadParseError = true;
		result.outcome = CompilationOutcome.PARSE_ERROR;
		return result;
    }
	ctx.ast = parseResult;
	if(PRINT_COMP_PIPELINE){
		ctx.ast.print();
	}
	// ------------ Analyze, Type-Check --
	List{TypeResult} analyzerErrors = compiler::analyzer::analyze(&ctx.ast, &ctx.symbolTable, &globals::compAllocator);
	ctx.analysisErrors = analyzerErrors;
	foreach(err : analyzerErrors){
		log::errlogn("Type error: %s at line %s, expected %s, got %s", err.errKind.asStr, err.errSpan.line, err.expected.type, err.value.type);
	}

	if(PRINT_COMP_PIPELINE){
		globals::print_struct_types();
	}

	if (analyzerErrors.len() > 0) {
		result.outcome = CompilationOutcome.ANALYSIS_ERROR;
		return result;
	}else{
		log::logn("Compiled successfully");
	}

	// ------------ Lower, MIR -----------
	MirProgram? mirProgram = compiler::mir::generate_mir(&ctx.ast, &ctx.symbolTable, &globals::compAllocator);
	if(catch err = mirProgram){
        log::errlogn("Mir generation error");
		ctx.hadMirError = true;
		result.outcome = CompilationOutcome.MIR_ERROR;
		return result;
    }
	ctx.mirProgram = mirProgram;

	if(PRINT_COMP_PIPELINE){
		mirProgram.print(&ctx.ast, &ctx.symbolTable);
	}

	// ------------ Lower, Bytecode -----------
	BCProgram? bcProgram = compiler::bytecode::generate_bytecode(&ctx.ast, &ctx.symbolTable, &ctx.mirProgram, &globals::runtimeAllocator);
	if(catch err = bcProgram){
        log::errlogn("Bytecode generation error");
		ctx.hadBytecodeError = true;
		result.outcome = CompilationOutcome.BYTECODE_ERROR;
		return result;
    }

	if(PRINT_COMP_PIPELINE){
		bcProgram.print();
	}
	ctx.bcProgram = bcProgram;
	result.compiledProgram = bcProgram;
	result.outcome = CompilationOutcome.NO_ERROR;
	return result;

}

fn void cleanup()
{
	globals::cleanup_globals();
}
