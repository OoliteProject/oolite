/*

OODebugMonitor.m


Oolite Debug OXP

Copyright (C) 2007 Jens Ayton

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
#import "OOLogging.h"
#import "ResourceManager.h"
#import "NSStringOOExtensions.h"

#import "OOJSConsole.h"
#import "OOScript.h"
#import "OOJSScript.h"
#import "OOJavaScriptEngine.h"
#import "OOJSSpecialFunctions.h"


static OODebugMonitor *sSingleton = nil;


@interface OODebugMonitor (Private) <OOJavaScriptEngineMonitor>

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

- (id)init
{
	NSUserDefaults				*defaults = nil;
	NSDictionary				*jsProps = nil;
	NSDictionary				*config = nil;
#if OOLITE_GNUSTEP
	NSString					*NSApplicationWillTerminateNotification = @"ApplicationWillTerminate";
#endif
	
	self = [super init];
	if (self != nil)
	{
		config = [[[ResourceManager dictionaryFromFilesNamed:@"debugConfig.plist"
													inFolder:@"Config"
													andMerge:YES] mutableCopy] autorelease];
		_configFromOXPs = [[self normalizeConfigDictionary:config] copy];
		
		defaults = [NSUserDefaults standardUserDefaults];
		config = [defaults dictionaryForKey:@"debug-settings-override"];
		config = [self normalizeConfigDictionary:config];
		if (config == nil)  config = [NSMutableDictionary dictionary];
		_configOverrides = [config retain];
		
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:) name:NSApplicationWillTerminateNotification object:nil];
		
#if OOJSENGINE_MONITOR_SUPPORT
		[[OOJavaScriptEngine sharedEngine] setMonitor:self];
#endif
		
		// Set up JavaScript side of console.
		jsProps = [NSDictionary dictionaryWithObjectsAndKeys:
								self, @"console",
								JSSpecialFunctionsObjectWrapper(NULL), @"special",
								nil];
		_script = [[OOScript nonLegacyScriptFromFileNamed:@"oolite-debug-console.js" properties:jsProps] retain];
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
		[[OOJavaScriptEngine sharedEngine] removeGCRoot:&_jsSelf];
	}
	
	[super dealloc];
}


+ (id)sharedDebugMonitor
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
	[_script doEvent:@"consolePerformJSCommand" withArgument:command];
}


- (void)appendJSConsoleLine:(id)string
				   colorKey:(NSString *)colorKey
			  emphasisRange:(NSRange)emphasisRange
{
	if (string == nil)  return;
	NS_DURING
		[_debugger debugMonitor:self
				jsConsoleOutput:string
					   colorKey:colorKey
				  emphasisRange:emphasisRange];
	NS_HANDLER
		OOLog(@"debugMonitor.debuggerConnection.exception", @"Exception while attempting to send JavaScript console text to debugger: %@ -- %@", [localException name], [localException reason]);
	NS_ENDHANDLER
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
	NS_DURING
		[_debugger debugMonitorClearConsole:self];
	NS_HANDLER
		OOLog(@"debugMonitor.debuggerConnection.exception", @"Exception while attempting to clear JavaScript console: %@ -- %@", [localException name], [localException reason]);
	NS_ENDHANDLER
}


- (void)showJSConsole
{
	NS_DURING
		[_debugger debugMonitorShowConsole:self];
	NS_HANDLER
		OOLog(@"debugMonitor.debuggerConnection.exception", @"Exception while attempting to show JavaScript console: %@ -- %@", [localException name], [localException reason]);
	NS_ENDHANDLER
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
			  stackSkip:(unsigned)stackSkip
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
	
	if (stackSkip == 0)
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
	else  showKey = @"show-console-on-warning";
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


- (jsval)javaScriptValueInContext:(JSContext *)context
{
	if (_jsSelf == NULL)
	{
		_jsSelf = DebugMonitorToJSConsole(context, self);
		if (_jsSelf != NULL)
		{
			if (!OO_AddJSGCRoot(context, &_jsSelf, "debug console"))
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
