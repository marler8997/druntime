import core.stdcpp.string;
import ci_string;

extern(C++) void foo();

void main()
{
  basic_string!(char, ci_char_traits) s1;
  basic_string!(char, ci_char_traits) s2;
  import std.stdio;
  writefln("s1.empty = %s", s1.empty);
  //writefln("s1.at(0) = '%s'", s1.at(0));
}
