#include <stdio.h>
#include "ci_string.hpp"

//template struct std::basic_string<char, ci_char_traits>;

void foo()
{
  std::basic_string<char, ci_char_traits> s = "hello";
  printf("s.front = '%s'\n", s.c_str());
}
