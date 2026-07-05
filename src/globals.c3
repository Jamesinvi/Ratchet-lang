module globals;
import compiler;
import common;
import main;
import std::collections::list;
import std::collections::map;

alias CompilationContext = main::CompilationContext;

bool globalsInitialized = false;
DynamicArenaAllocator compAllocator;
DynamicArenaAllocator runtimeAllocator;

CompilationContext compilationCtx;
List{Token} tokens;
StringInterner internedSourceStrings;

// This map is used by the parser so the user can't define the same struct twice
HashMap{String, DeclIdx} declaredStructs;
HashMap{String, DeclIdx} declaredFunctions;

// This map maps a struct name to its index in structTypes
HashMap{String, int} structNamesToIdx;
List{CompStructTypeInfo} structTypes;


fn void initialize_globals()
{
	if (globalsInitialized)
	{
		return;
	}
	compAllocator = { };
	runtimeAllocator = { };
	internedSourceStrings = { };
	compAllocator.init(mem, 64 * 1024);
	runtimeAllocator.init(mem, 64 * 512);
	tokens.init(&globals::compAllocator, 1024);
	internedSourceStrings.init(&globals::compAllocator, 1024);
	declaredStructs.init(&globals::compAllocator, 64);
	declaredFunctions.init(&globals::compAllocator, 128);
	structNamesToIdx.init(&globals::compAllocator, 64);
	structTypes.init(&globals::compAllocator, 64);
	compilationCtx = { };
	globalsInitialized = true;
}

fn void cleanup_globals()
{
	compilationCtx.deinit();
	compAllocator.free();
	runtimeAllocator.free();
	tokens = { };
	declaredStructs = { };
	declaredFunctions = { };
	structNamesToIdx = { };
	structTypes = { };
	internedSourceStrings = { };

	globalsInitialized = false;
}
