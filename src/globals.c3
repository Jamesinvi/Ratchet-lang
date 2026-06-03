module globals;
import parser;
import common;
import main;
import parser::analyzer;
import std::collections::list;
import std::collections::map;

alias CompilationContext = main::CompilationContext;

bool globalsInitialized = false;
DynamicArenaAllocator allocator;

CompilationContext compilationCtx;
List{Token} tokens;
StringInterner internedSourceStrings;

// This map is used by the parser so the user can't define the same struct twice
HashMap{String, DeclIdx} declaredStructs;
HashMap{String, DeclIdx} declaredFunctions;

// This map maps a struct name to its index in structTypes
HashMap{String, sz} structNamesToIdx;
List{CompStructTypeInfo} structTypes;


fn void initialize_globals()
{
	if (globalsInitialized)
	{
		return;
	}
	allocator = { };
	internedSourceStrings = { };
	allocator.init(mem, 64 * 1024);
	tokens.init(&globals::allocator, 1024);
	internedSourceStrings.init(&globals::allocator, 1024);
	declaredStructs.init(&globals::allocator, 64);
	declaredFunctions.init(&globals::allocator, 128);
	structNamesToIdx.init(&globals::allocator, 64);
	structTypes.init(&globals::allocator, 64);
	compilationCtx = { };
	globalsInitialized = true;
}

fn void cleanup_globals()
{
	allocator.free();
	tokens = { };
	declaredStructs = { };
	declaredFunctions = { };
	structNamesToIdx = { };
	structTypes = { };
	internedSourceStrings = { };
	compilationCtx.deinit();

	globalsInitialized = false;
}
