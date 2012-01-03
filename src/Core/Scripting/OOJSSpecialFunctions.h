/*

OOJSSpecialFunctions.h

Special functions for certain scripts, currently the global prefix script and
the debug console script. Note that it's possible for other scripts to get at
the "special" object through the debug console object
(debugConsole.script.special). If putting actually dangerous functions in here,
it'd be a good idea to learn to use SpiderMonkey's security architecture
(JSPrincipals and such).


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

#import "OOJavaScriptEngine.h"


void InitOOJSSpecialFunctions(JSContext *context, JSObject *global);
OOJSValue *JSSpecialFunctionsObjectWrapper(JSContext *context);
