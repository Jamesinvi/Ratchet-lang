
module vm;
import common;
import log;

fn void Vm.print_stack(Vm* vm)
{
	for(sz i = 0; i < 64; i+= int::size){
		int* src = (int*)&vm.stack[i];
		int value = mem::load(src, int::alignment);
		log::log("| %s ", value);
	}
	log::log("\n");
}