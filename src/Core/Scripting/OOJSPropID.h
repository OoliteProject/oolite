/*

OOJSPropID.h


JavaScript support for Oolite
Copyright (C) 2007-2013 David Taylor and Jens Ayton.

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

#include <jsapi.h>
#import "OOFunctionAttributes.h"

/*
	OOJSID(const char * [literal])
	Macro to create a string-based jsid. The string is interned and converted
	into a string by a helper the first time the macro is hit, then cached.
*/

#ifdef JS_USE_JSVAL_JSID_STRUCT_TYPES
#define OOJSID(str) ({ static jsid idCache; static JSBool inited; if (EXPECT_NOT(!inited)) { OOJSInitJSIDCachePRIVATE(""str, &idCache); inited = JS_TRUE; } idCache; })
#else
#define OOJSID(str) ({ static jsid idCache = JSID_VOID; if (EXPECT_NOT(idCache == JSID_VOID)) OOJSInitJSIDCachePRIVATE(""str, &idCache); idCache; })
#endif
void OOJSInitJSIDCachePRIVATE(const char *name, jsid *idCache);
