/*

OOJSCall.h

Basic JavaScript-to-ObjC bridge implementation.

Converted in bead oo-81hy (proposed ADR-0056 amendment oo-ppc; no class of its own): bool for BOOL.
Since bead oo-9ht.44 an entity is called through its generated name table (OOJSCallEntityMethods.h)
and the signature templates of any other object are @encode() strings: no Objective-C class or
protocol of its own is left (the bridge files are deleted).

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

#ifndef NDEBUG

#include "OOCocoa.h"
#include "ooscript/JSEngine.hpp"
#include "oofnd/StdLib.hpp"
#include <string>
/*	(OOJSCallObjCObjectMethod(), which called any Objective-C object's method by name for callObjC(),
	went with bead oo-4aq6a.5: the console's callObjC() is given only entities and monitors.)
*/


/*	OOJSCallEntityMethod()

	Function for implementing JavaScript call() methods on an entity (callObjC()'s `this` is the C++
	entity since bead oo-9ht.39.5.3), by name table (bead oo-9ht.44). The argument list is expected
	to be either a single string (the method's name), or a name ending with a : followed by arbitrary
	arguments which will be concatenated as a string; argv is assumed to hold at least one value.
	A result is set in *outResult; a method without one leaves it unchanged. Only a name of
	kOOJSCallEntityMethods that the entity answers
	(its object's per-part -respondsToSelector:) is called, with the table's signature; any other
	name (a root-class or lifetime selector, one with other arguments) does not respond.
*/
class Entity;
bool OOJSCallEntityMethod(ooscript::Context context, Entity *entity, const std::string &oo_jsClassName, unsigned argc, ooscript::Value *argv, ooscript::Value *outResult);

#endif
