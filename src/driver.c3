module main;

import lexer;
import parser;
import mir;
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
alias Chunk = common::Chunk;
alias compilationCtx = globals::compilationCtx;

enum CompilationResult : int
{
	NO_ERROR,
	PARSE_ERROR,
	ANALYSIS_ERROR,
}

struct CompilationContext
{
	Lexer 				lexer;
	Parser 				parser;
	SemanticAnalyzer	analyzer;
	MirGenerator		mirGen;
}

fn void CompilationContext.deinit(CompilationContext* this)
{
	this.parser.deinit();
	this.analyzer.deinit();
	this.mirGen.deinit();
}


fn CompilationResult compile_file(String path)
{
	String? file = (String)file::load(mem,path);
	if (catch err = file) {
		// Print the error
		log::errlogn("Failed to load %s: %s", path, err);
		// We return, so that below 'file' will be unwrapped.
		return CompilationResult.PARSE_ERROR;
	}

	globals::initialize_globals();

	compilationCtx.lexer.init(file);
	compilationCtx.lexer.parse_tokens();
	free(file);

    compilationCtx.parser.init();
    if(catch err = compilationCtx.parser.parse()){
        log::errlogn("Parse error");
        return CompilationResult.PARSE_ERROR;
    }
	compilationCtx.parser.outputAst.print();


	compilationCtx.analyzer.init(&compilationCtx.parser.outputAst);
	
	TypeResult typeResult = compilationCtx.analyzer.run();
	
	foreach(err : compilationCtx.analyzer.errors){
		log::errlogn("Type error: %s at line %s, expected %s, got %s", err.errKind.asStr, err.errSpan.line, err.expected.type, err.value.type);
	}
	if (typeResult.hadError || compilationCtx.analyzer.errors.len() > 0) {
		return CompilationResult.ANALYSIS_ERROR;
	}else{
		log::logn("Compiled successfully");
	}

	compilationCtx.mirGen.init(&compilationCtx.parser.outputAst, &compilationCtx.analyzer.symbolTable);
	compilationCtx.mirGen.run();

	return CompilationResult.NO_ERROR;

}


fn void cleanup()
{
	globals::cleanup_globals();
}


