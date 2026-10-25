/*

OOJSVector.h

JavaScript proxy for vectors.

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
#include "OOMaths.h"
#include "oofnd/StdLib.hpp"


#ifdef __cplusplus
extern "C" {
#endif

void InitOOJSVector(ooscript::Context context, ooscript::Object global);


ooscript::Object JSVectorWithVector(ooscript::Context context, Vector vector)  NONNULL_FUNC;
ooscript::Object JSVectorWithHPVector(ooscript::Context context, HPVector vector)  NONNULL_FUNC;

bool VectorToJSValue(ooscript::Context context, Vector vector, ooscript::Value *outValue)  NONNULL_FUNC;
bool HPVectorToJSValue(ooscript::Context context, HPVector vector, ooscript::Value *outValue)  NONNULL_FUNC;
bool NSPointToVectorJSValue(ooscript::Context context, NSPoint point, ooscript::Value *outValue)  NONNULL_FUNC;
bool JSValueToVector(ooscript::Context context, ooscript::Value value, Vector *outVector)  NONNULL_FUNC;
bool JSValueToHPVector(ooscript::Context context, ooscript::Value value, HPVector *outVector)  NONNULL_FUNC;

/*	Given a JS Vector object, get the corresponding Vector struct. Given a JS
	Entity, get its position. Given a JS Array with exactly three elements,
	all of them numbers, treat them as [x, y, z]  components. For anything
	else, return NO. (Other implicit conversions may be added in future.)
*/
bool JSObjectGetVector(ooscript::Context context, ooscript::Object vectorObj, HPVector *outVector)  GCC_ATTR((nonnull (1, 3)));

//	Set the value of a JS vector object.
bool JSVectorSetVector(ooscript::Context context, ooscript::Object vectorObj, Vector vector)  GCC_ATTR((nonnull (1)));
bool JSVectorSetHPVector(ooscript::Context context, ooscript::Object vectorObj, HPVector vector)  GCC_ATTR((nonnull (1)));


/*	VectorFromArgumentList()
	
	Construct a vector from an argument list which is either a (JS) vector, a
	(JS) entity, or an array of three numbers. The optional	outConsumed
	argument can be used to find out how many parameters were used
	(currently, this will be 0 on failure, otherwise 1).
	
	On failure, it will return NO and raise an error. If the caller is a JS
	callback, it must return NO to signal an error.
	
	DEPRECATED in favour of JSObjectGetVector(), since the list-of-number form
	is no longer used.
*/
extern "C++" {	// C++ parameters (proposed ADR-0043, bead oo-yhle)
bool VectorFromArgumentList(ooscript::Context context, const std::string &scriptClass, const std::string &function, unsigned argc, ooscript::Value *argv, HPVector *outVector, unsigned *outConsumed)  GCC_ATTR((nonnull (1, 5, 6)));
}

/*	VectorFromArgumentListNoError()
	
	Like VectorFromArgumentList(), but does not report an error on failure.
*/
bool VectorFromArgumentListNoError(ooscript::Context context, unsigned argc, ooscript::Value *argv, HPVector *outVector, unsigned *outConsumed)  GCC_ATTR((nonnull (1, 3, 4)));


#ifdef __cplusplus
}
#endif


#if OO_DEBUG
#include "oofnd/PList.hpp"

/*	The vector-conversion statistics the debug console reads with
	PS.callObjC("reportJSVectorStatistics"): the C++ PlayerEntity's static members of the same
	names forward here, reached by callObjC's name table (bead oo-9ht.15).
*/
oo::PList reportJSVectorStatistics(void);
void clearJSVectorStatistics(void);
#endif


