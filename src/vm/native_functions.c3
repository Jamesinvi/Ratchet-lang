module vm;
import common;
import std::time;

fn Value clock_native(int argCount, Value ... args)
{
    return common::make_double((double)std::time::os::native_clock());
}