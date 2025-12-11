module vm;
import common;

struct CallFrame
{
    ObjFunction* function;
    Byte* ip;
    ushort base;
}