module vm;
import common;
import std::time;

fn double clock_native()
{
    return (double)std::time::os::native_clock();
}