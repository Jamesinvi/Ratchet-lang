module common;
import globals;
import std::collections::list;
import std::collections::map;
alias StringID = sz;
alias StringIdx = int;

struct InternedString
{
	StringInterner* owner;
	StringID id;
}

macro String InternedString.text(InternedString* this)
{
    return this.owner.strings[this.id];
}

struct StringInterner
{
	List{String} strings;
	HashMap{String, InternedString} ids;
	Allocator allocator; 
}

fn void StringInterner.init(StringInterner* this, Allocator allocator, sz size)
{
	this.allocator = allocator;
	this.strings.init(this.allocator, size);
	this.ids.init(this.allocator, size);
}

fn InternedString StringInterner.get_or_intern(StringInterner* this, String input)
{
    InternedString? found = this.ids.get(input);
    if (catch err = found) {
        StringID nextIdx = this.strings.len();
        String stringCopy = String.copy(input, this.allocator);
        this.strings.push(stringCopy);
        InternedString internedString = { .owner = this, .id = nextIdx };
        this.ids[stringCopy] = internedString;
        return internedString;
    }
    return found;
}
