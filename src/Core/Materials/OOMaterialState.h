/*

OOMaterialState.h

The current-material slot of OOMaterial (OOMaterial.h), for plain C++
translation units.
A .cpp that only saves, clears and restores the current material, as
OODebugGLDrawing.cpp does around its wireframes, includes this instead of
OOMaterial.h. Defined in OOMaterial.cpp.


Copyright (C) 2007-2013 Jens Ayton and contributors

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

#include <memory>

class OOMaterial;

// OOMaterial::current(): the current material, shared with the caller; null for
// none.
std::shared_ptr<OOMaterial> OOMaterialRetainCurrent();

// OOMaterial::applyNone().
void OOMaterialApplyNone();

// Makes material current again (apply(); nothing for null); the caller's
// reference goes with the argument.
void OOMaterialApplyAndRelease(std::shared_ptr<OOMaterial> material);
