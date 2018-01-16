import std.traits;
import std.algorithm;
import std.array;
import std.range;
import std.string;
import std.format;
import std.path;
import std.file;
import std.stdio;
import std.process;

class SilentException : Exception { this() { super(null); } }
@property auto quit() { return new SilentException(); }

string testDir;
string stdcppDir;
string druntimeRoot;
string linker;
string cppCompiler;
string dCompiler;

string[] cppSpecificLinkerPreArgs;
string[] commonLinkerArgs;
string[] cppSpecificLinkerPostArgs;
string[] dSpecificLinkerArgs;

@property auto cppLinkerArgs()
{
    return chain(cppSpecificLinkerPreArgs, commonLinkerArgs, cppSpecificLinkerPostArgs);
}
@property auto dLinkerArgs()
{
    return chain(commonLinkerArgs, dSpecificLinkerArgs);
}
@property withPrefix(string prefix, T)(T arg)
{
    return map!(a => prefix ~ a)(arg);
}

string stripDirPrefix(string filename)
{
    if(filename.length > 2 && filename.startsWith("./"))
    {
        return filename[2..$];
    }
    return filename;
}
string testFile(string filename)
{
    return buildPath(testDir, filename).stripDirPrefix;
}

int main(string[] args)
{
    try { return main2(args); }
    catch(SilentException) { return 1; }
}
int main2(string[] args)
{
    // initialize global variables
    {
        auto testAbsoluteDir = __FILE_FULL_PATH__.dirName;
        testDir = relativePath(testAbsoluteDir);
        auto stdcppAbsoluteDir = testAbsoluteDir.dirName;
        stdcppDir = relativePath(stdcppAbsoluteDir);
        writefln("stdcppDir    = '%s'", stdcppDir);
        auto druntimeAbsoluteRoot = stdcppAbsoluteDir.dirName.dirName.dirName;
        druntimeRoot = relativePath(druntimeAbsoluteRoot);
        writefln("druntimeRoot = '%s'", druntimeRoot);
	linker = "ld";
        cppCompiler = "g++";
        writefln("cppCompiler  = '%s'", cppCompiler);
        dCompiler = buildPath(relativePath(druntimeAbsoluteRoot.dirName), "dmd", "generated", "linux", "release", "64", "dmd");
        writefln("dCompiler    = '%s'", dCompiler);
    }
    commonLinkerArgs = [
        "-m", "elf_x86_64",
        "-dynamic-linker", "/lib64/ld-linux-x86-64.so.2",
	"-L/usr/lib/gcc/x86_64-linux-gnu/4.9",
	"-L/usr/lib/gcc/x86_64-linux-gnu/4.9/../../../x86_64-linux-gnu",
	"-L/usr/lib/gcc/x86_64-linux-gnu/4.9/../../../../lib",
	"-L/lib/x86_64-linux-gnu",
	"-L/lib",
	"-L/usr/lib/x86_64-linux-gnu",
        "-L/usr/lib/",
        "-lstdc++",
        "-lm",
        "-lgcc_s",
        "-lgcc",
        "-lc",
    ];
    cppSpecificLinkerPreArgs = [
	"/usr/lib/gcc/x86_64-linux-gnu/4.9/../../../x86_64-linux-gnu/crt1.o",
	"/usr/lib/gcc/x86_64-linux-gnu/4.9/../../../x86_64-linux-gnu/crti.o",
	"/usr/lib/gcc/x86_64-linux-gnu/4.9/crtbegin.o",
    ];
    cppSpecificLinkerPostArgs = [
        "/usr/lib/gcc/x86_64-linux-gnu/4.9/crtend.o",
        "/usr/lib/gcc/x86_64-linux-gnu/4.9/../../../x86_64-linux-gnu/crtn.o",
    ];

    // Make sure all stdcpp files are up-to-date in the 'import' tree
    // Note: this is just a temporary step until a better approach is implemented
    runShell("cp", stdcppDir ~ "/*.d", druntimeRoot ~ "/import/core/stdcpp");

    // example 2
    runShell(cppCompiler, "-o", testFile("basic_string_cpp"), testFile("basic_string.cpp"));

    // example 1
    runShell(cppCompiler, "-o", testFile("foolib.cpp.o"), "-c", testFile("foolib.cpp"));

    // compile and link example1.cpp in 1 step
    runShell(cppCompiler, "-o", testFile("example1.cpp.exe"), testFile("example1.cpp"), testFile("foolib.cpp.o"));

    // compile example1.cpp then link
    runShell(cppCompiler, "-o", testFile("example1.cpp.o"), "-c", testFile("example1.cpp"));
    runShell(linker, "-o", testFile("example1.cpp.ld.exe"), testFile("example1.cpp.o"), testFile("foolib.cpp.o"), cppLinkerArgs);

    // compile example1.d and link in one step
    runShell(dCompiler, "-of" ~ testFile("example1.d.exe"), testFile("example1.d"), testFile("foolib.cpp.o"), dLinkerArgs.withPrefix!"-L");

    // compile example1.d then link
    //runShell(dCompiler, "-of" ~ testFile("example1.d.o"), "-c", testFile("example1.d"));
    //runShell(linker, "-o", testFile("example1.d.ld.exe"), testFile("example1.d.o"), testFile("foolib.cpp.o"), dLinkerArgs);


    //
    runShell(cppCompiler, "-o", testFile("ci_string_instance.cpp.o"), "-c", testFile("ci_string_instance.cpp"));
    runShell(cppCompiler, "-o", testFile("use_ci_string.cpp.exe"), testFile("use_ci_string.cpp"), testFile("ci_string_instance.cpp.o"));
    runShell(dCompiler, "-of" ~ testFile("use_ci_string.d.exe"), testFile("use_ci_string.d"), testFile("ci_string_instance.cpp.o"));
   
    return 0;
}

void appendArgument(T)(ref Appender!(char[]) command, T arg)
{
    if(command.data.length > 0)
      command.put(" ");

    auto start = command.data.length;
    formattedWrite(&command.put!(const(char)[]), "%s", arg);
    if(command.data[start..$].indexOf(' ') >= 0)
    {
        command.put(" ");
        foreach_reverse(i; start..command.data.length - 1)
        {
            command.data[i + 1] = command.data[i];
        }
        command.data[start] = '"';
        command.put("\"");
    }
}

string toCommandLine(T...)(T args)
{
    auto command = appender!(char[])();
    string prefix = "";
    foreach(arg; args)
    {
        static if( !isSomeString!(typeof(arg)) && isInputRange!(typeof(arg)))
        {
            foreach(subArg; arg)
            {
	       appendArgument(command, subArg);
            }
        }
	else
	{
	    appendArgument(command, arg);
	}
    }
    return cast(string)command.data;
}

auto tryRunShell(string command)
{
    writefln("[SHELL] %s", command);
    stdout.flush();
    auto pid = spawnShell(command);
    wait(pid);
    writeln();
    writeln("--------------------------------------------------------------------------------");
    return wait(pid);
}
void runShell(string command)
{
    auto exitCode = tryRunShell(command);
    if(exitCode)
    {
        writefln("last [SHELL] command failed with exit code %s", exitCode);
	throw quit;
    }
}
void runShell(T...)(T args)
{
    return runShell(toCommandLine(args));
}
