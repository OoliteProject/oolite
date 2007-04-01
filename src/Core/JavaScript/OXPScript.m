/*

OOJSScript.m

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

#import "OOJSScript.h"
#import "OOLogging.h"
#import "OOConstToString.h"
#import "Entity.h"
#import "OOJavaScriptEngine.h"


OOJSScript *currentOOJSScript;

JSClass script_class =
{
	"JSScript",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,
	JS_PropertyStub,
	JS_PropertyStub,
	JS_PropertyStub,
	JS_EnumerateStub,
	JS_ResolveStub,
	JS_ConvertStub,
	JS_FinalizeStub
};


#define JSValToNSString(cx, val) [NSString stringWithJavaScriptValue:val inContext:cx]


@interface OOJSScript (OOPrivate)

- (NSString *)scriptNameFromPath:(NSString *)path;

@end


@implementation OOJSScript

+ (id)scriptWithPath:(NSString *)path
{
	return [[[self alloc] initWithPath:path] autorelease];
}


- (id)initWithPath:(NSString *)path
{
	return [self initWithPath:path andContext:[[OOJavaScriptEngine sharedEngine] context]];
}


- (id)initWithPath:(NSString *)path andContext:(JSContext *)context
{
	self = [super init];
	
	obj = JS_NewObject(context, &script_class, 0x00, JS_GetGlobalObject(context));
	JS_AddRoot(context, &obj); // note 2nd arg is a pointer-to-pointer

	cx = context;

	jsval rval;
	JSBool ok;
    JSScript *script = JS_CompileFile(context, obj, [path fileSystemRepresentation]);
    if (script != NULL)
	{
		ok = JS_ExecuteScript(context, obj, script, &rval);
		if (ok)
		{
			ok = JS_GetProperty(context, obj, "name", &rval);
			if (ok && !JSVAL_IS_VOID(rval))
			{
				name = [[NSString stringWithJavaScriptValue:rval inContext:context] retain];
			}
			else
			{
				// No name given in the script so use the file name
				name = [[self scriptNameFromPath:path] retain];
			}
			
			ok = JS_GetProperty(context, obj, "description", &rval);
			if (ok && !JSVAL_IS_VOID(rval))
			{
				description = [[NSString stringWithJavaScriptValue:rval inContext:context] retain];
			}
			
			ok = JS_GetProperty(context, obj, "version", &rval);
			if (ok && !JSVAL_IS_VOID(rval))
			{
				version = [[NSString stringWithJavaScriptValue:rval inContext:context] retain];
			}
			
			OOLog(@"script.javaScript.compile.success", @"Loaded JavaScript OXP: %@ -- %@", [self displayName], description ? description : @"(no description)");

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
	}
	else
	{
		OOLog(@"script.javaScript.compile.failed", @"Failed to compile JavaScript script %@", path);
		[self release];
		return nil;
	}

	return self;
}

- (NSString *) name
{
	return name;
}

- (NSString *) scriptDescription
{
	return description;
}

- (NSString *) version
{
	return version;
}

- (void)runWithTarget:(Entity *)target
{
	[self doEvent:@"tickle" withStringArgument:[[PlayerEntity sharedPlayer] status_string]];
}

- (BOOL) doEvent: (NSString *) eventName
{
	jsval rval;
	JSBool ok;

	ok = JS_GetProperty(cx, obj, [eventName cString], &rval);
	if (ok && !JSVAL_IS_VOID(rval)) {
		JSFunction *func = JS_ValueToFunction(cx, rval);
		if (func != 0x00) {
			currentOOJSScript = self;
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
			currentOOJSScript = self;
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
			currentOOJSScript = self;
			jsval args[1];
			args[0] = [argument javaScriptValueInContext:cx];
			ok = JS_CallFunction(cx, obj, func, 1, args, &rval);
			if (ok)
				return YES;
		}
	}

	return NO;
}


/*	Generate default name for script which doesn't set its name property when
	first run.
	
	The generated name is <name>.anon-script, where <name> is selected as
	follows:
	  * If path is nil (futureproofing), use the address of the script object.
	  * If the file's name is something other than script.*, use the file name.
	  * If the containing directory is something other than Config, use the
		containing directory's name.
	  * Otherwise, use the containing directory's parent (which will generally
		be an OXP root directory).
	  * If either of the two previous steps results in an empty string, fall
		back on the full path.
*/
- (NSString *)scriptNameFromPath:(NSString *)path
{
	NSString		*lastComponent = nil;
	NSString		*truncatedPath = nil;
	NSString		*theName = nil;
	
	if (path == nil) theName = [NSString stringWithFormat:@"%p", self];
	else
	{
		lastComponent = [path lastPathComponent];
		if (![lastComponent hasPrefix:@"script."]) theName = lastComponent;
		else
		{
			truncatedPath = [path stringByDeletingLastPathComponent];
			if (NSOrderedSame == [[truncatedPath lastPathComponent] caseInsensitiveCompare:@"Config"])
			{
				truncatedPath = [truncatedPath stringByDeletingLastPathComponent];
			}
			if (NSOrderedSame == [[truncatedPath pathExtension] caseInsensitiveCompare:@"oxp"])
			{
				truncatedPath = [truncatedPath stringByDeletingPathExtension];
			}
			
			lastComponent = [truncatedPath lastPathComponent];
			theName = lastComponent;
		}
	}
	
	if (0 == [theName length]) theName = path;
	
	return [theName stringByAppendingString:@".anon-script"];
}

@end
