module ci_string;

import core.stdcpp.string : char_traits;

extern(C++) struct ci_char_traits// : public std::char_traits<char>
{
  static char to_upper(char c);
};
