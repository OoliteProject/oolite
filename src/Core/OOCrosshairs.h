/*

OOCrosshairs.h
Oolite

Copyright (C) 2008 Jens Ayton

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

#include "OOOpenGL.h"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"

class OOColor;

class OOCrosshairs : public oo::RefCounted {
 public:
  // points: the crosshair definition, a property-list array of 6-number arrays.
  OOCrosshairs(const oo::PList& points, GLfloat scale, OOColor* color,
               GLfloat alpha);
  ~OOCrosshairs() override;

  void render();

 private:
  friend struct OOCrosshairsTestAccess;  // tests/unit/core/test_OOCrosshairs.mm
                                         // reads the vertex buffer

  void setUpDataWithPoints(const oo::PList& points, GLfloat scale,
                           OOColor* color, GLfloat alpha);

  // pointInfo: nullptr for an entry that is not an array (as nil was).
  void setUpDataForOnePoint(const oo::PList* pointInfo, GLfloat scale,
                            float colorComps[4], GLfloat alpha,
                            GLfloat* ioBuffer);

  NSUInteger _count = {};
  GLfloat* _data = {};
};
