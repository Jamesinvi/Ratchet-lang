import tokenizer;
import parser;
import common;
import debug;
import vm;
import log;
import libc;
import std::collections;
import std::io::file;

alias Tokenizer = tokenizer::Tokenizer;
alias Parser = parser::Parser;
alias Chunk = common::Chunk;

fn int main(String[] args)
{
    if(args.len < 2)
    {
        log::errlogn("You need to specify a file to compile");
        return 1;
    }
	String filename = args[1];
    Tokenizer tokenizer ={};
    Parser parser ={};

    @pool()
    {
        String? file = (String)file::load_temp(filename);
        if (catch err = file)
        {
            // Print the error
            log::errlogn("Failed to load %s: %s", filename, err);
            // We return, so that below 'file' will be unwrapped.
            return 1;
        }
        tokenizer.init(file);
        tokenizer.parse_tokens();
    };

    debug::@print_tokens(&tokenizer);
    parser.init(tokenizer.tokens);
    if(catch err = parser.parse()){
        log::errlogn("Compile error");
        return 1;
    }
    tokenizer.deinit();
    parser.outputAst.print();
	SemanticAnalyzer semanticAnalyzer = {};
	semanticAnalyzer.init(&parser.outputAst);
	TypeResult typeResult = semanticAnalyzer.run();
	log::log("\n   Compilation output:");
	foreach(err : semanticAnalyzer.errors){
		log::errlogn("Type error: %s at line %s, expected %s, got %s", err.errKind.asStr, err.errSpan.line, err.expected.type, err.value.type);
	}
	if(semanticAnalyzer.errors.len() == 0){
		log::logn(" compiled successfully");
	}
	if (typeResult.hadError || semanticAnalyzer.errors.len() > 0) {
		return 1;
	}
	//parser.allocator.print_report();

    // vm::Vm vm ={};
    // vm.init(entryPoint, io::stdout());
    // vm::run(&vm);
    //vm.trackedHeap.debug_print();
    //vm.untrackedHeap.debug_print();
    //parser::print_all_struct_types();
    // vm.deinit();
    return 0;
}
