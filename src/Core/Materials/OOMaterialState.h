/*

OOMaterialState.h

The current-material slot of OOMaterial (OOMaterial.h), for plain C++ translation units
(bead oo-9ht.185, proposed ADR-0056 amendment oo-9ht.185). OOMaterial.h is Objective-C++ (it imports
OOCocoa.h); a .cpp that only
saves, clears and restores the current material, as OODebugGLDrawing.cpp does around its
wireframes, includes this instead. Defined in OOMaterial.mm.


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

#ifndef OOMATERIALSTATE_H
#define OOMATERIALSTATE_H

class OOMaterial;

// OOMaterial::current().leakRef(): the current material, retained by the caller; null for none.
OOMaterial *OOMaterialRetainCurrent();

// OOMaterial::applyNone().
void OOMaterialApplyNone();

// Makes material current again (apply(); nothing for null) and releases the caller's reference.
void OOMaterialApplyAndRelease(OOMaterial *material);

#endif	// OOMATERIALSTATE_H
