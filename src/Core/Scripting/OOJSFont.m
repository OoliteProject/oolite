/*

OOJSFont.m


Copyright (C) 2011-2012 Jens Ayton

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
#import "OOJavaScriptEngine.h"
#import "HeadUpDisplay.h"


static JSBool FontMeasureString(JSContext *context, uintN argc, jsval *vp);


// MARK: Public

void InitOOJSFont(JSContext *context, JSObject *global)
{
	JSObject *fontObject = JS_DefineObject(context, global, "defaultFont", NULL, NULL, OOJS_PROP_READONLY);
	JS_DefineFunction(context, fontObject, "measureString", FontMeasureString, 1, OOJS_METHOD_READONLY);
}


// MARK: Methods

static JSBool FontMeasureString(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(argc < 1) || JSVAL_IS_VOID(OOJS_ARGV[0]))
	{
		jsval undefined = JSVAL_VOID;
		OOJSReportBadArguments(context, nil, @"defaultFont.measureString", MIN(argc, 1U), &undefined, nil, @"string");
		return NO;
	}
	
	OOJS_RETURN_DOUBLE(OOStringWidthInEm(OOStringFromJSValue(context, OOJS_ARGV[0])));
	
	OOJS_NATIVE_EXIT
}
