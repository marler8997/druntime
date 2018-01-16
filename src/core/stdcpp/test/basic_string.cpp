#include "ci_string.hpp"

int main()
{
  std::basic_string<char, ci_char_traits> s1 = "Hello";
  std::basic_string<char, ci_char_traits> s2 = "heLLo";
  return s1 == s2;  
}
