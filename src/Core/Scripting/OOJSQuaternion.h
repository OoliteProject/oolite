/*

OOJSQuaternion.h

JavaScript proxy for quaternions.

Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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

#import <Foundation/Foundation.h>
#include <jsapi.h>
#import "OOMaths.h"


void InitOOJSQuaternion(JSContext *context, JSObject *global);


JSObject *JSQuaternionWithQuaternion(JSContext *context, Quaternion quaternion)  NONNULL_FUNC;

BOOL QuaternionToJSValue(JSContext *context, Quaternion quaternion, jsval *outValue)  NONNULL_FUNC;
BOOL JSValueToQuaternion(JSContext *context, jsval value, Quaternion *outQuaternion)  NONNULL_FUNC;

/*	Given a JS Quaternion object, get the corresponding Vector struct. Given a
	JS Entity, get its orientation. Given a JS Array with exactly four
	elements, all of them numbers, treat them as [w, x, y, z]  components. For
	anything else, return NO. (Other implicit conversions may be added in
	future.)
*/
BOOL JSObjectGetQuaternion(JSContext *context, JSObject *quaternionObj, Quaternion *outQuaternion)  GCC_ATTR((nonnull (1, 3)));

//	Set the value of a JS quaternion object.
BOOL JSQuaternionSetQuaternion(JSContext *context, JSObject *quaternionObj, Quaternion quaternion)  GCC_ATTR((nonnull (1)));


/*	QuaternionFromArgumentList()
	
	Construct a quaternion from an argument list which is either a (JS)
	quaternion, a (JS) entity, four numbers or a JS array of four numbers. The
	optional outConsumed argument can be used to find out how many parameters
	were used (currently, this will be 0 on failure, otherwise 1 or 4).
	
	On failure, it will return NO and raise an error. If the caller is a JS
	callback, it must return NO to signal an error.
*/
BOOL QuaternionFromArgumentList(JSContext *context, NSString *scriptClass, NSString *function, uintN argc, jsval *argv, Quaternion *outQuaternion, uintN *outConsumed)  GCC_ATTR((nonnull (1, 5, 6)));

/*	QuaternionFromArgumentList()
	
	Like VectorFromArgumentList(), but does not report an error on failure.
*/
BOOL QuaternionFromArgumentListNoError(JSContext *context, uintN argc, jsval *argv, Quaternion *outVector, uintN *outConsumed)  GCC_ATTR((nonnull (1, 3, 4)));
