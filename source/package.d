module parseopts;

public import parseopts.attributes;
public import parseopts.templates;

//import std.traits : hasUDA, getUDAs;
import std.meta : Alias, staticMap, Filter;

///Configuration for the parser
enum Config
{
	///Default arguments
	none = 0,

	///Indicates that several short flags can be expressed as a single
	///flag, e.g. "-abc" is equivalent to "-a -b c"
	bundling = 1,

	///Arguments that are not recognized are ignored
	passThrough = 2,

	///Indicates that the parser should throw an exception and stop when
	///it encounters the first item that does not look like an option,
	///e.g. ["--flag", "value", "badoption"] will throw an exception
	///when "badoption" is reached
	stopOnNonOption = 4,

	///Parsed arguments will be replaced with null when they are used
	consume = 8,
}

///
class ParserException : Exception
{
	import std.exception : basicExceptionCtors;
	mixin basicExceptionCtors;
}

///
Type parseOpts(Type)(string[] args, Config cfg = Config.none)
	if(is(Type == struct) ||
	   (is(Type == class) &&
	    __traits(compiles, new Type)))
{
	import std.regex : ctRegex, match, regex;
	import std.meta : ApplyLeft;

	//My VPS is too shit to compile these regexes
	version(none)
	{
		alias regShortFlag = ctRegex!`^\-[a-zA-Z]+$`; //originally [\w\d]
		alias regLongFlag = ctRegex!`^\-{2}(?:[a-zA-Z]+\-)*[a-zA-Z]+$`;
	}
	else
	{
		auto regShortFlag = regex(`^\-[a-zA-Z]+$`);
		auto regLongFlag = regex(`^\-{2}(?:[a-zA-Z]+\-)*[a-zA-Z]+$`);
	}

	Type res;
	static if(is(Type == class))
		res = new Type;

	//Remove the first entry if it does not look like an option
	//Assumed to be the ./programname entry in the args
	if(args && !args[0].match(regShortFlag) && !args[0].match(regLongFlag))
		args = args[1..$];

	bool hasBundling = (Config.bundling & cfg) != Config.none;
	bool hasPassThrough = (Config.passThrough & cfg) != Config.none;
	bool shouldStopOnNonOption = (Config.stopOnNonOption & cfg) != Config.none;
	bool shouldConsume = (Config.consume & cfg) != Config.none;

	debug
	{
		import std.stdio : writeln;
		writeln("Args: ", args);
		writeln("Has bundling: ", hasBundling);
		writeln("Has passthrough: ", hasPassThrough);
		writeln("Has stop on non-option: ", shouldStopOnNonOption);
		writeln("Has consume: ", shouldConsume);
		writeln();
	}

	void handle(ref string flag, ref string value)
	{
		import std.conv : to;
		import std.format : format;
		import std.traits : hasUDA, getUDAs;
		import std.meta : Alias, Filter;

		debug writeln("Flag: ", flag, " | Value: ", value);

		flag_switch:
		switch(flag)
		{
			/*static*/ foreach(varName; Filter!(ApplyLeft!(isOption, Type), __traits(allMembers, Type)))
			{
				alias symbol = getSymbol!(Type, varName);
				alias SymbolType = typeof(symbol);

				//Short flags should just jump directly to long flag cases
				static if(hasShortFlag!(Type, varName))
				{
					case getShortFlag!(Type, varName):
						goto case getLongFlag!(Type, varName);
				}

				//All options will have a long flag. If they don't have @longFlag(string),
				//the default flag is just --varName
				case getLongFlag!(Type, varName):
					static if(is(SymbolType == bool))
						__traits(getMember, res, varName) = true;
					else static if(is(SymbolType == string))
						__traits(getMember, res, varName) = value;
					else
						__traits(getMember, res, varName) = value.to!(SymbolType);
					break flag_switch;
			}
			default:
				if(hasPassThrough)
					return; //Return instead of break to avoid consuming args even though they're invalid
				else
					throw new ParserException(`Unknown flag "%s"`.format(flag));
		}

		if(shouldConsume)
			flag = value = null;
	}

	while(args.length)
	{
		import std.format : format;

		//Passthrough
		if(!args[0].match(regShortFlag) && !args[0].match(regLongFlag))
		{
			if(hasPassThrough)
				continue;
			else
				throw new ParserException(`Invalid argument: "%s"`.format(args[0]));
		}

		//Bundling
		//Check if 1) there is the potential for more than 1 flag present, and
		//         2) the first two chars [guaranteed to exist] look like a short flag
		if(args[0].length > 2 && args[0][0..2].match(regShortFlag))
		{
			//TODO: Make this better, while also respecting the fact
			//that handle will be potentially consuming our input
			//i.e. if the input is -abc, and only -a is valid, we should be left with -bc
			string dummy = null;

			//This string will be populated
			string result;
			if(shouldConsume)
			{
				result.reserve(args[0].length);
				result ~= '-'; //no cost, since we've preallocated enough space
			}

			foreach(ref flag; args[0][1..$])
			{
				string properFlag = ['-', flag];
				handle(properFlag, dummy);

				//Flag has NOT consumed
				if(shouldConsume && properFlag !is null)
				{
					result ~= flag;
				}
			}

			if(shouldConsume)
			{
				//All flags have been consumed, so result is simply "-"
				if(result.length <= 1)
				{
					//Consume
					args[0] = null;
				}
				else
				{
					args[0] = result;
				}
			}
			continue;
		}

		//Either we only have one argument left, or the NEXT argument is a flag
		if(args.length == 1 || args[1].match(regShortFlag) || args[1].match(regLongFlag))
		{
			//Because `handle` accepts args by ref, we need a dummy var for our null
			string dummy = null;
			handle(args[0], dummy);
			args = args[1..$];
		}
		else
		{
			handle(args[0], args[1]);
			args = args[2..$];
		}
	}

	return res;
}

template helpText(Type, size_t bufferWidth = 80)
{
	import std.traits : hasUDA, getUDAs;
	import std.meta : ApplyLeft, Filter, staticMap;
	import std.range : array, chain, only, repeat, zip;
	import std.algorithm : joiner, map, max, reduce;
	import std.format : format;

	//The help of the program itself
	static if(hasUDA!(Type, help))
		enum typeHelpText = getUDAs!(Type, help)[0].value;
	else
		enum typeHelpText = "No description available";

	//All of the valid flags belonging to Type
	alias flags = Filter!(ApplyLeft!(isOption, Type), __traits(allMembers, Type));

	//All of the short flag strings
	alias shortFlags = staticMap!(ApplyLeft!(getShortFlag, Type), Filter!(ApplyLeft!(hasShortFlag, Type), __traits(allMembers, Type)));

	//All of the long flag strings
	alias longFlags = staticMap!(ApplyLeft!(getLongFlag, Type), flags);

	//All of the help text strings
	alias flagHelpText = staticMap!(ApplyLeft!(getHelpText, Type), flags);

	//Length of the longest longFlag
	//Short flags are guaranteed to be 2 chars long
	enum maxWidth = only(longFlags)
			.map!(s => s.length)
			.reduce!max;

	//Format should be:
	//  -s, --long-flag  the description goes here
	enum helpText = typeHelpText
			.chain("\n\n")
			.chain( zip(only(shortFlags), only(longFlags), only(flagHelpText))
				.map!(t => format("  %s, %s%s  %s", t[0], t[1], ' '.repeat(maxWidth - t[1].length), t[2]))
				.joiner("\n"))
			.array;
}

version(unittest)
struct TestConfig
{
	@shortFlag('a') bool all; //

	@shortFlag('v') int verbose; //

	@shortFlag('p') string path; //

	@longFlag("recurse") bool shouldRecurse; //

	@shortFlag('c') @longFlag("color") Colour textColour; //
}

version(unittest)
enum Colour
{
	white,
	red,
	blue,
	green
}

//Config.none
unittest
{
	auto obj = parseOpts!TestConfig(["./prog", "--all", "-v", "10", "--recurse"]);
	assert(obj == TestConfig(true, 10, null, true, Colour.white));

	obj = parseOpts!TestConfig(["--recurse", "-c", "green", "-v", "-1"]);
	assert(obj == TestConfig(false, -1, null, true, Colour.green));

	obj = parseOpts!TestConfig(["./prog", "--path", "/tmp/"]);
	assert(obj == TestConfig(false, 0, "/tmp/", false, Colour.white));
}
