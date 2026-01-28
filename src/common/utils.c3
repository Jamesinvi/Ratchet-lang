module common;
import libc;
import log;

fn bool is_digit(char c)@inline {
    return c >= '0' && c <= '9';
}

fn bool is_alpha_ascii(char c) @inline{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

fn bool is_ref_char(char c) @inline{
    return (c == '&' || c == '*');
}

fn bool string_equals(String s1, String s2) @inline{
    return s1.len == s2.len && s1 == s2;
}
