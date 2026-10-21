/*

OOJSFont.m (QuickJS-ng)


Copyright (C) 2011-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOJSFont.h"
#import "HeadUpDisplay.h"
#import "OOJavaScriptEngine.h"

static JSValue FontMeasureString(OOJS_NATIVE_ARGS);

// MARK: Public

void InitOOJSFont(JSContext* context, JSValueConst global)
{
    JSValue fontObject = JS_NewObject(context);
    JS_DefinePropertyValueStr(context, fontObject, "measureString", JS_NewCFunction(context, FontMeasureString, "measureString", 1), OOJS_METHOD_READONLY);
    JS_DefinePropertyValueStr(context, global, "defaultFont", fontObject, OOJS_PROP_READONLY);
}

// MARK: Methods

static JSValue FontMeasureString(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (EXPECT_NOT(argc < 1) || JS_IsUndefined(OOJS_ARGV[0])) {
        JSValueConst undefined = JS_UNDEFINED;
        OOJSReportBadArguments(context, nil, @"defaultFont.measureString", MIN(argc, 1), &undefined, nil, @"string");
        return OOJSNativeFailure(context);
    }

    OOJS_RETURN_DOUBLE(OOStringWidthInEm(OOStringFromJSValue(context, OOJS_ARGV[0])));

    OOJS_NATIVE_EXIT
}
