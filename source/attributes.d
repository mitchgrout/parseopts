module parseopts.attributes;

///Indicates that a field can be filled out using a flag of the form -x
struct shortFlag
{
	this(char value)
	{
		this.value = ['-', value];
	}
	string value;
}

///Overrides the default long flag, which is --fieldName
struct longFlag
{
	this(string value)
	{
		assert(value.length);
		this.value = "--" ~ value;
	}
	string value;
}

///Specifies the help text for the program when attached to the
///type, and the help text for the flag when attached to the field
struct help
{
	this(string value)
	{
		assert(value.length);
		this.value = value;
	}
	string value;
}

///Indicates that a field should be ignored
struct ignore { }

///Indicates that a field must be filled out in the command line
struct required { }
