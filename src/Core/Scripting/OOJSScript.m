/*

OOJSScript.m

JavaScript support for Oolite
Copyright (C) 2007 David Taylor and Jens Ayton.

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
#import "NSStringOOExtensions.h"
#import "EntityOOJavaScriptExtensions.h"


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


#define JSValToNSString(context, val) [NSString stringWithJavaScriptValue:val inContext:context]


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


- (id)initWithPath:(NSString *)path andContext:(JSContext *)inContext
{
	NSString		*problem = nil;		// Acts as error flag.
	NSString		*fileContents = nil;
	NSData			*data = nil;
	JSScript		*script = NULL;
	jsval			returnValue;
	
	self = [super init];
	if (self == nil) problem = @"allocation failure";
	
	// Set up JS object
	if (!problem)
	{
		context = inContext;
		object = JS_NewObject(context, &script_class, 0x00, JS_GetGlobalObject(context));
		if (object == NULL) problem = @"allocation failure";
	}
	if (!problem)
	{
		if (!JS_AddRoot(context, &object)) // note 2nd arg is a pointer-to-pointer
		{
			problem = @"could not add JavaScript root object";
		}
	}
	
	if (!problem)
	{
		fileContents = [NSString stringWithContentsOfUnicodeFile:path];
		if (fileContents != nil)  data = [fileContents utf16DataWithBOM:NO];
		if (data == nil) problem = @"could not load file";
	}
	
	// Compile
	if (!problem)
	{
		script = JS_CompileUCScript(context, object, [data bytes], [data length] / sizeof(unichar), [path UTF8String], 1);
		if (script == NULL) problem = @"compilation failed";
	}
	
	// Run the script (allowing it to set up the properties we need, as well as setting up those event handlers)
    if (!problem)
	{
		if (!JS_ExecuteScript(context, object, script, &returnValue))
		{
			problem = @"could not run script";
		}
		
		// We don't need the script any more - the event handlers hang around as long as the JS object exists.
		JS_DestroyScript(context, script);
	}
	
	if (!problem)
	{
		// Get display attributes from script
		name = [JSPropertyAsString(context, object, "name") retain];
		if (name == nil) name = [[self scriptNameFromPath:path] retain];
		
		version = [JSPropertyAsString(context, object, "version") retain];
		description = [JSPropertyAsString(context, object, "description") retain];
		
		OOLog(@"script.javaScript.load.success", @"Loaded JavaScript OXP: %@ -- %@", [self displayName], description ? description : @"(no description)");
	}
	
	if (problem)
	{
		OOLog(@"script.javaScript.load.failed", @"***** Error loading JavaScript script %@ -- %@", path, problem);
		[self release];
		self = nil;
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
	[self doEvent:@"tickle" withArguments:[NSArray arrayWithObject:[[PlayerEntity sharedPlayer] status_string]]];
}


- (BOOL)doEvent:(NSString *)eventName withArguments:(NSArray *)arguments
{
	BOOL			OK;
	jsval			value;
	JSFunction		*function;
	uintN			argc;
	jsval			*argv = NULL;

	OK = JS_GetProperty(context, object, [eventName cString], &value);
	if (OK && !JSVAL_IS_VOID(value))
	{
		function = JS_ValueToFunction(context, value);
		if (function != NULL)
		{
			currentOOJSScript = self;
			JSArgumentsFromArray(context, arguments, &argc, &argv);
			OK = JS_CallFunction(context, object, function, argc, argv, &value);
			if (argv != NULL) free(argv);
			return OK;
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
