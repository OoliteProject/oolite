/*
        OOISNumberLiteral.h

        Utility function to recognize certain number literals, corresponding to
        C-style decimal integer literals and floating point literals without
        trailing type suffixes.


        Copyright (C) 2008-2013 Jens Ayton

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
*/

#pragma once

#if defined(__cplusplus) && !defined(OO_PLAIN_CPP_UNIT) // was __OBJC__: a game unit (an Objective-C++ unit until bead oo-dbz), not a plain C++ one
#include "OOFoundation.h"
#else
/*	Plain C++ translation unit (OOIsNumberLiteral.cpp, ADR-0012): only BOOL is needed, and OOFoundation.h
        imports Foundation, which does not compile outside Objective-C.
*/
#include "oofnd/objc/OOFoundationTypes.h" // BOOL, which <objc/runtime.h> gave until bead oo-dbz.2
#endif

#include "oofnd/StdLib.hpp"

/*	Recognise C-style decimal integer or float literals, without type suffix.
        More formally, it tests against the following grammar:

                number ::= [<whitespace>] [<sign>] basicNumber [<exponent>] [<whitespace>]
                whitespace ::=  <whitespaceChar> [<whitespace>]
                whitespaceChar ::= " " | "\t"
                sign ::= "+" | "-"
                basicNumber = integer [decimal] | decimal
                integer ::= <digit> [<integer>]
                digit ::= "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9"
                decimal ::= <decimalPoint> <integer>
                decimalPoint ::= "."
                exponent = <e> [<sign>] <integer>
                e ::= "e" | "E"

        if allowSpaces = NO, the [<whitespace>] terms are excluded.
*/
/*	Foundation sweep (proposed ADR-0043, bead oo-7zgv): the string is UTF-8. A nil string used to
        answer NO; callers pass oo::StdString(s), and "" answers NO too (no digits).
*/
BOOL OOIsNumberLiteral(const std::string& string, BOOL allowSpaces);
