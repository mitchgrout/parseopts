module parseopts;


public import parseopts.attributes;
public import parseopts.templates;


import std.meta : Alias, staticMap, Filter;


///Configuration for the parser
enum Config
{
	///Default arguments
	none = 0,

	///Indicates that several short flags can be expressed as a single
	///flag, e.g. "-abc" is equivalent to "-a -b c".
    ///The short flags must be boolean in order to be packed this way,
    ///i.e. -i 1 -j 1 cannot be packed as -ij 1.
	bundling = 1 << 0,

    ///Indicates that the parser should skip any flags which do not match
    ///any known flags.
    skipUnknownFlags = 1 << 1,

    ///Indicates that the parser should skip any non-flag arguments
    skipUnknownArgs = 1 << 2,
	
    ///Parsed arguments will be replaced with null when they are used.
	consume = 1 << 3,
}


///
class ParserException : Exception
{
	import std.exception : basicExceptionCtors;
	mixin basicExceptionCtors;
}


///
Type parseOpts(Type)(string[] args, Config cfg = Config.none)
	if(!__traits(isNested, Type) &&
            ((is(Type == struct) && __traits(compiles, { Type t; })) ||
	         (is(Type == class)  && __traits(compiles, new Type))))
{
	import std.regex : ctRegex, match, regex;
	import std.meta : ApplyLeft, templateAnd;

    //Type cannot be nested. See https://issues.dlang.org/show_bug.cgi?id=8850 for details.
    //For some reason, the nested error gets hidden, and only the message that
    //the given type doesnt match the declaration for parseOpts is printed.

    //Add a custom version to decide between compile-time regexes (memory intensive)
    //or simpler runtime regexes
    version(all) 
	{
		alias regShortFlag = ctRegex!`^\-[a-zA-Z]+$`;
		alias regLongFlag = ctRegex!`^\-{2}(?:[a-zA-Z]+\-)*[a-zA-Z]+$`;
	}
	else
	{
		auto regShortFlag = regex(`^\-[a-zA-Z]+$`);
		auto regLongFlag = regex(`^\-{2}(?:[a-zA-Z]+\-)*[a-zA-Z]+$`);
	}

    //Instantiate the config object
	Type res;
	static if(is(Type == class))
		res = new Type;

	//Remove the first entry if it does not look like an option
	//Assumed to be the ./programname entry in the args
	if(args.length && !args[0].match(regShortFlag) && !args[0].match(regLongFlag))
		args = args[1..$];

    //Extract flags
	bool hasBundling = !!(Config.bundling & cfg);
    bool shouldSkipUnknownFlags = !!(Config.skipUnknownFlags & cfg);
    bool shouldSkipUnknownArgs = !!(Config.skipUnknownArgs & cfg);
    bool shouldConsume = !!(Config.consume & cfg);

    //Get an AliasSeq of all options belonging to Type
    alias options = Filter!(ApplyLeft!(isOption, Type), __traits(allMembers, Type));

    //Get an AliasSeq of all required options belonging to Type
    alias requiredArgs = Filter!(ApplyLeft!(isRequired, Type), options);

    static if(requiredArgs.length)
    {
        import std.algorithm : any, filter;

        //Reserve a bool for each required arg
        bool[requiredArgs.length] set = false;
        
        foreach(item; args.filter!(k => k.match(regShortFlag) || k.match(regLongFlag)))
            switch(item)
            {
                //Match each arg with a unique id
                foreach(idx, arg; requiredArgs)
                {
                    case arg:
                        set[idx] = true;
                        break;
                }
                //Flag isnt a required option, skip it
                default: break;
            }

        //Raise an exception if any arg was not set
        if(set[].any!(k => !k))
            throw new ParserException("Missing required args");
    }

    //Helper function that deals with parsing a single flag and potential value
    void handle()(ref string flag, auto ref string value)
	{
		import std.conv : to;
		import std.format : format;
		import std.traits : hasUDA, getUDAs;
		import std.meta : Alias, Filter;

		switch(flag)
		{
			/*static*/ foreach(varName; options)
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
						bool toSet = (value is null)? true : value.to!bool;
					else static if(is(SymbolType == string))
                        string toSet = value;
					else
                    {
                        SymbolType toSet;
						try toSet = value.to!(SymbolType);
					    catch(Exception) throw new ParserException("Could not convert "~value~" to "~SymbolType.stringof);
                    }

                    alias preds = getInvariants!(Type, varName);
                    foreach(pred; preds)
                    {
                        if(!pred(toSet))
                            throw new ParserException("Value %s did not satisfy the predicates for %s".format(value, varName));
                    }
                    __traits(getMember, res, varName) = toSet;
                    
                    if(shouldConsume)
                        flag = value = null;
                    return;
			}

			default:
				if(shouldSkipUnknownFlags)
                    //Return instead of break to avoid consuming args even though they're invalid
					return;
				else
					throw new ParserException(`Unknown flag "%s"`.format(flag));
		}
	}

	while(args.length)
	{
		import std.format : format;

		if(!args[0].match(regShortFlag) && !args[0].match(regLongFlag))
		{
            //Skip them
			if(shouldSkipUnknownArgs)
            {
                args = args[1..$];
                continue;
            }
            else
				throw new ParserException(`Invalid argument: "%s"`.format(args[0]));
		}

		//Bundling
		//Check if 1) there is the potential for more than 1 flag present, and
		//         2) the first two chars [guaranteed to exist] look like a short flag
		if(args[0].length > 2 && args[0][0..2].match(regShortFlag))
		{
            if(!hasBundling)
                throw new ParserException("Bundling was disabled, but found bundled arguments");

			//This string will be populated
			string result;
			if(shouldConsume)
			{
				result.reserve(args[0].length);
                //We can now effectively copy all of args[0] to result without causing a reallocation
                result ~= '-';
			}

			foreach(ref flag; args[0][1..$])
			{
				string properFlag = ['-', flag];
				handle(properFlag, null);

				//Flag has NOT been consumed
				if(shouldConsume && properFlag !is null)
					result ~= flag;
			}

            //If all that is left is "-", nullify the argument
            if(shouldConsume)
                args[0] = result.length <= 1? null : result;
		
            args = args[1..$];
            continue;
		}

		//Either we only have one argument left, or the NEXT argument is a flag
		if(args.length == 1 || args[1].match(regShortFlag) || args[1].match(regLongFlag))
		{
			handle(args[0], null);
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

	//The help text of the program itself
	static if(hasUDA!(Type, help))
		enum typeHelpText = getUDAs!(Type, help)[0].value;
	else
		enum typeHelpText = "No description available";

	//All of the valid flags belonging to Type
	alias flags = Filter!(ApplyLeft!(isOption, Type), __traits(allMembers, Type));

	//All of the short flag strings
    template helpTextGetShortFlag(Type, string symbol)
    {
        static if(hasShortFlag!(Type, symbol)) enum helpTextGetShortFlag = getShortFlag!(Type, symbol) ~ ',';
        else enum helpTextGetShortFlag = "   ";
    }
	//alias shortFlags = staticMap!(ApplyLeft!(getShortFlag, Type), Filter!(ApplyLeft!(hasShortFlag, Type), __traits(allMembers, Type)));
    alias shortFlags = staticMap!(ApplyLeft!(helpTextGetShortFlag, Type), __traits(allMembers, Type));

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
    //Program help text
    //
	//  -s, --long-flag  the description goes here
	enum helpText = typeHelpText
			.chain("\n\n")
			.chain( zip(only(shortFlags), only(longFlags), only(flagHelpText))
				.map!(t => format("  %s %s%s  %s", t[0], t[1], ' '.repeat(maxWidth - t[1].length), t[2]))
				.joiner("\n"))
			.array;
}

///
unittest
{
    @help("Curl-like utility program")
    struct ProgramConfig
    {
        @help("The URL to connect to")
        @required string hostname;

        @help("The port to connect to. Default is 22")
        @shortFlag('p') int port = 22;
        
        @help("Whether or not we should use TLS")
        @shortFlag('H') @longFlag("use-tls") bool useTLS; 
    }
    
    assert(helpText!ProgramConfig ==
`Curl-like utility program

      --hostname  The URL to connect to
  -p, --port      The port to connect to. Default is 22
  -H, --use-tls   Whether or not we should use TLS`
          );
}


///Commonly used by unittests, so brought in as a private import
version(unittest) import std.exception;


///Test Config.none
unittest
{
    enum Colour { white, red, blue, green }
    
    struct TestConfig
    {
        @shortFlag('a') bool all;
        @shortFlag('v') int verbose;
        @shortFlag('p') string path;
        @longFlag("recurse") bool shouldRecurse;
        @shortFlag('c') @longFlag("color") Colour textColour;
    }

    assert(["./prog", "--all", "-v", "10", "--recurse"].parseOpts!TestConfig ==
           TestConfig(true, 10, null, true, Colour.white));

	assert(["--recurse", "-c", "green", "-v", "-1"].parseOpts!TestConfig ==
	       TestConfig(false, -1, null, true, Colour.green));

    assert(["./prog", "--path", "/tmp/"].parseOpts!TestConfig ==
	       TestConfig(false, 0, "/tmp/", false, Colour.white));
}


///Test Config.bundling
unittest
{
    struct TestConfig
    {
        @shortFlag('a') bool a;
        @shortFlag('b') bool b;
        @shortFlag('c') bool c;
        @shortFlag('d') int d;
    }

    assert(["-a", "-b", "-c"].parseOpts!TestConfig == TestConfig(true, true, true, 0));

    assert(["-abc"].parseOpts!TestConfig(Config.bundling) == TestConfig(true, true, true, 0));
    
    assert(["-cab"].parseOpts!TestConfig(Config.bundling) == TestConfig(true, true, true, 0));

    assertThrown!ParserException(["-abcd"].parseOpts!TestConfig(Config.bundling));
}


///Test Config.skipUnknownFlags
unittest
{
    struct TestConfig
    {
        int a, b, c;
    }

    assertThrown!ParserException(["--a", "1", "--b", "2", "--unknown", "7"].parseOpts!TestConfig);

    assertNotThrown!ParserException(["--a", "1", "--b", "2", "--unknown", "7"]
                                        .parseOpts!TestConfig(Config.skipUnknownFlags));
}


///Test Config.skipUnknownArgs
unittest
{
    struct TestConfig
    {
        int a, b, c;
    }

    assertThrown!ParserException(["--a", "1", "--b", "2", "unknown", "data"].parseOpts!TestConfig);

    assertNotThrown(["--a", "1", "--b", "2", "unknown", "data"].parseOpts!TestConfig(Config.skipUnknownArgs));
}


///Test Config.consume
unittest
{
    import std.algorithm : all;

    struct TestConfig
    {
        string path;
        bool verbose;
        @shortFlag('O') int optLevel;
    }

    {
        string[] args = ["--path", "/root/", "-O", "7"];
        assert(args.parseOpts!TestConfig(Config.consume) == TestConfig("/root/", false, 7));
        assert(args.all!(k => k is null));
    }
}


///Test the @required attribute
version(none) unittest
{
    struct TestConfig
    {
        int a;
        int b;
        int c;
        @required int d;
    }

    assertNotThrown!ParserException(["--a", "1", "--b", "2", "--c", "3", "--d", "4"].parseOpts!TestConfig);

    assertThrown!ParserException(["--a", "12", "--b", "2", "--c", "1"].parseOpts!TestConfig);
}


///Test the @verify attribute
unittest
{
    import std.regex;

    enum urlRegex = ctRegex!`https?:\/\/.*`;

    struct TestConfig
    {
        //Any number of predicates can be stored in a single @verify
        @verify!(k => k > 0, k => k < 4)
        int o;
    
        //However, they can also be split across multiple @verify
        @verify!(s => s[0] == '/')
        @verify!(s => s[$-1] == '/')
        string dir;
    
        @verify!(s => s.match(urlRegex))
        string url;
    }

    assertNotThrown!ParserException(["--o", "2"].parseOpts!TestConfig);
    assertNotThrown!ParserException(["--o", "3"].parseOpts!TestConfig);
    assertNotThrown!ParserException(["--dir", "/dev/"].parseOpts!TestConfig);
    assertNotThrown!ParserException(["--url", "https://google.com/"].parseOpts!TestConfig);

    assertThrown!ParserException(["--o", "-3"].parseOpts!TestConfig);
    assertThrown!ParserException(["--o", "47"].parseOpts!TestConfig);
    assertThrown!ParserException(["--dir", "NotADir"].parseOpts!TestConfig);
    assertThrown!ParserException(["--url", "file:///dev/null"].parseOpts!TestConfig);
}


///Ensure that parseOpts can still be used with
///member enums, aliases, and functions
unittest
{
    static struct Foo
    {
        int i;
        enum e = 1;
        alias t = int;
        void func() { }
    }

    assertNotThrown(["./prog"].parseOpts!Foo);
}
