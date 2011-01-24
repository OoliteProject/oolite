/*

OOJSScript.m

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

#ifndef OO_CACHE_JS_SCRIPTS
#define OO_CACHE_JS_SCRIPTS		1
#endif


#import "OOJSScript.h"
#import "OOJavaScriptEngine.h"
#import "OOJSEngineTimeManagement.h"

#import "OOLogging.h"
#import "OOConstToString.h"
#import "Entity.h"
#import "NSStringOOExtensions.h"
#import "EntityOOJavaScriptExtensions.h"
#import "OOConstToJSString.h"

#if OO_CACHE_JS_SCRIPTS
#import <jsxdrapi.h>
#import "OOCacheManager.h"
#endif


typedef struct RunningStack RunningStack;
struct RunningStack
{
	RunningStack		*back;
	OOJSScript			*current;
};


static JSObject			*sScriptPrototype;
static RunningStack		*sRunningStack = NULL;


static void AddStackToArrayReversed(NSMutableArray *array, RunningStack *stack);

static JSScript *LoadScriptWithName(JSContext *context, NSString *path, JSObject *object, JSObject **outScriptObject, NSString **outErrorMessage);

#if OO_CACHE_JS_SCRIPTS
static NSData *CompiledScriptData(JSContext *context, JSScript *script);
static JSScript *ScriptWithCompiledData(JSContext *context, NSData *data);
#endif

static NSString *StrippedName(NSString *string);


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
	JS_ConvertStub,
	OOJSObjectWrapperFinalize
};


static JSFunctionSpec sScriptMethods[] =
{
	// JS name					Function					min args
	{ "toString",				OOJSObjectWrapperToString,	0, },
	{ 0 }
};


@interface OOJSScript (OOPrivate)

- (NSString *)scriptNameFromPath:(NSString *)path;

@end


@implementation OOJSScript

+ (id) scriptWithPath:(NSString *)path properties:(NSDictionary *)properties
{
	return [[[self alloc] initWithPath:path properties:properties] autorelease];
}


- (id) initWithPath:(NSString *)path properties:(NSDictionary *)properties
{
	JSContext				*context = NULL;
	NSString				*problem = nil;		// Acts as error flag.
	JSScript				*script = NULL;
	JSObject				*scriptObject = NULL;
	jsval					returnValue = JSVAL_VOID;
	NSEnumerator			*keyEnum = nil;
	NSString				*key = nil;
	id						property = nil;
	
	self = [super init];
	if (self == nil) problem = @"allocation failure";
	
	context = OOJSAcquireContext();
	
	// Set up JS object
	if (!problem)
	{
		_jsSelf = JS_NewObject(context, &sScriptClass, sScriptPrototype, NULL);
		if (_jsSelf == NULL) problem = @"allocation failure";
	}
	
	if (!problem && !OOJSAddGCObjectRoot(context, &_jsSelf, "Script object"))
	{
		problem = @"could not add JavaScript root object";
	}
	
#if OO_NEW_JS
	if (!problem && !OOJSAddGCObjectRoot(context, &scriptObject, "Script GC holder"))
	{
		problem = @"could not add JavaScript root object";
	}
#endif
	
	if (!problem)
	{
		if (!JS_SetPrivate(context, _jsSelf, [self weakRetain]))  problem = @"could not set private backreference";
	}
	
	// Push self on stack of running scripts.
	RunningStack stackElement =
	{
		.back = sRunningStack,
		.current = self
	};
	sRunningStack = &stackElement;
	
	filePath = [path retain];
	
	if (!problem)
	{
		script = LoadScriptWithName(context, path, _jsSelf, &scriptObject, &problem);
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
	
	/*	Set initial name (in case of script error during initial run).
		The "name" ivar is not set here, so the property can be fetched from JS
		if we fail during setup. However, the "name" ivar is set later so that
		the script object can't be renamed after the initial run. This could
		probably also be achieved by fiddling with JS property attributes.
	*/
	OOJSPropID nameID = OOJSID("name");
	[self setProperty:[self scriptNameFromPath:path] withID:nameID inContext:context];
	
	// Run the script (allowing it to set up the properties we need, as well as setting up those event handlers)
	if (!problem)
	{
		OOJSStartTimeLimiterWithTimeLimit(kOOJSLongTimeLimit);
		if (!JS_ExecuteScript(context, _jsSelf, script, &returnValue))
		{
			problem = @"could not run script";
		}
		OOJSStopTimeLimiter();
		
		// We don't need the script any more - the event handlers hang around as long as the JS object exists.
		JS_DestroyScript(context, script);
	}
#if OO_NEW_JS
	JS_RemoveObjectRoot(context, &scriptObject);
#endif
	
	sRunningStack = stackElement.back;
	
	if (!problem)
	{
		// Get display attributes from script
		DESTROY(name);
		name = [StrippedName([[self propertyWithID:nameID inContext:context] description]) copy];
		if (name == nil)
		{
			name = [[self scriptNameFromPath:path] retain];
			[self setProperty:name withID:nameID inContext:context];
		}
		
		version = [[[self propertyWithID:OOJSID("version") inContext:context] description] copy];
		description = [[[self propertyWithID:OOJSID("description") inContext:context] description] copy];
		
		OOLog(@"script.javaScript.load.success", @"Loaded JavaScript OXP: %@ -- %@", [self displayName], description ? description : (NSString *)@"(no description)");
	}
	
	DESTROY(filePath);	// Only used for error reporting during startup.
	
	if (problem)
	{
		OOLog(@"script.javaScript.load.failed", @"***** Error loading JavaScript script %@ -- %@", path, problem);
		[self release];
		self = nil;
	}
	
	OOJSRelinquishContext(context);
	
	return self;
	// Analyzer: object leaked. [Expected, object is retained by JS object.]
}


- (void) dealloc
{
	[name release];
	[description release];
	[version release];
	DESTROY(filePath);
	
	JSContext *context = OOJSAcquireContext();
	
	OOJSObjectWrapperFinalize(context, _jsSelf);	// Release weakref to self
	JS_RemoveObjectRoot(context, &_jsSelf);			// Unroot jsSelf
	
	OOJSRelinquishContext(context);
	
	[weakSelf weakRefDrop];
	
	[super dealloc];
}


- (NSString *) oo_jsClassName
{
	return @"Script";
}


+ (OOJSScript *)currentlyRunningScript
{
	if (sRunningStack == NULL)  return NULL;
	return sRunningStack->current;
}


+ (NSArray *)scriptStack
{
	NSMutableArray			*result = nil;
	
	result = [NSMutableArray array];
	AddStackToArrayReversed(result, sRunningStack);
	return result;
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
	if (name == nil)  name = [[self propertyNamed:@"name"] copy];
	if (name == nil)  return [self scriptNameFromPath:filePath];	// Special case for parse errors during load.
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
	JSContext *context = OOJSAcquireContext();
	jsval arg = OOJSValueFromEntityStatus(context, [PLAYER status]);
	[self callMethod:OOJSID("tickle") inContext:context withArguments:&arg count:1 result:NULL];
	OOJSRelinquishContext(context);
}


- (BOOL) callMethod:(OOJSPropID)methodID
		  inContext:(JSContext *)context
	  withArguments:(jsval *)argv count:(intN)argc
			 result:(jsval *)outResult
{
	NSParameterAssert(name != NULL && (argv != NULL || argc == 0) && context != NULL && JS_IsInRequest(context));
	
	JSObject				*root = NULL;
	BOOL					OK = NO;
	jsval					method;
	jsval					ignoredResult = JSVAL_VOID;
	
	if (outResult == NULL)  outResult = &ignoredResult;
	OOJSAddGCObjectRoot(context, &root, "OOJSScript method root");
	
	if (EXPECT(OOJSGetMethod(context, _jsSelf, methodID, &root, &method) && !JSVAL_IS_VOID(method)))
	{
#ifndef NDEBUG
		OOLog(@"script.trace.javaScript", @"Calling [%@].%@()", [self name], OOStringFromJSPropID(methodID));
		OOLogIndentIf(@"script.trace.javaScript");
#endif
		
		// Push self on stack of running scripts.
		RunningStack stackElement =
		{
			.back = sRunningStack,
			.current = self
		};
		sRunningStack = &stackElement;
		
		// Call the method.
		OOJSStartTimeLimiter();
		OK = JS_CallFunctionValue(context, _jsSelf, method, argc, argv, outResult);
		OOJSStopTimeLimiter();
		
		// Pop running scripts stack
		sRunningStack = stackElement.back;
		
#if !OO_NEW_JS
		JS_ClearNewbornRoots(context);
#endif
		
#ifndef NDEBUG
		OOLogOutdentIf(@"script.trace.javaScript");
#endif
	}
	
	JS_RemoveObjectRoot(context, &root);
	
	return OK;
}


- (id) propertyWithID:(OOJSPropID)propID inContext:(JSContext *)context
{
	NSParameterAssert(context != NULL && JS_IsInRequest(context));
	
	jsval jsValue = JSVAL_VOID;
	if (OOJSGetProperty(context, _jsSelf, propID, &jsValue))
	{
		return OOJSNativeObjectFromJSValue(context, jsValue);
	}
	return nil;
}


- (BOOL) setProperty:(id)value withID:(OOJSPropID)propID inContext:(JSContext *)context
{
	NSParameterAssert(context != NULL && JS_IsInRequest(context));
	
	jsval jsValue = OOJSValueFromNativeObject(context, value);
	return OOJSSetProperty(context, _jsSelf, propID, &jsValue);
}


- (BOOL) defineProperty:(id)value withID:(OOJSPropID)propID inContext:(JSContext *)context
{
	NSParameterAssert(context != NULL && JS_IsInRequest(context));
	
	jsval jsValue = OOJSValueFromNativeObject(context, value);
	return OOJSDefineProperty(context, _jsSelf, propID, jsValue, NULL, NULL, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
}


- (id) propertyNamed:(NSString *)propName
{
	if (propName == nil)  return nil;
	
	JSContext *context = OOJSAcquireContext();
	id result = [self propertyWithID:OOJSPropIDFromString(propName) inContext:context];
	OOJSRelinquishContext(context);
	
	return result;
}


- (BOOL) setProperty:(id)value named:(NSString *)propName
{
	if (value == nil || propName == nil)  return NO;
	
	JSContext *context = OOJSAcquireContext();
	BOOL result = [self setProperty:value withID:OOJSPropIDFromString(propName) inContext:context];
	OOJSRelinquishContext(context);
	
	return result;
}


- (BOOL) defineProperty:(id)value named:(NSString *)propName
{
	if (value == nil || propName == nil)  return NO;
	
	JSContext *context = OOJSAcquireContext();
	BOOL result = [self defineProperty:value withID:OOJSPropIDFromString(propName) inContext:context];
	OOJSRelinquishContext(context);
	
	return result;
}


- (jsval)oo_jsValueInContext:(JSContext *)context
{
	return OBJECT_TO_JSVAL(_jsSelf);
}


+ (void)pushScript:(OOJSScript *)script
{
	RunningStack			*element = NULL;
	
	element = malloc(sizeof *element);
	if (element == NULL)  exit(EXIT_FAILURE);
	
	element->back = sRunningStack;
	element->current = script;
	sRunningStack = element;
}


+ (void)popScript:(OOJSScript *)script
{
	RunningStack			*element = NULL;
	
	assert(sRunningStack->current == script);
	
	element = sRunningStack;
	sRunningStack = sRunningStack->back;
	free(element);
}

@end


@implementation OOJSScript (OOPrivate)



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
	
	return StrippedName([theName stringByAppendingString:@".anon-script"]);
}

@end


@implementation OOScript (JavaScriptEvents)

- (BOOL) callMethod:(OOJSPropID)methodID
		  inContext:(JSContext *)context
	  withArguments:(jsval *)argv count:(intN)argc
			 result:(jsval *)outResult
{
	return NO;
}

@end


void InitOOJSScript(JSContext *context, JSObject *global)
{
	sScriptPrototype = JS_InitClass(context, global, NULL, &sScriptClass, OOJSUnconstructableConstruct, 0, NULL, sScriptMethods, NULL, NULL);
	OOJSRegisterObjectConverter(&sScriptClass, OOJSBasicPrivateObjectConverter);
}


static void AddStackToArrayReversed(NSMutableArray *array, RunningStack *stack)
{
	if (stack != NULL)
	{
		AddStackToArrayReversed(array, stack->back);
		[array addObject:stack->current];
	}
}


static JSScript *LoadScriptWithName(JSContext *context, NSString *path, JSObject *object, JSObject **outScriptObject, NSString **outErrorMessage)
{
#if OO_CACHE_JS_SCRIPTS
	OOCacheManager				*cache = nil;
#endif
	NSString					*fileContents = nil;
	NSData						*data = nil;
	JSScript					*script = NULL;
	
	NSCParameterAssert(outScriptObject != NULL && outErrorMessage != NULL);
	*outErrorMessage = nil;
	
#if OO_CACHE_JS_SCRIPTS
	// Look for cached compiled script
	cache = [OOCacheManager sharedCache];
	data = [cache objectForKey:path inCache:@"compiled JavaScript scripts"];
	if (data != nil)
	{
		script = ScriptWithCompiledData(context, data);
	}
#endif
	
	if (script == NULL)
	{
		fileContents = [NSString stringWithContentsOfUnicodeFile:path];
		if (fileContents != nil)  data = [fileContents utf16DataWithBOM:NO];
		if (data == nil)  *outErrorMessage = @"could not load file";
		else
		{
			script = JS_CompileUCScript(context, object, [data bytes], [data length] / sizeof(unichar), [path UTF8String], 1);
#if OO_NEW_JS
			if (script != NULL)  *outScriptObject = JS_NewScriptObject(context, script);
#endif
			if (script == NULL)  *outErrorMessage = @"compilation failed";
		}
		
#if OO_CACHE_JS_SCRIPTS
		if (script != NULL)
		{
			// Write compiled script to cache
			data = CompiledScriptData(context, script);
			[cache setObject:data forKey:path inCache:@"compiled JavaScript scripts"];
		}
#endif
	}
	
	return script;
}


#if OO_CACHE_JS_SCRIPTS
static NSData *CompiledScriptData(JSContext *context, JSScript *script)
{
	JSXDRState					*xdr = NULL;
	NSData						*result = nil;
	uint32						length;
	void						*bytes = NULL;
	
	xdr = JS_XDRNewMem(context, JSXDR_ENCODE);
	if (xdr != NULL)
	{
		if (JS_XDRScript(xdr, &script))
		{
			bytes = JS_XDRMemGetData(xdr, &length);
			if (bytes != NULL)
			{
				result = [NSData dataWithBytes:bytes length:length];
			}
		}
		JS_XDRDestroy(xdr);
	}
	
	return result;
}


static JSScript *ScriptWithCompiledData(JSContext *context, NSData *data)
{
	JSXDRState					*xdr = NULL;
	JSScript					*result = NULL;
	
	if (data == nil)  return NULL;
	
	xdr = JS_XDRNewMem(context, JSXDR_DECODE);
	if (xdr != NULL)
	{
		JS_XDRMemSetData(xdr, (void *)[data bytes], [data length]);
		if (!JS_XDRScript(xdr, &result))  result = NULL;
		
		JS_XDRMemSetData(xdr, NULL, 0);	// Don't let it be freed by XDRDestroy
		JS_XDRDestroy(xdr);
	}
	
	return result;
}
#endif


static NSString *StrippedName(NSString *string)
{
	static NSCharacterSet *invalidSet = nil;
	if (invalidSet == nil)  invalidSet = [[NSCharacterSet characterSetWithCharactersInString:@"_ \t\n\r\v"] retain];
	
	return [string stringByTrimmingCharactersInSet:invalidSet];
}
