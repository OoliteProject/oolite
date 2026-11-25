/*

OOJSPropID.h (QuickJS-ng)

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

#import "OOFunctionAttributes.h"
#include <quickjs.h>

/*	Engine-neutral names for a property ID and a value (jsid and jsval with
        SpiderMonkey). Declared here, rather than in OOJavaScriptEngine.h, so game
        headers imported by OOJavaScriptEngine.h can use them.
*/
typedef JSAtom OOJSPropID;
typedef JSValue OOJSVal;

/*
        OOJSID(const char * [literal])
        Macro to create a property ID. The string is interned the first time the
        macro is hit, then cached; the atom lives as long as the runtime.
*/
#define OOJSID(str) ({ static JSAtom idCache = JS_ATOM_NULL; if (EXPECT_NOT(idCache == JS_ATOM_NULL)) idCache = OOJSInternAtomPRIVATE(""str); idCache; })
JSAtom OOJSInternAtomPRIVATE(const char* name);
