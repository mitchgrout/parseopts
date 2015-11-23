//Very basic application that shows usage of parseopts

import parseopts;

@help("Usage: ./parseopts [OPTIONS]")
struct MyData {
	@shortFlag('v')
	bool verbose;

	@shortFlag('d')
	bool daemon;

	@shortFlag('p')
	string path;
}

void main(string[] args){
	import std.stdio;
	if(args.length == 1){
		helpText!MyData.writeln;
		return;
	}

	MyData result = parseOpts!MyData(args, config.bundling);
	writefln("result.verbose = %s", result.verbose);
	writefln("result.daemon = %s", result.daemon);
	writefln("result.path = %s", result.path);
}
