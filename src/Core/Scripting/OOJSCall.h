/*

OOJSCall.h

Basic JavaScript-to-ObjC bridge implementation.

Converted in bead oo-81hy (proposed ADR-0056 amendment oo-ppc; no class of its own): bool for BOOL.
An entity is called through its generated name table (OOJSCallEntityMethods.h) and the signature
templates of any other object are @encode() strings: no Objective-C class or protocol of its own is
left (the bridge files are deleted).

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

#ifdef OO_DEBUG_MONITOR_ENABLED

#import "OOFoundation.h"
#include "oofnd/StdLib.hpp"
#include <quickjs.h>
#include <string>

/*	OOJSCallObjCObjectMethod()

        Function for implementing JavaScript call() methods.

        The argument list is expected to be either a single string (selector), or
        a string ending with a : followed by arbitrary arguments which will be
        concatenated as a string. (This behaviour reflects Oolite's traditional
        scripting system and the expectations of its script methods. It also has
        the advantage that it needs only the runtime's method type encodings, not
        a general method-signature parser.)

        If the method returns an object, *outResult will be set to that object's
        -oo_jsValueInContext: (owned by the caller). Otherwise, it will be left
        unchanged, so the caller should initialize it (normally to JS_UNDEFINED).

        If it returns false, an error has been reported and the caller (a native)
        should return JS_EXCEPTION.

        argv is assumed to contain at least one value.
*/
bool OOJSCallObjCObjectMethod(JSContext* context, id object, const std::string& oo_jsClassName, int argc, JSValueConst* argv, JSValue* outResult);

/*	OOJSCallEntityMethod()

        The same for an entity (callObjC()'s `this` is the C++ entity), by name table: only a name
        of kOOJSCallEntityMethods that the entity answers (its object's per-part
        -respondsToSelector:) is called, with the table's signature; any other name (a root-class
        or lifetime selector, one with other arguments) does not respond.
*/
class Entity;
bool OOJSCallEntityMethod(JSContext* context, Entity* entity, const std::string& oo_jsClassName, int argc, JSValueConst* argv, JSValue* outResult);

#endif
