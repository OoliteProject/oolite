/*

OOJSVector.h

JavaScript proxy for vectors.

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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
#import <jsapi.h>
#import "OOMaths.h"


void InitOOJSVector(JSContext *context, JSObject *global);


JSObject *JSVectorWithVector(JSContext *context, Vector vector);

BOOL VectorToJSValue(JSContext *context, Vector vector, jsval *outValue);
BOOL JSValueToVector(JSContext *context, jsval value, Vector *outVector);

//	Given a JS Vector proxy, get the corresponding Vector struct. Given a JS Entity, get its position. For anything else, return NO. (Other implicit conversions may be added in future.)
BOOL JSVectorGetVector(JSContext *context, JSObject *vectorObj, Vector *outVector);

//	Set the value of a JS vector object, or the position of an entity.
BOOL JSVectorSetVector(JSContext *context, JSObject *vectorObj, Vector vector);

// Construct a vector from an argument list which is either a (JS) vector, a (JS) entity, or three things that can be considered numbers. The optional outConsumed argument can be used to find out how many parameters were used (currently, this will be 0 on failure, otherwise 1 or 3). If it fails (and returns NO) the vector will be unaltered.
BOOL VectorFromArgumentList(JSContext *context, uintN argc, jsval *argv, Vector *outVector, uintN *outConsumed);
