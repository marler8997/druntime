#include <string>

struct ci_char_traits : public std::char_traits<char>
{
  static char to_upper(char c) { return std::toupper((unsigned char)c); }
};
