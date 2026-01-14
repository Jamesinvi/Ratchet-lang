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

fn bool is_ref_char(char c){
    return (c == '&' || c == '*');
}


fn bool string_equals(String s1, String s2){
    return s1.len == s2.len && libc::memcmp(s1, s2, s1.len) == 0;
}
