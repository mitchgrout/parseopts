module parseopts.templates;

private import parseopts.attributes;

import std.traits : hasUDA, getUDAs;
import std.meta : Alias;

alias getSymbol(Type, string symbol) = Alias!(__traits(getMember, Type, symbol));

enum isOption(Type, string symbol) = !hasUDA!(getSymbol!(Type, symbol), ignore) &&
				     is(typeof(getSymbol!(Type, symbol) = typeof(getSymbol!(Type, symbol)).init));

template getLongFlag(Type, string symbol)
{
	static if(hasUDA!(getSymbol!(Type, symbol), longFlag))
		enum getLongFlag = getUDAs!(getSymbol!(Type, symbol), longFlag)[0].value;
	else
		enum getLongFlag = "--" ~ symbol;
}

enum hasShortFlag(Type, string symbol) = hasUDA!(getSymbol!(Type, symbol), shortFlag);

enum getShortFlag(Type, string symbol) = getUDAs!(getSymbol!(Type, symbol), shortFlag)[0].value;

template getHelpText(Type, string symbol)
{
	static if(hasUDA!(getSymbol!(Type, symbol), help))
		enum getHelpText = getUDAs!(getSymbol!(Type, symbol), help)[0].value;
	else
		enum getHelpText = "no help text available";
}
