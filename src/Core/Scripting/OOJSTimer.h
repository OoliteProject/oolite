/*

OOJSTimer.h

JavaScript timer class.


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

#import "OOScriptTimer.h"
#import "OOJSScript.h"
#include <jsapi.h>


@interface OOJSTimer: OOScriptTimer
{
@private
	jsval				_function;
	JSObject			*_jsThis;	// The object that is 'this' in the function call.
	
	OOJSScript			*_owningScript;
	
	JSObject			*_jsSelf;	// The JS Timer object proxy for this OOJSTimer.
}

@end


void InitOOJSTimer(JSContext *context, JSObject *global);
