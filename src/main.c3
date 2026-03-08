module main;
import log;

fn int main(String[] args)
{
    if(args.len < 2)
    {
        log::errlogn("You need to specify a file to compile");
        return 1;
    }
	String filename = args[1];

	compile_file(filename);
	cleanup();
    return 0;
}
