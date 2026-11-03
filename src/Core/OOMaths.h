/*

OOMaths.h

Mathematical framework for Oolite.

Provides utility routines for Vectors, Quaternions, rotation matrices, and
conversion to OpenGL transformation matrices.

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#pragma once

#ifdef __cplusplus
/* <tgmath.h> is <cmath> in C++, and libc++ declares templates there, which cannot have C
   language linkage. Include it before the extern "C" block opens; its include guard makes the
   include below a no-op. */
#include <tgmath.h>
extern "C" {
#endif

#include "OOBoundingBox.h"
#include "OOHPVector.h"
#include "OOMathsBase.h"
#include "OOMatrix.h"
#include "OOTriangle.h"
#include "OOVoxel.h"
#include "legacy_random.h"
