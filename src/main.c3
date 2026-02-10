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

bool globalsInitialized = false;

fn int main(String[] args)
{
    if(args.len < 2)
    {
        log::errlogn("You need to specify a file to compile");
        return 1;
    }
	String filename = args[1];
    Lexer lexer ={};
    Parser parser ={};

	String? file = (String)file::load(mem,filename);
	if (catch err = file) {
		// Print the error
		log::errlogn("Failed to load %s: %s", filename, err);
		// We return, so that below 'file' will be unwrapped.
		return 1;
	}

	initialize_globals();
	defer cleanup_globals();

	lexer.init(file);
	lexer.parse_tokens();
	free(file);

    parser.init();
	defer parser.deinit();
    if(catch err = parser.parse()){
        log::errlogn("Parse error");
        return 1;
    }
	//parser.outputAst.print();


	SemanticAnalyzer semanticAnalyzer = {};
	semanticAnalyzer.init(&parser.outputAst);
	defer semanticAnalyzer.deinit();
	
	TypeResult typeResult = semanticAnalyzer.run();
	
	
	foreach(err : semanticAnalyzer.errors){
		log::errlogn("Type error: %s at line %s, expected %s, got %s", err.errKind.asStr, err.errSpan.line, err.expected.type, err.value.type);
	}
	if (typeResult.hadError || semanticAnalyzer.errors.len() > 0) {
		return 1;
	}else{
		log::logn("Compiled successfully");
	}

	MirGenerator mirGen = {};
	defer mirGen.deinit();
	mirGen.init(&parser.outputAst, &semanticAnalyzer.symbolTable);
	mirGen.run();



    return 0;
}


fn void initialize_globals()
{
	if(globalsInitialized){
		return;
	}
	globals::allocator = {};
	globals::allocator.init(mem, 64 * 1024);
	globals::tokens.init(&globals::allocator, 1024);
	globals::tokenValues.init(&globals::allocator, 1024);
	globals::declaredStructs.init(&globals::allocator, 64);
	globals::declaredFunctions.init(&globals::allocator, 128);
	globals::structNamesToIdx.init(&globals::allocator, 64);
	globals::structTypes.init(&globals::allocator, 64);
	globalsInitialized = true;
}

fn void cleanup_globals()
{
	globals::allocator.free();
	globals::tokens = {};
	globals::tokenValues = {};
	globals::declaredStructs = {};
	globals::declaredFunctions = {};
	globals::structNamesToIdx = {};
	globals::structTypes = {};
	globalsInitialized = false;
}
