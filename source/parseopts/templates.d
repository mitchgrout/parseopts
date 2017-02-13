module parseopts.templates;

import parseopts.attributes;
import std.traits : hasUDA, getUDAs, staticMap, TemplateArgsOf;
import std.meta : Alias;


///Gets Type.symbol
alias getSymbol(Type, string symbol) = Alias!(__traits(getMember, Type, symbol));


///Determine if Type.symbol is an option
template isOption(Type, string symbol)
    if(__traits(hasMember, Type, symbol))
{
    //This check determines if the given symbol is at all mutable, which includes determining
    //if it is an enum / alias or a proper member variable.
    static if(__traits(compiles, { Type t;
                __traits(getMember, t, symbol) = typeof(__traits(getMember, t, symbol)).init; }))
        enum isOption = !hasUDA!(getSymbol!(Type, symbol), ignore);
    else
        enum isOption = false;
}


///
unittest
{
    enum MyEnum { _ }

    //Note: This is marked as static as it *contains a function*
    //If the function is removed, the static keyword may be removed
    static struct MyConfig
    {
        int i;
        const(int) ci;
        immutable(int) ii;

        string s;
        const(string) cs;
        immutable(string) is_;

        MyEnum e;
        alias T = int;
        enum C = 420;
        void func() { }
    }

    //Mutable members are fine
    static assert( isOption!(MyConfig, "i"));
    //Const/Immutable are not
    static assert(!isOption!(MyConfig, "ci"));
    static assert(!isOption!(MyConfig, "ii"));

    //Types with immutable members are fine
    static assert( isOption!(MyConfig, "s"));
    //Const/Immutable are not
    static assert(!isOption!(MyConfig, "cs"));
    static assert(!isOption!(MyConfig, "is_"));

    //User-defined enums are fine
    static assert( isOption!(MyConfig, "e"));
    //Constants are not
    static assert(!isOption!(MyConfig, "T"));
    static assert(!isOption!(MyConfig, "C"));
    static assert(!isOption!(MyConfig, "func"));
}


///Determine if Type.symbol has the required flag
template isRequired(Type, string symbol)
    if(isOption!(Type, symbol))
{
    enum isRequired = hasUDA!(getSymbol!(Type, symbol), required);
}


///
unittest
{
    struct MyConfig
    {
        @required int a;
        int b;
    }

    static assert( isRequired!(MyConfig, "a"));
    static assert(!isRequired!(MyConfig, "b"));
}


///Get the set of predicates belonging to Type.symbol
template getInvariants(Type, string symbol)
    if(isOption!(Type, symbol))
{
    alias item = getSymbol!(Type, symbol);
    alias getInvariants = staticMap!(TemplateArgsOf, getUDAs!(item, verify));
}


///Get the long flag corresponding to the given symbol.
///If the symbol does not have an explicit long flag, it will
///be --symbol
template getLongFlag(Type, string symbol)
    if(isOption!(Type, symbol))
{
    import std.format : format;

    //Get all of the longFlag UDAs associated with Type.symbol
    alias UDAlist = getUDAs!(getSymbol!(Type, symbol), longFlag);
        
    //Having more than one is ambiguous, fail in that case.
    static assert(UDAlist.length <= 1, "%s.%s must have either zero or one long flags, not %s"
                                       .format(Type.stringof, symbol, UDAlist.length));

    static if(UDAlist.length == 1)
		enum getLongFlag = UDAlist[0].value;
    else
		enum getLongFlag = "--" ~ symbol;
}


///
unittest
{
    struct MyConfig
    {
        int a;
        @longFlag("foo") int b;
        @longFlag("42") int c;
    }

    static assert(getLongFlag!(MyConfig, "a") == "--a");
    static assert(getLongFlag!(MyConfig, "b") == "--foo");
    static assert(getLongFlag!(MyConfig, "c") == "--42");
}


///Determine if Type.symbol has a short flag
template hasShortFlag(Type, string symbol)
    if(isOption!(Type, symbol))
{
    enum hasShortFlag = hasUDA!(getSymbol!(Type, symbol), shortFlag);
}


///
unittest
{
    struct MyConfig
    {
        @shortFlag('a') int a;
        int b;
    }

    static assert( hasShortFlag!(MyConfig, "a"));
    static assert(!hasShortFlag!(MyConfig, "b"));
}


///Gets the short flag associated with Type.symbol
template getShortFlag(Type, string symbol)
    if(hasShortFlag!(Type, symbol))
{
    //Get all of the shortFlag UDAs associated with Type.symbol
    alias UDAlist = getUDAs!(getSymbol!(Type, symbol), shortFlag);

    static assert(UDAlist.length == 1, "%s.%s must have one short flag, not %s"
                                       .format(Type.stringof, symbol, UDAlist.length));

    enum getShortFlag = UDAlist[0].value; 
}


///
unittest
{
    struct MyConfig
    {
        @shortFlag('a') int a;
        int b;
    }

    static assert(getShortFlag!(MyConfig, "a") == "-a");
}


///Get the help text associated with Type.symbol. If no help text
///is explicitly given, it will default to stating no text is available.
template getHelpText(Type, string symbol)
    if(isOption!(Type, symbol))
{
	static if(hasUDA!(getSymbol!(Type, symbol), help))
		enum getHelpText = getUDAs!(getSymbol!(Type, symbol), help)[0].value;
	else
		enum getHelpText = "no help text available";
}


///
unittest
{
    struct MyConfig
    {
        @help("string 1") int a;
        int b;
        @help("string 3") int c;
    }

    static assert(getHelpText!(MyConfig, "a") == "string 1");
    static assert(getHelpText!(MyConfig, "b") == "no help text available");
    static assert(getHelpText!(MyConfig, "c") == "string 3");
}
