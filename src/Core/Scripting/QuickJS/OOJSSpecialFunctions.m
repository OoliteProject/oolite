/*

OOJSSpecialFunctions.m


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

#import "OOJSSpecialFunctions.h"

static JSValue SpecialJSWarning(OOJS_NATIVE_ARGS);
#ifdef OO_DEBUG_MONITOR_ENABLED
static JSValue SpecialMarkConsoleEntryPoint(OOJS_NATIVE_ARGS);
#endif

static const JSCFunctionListEntry sSpecialFunctionsMethods[] = {
    // JS name					Function						min args
    JS_CFUNC_DEF("jsWarning", 1, SpecialJSWarning),
#ifdef OO_DEBUG_MONITOR_ENABLED
    JS_CFUNC_DEF("markConsoleEntryPoint", 0, SpecialMarkConsoleEntryPoint),
#endif
};

void InitOOJSSpecialFunctions(JSContext* context, JSValueConst global)
{
}

JSValue JSSpecialFunctionsObjectWrapper(JSContext* context)
{
    /*
            Special object is created on the fly so it can be GCed (the debug
            console script keeps a reference to its copy, but the prefix script
            doesn't) and so we don't need to clean up a root on JS engine reset.
            -- Ahruman 2011-03-30

            With QuickJS, the caller owns the returned object.
    */

    JSValue special = JS_NewObject(context);
    if (JS_IsException(special)) {
        OOJSReportPendingException(context);
        return JS_NULL;
    }
    JS_SetPropertyFunctionList(context, special, sSpecialFunctionsMethods, OOJS_COUNT(sSpecialFunctionsMethods));
    JS_FreezeObject(context, special);

    return special;
}

static JSValue SpecialJSWarning(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER // These functions are exception-safe

        if (EXPECT_NOT(argc < 1))
    {
        OOJSReportBadArguments(context, @"special", @"jsWarning", argc, OOJS_ARGV, nil, @"string");
        return JS_EXCEPTION;
    }

    OOJSSetWarningOrErrorStackSkip(1);
    OOJSReportWarning(context, @"%@", OOStringFromJSValue(context, OOJS_ARGV[0]));
    OOJSSetWarningOrErrorStackSkip(0);

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

#ifdef OO_DEBUG_MONITOR_ENABLED
static JSValue SpecialMarkConsoleEntryPoint(OOJS_NATIVE_ARGS)
{
    /*	The SpiderMonkey version recorded the calling stack frame (in eval() in
            console.script.evaluate()) with OOJSMarkConsoleEvalLocation(), so that
            OOJSDescribeLocation() could describe locations in console-evaluated
            code specially. QuickJS has no stack frame API and the engine has no
            OOJSDescribeLocation(), so this does nothing; locations in console
            code are reported like any other.
    */
    OOJS_RETURN_VOID;
}
#endif
