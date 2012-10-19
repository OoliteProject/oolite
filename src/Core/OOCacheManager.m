/*

OOCacheManager.m

Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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

#import "OOCacheManager.h"
#import "OOPListParsing.h"
#import "OODeepCopy.h"
#import "OOCollectionExtractors.h"
#import "OOJavaScriptEngine.h"
#import "NSFileManagerOOExtensions.h"


#define WRITE_ASYNC				1
#define PROFILE_WRITES			0


// Use the (presumed) most efficient plist format for each platform.
#if OOLITE_MAC_OS_X
#define CACHE_PLIST_FORMAT	NSPropertyListBinaryFormat_v1_0
#else
#define CACHE_PLIST_FORMAT	NSPropertyListGNUstepBinaryFormat
#endif


#if WRITE_ASYNC
#import "OOAsyncWorkManager.h"
#endif
#if PROFILE_WRITES
#import "OOProfilingStopwatch.h"
#endif


static NSString * const kOOLogDataCacheFound				= @"dataCache.found";
static NSString * const kOOLogDataCacheNotFound				= @"dataCache.notFound";
static NSString * const kOOLogDataCacheRebuild				= @"dataCache.rebuild";
static NSString * const kOOLogDataCacheWriteSuccess			= @"dataCache.write.success";
static NSString * const kOOLogDataCacheWriteFailed			= @"dataCache.write.failed";
static NSString * const kOOLogDataCacheRetrieveSuccess		= @"dataCache.retrieve.success";
static NSString * const kOOLogDataCacheRetrieveFailed		= @"dataCache.retrieve.failed";
static NSString * const kOOLogDataCacheSetSuccess			= @"dataCache.set.success";
static NSString * const kOOLogDataCacheSetFailed			= @"dataCache.set.failed";
static NSString * const kOOLogDataCacheRemoveSuccess		= @"dataCache.remove.success";
static NSString * const kOOLogDataCacheClearSuccess			= @"dataCache.clear.success";
static NSString * const kOOLogDataCacheParamError			= @"general.error.parameterError.OOCacheManager";
static NSString * const kOOLogDataCacheBuildPathError		= @"dataCache.write.buildPath.failed";
static NSString * const kOOLogDataCacheSerializationError	= @"dataCache.write.serialize.failed";

static NSString * const kCacheKeyVersion					= @"version";
static NSString * const kCacheKeyEndianTag					= @"endian tag";
static NSString * const kCacheKeyFormatVersion				= @"format version";
static NSString * const kCacheKeyCaches						= @"caches";


enum
{
	kEndianTagValue			= 0x0123456789ABCDEFULL,
	kFormatVersionValue		= 207
};


static OOCacheManager *sSingleton = nil;


@interface OOCacheManager (Private)

- (void)loadCache;
- (void)write;
- (void)clear;
- (BOOL)dirty;
- (void)markClean;

- (NSDictionary *)loadDict;
- (BOOL)writeDict:(NSDictionary *)inDict;

- (void)buildCachesFromDictionary:(NSDictionary *)inDict;
- (NSDictionary *)dictionaryOfCaches;

- (BOOL)directoryExists:(NSString *)inPath create:(BOOL)inCreate;

@end


@interface OOCacheManager (PlatformSpecific)

- (NSString *)cachePathCreatingIfNecessary:(BOOL)inCreate;

@end


#if WRITE_ASYNC
@interface OOAsyncCacheWriter: NSObject <OOAsyncWorkTask>
{
@private
	NSDictionary			*_cacheContents;
}

- (id) initWithCacheContents:(NSDictionary *)cacheContents;

@end
#endif


@implementation OOCacheManager

- (id)init
{
	self = [super init];
	if (self != nil)
	{
		_permitWrites = YES;
		[self loadCache];
	}
	return self;
}


- (void)dealloc
{
	[self clear];
	
	[super dealloc];
}


- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p>{dirty=%s}", [self class], self, [self dirty] ? "yes" : "no"];
}


+ (OOCacheManager *) sharedCache
{
	// NOTE: assumes single-threaded access.
	if (sSingleton == nil)
	{
		sSingleton = [[self alloc] init];
	}
	
	return sSingleton;
}


- (id)objectForKey:(NSString *)inKey inCache:(NSString *)inCacheKey
{
	NSMutableDictionary		*cache = nil;
	id						result = nil;
	
	NSParameterAssert(inKey != nil && inCacheKey != nil);
	
	cache = [_caches objectForKey:inCacheKey];
	if (cache != nil)
	{
		result = [cache objectForKey:inKey];
		if (result != nil)
		{
			OODebugLog(kOOLogDataCacheRetrieveSuccess, @"Retrieved \"%@\" cache object %@.", inCacheKey, inKey);
		}
		else
		{
			OODebugLog(kOOLogDataCacheRetrieveFailed, @"Failed to retrieve \"%@\" cache object %@ -- no such entry.", inCacheKey, inKey);
		}
	}
	else
	{
		OODebugLog(kOOLogDataCacheRetrieveFailed, @"Failed to retreive \"%@\" cache object %@ -- no such cache.", inCacheKey, inKey);
	}
	
	return result;
}



- (void)setObject:(id)inObject forKey:(NSString *)inKey inCache:(NSString *)inCacheKey
{
	NSMutableDictionary		*cache = nil;
	
	NSParameterAssert(inObject != nil && inKey != nil && inCacheKey != nil);
	
	if (EXPECT_NOT(_caches == nil))  return;
	
	cache = [_caches objectForKey:inCacheKey];
	if (cache == nil)
	{
		cache = [NSMutableDictionary dictionary];
		if (cache == nil)
		{
			OODebugLog(kOOLogDataCacheSetFailed, @"Failed to create cache for key \"%@\".", inCacheKey);
			return;
		}
		[_caches setObject:cache forKey:inCacheKey];
	}
	
	[cache setObject:inObject forKey:inKey];
	_dirty = YES;
	OODebugLog(kOOLogDataCacheSetSuccess, @"Updated entry %@ in cache \"%@\".", inKey, inCacheKey);
}


- (void)removeObjectForKey:(NSString *)inKey inCache:(NSString *)inCacheKey
{
	NSMutableDictionary		*cache = nil;
	
	NSParameterAssert(inKey != nil && inCacheKey != nil);
	
	cache = [_caches objectForKey:inCacheKey];
	if (cache != nil)
	{
		if (nil != [cache objectForKey:inKey])
		{
			[cache removeObjectForKey:inKey];
			_dirty = YES;
			OODebugLog(kOOLogDataCacheRemoveSuccess, @"Removed entry keyed %@ from cache \"%@\".", inKey, inCacheKey);
		}
		else
		{
			OODebugLog(kOOLogDataCacheRemoveSuccess, @"No need to remove non-existent entry keyed %@ from cache \"%@\".", inKey, inCacheKey);
		}
	}
	else
	{
		OODebugLog(kOOLogDataCacheRemoveSuccess, @"No need to remove entry keyed %@ from non-existent cache \"%@\".", inKey, inCacheKey);
	}
}


- (void)clearCache:(NSString *)inCacheKey
{
	NSParameterAssert(inCacheKey != nil);
	
	if (nil != [_caches objectForKey:inCacheKey])
	{
		[_caches removeObjectForKey:inCacheKey];
		_dirty = YES;
		OODebugLog(kOOLogDataCacheClearSuccess, @"Cleared cache \"%@\".", inCacheKey);
	}
	else
	{
		OODebugLog(kOOLogDataCacheClearSuccess, @"No need to clear non-existent cache \"%@\".", inCacheKey);
	}
}


- (void)clearAllCaches
{
	[self clear];
	_caches = [[NSMutableDictionary alloc] init];
	_dirty = YES;
}


- (void) reloadAllCaches
{
	[self clear];
	[self loadCache];
}


- (void)flush
{
	if (_permitWrites && [self dirty] && _scheduledWrite == nil)
	{
		[self write];
		[self markClean];
	}
}


- (void)finishOngoingFlush
{
#if WRITE_ASYNC
	[[OOAsyncWorkManager sharedAsyncWorkManager] waitForTaskToComplete:_scheduledWrite];
#endif
}


- (void)setAllowCacheWrites:(BOOL)flag
{
	_permitWrites = (flag != NO);
}

@end


@implementation OOCacheManager (Private)

- (void)loadCache
{
	NSDictionary			*cache = nil;
	NSString				*cacheVersion = nil;
	NSString				*ooliteVersion = nil;
	NSData					*endianTag = nil;
	NSNumber				*formatVersion = nil;
	BOOL					accept = YES;
	uint64_t				endianTagValue = 0;
	
	ooliteVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
	
	[self clear];
	
	cache = [self loadDict];
	if (cache != nil)
	{
		// We have a cache
		OOLog(kOOLogDataCacheFound, @"Found data cache.");
		OOLogIndentIf(kOOLogDataCacheFound);
		
		cacheVersion = [cache objectForKey:kCacheKeyVersion];
		if (![cacheVersion isEqual:ooliteVersion])
		{
			OOLog(kOOLogDataCacheRebuild, @"Data cache version (%@) does not match Oolite version (%@), rebuilding cache.", cacheVersion, ooliteVersion);
			accept = NO;
		}
		
		formatVersion = [cache objectForKey:kCacheKeyFormatVersion];
		if (accept && [formatVersion unsignedIntValue] != kFormatVersionValue)
		{
			OOLog(kOOLogDataCacheRebuild, @"Data cache format (%@) is not supported format (%u), rebuilding cache.", formatVersion, kFormatVersionValue);
			accept = NO;
		}
		
		if (accept)
		{
			endianTag = [cache objectForKey:kCacheKeyEndianTag];
			if (![endianTag isKindOfClass:[NSData class]] || [endianTag length] != sizeof endianTagValue)
			{
				OOLog(kOOLogDataCacheRebuild, @"Data cache endian tag is invalid, rebuilding cache.");
				accept = NO;
			}
			else
			{
				endianTagValue = *(const uint64_t *)[endianTag bytes];
				if (endianTagValue != kEndianTagValue)
				{
					OOLog(kOOLogDataCacheRebuild, @"Data cache endianness is inappropriate for this system, rebuilding cache.");
					accept = NO;
				}
			}
		}
		
		if (accept)
		{
			// We have a cache, and it's the right format.
			[self buildCachesFromDictionary:[cache objectForKey:kCacheKeyCaches]];
		}
		
		OOLogOutdentIf(kOOLogDataCacheFound);
	}
	else
	{
		// No cache
		OOLog(kOOLogDataCacheNotFound, @"No data cache found, starting from scratch.");
	}
	
	// If loading failed, or there was a version or endianness conflict
	if (_caches == nil) _caches = [[NSMutableDictionary alloc] init];
	[self markClean];
}


- (void)write
{
	NSMutableDictionary		*newCache = nil;
	NSString				*ooliteVersion = nil;
	NSData					*endianTag = nil;
	NSNumber				*formatVersion = nil;
	NSDictionary			*pListRep = nil;
	uint64_t				endianTagValue = kEndianTagValue;
	
	if (_caches == nil) return;
	if (_scheduledWrite != nil)  return;
	
#if PROFILE_WRITES
	OOProfilingStopwatch *stopwatch = [OOProfilingStopwatch stopwatch];
#endif
	
#if WRITE_ASYNC
	OOLog(@"dataCache.willWrite", @"Scheduling data cache write.");
#else
	OOLog(@"dataCache.willWrite", @"About to write cache.");
#endif
	
	ooliteVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
	endianTag = [NSData dataWithBytes:&endianTagValue length:sizeof endianTagValue];
	formatVersion = [NSNumber numberWithUnsignedInt:kFormatVersionValue];
	
	pListRep = [self dictionaryOfCaches];
	if (ooliteVersion == nil || endianTag == nil || formatVersion == nil || pListRep == nil)
	{
		OOLog(@"dataCache.cantWrite", @"Failed to write data cache -- prerequisites not fulfilled. %@",@"This is an internal error, please report it.");
		return;
	}
	
	newCache = [NSMutableDictionary dictionaryWithCapacity:4];
	[newCache setObject:ooliteVersion forKey:kCacheKeyVersion];
	[newCache setObject:formatVersion forKey:kCacheKeyFormatVersion];
	[newCache setObject:endianTag forKey:kCacheKeyEndianTag];
	[newCache setObject:pListRep forKey:kCacheKeyCaches];
	
#if PROFILE_WRITES && !WRITE_ASYNC
	OOTimeDelta prepareT = [stopwatch reset];
#endif
	
#if WRITE_ASYNC
	NSDictionary *cacheData = newCache;
	_scheduledWrite = [[OOAsyncCacheWriter alloc] initWithCacheContents:cacheData];
	
#if PROFILE_WRITES
	OOTimeDelta endT = [stopwatch reset];
	OOLog(@"dataCache.profile", @"Time to prepare cache data: %g seconds.", endT);
#endif
	
	[[OOAsyncWorkManager sharedAsyncWorkManager] addTask:_scheduledWrite priority:kOOAsyncPriorityLow];
#else
#if PROFILE_WRITES
	OOLog(@"dataCache.profile", @"Time to prepare cache data: %g seconds.", prepareT);
#endif
	
	if ([self writeDict:newCache])
	{
		[self markClean];
		OOLog(kOOLogDataCacheWriteSuccess, @"Wrote data cache.");
	}
	else
	{
		OOLog(kOOLogDataCacheWriteFailed, @"Failed to write data cache.");
	}
#endif
}


- (void)clear
{
	[_caches release];
	_caches = nil;
}


- (BOOL)dirty
{
	return _dirty;
}


- (void)markClean
{
	_dirty = NO;
}


- (NSDictionary *)loadDict
{
	NSString			*path = nil;
	NSData				*data = nil;
	NSString			*errorString = nil;
	id					contents = nil;
	
	path = [self cachePathCreatingIfNecessary:NO];
	if (path == nil) return nil;
	
	@try
	{
		data = [NSData dataWithContentsOfFile:path];
		if (data == nil)  return nil;
		
		contents = [NSPropertyListSerialization propertyListFromData:data
													mutabilityOption:NSPropertyListImmutable
															  format:NULL
													errorDescription:&errorString];
	}
	@catch (NSException *exception)
	{
		errorString = [exception reason];
		contents = nil;
	}
	
	if (errorString != nil)
	{
		OOLog(@"dataCache.badData", @"Could not read data cache: %@", errorString);
#if OOLITE_RELEASE_PLIST_ERROR_STRINGS
		[errorString release];
#endif
		return nil;
	}
	if (![contents isKindOfClass:[NSDictionary class]])  return nil;
	
	return contents;
}


- (BOOL)writeDict:(NSDictionary *)inDict
{
	NSString			*path = nil;
	NSData				*plist = nil;
	NSString			*errorDesc = nil;
	
	path = [self cachePathCreatingIfNecessary:YES];
	if (path == nil) return NO;	
	
#if PROFILE_WRITES
	OOProfilingStopwatch *stopwatch = [OOProfilingStopwatch stopwatch];
#endif
	
	plist = [NSPropertyListSerialization dataFromPropertyList:inDict format:CACHE_PLIST_FORMAT errorDescription:&errorDesc];
	if (plist == nil)
	{
#if OOLITE_RELEASE_PLIST_ERROR_STRINGS
		[errorDesc autorelease];
#endif
		OOLog(kOOLogDataCacheSerializationError, @"Could not convert data cache to property list data: %@", errorDesc);
		return NO;
	}
	
#if PROFILE_WRITES
	OOTimeDelta serializeT = [stopwatch reset];
#endif
	
	BOOL result = [plist writeToFile:path atomically:NO];
	
#if PROFILE_WRITES
	OOTimeDelta writeT = [stopwatch reset];
	
	OOLog(@"dataCache.profile", @"Time to serialize cache: %g seconds. Time to write data: %g seconds.", serializeT, writeT);
#endif
	
#if WRITE_ASYNC
	DESTROY(_scheduledWrite);
#endif
	return result;
}


- (void)buildCachesFromDictionary:(NSDictionary *)inDict
{
	NSEnumerator				*keyEnum = nil;
	id							key = nil;
	id							value = nil;
	NSMutableDictionary			*cache = nil;
	
	if (inDict == nil ) return;
	
	[_caches release];
	_caches = [[NSMutableDictionary alloc] initWithCapacity:[inDict count]];
	
	for (keyEnum = [inDict keyEnumerator]; (key = [keyEnum nextObject]); )
	{
		value = [inDict oo_dictionaryForKey:key];
		if (value != nil)
		{
			cache = [NSMutableDictionary dictionaryWithDictionary:value];
			if (cache != nil)
			{
				[_caches setObject:cache forKey:key];
			}
		}
	}
}


- (NSDictionary *)dictionaryOfCaches
{
	return [OODeepCopy(_caches) autorelease];
}


- (BOOL)directoryExists:(NSString *)inPath create:(BOOL)inCreate
{
	BOOL				exists, directory;
	NSFileManager		*fmgr =  [NSFileManager defaultManager];
	
	exists = [fmgr fileExistsAtPath:inPath isDirectory:&directory];
	
	if (exists && !directory)
	{
		OOLog(kOOLogDataCacheBuildPathError, @"Expected %@ to be a folder, but it is a file.", inPath);
		return NO;
	}
	if (!exists)
	{
		if (!inCreate) return NO;
		if (![fmgr oo_createDirectoryAtPath:inPath attributes:nil])
		{
			OOLog(kOOLogDataCacheBuildPathError, @"Could not create folder %@.", inPath);
			return NO;
		}
	}
	
	return YES;
}

@end


@implementation OOCacheManager (PlatformSpecific)

#if OOLITE_MAC_OS_X

- (NSString *)cachePathCreatingIfNecessary:(BOOL)inCreate
{
	NSString			*cachePath = nil;
	
	/*	Construct the path for the cache file, which is:
			~/Library/Caches/org.aegidian.oolite/Data Cache.plist
		In addition to generally being the right place to put caches,
		~/Library/Caches has the particular advantage of not being indexed by
		Spotlight or, in future, backed up by Time Machine.
	*/
	cachePath = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	cachePath = [cachePath stringByAppendingPathComponent:@"Caches"];
	if (![self directoryExists:cachePath create:inCreate]) return nil;
	cachePath = [cachePath stringByAppendingPathComponent:@"org.aegidian.oolite"];
	if (![self directoryExists:cachePath create:inCreate]) return nil;
	cachePath = [cachePath stringByAppendingPathComponent:@"Data Cache.plist"];
	return cachePath;
}

#else

- (NSString *)cachePathCreatingIfNecessary:(BOOL)inCreate
{
	NSString			*cachePath = nil;
	
	/*	Construct the path for the cache file, which is:
			~/GNUstep/Library/Caches/Oolite-cache.plist
		
		FIXME: we shouldn't be hard-coding ~/GNUstep/. Does
		NSSearchPathForDirectoriesInDomains() not work?
		-- Ahruman 2009-09-06
	*/
	cachePath = [NSHomeDirectory() stringByAppendingPathComponent:@"GNUstep"];
	if (![self directoryExists:cachePath create:inCreate]) return nil;
	cachePath = [cachePath stringByAppendingPathComponent:@"Library"];
	if (![self directoryExists:cachePath create:inCreate]) return nil;
	cachePath = [cachePath stringByAppendingPathComponent:@"Caches"];
	if (![self directoryExists:cachePath create:inCreate]) return nil;
	cachePath = [cachePath stringByAppendingPathComponent:@"Oolite-cache.plist"];
	
	return cachePath;
}

#endif

@end


@implementation OOCacheManager (Singleton)

/*	Canonical singleton boilerplate.
	See Cocoa Fundamentals Guide: Creating a Singleton Instance.
	See also +sharedCache above.
	
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


- (NSUInteger)retainCount
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


#if WRITE_ASYNC
@implementation OOAsyncCacheWriter

- (id) initWithCacheContents:(NSDictionary *)cacheContents
{
	if ((self = [super init]))
	{
		_cacheContents = [cacheContents copy];
		if (_cacheContents == nil)
		{
			[self release];
			self = nil;
		}
	}
	
	return self;
}


- (void) dealloc
{
	DESTROY(_cacheContents);
	
	[super dealloc];
}


- (void) performAsyncTask
{
	if ([[OOCacheManager sharedCache] writeDict:_cacheContents])
	{
		OOLog(kOOLogDataCacheWriteSuccess, @"Wrote data cache.");
	}
	else
	{
		OOLog(kOOLogDataCacheWriteFailed, @"Failed to write data cache.");
	}
	DESTROY(_cacheContents);
}


- (void) completeAsyncTask
{
	// Don't need to do anything, but this needs to be here so we can wait on it.
}

@end
#endif	// WRITE_ASYNC
