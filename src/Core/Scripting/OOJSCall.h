/*

OOJSCall.h

Declarations for the debug console's callObjC().

An entity is called through its generated name table (OOJSCallEntityMethods.h)
and the signature templates of any other object are @encode() strings.

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

#ifdef OO_DEBUG_MONITOR_ENABLED

#include <quickjs.h>

#include <string>

#include "OOFoundation.h"
#include "oofnd/StdLib.hpp"

/*	OOJSCallEntityMethod()

        Function for implementing JavaScript call() methods on an entity
   (callObjC()'s `this` is the C++ entity), by name table. The argument list is
   expected to be either a single string (the method's name), or a name ending
   with a : followed by arbitrary arguments which will be concatenated as a
        string; argv is assumed to hold at least one value. A result is set in
   *outResult (owned by the caller); a method without one leaves it unchanged,
   so the caller should initialize it (normally to JS_UNDEFINED). Only a name of
   kOOJSCallEntityMethods that the entity answers (its object's per-part
   -respondsToSelector:) is called, with the table's signature; any other name
   (a root-class or lifetime selector, one with other arguments) does not
   respond.

        If it returns false, an error has been reported and the caller (a
   native) should return JS_EXCEPTION.
*/
class Entity;
bool OOJSCallEntityMethod(JSContext* context, Entity* entity,
                          const std::string& oo_jsClassName, int argc,
                          JSValueConst* argv, JSValue* outResult);

#endif
