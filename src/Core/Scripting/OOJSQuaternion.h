/*

OOJSQuaternion.h

JavaScript proxy for quaternions.

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

#include "OOCocoa.h"
#include "ooscript/JSEngine.hpp"
#include "oofnd/StdLib.hpp"
#include "OOMaths.h"


#ifdef __cplusplus
extern "C" {
#endif

void InitOOJSQuaternion(ooscript::Context context, ooscript::Object global);


ooscript::Object JSQuaternionWithQuaternion(ooscript::Context context, Quaternion quaternion)  NONNULL_FUNC;

bool QuaternionToJSValue(ooscript::Context context, Quaternion quaternion, ooscript::Value *outValue)  NONNULL_FUNC;
bool JSValueToQuaternion(ooscript::Context context, ooscript::Value value, Quaternion *outQuaternion)  NONNULL_FUNC;

/*	Given a JS Quaternion object, get the corresponding Vector struct. Given a
	JS Entity, get its orientation. Given a JS Array with exactly four
	elements, all of them numbers, treat them as [w, x, y, z]  components. For
	anything else, return NO. (Other implicit conversions may be added in
	future.)
*/
bool JSObjectGetQuaternion(ooscript::Context context, ooscript::Object quaternionObj, Quaternion *outQuaternion)  GCC_ATTR((nonnull (1, 3)));

//	Set the value of a JS quaternion object.
bool JSQuaternionSetQuaternion(ooscript::Context context, ooscript::Object quaternionObj, Quaternion quaternion)  GCC_ATTR((nonnull (1)));


/*	QuaternionFromArgumentList()
	
	Construct a quaternion from an argument list which is either a (JS)
	quaternion, a (JS) entity, four numbers or a JS array of four numbers. The
	optional outConsumed argument can be used to find out how many parameters
	were used (currently, this will be 0 on failure, otherwise 1 or 4).
	
	On failure, it will return NO and raise an error. If the caller is a JS
	callback, it must return NO to signal an error.
*/
extern "C++" {	// C++ parameters (proposed ADR-0043, bead oo-38bp)
bool QuaternionFromArgumentList(ooscript::Context context, const std::string &scriptClass, const std::string &function, unsigned argc, ooscript::Value *argv, Quaternion *outQuaternion, unsigned *outConsumed)  GCC_ATTR((nonnull (1, 5, 6)));
}

/*	QuaternionFromArgumentList()
	
	Like VectorFromArgumentList(), but does not report an error on failure.
*/
bool QuaternionFromArgumentListNoError(ooscript::Context context, unsigned argc, ooscript::Value *argv, Quaternion *outVector, unsigned *outConsumed)  GCC_ATTR((nonnull (1, 3, 4)));


#ifdef __cplusplus
}
#endif


#if OO_DEBUG
#include "oofnd/PList.hpp"

/*	The quaternion-conversion statistics the debug console reads with
	PS.callObjC("reportJSQuaternionStatistics"): the C++ PlayerEntity's static members of the same
	names forward here, reached by callObjC's name table (bead oo-9ht.15).
*/
oo::PList reportJSQuaternionStatistics(void);
void clearJSQuaternionStatistics(void);
#endif
