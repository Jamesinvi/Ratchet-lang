module globals;
import compiler;
import common;
import main;
import std::collections::list;
import std::collections::map;

alias CompilationContext = main::CompilationContext;

bool globalsInitialized = false;
DynamicArenaAllocator compAllocator;		// Freed after compilation finishes unless in debug mode
DynamicArenaAllocator typeInfoAllocator;	// Kept at runtime until type registry is disposed before shutdown
DynamicArenaAllocator runtimeAllocator;		// Kept at runtime until program finishes

CompilationContext compilationCtx;
List{Token} tokens;
StringInterner internedSourceStrings;

// This map is used by the parser so the user can't define the same struct twice
StringInterner typeInfoStrings;
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
	typeInfoAllocator = { };
	runtimeAllocator = { };
	internedSourceStrings = { };
	typeInfoStrings = { };
	compAllocator.init(mem, 64 * 1024);
	runtimeAllocator.init(mem, 32 * 1024);
	typeInfoAllocator.init(mem, 32 * 1024);
	internedSourceStrings.init(&globals::compAllocator, 512);
	typeInfoStrings.init(&globals::typeInfoAllocator, 512);
	declaredStructs.init(&globals::compAllocator, 64);
	declaredFunctions.init(&globals::compAllocator, 128);
	structNamesToIdx.init(&globals::compAllocator, 64);
	structTypes.init(&globals::typeInfoAllocator, 64);
	compilationCtx = { };
	globalsInitialized = true;
}

fn void cleanup_globals()
{
	compAllocator.free();
	runtimeAllocator.free();
	typeInfoAllocator.free();
	compilationCtx = { };
	tokens = { };
	declaredStructs = { };
	declaredFunctions = { };
	structNamesToIdx = { };
	structTypes = { };
	internedSourceStrings = { };
	typeInfoStrings = { };

	globalsInitialized = false;
}


fn void print_struct_types()
{
	foreach(&structInfo : structTypes){
		structInfo.print();
	}
}
