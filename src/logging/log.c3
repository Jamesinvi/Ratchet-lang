module log;
import std::io;



fn void log(String msg, args ...){
    io::printf(msg,...args);
}

fn void logn(String msg, args ...){
    io::printfn(msg,...args);
}

fn void errlog(String msg, args ...){
    io::eprintf(msg,...args);
}

fn void errlogn(String msg, args ...){
    io::eprintfn(msg,...args);
}
