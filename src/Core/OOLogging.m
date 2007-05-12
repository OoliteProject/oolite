/*

OOLogging.h
By Jens Ayton

More flexible alternative to NSLog().

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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


#import "OOLogging.h"
#import "OOPListParsing.h"
#import "OOFunctionAttributes.h"
#import "ResourceManager.h"


#define PER_THREAD_INDENTATION		1
#ifndef APPNAME
#define APPNAME						@"Oolite"
#endif


#if OOLITE_MAC_OS_X
#define SHOW_APPLICATION			1
#else
#define SHOW_APPLICATION			0
#endif


#if PER_THREAD_INDENTATION
	#if OOLITE_USE_TLS	// Define to use __thread keyword where supported
		#define USE_INDENT_GLOBALS	1
		#define THREAD_LOCAL		__thread
	#else
		#define USE_INDENT_GLOBALS	0
		static NSString * const kIndentLevelKey = @"org.aegidian.oolite.oolog.indentLevel";
		static NSString * const kIndentStackKey = @"org.aegidian.oolite.oolog.indentStack";
	#endif
#else
	#define USE_INDENT_GLOBALS		1
	#define THREAD_LOCAL
#endif


// Control flags for OOLogInternal() - like message classes, but less cool.
#define OOLOG_NOT_INITED			1
#define OOLOG_SETTING_SET			0
#define OOLOG_SETTING_RETRIEVE		0
#define OOLOG_METACLASS_LOOP		1
#define OOLOG_UNDEFINED_METACLASS	1
#define OOLOG_BAD_SETTING			1
#define OOLOG_BAD_DEFAULT_SETTING	1
#define OOLOG_BAD_POP_INDENT		1


// Used to track OOLogPushIndent()/OOLogPopIndent() state.
typedef struct OOLogIndentStackElement OOLogIndentStackElement;
struct OOLogIndentStackElement
{
	OOLogIndentStackElement		*link;
	unsigned					indent;
};


// We could probably use less state variables.
static BOOL						sInited = NO;
static NSLock					*sLock = nil;
static NSMutableDictionary		*sExplicitSettings = nil;
static NSMutableDictionary		*sDerivedSettingsCache = nil;
static NSMutableDictionary		*sFileNamesCache = nil;
#if USE_INDENT_GLOBALS
static THREAD_LOCAL unsigned	sIndentLevel = 0;
static THREAD_LOCAL OOLogIndentStackElement
								*sIndentStack = NULL;
#endif
static BOOL						sShowFunction = NO;
static BOOL						sShowFileAndLine = NO;
static BOOL						sShowClass = YES;
static BOOL						sDefaultDisplay = YES;
static BOOL						sShowApplication = SHOW_APPLICATION;
static BOOL						sOverrideInEffect = NO;
static BOOL						sOverrideValue = NO;

// These specific values are used for true, false and inherit in the cache and explicitSettings dictionaries so we can use pointer comparison.
static NSString * const			kTrueToken = @"on";
static NSString * const			kFalseToken = @"off";
static NSString * const			kInheritToken = @"inherit";


// To avoid recursion/self-dependencies, OOLog gets its own logging function.
#define OOLogInternal(cond, format, ...) do { if ((cond)) { OOLogInternal_(OOLOG_FUNCTION_NAME, format, ## __VA_ARGS__); }} while (0)
static void OOLogInternal_(const char *inFunction, NSString *inFormat, ...);


// Functions used internally
static void LoadExplicitSettings(void);
static void LoadExplicitSettingsFromDictionary(NSDictionary *inDict);
static NSString *AbbreviatedFileName(const char *inName);
static id ResolveDisplaySetting(NSString *inMessageClass);
static id ResolveMetaClassReference(NSString *inMetaClass, NSMutableSet *ioSeenMetaClasses);

OOINLINE unsigned GetIndentLevel(void) PURE_FUNC;
OOINLINE void SetIndentLevel(unsigned level);


/*	void PrimitiveLog(NSString *)
	This is the bottleneck output function used by both the OOLog() family and
	OOLogInternal(). Under GNUstep, it uses NSLog(), which I believe logs to a
	file. Under Mac OS X, it writes to, because NSLog() adds its own prefix
	before writing to stout.
	To do: add option to log to file under OS X.
*/
static inline void PrimitiveLog(NSString *inString)
{
	#ifdef GNUSTEP
		#undef NSLog
		NSLog(@"%@", inString);
	#else
		puts([inString UTF8String]);
	#endif
}


// Given a boolean, return the appropriate value for the cache dictionary.
static inline id CacheValue(BOOL inValue) __attribute__((pure));
static inline id CacheValue(BOOL inValue)
{
	return inValue ? kTrueToken : kFalseToken;
}


/*	Inited()
	Test wether OOLoggingInit() has been called.
*/
static inline BOOL Inited(void)
{
	if (EXPECT(sInited)) return YES;
	OOLogInternal(OOLOG_NOT_INITED, @"ERROR: OOLoggingInit() has not been called.");
	return NO;
}


BOOL OOLogWillDisplayMessagesInClass(NSString *inMessageClass)
{
	id				value = nil;
	
	if (!Inited()) return NO;
	
	[sLock lock];
	
	// Look for cached value
	value = [sDerivedSettingsCache objectForKey:inMessageClass];
	if (EXPECT_NOT(value == nil))
	{
		// No cached value.
		value = ResolveDisplaySetting(inMessageClass);
		
		if (value != nil)
		{
			if (EXPECT_NOT(sDerivedSettingsCache == nil)) sDerivedSettingsCache = [[NSMutableDictionary alloc] init];
			[sDerivedSettingsCache setObject:value forKey:inMessageClass];
		}
	}
	[sLock unlock];
	
	OOLogInternal(OOLOG_SETTING_RETRIEVE, @"%@ is %s", inMessageClass, (value == kTrueToken) ? "on" : "off");
	return value == kTrueToken;
}


void OOLogSetDisplayMessagesInClass(NSString *inClass, BOOL inFlag)
{
	id				value = nil;
	
	if (!Inited()) return;
	
	[sLock lock];
	value = [sExplicitSettings objectForKey:inClass];
	if (value == nil || value != CacheValue(inFlag))
	{
		OOLogInternal(OOLOG_SETTING_SET, @"Setting %@ to %s", inClass, inFlag ? "ON" : "OFF");
		
		[sExplicitSettings setObject:CacheValue(inFlag) forKey:inClass];
		
		// Clear cache and let it be rebuilt as needed. Cost of rebuilding cache is not sufficient to warrant complexity of a partial clear.
		[sDerivedSettingsCache release];
		sDerivedSettingsCache = nil;
	}
	else
	{
		OOLogInternal(OOLOG_SETTING_SET, @"Keeping %@ %s", inClass, inFlag ? "ON" : "OFF");
	}
	[sLock unlock];
}


NSString *OOLogGetParentMessageClass(NSString *inClass)
{
	NSRange					range;
	
	if (inClass == nil) return nil;
	
	range = [inClass rangeOfString:@"." options:NSCaseInsensitiveSearch | NSLiteralSearch | NSBackwardsSearch];	// Only NSBackwardsSearch is important, others are optimizations
	if (range.location == NSNotFound) return nil;
	
	return [inClass substringToIndex:range.location];
}


#if !OOLOG_SHORT_CIRCUIT

void OOLogIndentIf(NSString *inMessageClass)
{
	if (OOLogWillDisplayMessagesInClass(inMessageClass)) OOLogIndent();
}


void OOLogOutdentIf(NSString *inMessageClass)
{
	if (OOLogWillDisplayMessagesInClass(inMessageClass)) OOLogOutdent();
}

#endif


#if USE_INDENT_GLOBALS

#if OOLITE_USE_TLS
	#define INDENT_LOCK()		do {} while (0)
	#define INDENT_UNLOCK()		do {} while (0)
#else
	#define INDENT_LOCK()		[sLock lock]
	#define INDENT_UNLOCK()		[sLock unlock]
#endif


OOINLINE unsigned GetIndentLevel(void)
{
	return sIndentLevel;
}


OOINLINE void SetIndentLevel(unsigned value)
{
	sIndentLevel = value;
}


void OOLogPushIndent(void)
{
	OOLogIndentStackElement	*elem = NULL;
	
	elem = malloc(sizeof *elem);
	if (elem != NULL)
	{
		INDENT_LOCK();
		
		elem->indent = sIndentLevel;
		elem->link = sIndentStack;
		sIndentStack = elem;
		
		INDENT_UNLOCK();
	}
}


void OOLogPopIndent(void)
{
	INDENT_LOCK();
	
	OOLogIndentStackElement	*elem = sIndentStack;
	
	if (elem != NULL)
	{
		sIndentStack = elem->link;
		sIndentLevel = elem->indent;
		free(elem);
	}
	else
	{
		OOLogInternal(OOLOG_BAD_POP_INDENT, @"OOLogPopIndent(): state stack underflow.");
	}
	INDENT_UNLOCK();
}

#else	// !USE_INDENT_GLOBALS

#define INDENT_LOCK()			do {} while (0)
#define INDENT_UNLOCK()			do {} while (0)


OOINLINE unsigned GetIndentLevel(void)
{
	NSMutableDictionary *threadDict = [[NSThread currentThread] threadDictionary];
	return [[threadDict objectForKey:kIndentLevelKey] unsignedIntValue];
}


OOINLINE void SetIndentLevel(unsigned value)
{
	NSMutableDictionary *threadDict = [[NSThread currentThread] threadDictionary];
	[threadDict setObject:[NSNumber numberWithUnsignedInt:value] forKey:kIndentLevelKey];
}


void OOLogPushIndent(void)
{
	OOLogIndentStackElement	*elem = NULL;
	NSMutableDictionary		*threadDict = nil;
	NSValue					*val = nil;
	
	elem = malloc(sizeof *elem);
	if (elem != NULL)
	{
		threadDict = [[NSThread currentThread] threadDictionary];
		val = [threadDict objectForKey:kIndentStackKey];
		
		elem->indent = [[threadDict objectForKey:kIndentLevelKey] intValue];
		elem->link = [val pointerValue];
		[threadDict setObject:[NSValue valueWithPointer:elem] forKey:kIndentStackKey];
	}
}


void OOLogPopIndent(void)
{
	OOLogIndentStackElement	*elem = NULL;
	NSMutableDictionary		*threadDict = nil;
	NSValue					*val = nil;
	
	threadDict = [[NSThread currentThread] threadDictionary];
	val = [threadDict objectForKey:kIndentStackKey];
	
	elem = [val pointerValue];
	
	if (elem != NULL)
	{
		[threadDict setObject:[NSNumber numberWithUnsignedInt:elem->indent] forKey:kIndentLevelKey];
		[threadDict setObject:[NSValue valueWithPointer:elem->link] forKey:kIndentStackKey];
		free(elem);
	}
	else
	{
		OOLogInternal(OOLOG_BAD_POP_INDENT, @"OOLogPopIndent(): state stack underflow.");
	}
}

#endif	// USE_INDENT_GLOBALS


void OOLogIndent(void)
{
	INDENT_LOCK();

	SetIndentLevel(GetIndentLevel() + 1);
	
	INDENT_UNLOCK();
}


void OOLogOutdent(void)
{
	INDENT_LOCK();
	
	unsigned indentLevel = GetIndentLevel();
	if (indentLevel != 0)  SetIndentLevel(indentLevel - 1);
	
	INDENT_UNLOCK();
}


void OOLogWithFunctionFileAndLine(NSString *inMessageClass, const char *inFunction, const char *inFile, unsigned long inLine, NSString *inFormat, ...)
{
	va_list				args;
	
	va_start(args, inFormat);
	OOLogWithFunctionFileAndLineAndArguments(inMessageClass, inFunction, inFile, inLine, inFormat, args);
	va_end(args);
}


void OOLogWithFunctionFileAndLineAndArguments(NSString *inMessageClass, const char *inFunction, const char *inFile, unsigned long inLine, NSString *inFormat, va_list inArguments)
{
	NSAutoreleasePool	*pool = nil;
	NSString			*formattedMessage = nil;
	unsigned			indentLevel;
	
	pool = [[NSAutoreleasePool alloc] init];
	
	#if !OOLOG_SHORT_CIRCUIT
		if (!OOLogWillDisplayMessagesInClass(inMessageClass))
		{
			[pool release];
			return;
		}
	#endif
	
	// Do argument substitution
	formattedMessage = [[[NSString alloc] initWithFormat:inFormat arguments:inArguments] autorelease];
	
	// Apply various prefix options
	if (sShowFunction)
	{
		if (sShowFileAndLine)
		{
			formattedMessage = [NSString stringWithFormat:@"%s (%@:%u): %@", inFunction, AbbreviatedFileName(inFile), inLine, formattedMessage];
		}
		else
		{
			formattedMessage = [NSString stringWithFormat:@"%s: %@", inFunction, formattedMessage];
		}
	}
	else
	{
		if (sShowFileAndLine)
		{
			formattedMessage = [NSString stringWithFormat:@"%@:%u: %@", AbbreviatedFileName(inFile), inLine, formattedMessage];
		}
	}
	
	if (sShowClass)
	{
		if (sShowFunction || sShowFileAndLine)
		{
			formattedMessage = [NSString stringWithFormat:@"[%@] %@", inMessageClass, formattedMessage];
		}
		else
		{
			formattedMessage = [NSString stringWithFormat:@"[%@]: %@", inMessageClass, formattedMessage];
		}
	}
	
	if (sShowApplication)
	{
		if (sShowClass)
		{
			formattedMessage = [NSString stringWithFormat:@"%@ %@", APPNAME, formattedMessage];
		}
		else if (sShowFunction || sShowFileAndLine)
		{
			formattedMessage = [NSString stringWithFormat:@"%@ - %@", APPNAME, formattedMessage];
		}
		else
		{
			formattedMessage = [NSString stringWithFormat:@"%@: %@", APPNAME, formattedMessage];
		}
	}
	
	// Apply indentation
	indentLevel = GetIndentLevel();
	if (indentLevel != 0)
	{
		#define INDENT_FACTOR	2		/* Spaces per indent level */
		#define MAX_INDENT		64		/* Maximum number of indentation _spaces_ */
		
		unsigned			indent;
							// String of 64 spaces (null-terminated)
		const char			spaces[MAX_INDENT + 1] =
							"                                                                ";
		const char			*indentString;
		
		indent = INDENT_FACTOR * indentLevel;
		if (MAX_INDENT < indent) indent = MAX_INDENT;
		indentString = &spaces[MAX_INDENT - indent];
		
		formattedMessage = [NSString stringWithFormat:@"%s%@", indentString, formattedMessage];
	}
	
	PrimitiveLog(formattedMessage);
	
	[pool release];
}


void OOLogGenericParameterErrorForFunction(const char *inFunction)
{
	OOLog(kOOLogParameterError, @"***** %s: bad parameters. (This is an internal programming error, please report it.)", inFunction);
}


void OOLogGenericSubclassResponsibilityForFunction(const char *inFunction)
{
	OOLog(kOOLogParameterError, @"***** %s is a subclass responsibility. (This is an internal programming error, please report it.)", inFunction);
}


void OOLoggingInit(void)
{
	NSAutoreleasePool		*pool = nil;
	
	if (sInited) return;
	
	pool = [[NSAutoreleasePool alloc] init];
	sLock = [[NSLock alloc] init];
	if (sLock == nil) abort();
	
	LoadExplicitSettings();
	sInited = YES;
	[pool release];
}


NSString * const kOOLogSubclassResponsibility		= @"general.error.subclassResponsibility";
NSString * const kOOLogParameterError				= @"general.error.parameterError";
NSString * const kOOLogDeprecatedMethod				= @"general.error.deprecatedMethod";
NSString * const kOOLogAllocationFailure			= @"general.error.allocationFailure";
NSString * const kOOLogException					= @"exception";
NSString * const kOOLogFileNotFound					= @"files.notFound";
NSString * const kOOLogFileNotLoaded				= @"files.notLoaded";
NSString * const kOOLogOpenGLError					= @"rendering.opengl.error";
NSString * const kOOLogUnconvertedNSLog				= @"unclassified";


/*	OOLogInternal_()
	Implementation of OOLogInternal(), private logging function used by
	OOLogging so it doesn’t depend on itself (and risk recursiveness).
*/
static void OOLogInternal_(const char *inFunction, NSString *inFormat, ...)
{
	va_list				args;
	NSString			*formattedMessage = nil;
	NSAutoreleasePool	*pool = nil;
	
	pool = [[NSAutoreleasePool alloc] init];
	
	va_start(args, inFormat);
	formattedMessage = [[[NSString alloc] initWithFormat:inFormat arguments:args] autorelease];
	va_end(args);
	
	formattedMessage = [NSString stringWithFormat:@"OOLogging internal - %s: %@", inFunction, formattedMessage];
	if (sShowApplication) formattedMessage = [APPNAME stringByAppendingString:formattedMessage];
	
	PrimitiveLog(formattedMessage);
	
	[pool release];
}


/*	LoadExplicitSettings()
	Read settings from logcontrol.plist, merge in settings from preferences.
*/
static void LoadExplicitSettings(void)
{
	NSEnumerator		*rootEnum = nil;
	NSString			*basePath = nil;
	NSString			*configPath = nil;
	NSDictionary		*dict = nil;
	NSUserDefaults		*prefs = nil;
	id					value = nil;
	
	if (sExplicitSettings != nil) return;
	
	sExplicitSettings = [[NSMutableDictionary alloc] init];
	
	rootEnum = [[ResourceManager rootPaths] objectEnumerator];
	while ((basePath = [rootEnum nextObject]))
	{
		configPath = [[basePath stringByAppendingPathComponent:@"Config"]
								stringByAppendingPathComponent:@"logcontrol.plist"];
		dict = OODictionaryFromFile(configPath);
		if (dict == nil)
		{
			configPath = [basePath stringByAppendingPathComponent:@"logcontrol.plist"];
			dict = OODictionaryFromFile(configPath);
		}
		if (dict != nil)
		{
			LoadExplicitSettingsFromDictionary(dict);
		}
	}
	
	// Get overrides from preferences
	prefs = [NSUserDefaults standardUserDefaults];
	dict = [prefs objectForKey:@"logging-enable"];
	if ([dict isKindOfClass:[NSDictionary class]])
	{
		LoadExplicitSettingsFromDictionary(dict);
	}
	
	// Get _default and _override value
	value = [sExplicitSettings objectForKey:@"_default"];
	if (value != nil && [value respondsToSelector:@selector(boolValue)])
	{
		if (value == kTrueToken) sDefaultDisplay = YES;
		else if (value == kFalseToken) sDefaultDisplay = NO;
		else OOLogInternal(OOLOG_BAD_DEFAULT_SETTING, @"_default may not be set to a metaclass, ignoring.");
		
		[sExplicitSettings removeObjectForKey:@"_default"];
	}
	value = [sExplicitSettings objectForKey:@"_override"];
	if (value != nil && [value respondsToSelector:@selector(boolValue)])
	{
		if (value == kTrueToken)
		{
			sOverrideInEffect = YES;
			sOverrideValue = YES;
		}
		else if (value == kFalseToken)
		{
			sOverrideInEffect = YES;
			sOverrideValue = NO;
		}
		else OOLogInternal(OOLOG_BAD_DEFAULT_SETTING, @"_override may not be set to a metaclass, ignoring.");
		
		[sExplicitSettings removeObjectForKey:@"_override"];
	}
	
	// Load display settings
	value = [prefs objectForKey:@"logging-show-app-name"];
	if (value != nil && [value respondsToSelector:@selector(boolValue)])
	{
		sShowApplication = [value boolValue];
	}
	value = [prefs objectForKey:@"logging-show-function"];
	if (value != nil && [value respondsToSelector:@selector(boolValue)])
	{
		sShowFunction = [value boolValue];
	}
	value = [prefs objectForKey:@"logging-show-file-and-line"];
	if (value != nil && [value respondsToSelector:@selector(boolValue)])
	{
		sShowFileAndLine = [value boolValue];
	}
	value = [prefs objectForKey:@"logging-show-class"];
	if (value != nil && [value respondsToSelector:@selector(boolValue)])
	{
		sShowClass = [value boolValue];
	}
	
	OOLogInternal(OOLOG_SETTING_SET, @"Settings: %@", sExplicitSettings);
}


/*	LoadExplicitSettingsFromDictionary()
	Helper for LoadExplicitSettings().
*/
static void LoadExplicitSettingsFromDictionary(NSDictionary *inDict)
{
	NSEnumerator		*keyEnum = nil;
	id					key = nil;
	id					value = nil;
	
	for (keyEnum = [inDict keyEnumerator]; (key = [keyEnum nextObject]); )
	{
		value = [inDict objectForKey:key];
		
		/*	Supported values:
			"yes", "true" or "on" -> kTrueToken
			"no", "false" or "off" -> kFalseToken
			"inherit" or "inherited" -> nil
			NSNumber -> kTrueToken or kFalseToken
			"$metaclass" -> "$metaclass"
		*/
		if ([value isKindOfClass:[NSString class]])
		{
			if (NSOrderedSame == [value caseInsensitiveCompare:@"yes"] ||
				NSOrderedSame == [value caseInsensitiveCompare:@"true"] ||
				NSOrderedSame == [value caseInsensitiveCompare:@"on"])
			{
				value = kTrueToken;
			}
			else if (NSOrderedSame == [value caseInsensitiveCompare:@"no"] ||
				NSOrderedSame == [value caseInsensitiveCompare:@"false"] ||
				NSOrderedSame == [value caseInsensitiveCompare:@"off"])
			{
				value = kFalseToken;
			}
			else if (NSOrderedSame == [value caseInsensitiveCompare:@"inherit"] ||
				NSOrderedSame == [value caseInsensitiveCompare:@"inherited"])
			{
				value = nil;
				[sExplicitSettings removeObjectForKey:key];
			}
			else if (![value hasPrefix:@"$"])
			{
				OOLogInternal(OOLOG_BAD_SETTING, @"Bad setting value \"%@\" (expected yes, no, inherit or $metaclass).", value);
				value = nil;
			}
		}
		else if ([value respondsToSelector:@selector(boolValue)])
		{
			value = CacheValue([value boolValue]);
		}
		else
		{
			OOLogInternal(OOLOG_BAD_SETTING, @"Bad setting value \"%@\" (expected yes, no, inherit or $metaclass).", value);
			value = nil;
		}
		
		if (value != nil)
		{
			[sExplicitSettings setObject:value forKey:key];
		}
	}
}


/*	AbbreviatedFileName()
	Map full file paths provided by __FILE__ to more mananagable file names,
	with caching.
*/
static NSString *AbbreviatedFileName(const char *inName)
{
	NSValue				*key = nil;
	NSString			*name = nil;
	
	[sLock lock];
	key = [NSValue valueWithPointer:inName];
	name = [sFileNamesCache objectForKey:key];
	if (name == nil)
	{
		name = [[NSString stringWithUTF8String:inName] lastPathComponent];
		if (sFileNamesCache == nil) sFileNamesCache = [[NSMutableDictionary alloc] init];
		[sFileNamesCache setObject:name forKey:key];
	}
	[sLock unlock];
	
	return name;
}


/*	Look up setting for a message class in explicit settings, resolving
	inheritance and metaclasses.
*/
static id ResolveDisplaySetting(NSString *inMessageClass)
{
	id					value = nil;
	NSMutableSet		*seenMetaClasses = nil;
	
	if (inMessageClass == nil) return CacheValue(sDefaultDisplay);
	
	value = [sExplicitSettings objectForKey:inMessageClass];
	
	// Simple case: explicit setting for this value
	if (value == kTrueToken || value == kFalseToken) return value;
	
	// Simplish case: use inherited value
	if (value == nil || value == kInheritToken) return ResolveDisplaySetting(OOLogGetParentMessageClass(inMessageClass));
	
	// Less simple case: should be a metaclass.
	seenMetaClasses = [NSMutableSet set];
	return ResolveMetaClassReference(value, seenMetaClasses);
}


/*	Resolve a metaclass reference, recursively if necessary. The
	ioSeenMetaClasses dictionary is used to avoid loops.
*/
static id ResolveMetaClassReference(NSString *inMetaClass, NSMutableSet *ioSeenMetaClasses)
{
	id					value = nil;
	
	// All values should have been checked at load time, but what the hey.
	if (![inMetaClass isKindOfClass:[NSString class]] || ![inMetaClass hasPrefix:@"$"])
	{
		OOLogInternal(OOLOG_BAD_SETTING, @"Bad setting value \"%@\" (expected yes, no, inherit or $metaclass). Falling back to _default.", inMetaClass);
		return CacheValue(sDefaultDisplay);
	}
	
	[ioSeenMetaClasses addObject:inMetaClass];
	
	value = [sExplicitSettings objectForKey:inMetaClass];
	
	if (value == kTrueToken || value == kFalseToken) return value;
	if (value == nil)
	{
		OOLogInternal(OOLOG_UNDEFINED_METACLASS, @"Reference to undefined metaclass %@, falling back to _default.", inMetaClass);
		return CacheValue(sDefaultDisplay);
	}
	
	// If we get here, it should be a metaclass reference.
	return ResolveMetaClassReference(value, ioSeenMetaClasses);
}
