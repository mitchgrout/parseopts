# parseopts
Basic command-line options parser written in D.
Unlike `std.getopt`, instead of passing information about flags as arguments to `getopt`,
information is stored within a struct or class. This type is inspected by the function `parseOpts`,
and parsing code is generated as necessary.


### Example usage:
```d
import parseopts;

struct MyConfig
{
    @shortFlag('v') int verbosity;
    @shortFlag('l') @longFlag("should-log") bool log;
    string filename;
    @ignore string importantSecrets;
}

void main(string[] args)
{
    MyConfig cfg = args.parseOpts!MyConfig;
    //...
}
//Used like: ./myprogram -v 7 --should-log --filename "prog.log"
```

By default, the flag for any given symbol is `--symbol`. So, to set the member `filename`, one would give the command line argument `--filename "/dev/null"`.
The default long flag can be overridden with the `longFlag` attribute. Using this sets the long flag of the member to any given non-empty alphanumeric string.
By default, no short flags are generated. They may be set by annotating the member with the `shortFlag` attribute. These may be used like `-v 7`. For boolean types, simply `-l`.
If the struct contains a member that should not be settable via command line arguments, the attribute `ignore` may be annotated.

There are various runtime options which can be passed to the function `parseOpts` which affects its behaviour.
  - Bundling: Short flags can be packed together into a single argument, e.g. `-abc` is equivalent to `-a -b -c`.
  - Passthrough: Unknown flags are ignored.
  - Stop-on-non-option: If a value is parsed and it does not look like a flag, then an exception is raised.
  - Consume: Arguments are replaced with `null` as they are parsed.

Help text may also be programmatically generated based on annotations. The type may be annotated with `help` to specify the general help text for the program, and member may be annotated with `help` to specify meaning of each flag.

### Example usage:
```d
@help("A simple webserver which echos all requests back to the user")
struct ServerConfig
{
    @help("The path where logfiles will be stored")
    string path;
    
    @help("Specify how much information the server should log")
    int verbosity;
    
    //...
}
```

## Todo:
- [x] Implement the `required` attribute
- [ ] Implement help text generation
- [ ] Add invariants to members to control the values they can take
- [ ] Ensure that parsing adheres to the POSIX syntax
