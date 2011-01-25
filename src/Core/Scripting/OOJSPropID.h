/*

OOJSPropID.h


JavaScript support for Oolite
Copyright (C) 2007-2011 David Taylor and Jens Ayton.

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

#import <jsapi.h>


#ifndef OO_NEW_JS
#define OO_NEW_JS				0
#endif


/*	OOJSPropID
	Th type that identifies JavaScript properties/methods.
	
	OOJSID(const char * [literal])
	Macro to create a string-based ID. The string is interned and converted
	into a string by a helper the first time the macro is hit, then cached.
	
	OOStringFromJSPropID(propID)
	OOJSPropIDFromString(string)
	Converters.
*/
#if OO_NEW_JS
typedef jsid OOJSPropID;
#else
typedef const char *OOJSPropID;
#endif


#if OO_NEW_JS
#define OOJSID(str) ({ static jsid idCache; static BOOL inited; if (EXPECT_NOT(!inited)) OOJSInitPropIDCachePRIVATE(""str, &idCache, &inited); idCache; })
void OOJSInitPropIDCachePRIVATE(const char *name, jsid *idCache, BOOL *inited);
#else
#define OOJSID(str) (""str)
#endif
NSString *OOStringFromJSPropID(OOJSPropID propID);
OOJSPropID OOJSPropIDFromString(NSString *string);
