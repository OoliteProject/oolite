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


typedef struct RunningStack RunningStack;
struct RunningStack
{
	RunningStack		*back;
	OOJSScript			*current;
};


static JSObject			*sScriptPrototype;
static RunningStack		*sRunningStack = NULL;


static JSBool JSScriptConvert(JSContext *context, JSObject *this, JSType type, jsval *outValue);
static void JSScriptFinalize(JSContext *context, JSObject *this);


static JSClass sScriptClass =
{
	"Script",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,
	JS_PropertyStub,
	JS_PropertyStub,
	JS_PropertyStub,
	JS_EnumerateStub,
	JS_ResolveStub,
	JSScriptConvert,
	JSScriptFinalize
};


@interface OOJSScript (OOPrivate)

- (NSString *)scriptNameFromPath:(NSString *)path;

@end


@implementation OOJSScript

+ (id)scriptWithPath:(NSString *)path properties:(NSDictionary *)properties
{
	return [[[self alloc] initWithPath:path properties:properties] autorelease];
}


- (id)initWithPath:(NSString *)path properties:(NSDictionary *)properties
{
	return [self initWithPath:path properties:properties context:[[OOJavaScriptEngine sharedEngine] context]];
}


- (id)initWithPath:(NSString *)path properties:(NSDictionary *)properties context:(JSContext *)inContext
{
	NSString				*problem = nil;		// Acts as error flag.
	NSString				*fileContents = nil;
	NSData					*data = nil;
	JSScript				*script = NULL;
	jsval					returnValue;
	NSEnumerator			*keyEnum = nil;
	NSString				*key = nil;
	id						property = nil;
	
	self = [super init];
	if (self == nil) problem = @"allocation failure";
	
	// Set up JS object
	if (!problem)
	{
		context = inContext;
		// Do we actually want parent to be the global object here?
		object = JS_NewObject(context, &sScriptClass, sScriptPrototype, JS_GetGlobalObject(context));
		if (object == NULL) problem = @"allocation failure";
	}
	
	if (!problem)
	{
		if (!JS_SetPrivate(context, object, [self weakRetain]))  problem = @"could not set private backreference";
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
	
	// Set properties.
	if (!problem && properties != nil)
	{
		for (keyEnum = [properties keyEnumerator]; (key = [keyEnum nextObject]); )
		{
			if ([key isKindOfClass:[NSString class]])
			{
				property = [properties objectForKey:key];
				[self defineProperty:property named:key];
			}
		}
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
		if (name == nil)
		{
			name = [[self scriptNameFromPath:path] retain];
			[self setProperty:name named:@"name"];
		}
		
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


- (void) dealloc
{
	[name release];
	[description release];
	[version release];
	[weakSelf weakRefDrop];
	
	[super dealloc];
}


+ (OOJSScript *)currentlyRunningScript
{
	if (sRunningStack == NULL)  return NULL;
	return sRunningStack->current;
}


- (id) weakRetain
{
	if (weakSelf == nil)  weakSelf = [OOWeakReference weakRefWithObject:self];
	return [weakSelf retain];
}


- (void) weakRefDied:(OOWeakReference *)weakRef
{
	if (weakRef == weakSelf)  weakSelf = nil;
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
	RunningStack	stackElement;

	OK = JS_GetProperty(context, object, [eventName cString], &value);
	if (OK && !JSVAL_IS_VOID(value))
	{
		function = JS_ValueToFunction(context, value);
		if (function != NULL)
		{
			// Push self on stack of running scripts
			stackElement.back = sRunningStack;
			stackElement.current = self;
			sRunningStack = &stackElement;
			
			JSArgumentsFromArray(context, arguments, &argc, &argv);
			OK = JS_CallFunction(context, object, function, argc, argv, &value);
			if (argv != NULL) free(argv);
			
			// Pop running scripts stack
			sRunningStack = stackElement.back;
			
			return OK;
		}
	}

	return NO;
}


- (id)propertyNamed:(NSString *)propName
{
	BOOL						OK;
	jsval						value = nil;
	
	if (propName == nil)  return nil;
	
	OK = JS_GetProperty(context, object, [propName UTF8String], &value);
	if (!OK || JSVAL_IS_VOID(value))  return nil;
	
	return JSValueToObject(context, value);
}


- (BOOL)setProperty:(id)value named:(NSString *)propName
{
	jsval						jsValue;
	
	if (value == nil || propName == nil)  return NO;
	
	jsValue = [value javaScriptValueInContext:context];
	if (!JSVAL_IS_VOID(jsValue))
	{
		return JS_DefineProperty(context, object, [propName UTF8String], jsValue, NULL, NULL, JSPROP_ENUMERATE);
	}
	return NO;
}


- (BOOL)defineProperty:(id)value named:(NSString *)propName
{
	jsval						jsValue;
	
	if (value == nil || propName == nil)  return NO;
	
	jsValue = [value javaScriptValueInContext:context];
	if (!JSVAL_IS_VOID(jsValue))
	{
		return JS_DefineProperty(context, object, [propName UTF8String], jsValue, NULL, NULL, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
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


- (jsval)javaScriptValueInContext:(JSContext *)context
{
	return OBJECT_TO_JSVAL(object);
}

@end


@implementation OOScript(OOJavaScriptConversion)

- (jsval)javaScriptValueInContext:(JSContext *)context
{
	return JSVAL_NULL;
}

@end


void InitOOJSScript(JSContext *context, JSObject *global)
{
	sScriptPrototype = JS_InitClass(context, global, NULL, &sScriptClass, NULL, 0, NULL, NULL, NULL, NULL);
	JSRegisterObjectConverter(&sScriptClass, JSBasicPrivateObjectConverter);
}


static JSBool JSScriptConvert(JSContext *context, JSObject *this, JSType type, jsval *outValue)
{
	OOJSScript					*script = nil;
	
	switch (type)
	{
		case JSTYPE_VOID:		// Used for string concatenation.
		case JSTYPE_STRING:
			// Return description of script
			script = JS_GetInstancePrivate(context, this, &sScriptClass, NULL);
			script = [script weakRefUnderlyingObject];
			if (script != nil)
			{
				*outValue = [[script description] javaScriptValueInContext:context];
			}
			else
			{
				*outValue = STRING_TO_JSVAL(JS_InternString(context, "[stale Script]"));
			}
			return YES;
			
		default:
			// Contrary to what passes for documentation, JS_ConvertStub is not a no-op.
			return JS_ConvertStub(context, this, type, outValue);
	}
}


static void JSScriptFinalize(JSContext *context, JSObject *this)
{
	OOLog(@"js.script.temp", @"%@ called for %p", this);
	[(id)JS_GetPrivate(context, this) release];
	JS_SetPrivate(context, this, nil);
}
