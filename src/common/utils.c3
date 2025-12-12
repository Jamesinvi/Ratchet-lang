module common;
import libc;
import log;

interface DebugPrintable
{
    fn void debug_print();
}

fn bool is_digit(char c) {
    return c >= '0' && c <= '9';
}

fn bool is_alpha_ascii(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

fn int parse_int(String s) {
    int? result = String.to_int(s);
    if(catch err = result){
        log::logn("%s is not parsable as int", s);
        return -1;
    }
    return result;
}
fn float parse_float(String s) {
    float? result = String.to_float(s);
    if(catch err = result){
        log::logn("%s is not parsable as float", s);
        return -1;
    }
    return result;
}

fn double parse_double(String s) {
    double? result = String.to_double(s);
    if(catch err = result){
        log::logn("%s is not parsable as double", s);
        return -1;
    }
    return result;
}


fn bool string_equals(String s1, String s2){
    return s1.len == s2.len && libc::memcmp(s1, s2, s1.len) == 0;
}
