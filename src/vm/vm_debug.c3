
module vm;
import common;
import log;

fn void Vm.print_stack(Vm* vm)
{
	// This function is AI generated.
	// It should print all the stack bytes in hex
	log::logn("stack bytes:");
	for(sz i = 0; i < 64; i++){
		if (i % 16 == 0) {
			log::log("%04d: ", i);
		}

		log::log("%02x ", vm.stack[i]);

		if ((i + 1) % 16 == 0) {
			log::log("\n");
		}
	}
}
