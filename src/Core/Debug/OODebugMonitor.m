/*

OODebugMonitor.m


Oolite debug support

Copyright (C) 2007-2012 Jens Ayton

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

#ifndef OO_EXCLUDE_DEBUG_SUPPORT


#import "OODebugMonitor.h"
#import "OOCollectionExtractors.h"
#import "OOLoggingExtended.h"
#import "ResourceManager.h"
#import "NSStringOOExtensions.h"

#import "OOJSConsole.h"
#import "OOJSScript.h"
#import "OOJSEngineTimeManagement.h"
#import "OOJSSpecialFunctions.h"

#import "NSObjectOOExtensions.h"
#import "OOTexture.h"
#import "OOConcreteTexture.h"
#import "OODrawable.h"


static OODebugMonitor *sSingleton = nil;


@interface OODebugMonitor (Private) <OOJavaScriptEngineMonitor>

- (void) setUpDebugConsoleScript;
- (void) javaScriptEngineWillReset:(NSNotification *)notification;

- (void)disconnectDebuggerWithMessage:(NSString *)message;

- (NSDictionary *)mergedConfiguration;

/*	Convert a configuration dictionary to a standard form. In particular,
	convert all colour specifiers to RGBA arrays with values in [0, 1], and
	converts "show-console" values to booleans.
*/
- (NSMutableDictionary *)normalizeConfigDictionary:(NSDictionary *)dictionary;
- (id)normalizeConfigValue:(id)value forKey:(NSString *)key;

- (NSArray *)loadSourceFile:(NSString *)filePath;

@end


@implementation OODebugMonitor
#if OOLITE_GNUSTEP
	NSString					*NSApplicationWillTerminateNotification = @"ApplicationWillTerminate";
#endif

- (id)init
{
	NSUserDefaults				*defaults = nil;
	NSMutableDictionary			*config = nil;
	
	self = [super init];
	if (self != nil)
	{
		config = [[[ResourceManager dictionaryFromFilesNamed:@"debugConfig.plist"
													inFolder:@"Config"
													andMerge:YES] mutableCopy] autorelease];
		_configFromOXPs = [[self normalizeConfigDictionary:config] copy];
		
		defaults = [NSUserDefaults standardUserDefaults];
		config = [self normalizeConfigDictionary:[defaults dictionaryForKey:@"debug-settings-override"]];
		if (config == nil)  config = [NSMutableDictionary dictionary];
		_configOverrides = [config retain];
		
		_TCPIgnoresDroppedPackets = NO;
		
		OOJavaScriptEngine *jsEng = [OOJavaScriptEngine sharedEngine];
#if OOJSENGINE_MONITOR_SUPPORT
		[jsEng setMonitor:self];
#endif
		
		[self setUpDebugConsoleScript];
		
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(applicationWillTerminate:)
													 name:NSApplicationWillTerminateNotification
												   object:nil];
		
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(javaScriptEngineWillReset:)
													 name:kOOJavaScriptEngineWillResetNotification
												   object:jsEng];
		
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(setUpDebugConsoleScript)
													 name:kOOJavaScriptEngineDidResetNotification
												   object:jsEng];
	}
	
	return self;
}


- (void)dealloc
{
	[self disconnectDebuggerWithMessage:@"Debug controller object destroyed while debugging in progress."];
	
	[_configFromOXPs release];
	[_configOverrides release];
	
	[_fgColors release];
	[_bgColors release];
	[_sourceFiles release];
	
	if (_jsSelf != NULL)
	{
		[[OOJavaScriptEngine sharedEngine] removeGCObjectRoot:&_jsSelf];
	}
	
	[super dealloc];
}


+ (OODebugMonitor *) sharedDebugMonitor
{
	// NOTE: assumes single-threaded access. The debug monitor is not, on the whole, thread safe.
	if (sSingleton == nil)
	{
		sSingleton = [[self alloc] init];
	}
	
	return sSingleton;
}


- (BOOL)setDebugger:(id<OODebuggerInterface>)newDebugger
{
	NSString					*error = nil;
	
	if (newDebugger != _debugger)
	{
		// Disconnect existing debugger, if any.
		if (newDebugger != nil)
		{
			[self disconnectDebuggerWithMessage:@"New debugger set."];
		}
		else
		{
			[self disconnectDebuggerWithMessage:@"Debugger disconnected programatically."];
		}
		
		// If a new debugger was specified, try to connect it.
		if (newDebugger != nil)
		{
			NS_DURING
				if ([newDebugger connectDebugMonitor:self errorMessage:&error])
				{
					[newDebugger debugMonitor:self
							noteConfiguration:[self mergedConfiguration]];
					_debugger = [newDebugger retain];
				}
				else
				{
					OOLog(@"debugMonitor.setDebugger.failed", @"Could not connect to debugger %@, because an error occurred: %@", newDebugger, error);
				}
			NS_HANDLER
				OOLog(@"debugMonitor.setDebugger.failed", @"Could not connect to debugger %@, because an exception occurred: %@ -- %@", newDebugger, [localException name], [localException reason]);
			NS_ENDHANDLER
		}
	}
	
	return _debugger == newDebugger;
}


- (oneway void)performJSConsoleCommand:(in NSString *)command
{
	JSContext *context = OOJSAcquireContext();
	jsval commandVal = OOJSValueFromNativeObject(context, command);
	OOJSStartTimeLimiterWithTimeLimit(kOOJSLongTimeLimit);
	[_script callMethod:OOJSID("consolePerformJSCommand") inContext:context withArguments:&commandVal count:1 result:NULL];
	OOJSStopTimeLimiter();
	OOJSRelinquishContext(context);
}


- (void)appendJSConsoleLine:(id)string
				   colorKey:(NSString *)colorKey
			  emphasisRange:(NSRange)emphasisRange
{
	if (string == nil)  return;
	OOJSPauseTimeLimiter();
	NS_DURING
		[_debugger debugMonitor:self
				jsConsoleOutput:string
					   colorKey:colorKey
				  emphasisRange:emphasisRange];
	NS_HANDLER
		OOLog(@"debugMonitor.debuggerConnection.exception", @"Exception while attempting to send JavaScript console text to debugger: %@ -- %@", [localException name], [localException reason]);
	NS_ENDHANDLER
	OOJSResumeTimeLimiter();
}


- (void)appendJSConsoleLine:(id)string
				   colorKey:(NSString *)colorKey
{
	[self appendJSConsoleLine:string
					 colorKey:colorKey
				emphasisRange:NSMakeRange(0, 0)];
}


- (void)clearJSConsole
{
	OOJSPauseTimeLimiter();
	NS_DURING
		[_debugger debugMonitorClearConsole:self];
	NS_HANDLER
		OOLog(@"debugMonitor.debuggerConnection.exception", @"Exception while attempting to clear JavaScript console: %@ -- %@", [localException name], [localException reason]);
	NS_ENDHANDLER
	OOJSResumeTimeLimiter();
}


- (void)showJSConsole
{
	OOJSPauseTimeLimiter();
	NS_DURING
		[_debugger debugMonitorShowConsole:self];
	NS_HANDLER
		OOLog(@"debugMonitor.debuggerConnection.exception", @"Exception while attempting to show JavaScript console: %@ -- %@", [localException name], [localException reason]);
	NS_ENDHANDLER
	OOJSResumeTimeLimiter();
}


- (id)configurationValueForKey:(in NSString *)key
{
	return [self configurationValueForKey:key class:Nil defaultValue:nil];
}


- (id)configurationValueForKey:(NSString *)key class:(Class)class defaultValue:(id)value
{
	id							result = nil;
	
	if (class == Nil)  class = [NSObject class];
	
	result = [_configOverrides objectForKey:key];
	if (![result isKindOfClass:class] && result != [NSNull null])  result = [_configFromOXPs objectForKey:key];
	if (![result isKindOfClass:class] && result != [NSNull null])  result = [[value retain] autorelease];
	if (result == [NSNull null])  result = nil;
	
	return result;
}


- (long long)configurationIntValueForKey:(NSString *)key defaultValue:(long long)value
{
	long long					result;
	id							object = nil;
	
	object = [self configurationValueForKey:key];
	if ([object respondsToSelector:@selector(longLongValue)])  result = [object longLongValue];
	else if ([object respondsToSelector:@selector(intValue)])  result = [object intValue];
	else  result = value;
	
	return result;
}


- (void)setConfigurationValue:(in id)value forKey:(in NSString *)key
{
	if (key == nil)  return;
	
	value = [self normalizeConfigValue:value forKey:key];
	
	if (value == nil)
	{
		[_configOverrides removeObjectForKey:key];
	}
	else
	{
		if (_configOverrides == nil)  _configOverrides = [[NSMutableDictionary alloc] init];
		[_configOverrides setObject:value forKey:key];
	}
	
	// Send changed value to debugger
	if (value == nil)
	{
		// Setting a nil value removes an override, and may reveal an underlying OXP-defined value
		value = [self configurationValueForKey:key];
	}
	NS_DURING
		[_debugger debugMonitor:self
   noteChangedConfigrationValue:value
						 forKey:key];
	NS_HANDLER
		OOLog(@"debugMonitor.debuggerConnection.exception", @"Exception while attempting to send configuration update to debugger: %@ -- %@", [localException name], [localException reason]);
	NS_ENDHANDLER
}


- (NSArray *)configurationKeys
{
	NSMutableSet				*result = nil;
	
	result = [NSMutableSet setWithCapacity:[_configFromOXPs count] + [_configOverrides count]];
	[result addObjectsFromArray:[_configFromOXPs allKeys]];
	[result addObjectsFromArray:[_configOverrides allKeys]];
	
	return [[result allObjects] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
}


- (BOOL) debuggerConnected
{
	return _debugger != nil;
}


- (void) writeMemStat:(NSString *)format, ...
{
	va_list args;
	va_start(args, format);
	NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	
	OOLog(@"debug.memStats", @"%@", message);
	[self appendJSConsoleLine:message colorKey:@"command-result"];
	
	[message release];
}


static NSString *SizeString(size_t size)
{
	enum
	{
		kThreshold = 2	// 2 KiB, 2 MiB etc.
	};
	
	unsigned magnitude = 0;
	NSString *suffix = @"";
	
	if (size < kThreshold << 10)
	{
		return [NSString stringWithFormat:@"%zu bytes", size];
	}
	if (size < kThreshold << 20)
	{
		magnitude = 1;
		suffix = @"KiB";
	}
	else if (size < (size_t)(kThreshold << 30))
	{
		magnitude = 2;
		suffix = @"MiB";
	}
	else
	{
		magnitude = 3;
		suffix = @"GiB";
	}
	
	float unit = 1 << (magnitude * 10);
	float sizef = (float)size / unit;
	sizef = round(sizef * 100.0f) / 100.f;
	
	return [NSString stringWithFormat:@"%.2f %@", sizef, suffix];
}


typedef struct
{
	NSMutableSet		*entityTextures;
	NSMutableSet		*visibleEntityTextures;
	NSMutableSet		*seenEntities;
	unsigned			seenCount;
	size_t				totalEntityObjSize;
	size_t				totalDrawableSize;
} EntityDumpState;


- (void) dumpEntity:(id)entity withState:(EntityDumpState *)state parentVisible:(BOOL)parentVisible
{
	if ([state->seenEntities containsObject:entity] || entity == nil)  return;
	[state->seenEntities addObject:entity];
	
	state->seenCount++;
	
	size_t entitySize = [entity oo_objectSize];
	size_t drawableSize = 0;
	if ([entity isKindOfClass:[OOEntityWithDrawable class]])
	{
		OODrawable *drawable = [entity drawable];
		drawableSize = [drawable totalSize];
	}
	
	BOOL visible = parentVisible && [entity isVisible];
	
	NSSet *textures = [entity allTextures];
	if (textures != nil)
	{
		[state->entityTextures unionSet:textures];
		if (visible)  [state->visibleEntityTextures unionSet:textures];
	}
	
	NSString *extra = @"";
	if (visible)
	{
		extra = [extra stringByAppendingString:@", visible"];
	}
	
	if (drawableSize != 0)
	{
		extra = [extra stringByAppendingFormat:@", drawable: %@", SizeString(drawableSize)];
	}
	
	[self writeMemStat:@"%@: %@%@", [entity shortDescription], SizeString(entitySize), extra];
	
	state->totalEntityObjSize += entitySize;
	state->totalDrawableSize += drawableSize;
	
	OOLogIndent();
	if ([entity isShip])
	{
		NSEnumerator *subEnum = nil;
		id subentity = nil;
		for (subEnum = [entity subEntityEnumerator]; (subentity = [subEnum nextObject]); )
		{
			[self dumpEntity:subentity withState:state parentVisible:visible];
		}
		
		if ([entity isPlayer])
		{
			unsigned i, count = [entity dialMaxMissiles];
			for (i = 0; i < count; i++)
			{
				subentity = [entity missileForPylon:i];
				if (subentity != nil)  [self dumpEntity:subentity withState:state parentVisible:NO];
			}
		}
	}
	if ([entity isPlanet])
	{
#if NEW_PLANETS
		// FIXME: dump atmosphere texture.
#else
		PlanetEntity *atmosphere = [entity atmosphere];
		if (atmosphere != nil)
		{
			[self dumpEntity:atmosphere withState:state parentVisible:visible];
		}
#endif
	}
	if ([entity isWormhole])
	{
		NSEnumerator *shipEnum = nil;
		NSDictionary *shipInfo = nil;
		for (shipEnum = [[entity shipsInTransit] objectEnumerator]; (shipInfo = [shipEnum nextObject]); )
		{
			ShipEntity *ship = [shipInfo objectForKey:@"ship"];
			[self dumpEntity:ship withState:state parentVisible:NO];
		}
	}
	OOLogOutdent();
}


- (void) dumpMemoryStatistics
{
	OOLog(@"debug.memStats", @"Memory statistics:");
	OOLogIndent();
	
	//	Get texture retain counts before the entity dumper starts messing with them.
	NSSet *allTextures = [OOTexture allTextures];
	NSMutableDictionary *textureRefCounts = [NSMutableDictionary dictionaryWithCapacity:[allTextures count]];
	
	OOTexture *tex = nil;
	NSEnumerator *texEnum = nil;
	for (texEnum = [allTextures objectEnumerator]; (tex = [texEnum nextObject]); )
	{
		// We subtract one because allTextures retains the textures.
		[textureRefCounts setObject:[NSNumber numberWithUnsignedInt:[tex retainCount] - 1] forKey:[NSValue valueWithNonretainedObject:tex]];
	}
	
	size_t totalSize = 0;
	
	[self writeMemStat:@"Entitites:"];
	OOLogIndent();
	
	NSArray *entities = [UNIVERSE entityList];
	EntityDumpState entityDumpState =
	{
		.entityTextures = [NSMutableSet set],
		.visibleEntityTextures = [NSMutableSet set],
		.seenEntities = [NSMutableSet set]
	};
	
	id entity = nil;
	NSEnumerator *entityEnum = nil;
	for (entityEnum = [entities objectEnumerator]; (entity = [entityEnum nextObject]); )
	{
		[self dumpEntity:entity withState:&entityDumpState parentVisible:YES];
	}
	for (entityEnum = [[PLAYER scannedWormholes] objectEnumerator]; (entity = [entityEnum nextObject]); )
	{
		[self dumpEntity:entity withState:&entityDumpState parentVisible:YES];
	}
	
	OOLogOutdent();
	[self writeMemStat:@"Total entity size (excluding %u entities not accounted for): %@ (%@ entity objects, %@ drawables)",
	 gLiveEntityCount - entityDumpState.seenCount,
	 SizeString(entityDumpState.totalEntityObjSize + entityDumpState.totalDrawableSize),
	 SizeString(entityDumpState.totalEntityObjSize),
	 SizeString(entityDumpState.totalDrawableSize)];
	totalSize += entityDumpState.totalEntityObjSize + entityDumpState.totalDrawableSize;
	
	/*	Sort textures so that textures in the "recent cache" come first by age,
		followed by others.
	*/
	NSMutableArray *textures = [[[OOTexture cachedTexturesByAge] mutableCopy] autorelease];
	
	for (texEnum = [allTextures objectEnumerator]; (tex = [texEnum nextObject]); )
	{
		if ([textures indexOfObject:tex] == NSNotFound)
		{
			[textures addObject:tex];
		}
	}
	
	size_t totalTextureObjSize = 0;
	size_t totalTextureDataSize = 0;
	size_t visibleTextureDataSize = 0;
	
	[self writeMemStat:@"Textures:"];
	OOLogIndent();
	
	for (texEnum = [textures objectEnumerator]; (tex = [texEnum nextObject]); )
	{
		size_t objSize = [tex oo_objectSize];
		size_t dataSize = [tex dataSize];
		
#if OOTEXTURE_RELOADABLE
		NSString *byteCountSuffix = @"";
#else
		NSString *byteCountSuffix = @" (* 2)";
#endif
		
		NSString *usage = @"";
		if ([entityDumpState.visibleEntityTextures containsObject:tex])
		{
			visibleTextureDataSize += dataSize;	// NOT doubled if !OOTEXTURE_RELOADABLE, because we're interested in what the GPU sees.
			usage = @", visible";
		}
		else if ([entityDumpState.entityTextures containsObject:tex])
		{
			usage = @", active";
		}
		
		unsigned refCount = [textureRefCounts oo_unsignedIntForKey:[NSValue valueWithNonretainedObject:tex]];
		
		[self writeMemStat:@"%@: [%u refs%@] %@%@",
		 [tex name],
		 refCount,
		 usage,
		 SizeString(objSize + dataSize),
		 byteCountSuffix];
		
		totalTextureDataSize += dataSize;
		totalTextureObjSize += objSize;
	}
	totalSize += totalTextureObjSize + totalTextureDataSize;
	
	OOLogOutdent();
	
#if !OOTEXTURE_RELOADABLE
	totalTextureDataSize *= 2;
#endif
	[self writeMemStat:@"Total texture size: %@ (%@ object overhead, %@ data, %@ visible texture data)",
	 SizeString(totalTextureObjSize + totalTextureDataSize),
	 SizeString(totalTextureObjSize),
	 SizeString(totalTextureDataSize),
	 SizeString(visibleTextureDataSize)];
	
	JSContext *context = OOJSAcquireContext();
	
	JSRuntime *runtime = JS_GetRuntime(context);
	size_t jsSize = JS_GetGCParameter(runtime, JSGC_BYTES);
	size_t jsMax = JS_GetGCParameter(runtime, JSGC_MAX_BYTES);
	uint32_t jsGCCount = JS_GetGCParameter(runtime, JSGC_NUMBER);
	
	OOJSRelinquishContext(context);
	
	[self writeMemStat:@"JavaScript heap: %@ (limit %@, %u collections to date)", SizeString(jsSize), SizeString(jsMax), jsGCCount];
	totalSize += jsSize;
	
	[self writeMemStat:@"Total: %@", SizeString(totalSize)];
	
	OOLogOutdent();
}


- (void) setTCPIgnoresDroppedPackets:(BOOL)flag
{
	if (_TCPIgnoresDroppedPackets != flag)
	{
		OOLog(@"debugMonitor.TCPSettings", @"The TCP console will %@ TCP packets.",
				(flag ? @"try to stay connected, ignoring dropped" : @"disconnect if an error affects"));
	}
	_TCPIgnoresDroppedPackets = flag;
}


- (BOOL) TCPIgnoresDroppedPackets
{
	return _TCPIgnoresDroppedPackets;
}


- (void) setUsingPlugInController:(BOOL)flag
{
	_usingPlugInController = flag;
}


- (BOOL) usingPlugInController
{
	return _usingPlugInController;
}


- (NSString *)sourceCodeForFile:(in NSString *)filePath line:(in unsigned)line
{
	id							linesForFile = nil;
	
	linesForFile = [_sourceFiles objectForKey:filePath];
	
	if (linesForFile == nil)
	{
		linesForFile = [self loadSourceFile:filePath];
		if (linesForFile == nil)  linesForFile = [NSArray arrayWithObject:[NSString stringWithFormat:@"<Can't load file %@>", filePath]];
		
		if (_sourceFiles == nil)  _sourceFiles = [[NSMutableDictionary alloc] init];
		[_sourceFiles setObject:linesForFile forKey:filePath];
	}
	
	if ([linesForFile count] < line || line == 0)  return @"<line out of range!>";
	
	return [linesForFile objectAtIndex:line - 1];
}


- (void)disconnectDebugger:(in id<OODebuggerInterface>)debugger
				   message:(in NSString *)message
{
	if (debugger == nil)  return;
		
	if (debugger == _debugger)
	{
		[self disconnectDebuggerWithMessage:message];
	}
	else
	{
		OOLog(@"debugMonitor.disconnect.ignored", @"Attempt to disconnect debugger %@, which is not current debugger; ignoring.", debugger);
	}
}


#if OOLITE_GNUSTEP
- (void) applicationWillTerminate
{
	[[NSNotificationCenter defaultCenter] postNotificationName:NSApplicationWillTerminateNotification object:nil];
}
#endif


- (void)applicationWillTerminate:(NSNotification *)notification
{
	if (_configOverrides != nil)
	{
		[[NSUserDefaults standardUserDefaults] setObject:_configOverrides forKey:@"debug-settings-override"];
	}
	
	[self disconnectDebuggerWithMessage:@"Oolite is terminating."];
}


@end


@implementation OODebugMonitor (Private)

- (void) setUpDebugConsoleScript
{
	JSContext *context = OOJSAcquireContext();
	/*	The path to the console script is saved in this here static variable
		so that we can reload it when resetting into strict mode.
		-- Ahruman 2011-02-06
	*/
	static NSString *path = nil;
	
	if (path == nil)
	{
		path = [[ResourceManager pathForFileNamed:@"oolite-debug-console.js" inFolder:@"Scripts"] retain];
	}
	if (path != nil)
	{
		NSDictionary *jsProps = [NSDictionary dictionaryWithObjectsAndKeys:
								 self, @"console",
								 JSSpecialFunctionsObjectWrapper(context), @"special",
								 nil];
		_script = [[OOJSScript scriptWithPath:path properties:jsProps] retain];
	}
	
	// If no script, just make console visible globally as debugConsole.
	if (_script == nil)
	{
		JSObject *global = [[OOJavaScriptEngine sharedEngine] globalObject];
		JS_DefineProperty(context, global, "debugConsole", [self oo_jsValueInContext:context], NULL, NULL, JSPROP_ENUMERATE);
	}
	
	OOJSRelinquishContext(context);
}


- (void) javaScriptEngineWillReset:(NSNotification *)notification
{
	DESTROY(_script);
	_jsSelf = NULL;
	
	OOJSConsoleDestroy();
}


- (void)disconnectDebuggerWithMessage:(NSString *)message
{
	NS_DURING
		[_debugger disconnectDebugMonitor:self message:message];
	NS_HANDLER
		OOLog(@"debugMonitor.debuggerConnection.exception", @"Exception while attempting to disconnect debugger: %@ -- %@", [localException name], [localException reason]);
	NS_ENDHANDLER
	
	id debugger = _debugger;
	_debugger = nil;
	[debugger release];
}


- (NSDictionary *)mergedConfiguration
{
	NSMutableDictionary			*result = nil;
	
	result = [NSMutableDictionary dictionary];
	if (_configFromOXPs != nil)  [result addEntriesFromDictionary:_configFromOXPs];
	if (_configOverrides != nil)  [result addEntriesFromDictionary:_configOverrides];
	
	return result;
}


- (NSArray *)loadSourceFile:(NSString *)filePath
{
	NSString					*contents = nil;
	NSArray						*lines = nil;
	
	if (filePath == nil)  return nil;
	
	contents = [NSString stringWithContentsOfUnicodeFile:filePath];
	if (contents == nil)  return nil;
	
	/*	Extract lines from file.
FIXME: this works with CRLF and LF, but not CR.
		*/
	lines = [contents componentsSeparatedByString:@"\n"];
	return lines;
}


- (NSMutableDictionary *)normalizeConfigDictionary:(NSDictionary *)dictionary
{
	NSMutableDictionary		*result = nil;
	NSEnumerator			*keyEnum = nil;
	NSString				*key = nil;
	id						value = nil;
	
	result = [NSMutableDictionary dictionaryWithCapacity:[dictionary count]];
	for (keyEnum = [dictionary keyEnumerator]; (key = [keyEnum nextObject]); )
	{
		value = [dictionary objectForKey:key];
		value = [self normalizeConfigValue:value forKey:key];
		
		if (key != nil && value != nil)  [result setObject:value forKey:key];
	}
	
	return result;
}


- (id)normalizeConfigValue:(id)value forKey:(NSString *)key
{
	OOColor					*color = nil;
	BOOL					boolValue;
	
	if (value != nil)
	{
		if ([key hasSuffix:@"-color"] || [key hasSuffix:@"-colour"])
		{
			color = [OOColor colorWithDescription:value];
			value = [color normalizedArray];
		}
		else if ([key hasPrefix:@"show-console"])
		{
			boolValue = OOBooleanFromObject(value, NO);
			value = [NSNumber numberWithBool:boolValue];
		}
	}
	
	return value;
}


- (oneway void)jsEngine:(in byref OOJavaScriptEngine *)engine
				context:(in JSContext *)context
				  error:(in JSErrorReport *)errorReport
			  stackSkip:(in unsigned)stackSkip
		showingLocation:(in BOOL)showLocation
			withMessage:(in NSString *)message
{
	NSString					*colorKey = nil;
	NSString					*prefix = nil;
	NSString					*filePath = nil;
	NSString					*sourceLine = nil;
	NSString					*scriptLine = nil;
	NSMutableString				*formattedMessage = nil;
	NSRange						emphasisRange;
	NSString					*showKey = nil;
	
	if (_debugger == nil)  return;
	
	if (errorReport->flags & JSREPORT_WARNING)
	{
		colorKey = @"warning";
		prefix = @"Warning";
	}
	else if (errorReport->flags & JSREPORT_EXCEPTION)
	{
		colorKey = @"exception";
		prefix = @"Exception";
	}
	else
	{
		colorKey = @"error";
		prefix = @"Error";
	}
	
	if (errorReport->flags & JSREPORT_STRICT)
	{
		prefix = [prefix stringByAppendingString:@" (strict mode)"];
	}
	
	// Prefix and subsequent colon should be bold:
	emphasisRange = NSMakeRange(0, [prefix length] + 1);
	
	formattedMessage = [NSMutableString stringWithFormat:@"%@: %@", prefix, message];
	
	// Note that the "active script" isn't necessarily the one causing the
	// error, since one script can call another's methods.
	
	// avoid windows DEP exceptions!
	OOJSScript *thisScript = [[OOJSScript currentlyRunningScript] weakRetain];
	scriptLine = [[thisScript weakRefUnderlyingObject] displayName];
	[thisScript release];
	
	if (scriptLine != nil)
	{
		[formattedMessage appendFormat:@"\n    Active script: %@", scriptLine];
	}
	
	if (showLocation && stackSkip == 0)
	{
		// Append file name and line
		if (errorReport->filename != NULL)  filePath = [NSString stringWithUTF8String:errorReport->filename];
		if ([filePath length] != 0)
		{
			[formattedMessage appendFormat:@"\n    %@, line %u", [filePath lastPathComponent], errorReport->lineno];
			
			// Append source code
			sourceLine = [self sourceCodeForFile:filePath line:errorReport->lineno];
			if (sourceLine != nil)
			{
				[formattedMessage appendFormat:@":\n    %@", sourceLine];
			}
		}
	}
	
	[self appendJSConsoleLine:formattedMessage
					 colorKey:colorKey
				emphasisRange:emphasisRange];
	
	if (errorReport->flags & JSREPORT_WARNING)  showKey = @"show-console-on-warning";
	else  showKey = @"show-console-on-error";	// if not a warning, it's a proper error.
	if (OOBooleanFromObject([self configurationValueForKey:showKey], NO))
	{
		[self showJSConsole];
	}
}


- (oneway void)jsEngine:(in byref OOJavaScriptEngine *)engine
				context:(in JSContext *)context
			 logMessage:(in NSString *)message
				ofClass:(in NSString *)messageClass
{
	[self appendJSConsoleLine:message colorKey:@"log"];
	if (OOBooleanFromObject([self configurationValueForKey:@"show-console-on-log"], NO))
	{
		[self showJSConsole];
	}
}


- (jsval)oo_jsValueInContext:(JSContext *)context
{
	if (_jsSelf == NULL)
	{
		_jsSelf = DebugMonitorToJSConsole(context, self);
		if (_jsSelf != NULL)
		{
			if (!OOJSAddGCObjectRoot(context, &_jsSelf, "debug console"))
			{
				_jsSelf = NULL;
			}
		}
	}
	
	if (_jsSelf != NULL)  return OBJECT_TO_JSVAL(_jsSelf);
	else  return JSVAL_NULL;
}

@end


@implementation OODebugMonitor (Singleton)

/*	Canonical singleton boilerplate.
See Cocoa Fundamentals Guide: Creating a Singleton Instance.
See also +sharedDebugMonitor above.

NOTE: assumes single-threaded access.
*/

+ (id)allocWithZone:(NSZone *)inZone
{
	if (sSingleton == nil)
	{
		sSingleton = [super allocWithZone:inZone];
		return sSingleton;
	}
	return nil;
}


- (id)copyWithZone:(NSZone *)inZone
{
	return self;
}


- (id)retain
{
	return self;
}


- (OOUInteger)retainCount
{
	return UINT_MAX;
}


- (void)release
{}


- (id)autorelease
{
	return self;
}

@end

#endif /* OO_EXCLUDE_DEBUG_SUPPORT */
