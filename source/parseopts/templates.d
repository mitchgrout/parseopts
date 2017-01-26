module parseopts.templates;

import parseopts.attributes;
import std.traits : hasUDA, getUDAs;
import std.meta : Alias;


///Gets Type.symbol
alias getSymbol(Type, string symbol) = Alias!(__traits(getMember, Type, symbol));


///Determine if Type.symbol is an option
enum isOption(Type, string symbol) = !hasUDA!(getSymbol!(Type, symbol), ignore) &&
				     is(typeof(getSymbol!(Type, symbol) = typeof(getSymbol!(Type, symbol)).init));


///Determine if Type.symbol has the required flag
template isRequired(Type, string symbol)
    if(isOption!(Type, symbol))
{
    enum isRequired = hasUDA!(getSymbol!(Type, symbol), required);
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


///Determine if Type.symbol has a short flag
template hasShortFlag(Type, string symbol)
    if(isOption!(Type, symbol))
{
    enum hasShortFlag = hasUDA!(getSymbol!(Type, symbol), shortFlag);
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
