/*

OOJSEngineTransitionHelpers.h
(Included by OOJavaScriptEngine.h)

Macros and inlines to help transition from SpiderMonkey 1.7 to
SpiderMonkey 1.8.5/1.9/whatever.


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


/***** Transitional compatibility stuff - remove when switching to OO_NEW_JS permanently. *****/


// Before removing, switch to DOUBLE_TOJSVAL() everywhere.
OOINLINE JSBool JS_NewDoubleValue(JSContext *cx, jsdouble d, jsval *rval)
{
	NSCParameterAssert(rval != NULL);
	*rval = DOUBLE_TO_JSVAL(d);
	return YES;
}




/***** Helpers to write callbacks and abstract API changes. *****/

// Native callback conventions have changed.
#define OOJS_THIS							JS_THIS_OBJECT(context, vp)
#define OOJS_ARGV							JS_ARGV(context, vp)
#define OOJS_RVAL							JS_RVAL(context, vp)
#define OOJS_SET_RVAL(v)					JS_SET_RVAL(context, vp, v)

#define OOJS_ARG(n)							(OOJS_ARGV[(n)])
