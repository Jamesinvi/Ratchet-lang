module vm;
import common;

struct CallFrame
{
    ObjFunction* function;
    Byte* ip;
    Value* slots;
}