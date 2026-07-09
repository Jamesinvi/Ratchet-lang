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

fn void list_append_fill(List{Type}* list, Type val, sz maxSize) <Type>
{
	list.reserve(maxSize);
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

<* 
 	Helper to align fields so that all fields respect their alignment, so if i have an int at the top of the stack
	and i need to store a double, i add 4 bytes of padding so alignment is correct, vm thanks us
*>
fn short align_offset(short offset, short alignment)
{
	short remainder = offset % alignment;
	if (remainder == 0) {
		return offset;
	}
	return offset + (alignment - remainder);
}

