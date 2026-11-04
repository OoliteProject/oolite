/*
        OOISNumberLiteral.m

        Copyright (C) 2008-2013 Jens Ayton

        Permission is hereby granted, free of charge, to any person obtaining a
   copy of this software and associated documentation files (the "Software"), to
   deal in the Software without restriction, including without limitation the
   rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
   sell copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included
   in all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
   OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
   THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
   IN THE SOFTWARE.
*/

#define OO_PLAIN_CPP_UNIT \
  1  // a plain C++ unit: the shared headers' game-unit parts stay out of it
#include "OOIsNumberLiteral.h"

#if 0
#include "oofnd/Log.hpp"
#define FAIL(s)                                                                \
  do {                                                                         \
    OO_LOG("unclassified", "OOIsNumberLiteral failed for \"{}\": {}.", string, \
           s);                                                                 \
    return false;                                                              \
  } while (0)
#else
#define FAIL(s)   \
  do {            \
    return false; \
  } while (0)
#endif

bool OOIsNumberLiteral(const std::string& string, bool allowSpaces) {
  bool leadingSpace = allowSpaces, trailingSpace = false, allowSign = true,
       allowE = false, hadE = false, hadExp = false, allowDec = true,
       hadNumber = false;
  std::size_t i, count;

  count = string.size();
  for (i = 0; i != count; ++i) {
    switch (string[i]) {
      // <digit>
      case '0':
      case '1':
      case '2':
      case '3':
      case '4':
      case '5':
      case '6':
      case '7':
      case '8':
      case '9':
        leadingSpace = false;
        if (trailingSpace) FAIL("Digit after trailing whitespace");
        if (!hadE)
          allowE = true;
        else
          hadExp = true;
        allowSign = false;
        hadNumber = true;
        break;

      // <whitespaceChar>
      case ' ':
      case '\t':
        if (leadingSpace || trailingSpace) break;
        if (hadNumber && allowSpaces) {
          trailingSpace = true;
          allowSign = allowE = allowDec = false;
          break;
        }
        FAIL("Space in unpermitted position");

      // <sign>
      case '-':
      case '+':
        leadingSpace = false;
        if (allowSign) {
          allowSign = false;
          break;
        }
        FAIL("Sign (+ or -) in unpermitted position");

      // <decimalPoint>
      case '.':
        leadingSpace = false;
        if (allowDec) {
          allowDec = false;
          continue;
        }
        FAIL("Sign (+ or -) in unpermitted position");

      // <e>
      case 'e':
      case 'E':
        leadingSpace = false;
        if (allowE) {
          allowE = false;
          allowSign = true;
          allowDec = false;
          hadE = true;
          continue;
        }
        FAIL("E in unpermitted position");

      default:
        FAIL("Unpermitted character");
    }
  }

  if (hadE && !hadExp) FAIL("E with no exponent");
  if (!hadNumber) FAIL("No digits in string");

  return true;
}
