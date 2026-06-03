module common;
import libc;
import log;
import std::collections::list;

fn bool is_digit(char c)@inline {
    return c >= '0' && c <= '9';
}

fn bool is_alpha_ascii(char c) @inline{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

fn bool is_ref_char(char c) @inline{
    return (c == '&' || c == '*');
}

fn void list_fill(List{Type}* list, Type val, sz maxSize) <Type>
{
    for(sz i = 0; i < maxSize; i++){
        list.push(val);
    }
}

fn void list_set_values(List{Type}* list, Type val) <Type>
{
    for(sz i = 0; i < list.len(); i++){
        (*list)[i] = val;
    }
}

