/*

OOJSVector.h (QuickJS-ng proof of concept)

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

#include <quickjs.h>

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "OOFoundation.h"
#include "OOMaths.h"

void InitOOJSVector(JSContext* context, JSValueConst global);

// Return an owned Vector3D object, or JS_EXCEPTION.
JSValue JSVectorWithVector(JSContext* context, Vector vector) NONNULL_FUNC;
JSValue JSVectorWithHPVector(JSContext* context, HPVector vector) NONNULL_FUNC;

// *outValue is owned by the caller on success.
bool VectorToJSValue(JSContext* context, Vector vector,
                     JSValue* outValue) NONNULL_FUNC;
bool HPVectorToJSValue(JSContext* context, HPVector vector,
                       JSValue* outValue) NONNULL_FUNC;
bool NSPointToVectorJSValue(JSContext* context, NSPoint point,
                            JSValue* outValue) NONNULL_FUNC;
bool JSValueToVector(JSContext* context, JSValueConst value,
                     Vector* outVector) NONNULL_FUNC;
bool JSValueToHPVector(JSContext* context, JSValueConst value,
                       HPVector* outVector) NONNULL_FUNC;

/*	Given a JS Vector object, get the corresponding Vector struct. Given a
   JS Entity, get its position. Given a JS Array with exactly three elements,
        all of them numbers, treat them as [x, y, z]  components. For anything
        else, return NO. (Other implicit conversions may be added in future.)
*/
bool JSObjectGetVector(JSContext* context, JSValueConst vectorObj,
                       HPVector* outVector) GCC_ATTR((nonnull(1, 3)));

//	Set the value of a JS vector object.
bool JSVectorSetVector(JSContext* context, JSValueConst vectorObj,
                       Vector vector) GCC_ATTR((nonnull(1)));
bool JSVectorSetHPVector(JSContext* context, JSValueConst vectorObj,
                         HPVector vector) GCC_ATTR((nonnull(1)));

/*	VectorFromArgumentList()

        Construct a vector from an argument list which is either a (JS) vector,
   a (JS) entity, or an array of three numbers. The optional	outConsumed
        argument can be used to find out how many parameters were used
        (currently, this will be 0 on failure, otherwise 1).

        On failure, it will return NO and raise an error. If the caller is a JS
        callback, it must return JS_EXCEPTION to signal an error.

        DEPRECATED in favour of JSObjectGetVector(), since the list-of-number
   form is no longer used.
*/
bool VectorFromArgumentList(JSContext* context, const std::string& scriptClass,
                            const std::string& function, int argc,
                            JSValueConst* argv, HPVector* outVector,
                            int* outConsumed) GCC_ATTR((nonnull(1, 6)));

/*	VectorFromArgumentListNoError()

        Like VectorFromArgumentList(), but does not report an error on failure.
*/
bool VectorFromArgumentListNoError(JSContext* context, int argc,
                                   JSValueConst* argv, HPVector* outVector,
                                   int* outConsumed) GCC_ATTR((nonnull(1, 4)));
