/*

OXPScript.m

JavaScript support for Oolite
Copyright (C) 2007 David Taylor

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

#import "OXPScript.h"
#import "OOLogging.h"


OXPScript *currentOXPScript;

JSClass OXP_class = {
	"OXPScript", JSCLASS_HAS_PRIVATE,
	JS_PropertyStub,JS_PropertyStub,JS_PropertyStub,JS_PropertyStub,
	JS_EnumerateStub,JS_ResolveStub,JS_ConvertStub,JS_FinalizeStub
};

extern NSString *JSValToNSString(JSContext *cx, jsval val);

@implementation OXPScript

- (id) initWithContext: (JSContext *) context andFilename: (NSString *) filename
{
	// Check if file exists before doing anything else
	// ...

	self = [super init];
	
	obj = JS_NewObject(context, &OXP_class, 0x00, JS_GetGlobalObject(context));
	JS_AddRoot(context, &obj); // note 2nd arg is a pointer-to-pointer

	cx = context;

	jsval rval;
	JSBool ok;
    JSScript *script = JS_CompileFile(context, obj, [filename cString]);
    if (script != NULL) {
		ok = JS_ExecuteScript(context, obj, script, &rval);
		if (ok) {
			ok = JS_GetProperty(context, obj, "Name", &rval);
			if (ok) {
				name = JSValToNSString(context, rval);
			} else {
				// No name given in the script so use the filename
				name = [NSString stringWithString:filename];
			}
			ok = JS_GetProperty(context, obj, "Description", &rval);
			if (ok) {
				description = JSValToNSString(context, rval);
			} else {
				description = @"";
			}
			ok = JS_GetProperty(context, obj, "Version", &rval);
			if (ok) {
				version = JSValToNSString(context, rval);
			} else {
				version= @"";
			}
			OOLog(@"script.javascript.compile.success", @"Loaded JavaScript OXP: %@ %@ %@", name, description, version);

			/*
			 * Example code to read the mission variables.
			 *
			 * So far, this just gets their names. Need to add code to get their values
			 * and convert the whole thing to Obj-C friendly NSArray and types.
			 *
			ok = JS_GetProperty(context, obj, "MissionVars", &rval);
			if (ok && JSVAL_IS_OBJECT(rval)) {
				JSObject *ar = JSVAL_TO_OBJECT(rval);
				JSIdArray *ids = JS_Enumerate(context, ar);
				int i;
				for (i = 0; i < ids->length; i++) {
					if (JS_IdToValue(cx, ids->vector[i], &rval) == JS_TRUE) {
						if (JSVAL_IS_BOOLEAN(rval))	fprintf(stdout, "a boolean\r\n");
						if (JSVAL_IS_DOUBLE(rval))	fprintf(stdout, "a double\r\n");
						if (JSVAL_IS_INT(rval))	fprintf(stdout, "an integer\r\n");
						if (JSVAL_IS_NUMBER(rval))	fprintf(stdout, "a number\r\n");
						if (JSVAL_IS_OBJECT(rval))	fprintf(stdout, "an object\r\n");
						if (JSVAL_IS_STRING(rval)) {
							fprintf(stdout, "%s\r\n", JS_GetStringBytes(JSVAL_TO_STRING(rval)));
						}
					}
				}
				JS_DestroyIdArray(context, ids);
			}
			*/
		}
		JS_DestroyScript(context, script);
	} else {
		OOLog(@"script.javascript.compile.failed", @"Script compilation failed");
		[self release];
		return nil;
	}

	return self;
}

- (NSString *) name
{
	return name;
}

- (NSString *) description
{
	return description;
}

- (NSString *) version
{
	return version;
}

- (BOOL) doEvent: (NSString *) eventName
{
	jsval rval;
	JSBool ok;

	ok = JS_GetProperty(cx, obj, [eventName cString], &rval);
	if (ok && !JSVAL_IS_VOID(rval)) {
		JSFunction *func = JS_ValueToFunction(cx, rval);
		if (func != 0x00) {
			currentOXPScript = self;
			ok = JS_CallFunction(cx, obj, func, 0, 0x00, &rval);
			if (ok)
				return YES;
		}
	}

	return NO;
}

- (BOOL) doEvent: (NSString *) eventName withIntegerArgument:(int)argument
{
	jsval rval;
	JSBool ok;

	ok = JS_GetProperty(cx, obj, [eventName cString], &rval);
	if (ok && !JSVAL_IS_VOID(rval)) {
		JSFunction *func = JS_ValueToFunction(cx, rval);
		if (func != 0x00) {
			currentOXPScript = self;
			jsval args[1];
			args[0] = INT_TO_JSVAL(argument);
			ok = JS_CallFunction(cx, obj, func, 1, args, &rval);
			if (ok)
				return YES;
		}
	}

	return NO;
}

- (BOOL) doEvent: (NSString *) eventName withStringArgument:(NSString *)argument
{
	jsval rval;
	JSBool ok;

	ok = JS_GetProperty(cx, obj, [eventName cString], &rval);
	if (ok && !JSVAL_IS_VOID(rval)) {
		JSFunction *func = JS_ValueToFunction(cx, rval);
		if (func != 0x00) {
			currentOXPScript = self;
			ok = JS_CallFunction(cx, obj, func, 0, 0x00, &rval);
			if (ok)
				return YES;
		}
	}

	return NO;
}

@end
