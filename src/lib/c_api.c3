module lib;
import main;
import std::core::string;
import parser::analyzer;
import globals;

fn int ratchet_compile_file(ZString path) @export("ratchet_compile_file")
{
    return (int)main::compile_file(path.str_view());
}

fn ZString ratchet_get_last_err() @export("ratchet_get_last_error")
{
    main::CompilationContext* ctx = &globals::compilationCtx;

    if(ctx.parser.hadError){
        return "parse error (specific query not available yet)\0";
    }

    if(ctx.analyzer.errors.len() > 0){
        TypeResult err = ctx.analyzer.errors[ctx.analyzer.errors.len()-1];
        return (ZString)string::format(&globals::allocator, "Anaylsis Error: %s at line %s, expected %s, got %s\0", err.errKind.asStr, err.errSpan.line, err.expected.type, err.value.type); 
    }
    return "\0";
}

fn void ratchet_cleanup() @export ("ratchet_cleanup")
{   
    main::cleanup();
}
