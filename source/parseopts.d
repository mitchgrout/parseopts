module parseopts;

import std.traits;
import std.stdio;
import std.regex;
import std.format;

//UDAs

struct shortFlag {
	this(char value){
		assert((value >= 'a' && value <= 'z')
		    || (value >= 'A' && value <= 'Z')
		    || (value >= '0' && value <= '9'), "Invalid flag supplied, must be in the range a-z, A-Z, or 0-9");
		this.value = value;	
	}
	char value;
	alias value this;
}


struct help {
	this(string value){
		assert(value.length, "Help text cannot be empty");
		this.value = value;
	}
	string value;
	alias value this;
}

enum ignore;

//UDAs


//Configuration options for parsing
enum config {
	//Nothing
	none = 0,
	
	//Allow short bool options to be combined, -a -b -c <=> -abc
	bundling = 1,
	
	//Pass-through unrecognized flags, --no-such-variable-name
	passThrough = 2,
	
	//Stop on anything that does not look like an option
	stopOnNonOption = 4,
	
	//To implement: Remove flags from args[] after they are evaluate
	consumeArgs = 8 
}


//Basic custom exception used when passThrough is not set
class ArgumentException : Exception {
	this(string msg, string file = __FILE__, size_t line = __LINE__, Exception next = null){
		super(msg, file, line, next);
	}
}


//Check if a member is a valid option
template isValidOption(T, string member){
	enum isValidOption = !hasUDA!(__traits(getMember, T, member), ignore) 
			&& is(typeof(__traits(getMember, T, member) = typeof(__traits(getMember, T, member)).init));
}


//Temporary workaround for aliasing a __traits expression
//Does not work for making assignments, __traits must be used
private alias Alias(alias s) = s;

template parseOpts(T) if(is(T == struct) || (is(T == class) && __traits(compiles, new T))) {
	//Default settings:
	// - Strictly case sensitive (not configurable)
	// - No bundling permissible
	// - No passthrough permissible
	T parseOpts(ref string[] args, config options = config.none) {
		import std.conv : to;
		
		T res;
		static if(is(T == class)) res = new T();

		//Matches all long and short options, i.e. -a, --daemon, --no-preserve-root
		//Does not match things such as: meme--tastic, me-me, "why are there --spaces", or "--option lmao"
		static regopt = ctRegex!`^-[a-zA-Z0-9]+$|^--[a-zA-Z0-9][a-zA-Z0-9\-]*$`;
		//static longopt = ctRegex!`^--[a-zA-Z0-9][a-zA-Z0-9\-]*$`;
		static shortopt = ctRegex!`^-[a-zA-Z0-9]+$`;

		//If the arguments are completely empty, just give up straight away
		if(!args.length) return res;

		size_t i = 0;
		//Check if the ./program is still in the args, if so, skip ahead one instead. We don't want to consume this.
		if(!args[0].match(regopt)) i++;
		
		args_loop:
		for(; i < args.length; i++){
			//stopOnNonOption: If it doesn't look like an option, fail
			if(!args[i].match(regopt)){
				if(options & config.stopOnNonOption){
					throw new ArgumentException(format("Non-option found at index %s: \"%s\"", i, args[i]));
				} else {
					continue args_loop;
				}
			} 

			//Some bundled options to deal with (strictly bool flags)
			if(options & config.bundling && args[i].match(shortopt)) {
				//Trim off the initial - and check every flag
				bundle_loop:
				foreach(flag ; args[i][1..$]){
					foreach(member; __traits(allMembers, T)){
						//Check if it's an option, has a short flag, and is boolean
						static if(isValidOption!(T, member) 
							&& hasUDA!(__traits(getMember, T, member), shortFlag) 
							&& is(typeof(__traits(getMember, T, member) = true))){
							if(getUDAs!(__traits(getMember, T, member), shortFlag)[0] == flag){
								__traits(getMember, res, member) = true;
								continue bundle_loop;
							}
						}
					}

					//If we reach this point, then an unknown flag was found. Fail if no passthrough
					if(options & config.passThrough){
						continue bundle_loop;
					} else {
						throw new ArgumentException(format("Unknown bundled flag at index %s: \"%s\"", i, flag));
					}
				}
				if(options & config.consumeArgs){
					args[i] = ""; //Remove the args we just dealt with
				}
				continue args_loop;
			}

			//Static-foreach of all the members in the type T
			foreach(member; __traits(allMembers, T)){
				//This is simply used for code cleanliness
				alias var = Alias!(__traits(getMember, res, member));
				
				//Ensure that the variable is 1) not set to be ignored, 2) is assignable (covers void functions and immutability)
				static if(isValidOption!(T, member)){
					//The regopt regex ensures the input is at least two characters long, so the below is safe
					if(args[i][0..2] == "--" && args[i][2..$] == member){
						static if(is(typeof(var) == bool)) {
							__traits(getMember, res, member) = true; 
						} else { 
							if(i+1 >= args.length) throw new ArgumentException("Expected value to follow flag %s at index %s", args[i], i);
							__traits(getMember, res, member) = args[++i].to!(typeof(var));
							if(options & config.consumeArgs) args[i-1] = "";
						}
						if(options & config.consumeArgs){
							args[i] = ""; //Remove the args we just dealt with
						}
						continue args_loop;
					}
					static if(hasUDA!(var, shortFlag)){
						//If bundling is not enabled, then we handle short options here
						//Strictly 2 characters long (-x), so the first check must be length==2
						if(args[i].length == 2 && args[i][0] == '-' && args[i][1] == getUDAs!(var, shortFlag)[0]){
							static if(is(typeof(var) == bool)) {
								__traits(getMember, res, member) = true; 
							} else { 
								if(i+1 >= args.length) throw new ArgumentException("Expected value to follow flag %s at index %s", args[i], i);
								__traits(getMember, res, member) = args[++i].to!(typeof(var));
								if(options & config.consumeArgs) args[i-1] = "";
							}
							if(options & config.consumeArgs){
								args[i] = ""; //Remove the args we just dealt with
							}
							continue args_loop;
						}
					}
				}
			}
			//Unknown flag was given
			if(!(options & config.passThrough))
				throw new ArgumentException(format("Unknown flag found at index %s: \"%s\"", i, args[i]));
		}

 		//Filter out all the blank values in the args
		if(options & config.consumeArgs){
			import std.algorithm : filter;
			import std.array : array;
			args = args.filter!"a.length".array;
		}

		return res;
	}

}


template helpText(T) {
	enum helpText = helpTextImpl;
	auto helpTextImpl(){
		import std.meta : staticMap, Filter;
		import std.array : array;
		import std.range : chain, only, repeat;
		import std.algorithm : joiner, map;

		static assert(hasUDA!(T, help), T.stringof ~ " must have a @help description showing usage");
		size_t max = 0;
		alias valid(string m) = isValidOption!(T, m);
		auto udas(string m)(){ 
			string[] res = new string[](3);
			static if(hasUDA!(__traits(getMember, T, m), shortFlag)) res[0] = "-"~getUDAs!(__traits(getMember, T, m), shortFlag)[0];
			else res[0] = "  ";

			res[1] = "--"~m;
			if(res[1].length > max) max = res[1].length;
		
			static if(hasUDA!(__traits(getMember, T, m), help)) res[2] = getUDAs!(__traits(getMember, T, m), help)[0];
			else res[2] = "No help available";

			return res;
		}
				
		return getUDAs!(T, help)[0]
			.chain("\n\n").chain(
				staticMap!(udas, Filter!(valid, __traits(allMembers, T)))
				.only
				.map!(r => format("  %s %s%s  %s", r[0], r[1], ' '.repeat(max-r[1].length), r[2])) //Replace 3rd opt with padRight
				.joiner("\n")
				.chain("\n")
			).array;
	}	
}

//Tests:

unittest {
	//Basic struct test, no configuration

	struct Test {
		@shortFlag('v') int verbose; //--verbose, -v
		@shortFlag('d') bool daemon; //--daemon, -d
		string path; //--path only
		immutable int id = -1; //invalid option, skip
		@ignore string password; //ignored option, skip
	}

	string[] args = ["./program", "--verbose", "7", "-d", "--path", "/some/path/home/"];
	Test t = parseOpts!Test(args);
	assert(t.verbose == 7);
	assert(t.daemon == true);
	assert(t.path == "/some/path/home/");
	assert(t.id == -1);
	assert(t.password == "");

	//This should not error:
	args = [];
	parseOpts!Test(args);
	//Nor should:
	args = ["./prog"];
	parseOpts!Test(args);
}

unittest {
	//Basic class test, no configuration. Same fields as above

	static class Test {
		@shortFlag('v') int verbose; //--verbose, -v
		@shortFlag('d') bool daemon; //--daemon, -d
		string path; //--path only
		immutable int id = -1; //invalid option, skip
		@ignore string password; //ignored option, skip
	}

	string[] args = ["./program", "-v", "42", "--path", "/some/path/home/"];
	Test t = parseOpts!Test(args);
	assert(t.verbose == 42);
	assert(t.daemon == false);
	assert(t.path == "/some/path/home/");
	assert(t.id == -1);
	assert(t.password == "");
}

unittest {
	//Pass-through test, invalid options
	
	struct Test {
		bool quiet;
		int loglevel;
		string path;
	}

	string[] args = ["./program", "-q", "--loglevel", "7", "-p", "/var/log/"];
	Test t = parseOpts!Test(args, config.passThrough);
	assert(t.quiet == false); //No -q flag, quiet should not be set
	assert(t.loglevel == 7); //Loglevel should be properly set
	assert(t.path == ""); //No -p flag, path should not be set
}

unittest {
	//Bundling test

	struct Test {
		@shortFlag('a') bool opt1;
		@shortFlag('b') bool opt2;
		@shortFlag('c') bool opt3;
	}

	string[] args = ["./program", "-a", "--opt2", "-c"];
	//Options should still be accepted even if unbundled
	Test t1 = parseOpts!Test(args, config.bundling);
	assert(t1.opt1 == true);
	assert(t1.opt2 == true);
	assert(t1.opt3 == true);

	args = ["./program", "-ac"];
	Test t2 = parseOpts!Test(args, config.bundling);
	assert(t2.opt1 == true);
	assert(t2.opt2 == false);
	assert(t2.opt3 == true);

	//Continuation: Bundling and pass-through
	args = ["./program", "-bcefg", "--bad-opt", "-z"];
	Test t3 = parseOpts!Test(args, config.bundling | config.passThrough);
	assert(t3.opt1 == false);
	assert(t3.opt2 == true);
	assert(t3.opt3 == true);
}

unittest {
	//Stop-on-non-option test

	struct Test {
		string path;
	}

	try {
		string[] args = ["./program", "--path", "/etc/", "not an option"];
		Test t = parseOpts!Test(args, config.stopOnNonOption);
		assert(0, "Above expression should fail.");
	} catch(ArgumentException e){ }
}

unittest {
	//Consume args test

	@help("Usage: ./foo [OPTIONS] filename")
	struct Test {
		@shortFlag('p') string path = "/var/log/";
	}
	import std.stdio;
	string[] args = ["./foo", "-p", "/etc/foobaz/", "mycoolfile"];
	Test t = parseOpts!Test(args, config.consumeArgs);
	assert(t.path == "/etc/foobaz/");
	args.writeln;
	assert(args.length == 2); //Removed -p and /etc/foobaz/
	assert(args[0] == "./foo");
	assert(args[1] == "mycoolfile");
}
