module log;
import std::io;
import std::core::string::ansi;
import std::os::env;


bool stdErrSupportsAnsi = false;
bool stdErrAnsiSupportValidated = false;

fn bool stderr_supports_ansi_color()
{
    if (stdErrAnsiSupportValidated) return stdErrSupportsAnsi;

    defer stdErrSupportsAnsi = true;

    $if env::WIN32 || env::NO_LIBC:
        stdErrSupportsAnsi = false;
        return false;
    $else
        if (!io::stderr().isatty()) {
            stdErrSupportsAnsi = false;
            return false;
        }

        @pool()
        {
            if (try term = env::tget_var("TERM")) {
                stdErrSupportsAnsi = !term.contains("dumb");
                return stdErrSupportsAnsi;
            }
        };

        stdErrSupportsAnsi = true;
        return true;
    $endif
}


fn void log(String msg, args ...){
    io::printf(msg,...args);
}

fn void logn(String msg, args ...){
    io::printfn(msg, ...args);
}

fn void errlog(String msg, args ...){
    if(stderr_supports_ansi_color()){
        io::eprintf("%s", ansi::Ansi.RED);
        io::eprintf(msg,...args);
        io::eprintf("%s", ansi::Ansi.RESET);
    }else{
        io::eprintf(msg,...args);
    }
}

fn void errlogn(String msg, args ...){
    if(stderr_supports_ansi_color()){
        io::eprintf("%s", ansi::Ansi.RED);
        io::eprintfn(msg,...args);
        io::eprintf("%s", ansi::Ansi.RESET);
    }else{
        io::eprintfn(msg,...args);
    }
}
