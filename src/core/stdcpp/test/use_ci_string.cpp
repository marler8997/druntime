#include <stdio.h>
#include <string>
#include "ci_string.hpp"

int main(int argc, char* argv[])
{
  std::basic_string<char, ci_char_traits> s1 = "hello";
  std::basic_string<char, ci_char_traits> s2 = "foo";
  printf("s1.empty() = %d\n", s1.empty());
  printf("s1.at(0) = '%d'\n", s1.at(0));
  return 0;
}
