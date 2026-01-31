module globals;
import parser;
import common;
import parser::analyzer;
import std::collections::list;
import std::collections::map;

DynamicArenaAllocator allocator;

List{Token} tokens;
List{String} tokenValues;

// This map is used by the parser so the user can't define the same struct twice
HashMap{String, DeclIdx} declaredStructs;
HashMap{String, DeclIdx} declaredFunctions;

// This map maps a struct name to its index in structTypes
HashMap{String, usz} structNamesToIdx;
List{CompStructTypeInfo} structTypes;
