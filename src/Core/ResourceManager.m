/*

ResourceManager.m

Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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

#import "ResourceManager.h"
#import "NSScannerOOExtensions.h"
#import "NSMutableDictionaryOOExtensions.h"
#import "OOSound.h"
#import "OOCacheManager.h"
#import "Universe.h"
#import "OOStringParsing.h"
#import "OOPListParsing.h"
#import "MyOpenGLView.h"
#import "OOCollectionExtractors.h"
#import "OOLogOutputHandler.h"

#import "OOJSScript.h"
#import "OOPListScript.h"

#define kOOLogUnconvertedNSLog @"unclassified.ResourceManager"


static NSString * const kOOLogCacheUpToDate				= @"dataCache.upToDate";
static NSString * const kOOLogCacheExplicitFlush		= @"dataCache.rebuild.explicitFlush";
static NSString * const kOOLogCacheStalePaths			= @"dataCache.rebuild.pathsChanged";
static NSString * const kOOLogCacheStaleDates			= @"dataCache.rebuild.datesChanged";
static NSString * const kOOCacheSearchPathModDates		= @"search path modification dates";
static NSString * const kOOCacheKeySearchPaths			= @"search paths";
static NSString * const kOOCacheKeyModificationDates	= @"modification dates";


extern NSDictionary* ParseOOSScripts(NSString* script);


@interface ResourceManager (OOPrivate)

+ (void)checkPotentialPath:(NSString *)path :(NSMutableArray *)searchPaths;
+ (BOOL)areRequirementsFulfilled:(NSDictionary*)requirements forOXP:(NSString *)path;
+ (void) addErrorWithKey:(NSString *)descriptionKey param1:(id)param1 param2:(id)param2;
+ (void)checkCacheUpToDateForPaths:(NSArray *)searchPaths;
+ (NSString *) diagnosticFileLocation;

@end


static NSMutableArray	*sSearchPaths;
static BOOL				sUseAddOns = YES;
static NSMutableArray	*sExternalPaths;
static NSMutableArray	*sErrors;

// caches allow us to load any given file once only
//
static NSMutableDictionary *sound_cache;
static NSMutableDictionary *string_cache;


@implementation ResourceManager

+ (NSString *) errors
{
	NSArray					*error = nil;
	unsigned				i, count;
	NSMutableArray			*result = nil;
	NSString				*errStr = nil;
	
	count = [sErrors count];
	if (count == 0)  return nil;
	
	// Expand error messages. This is deferred for localizability.
	result = [NSMutableArray arrayWithCapacity:count];
	for (i = 0; i != count; ++i)
	{
		error = [sErrors objectAtIndex:i];
		errStr = [UNIVERSE descriptionForKey:[error stringAtIndex:0]];
		if (errStr != nil)
		{
			errStr = [NSString stringWithFormat:errStr, [error objectAtIndex:1], [error objectAtIndex:2]];
			[result addObject:errStr];
		}
	}
	
	[sErrors release];
	sErrors = nil;
	
	return [result componentsJoinedByString:@"\n"];
}


+ (NSArray *)rootPaths
{
	static NSArray			*sRootPaths = nil;
	
	if (sRootPaths == nil)
	{
#if OOLITE_MAC_OS_X
		NSString	*app_addon_path = [[[[NSBundle mainBundle] bundlePath]
									stringByDeletingLastPathComponent]
									stringByAppendingPathComponent:@"AddOns"];
		NSString	*appsupport_path = [[[[NSHomeDirectory()
										stringByAppendingPathComponent:@"Library"]
										stringByAppendingPathComponent:@"Application Support"]
										stringByAppendingPathComponent:@"Oolite"]
										stringByAppendingPathComponent:@"AddOns"];
#elif OOLITE_WINDOWS
		NSString	*app_addon_path = @"../AddOns";
		NSString	*appsupport_path = nil;
#else
		NSString	*app_addon_path = @"AddOns";
		NSString	*appsupport_path = nil;
#endif
		NSString	*nix_path = nil;
#if !OOLITE_WINDOWS
		/*	Enabling this path in Windows causes a log message, and it's not
			actually useful.
		*/
		nix_path = [[NSHomeDirectory()
					stringByAppendingPathComponent:@".Oolite"]
					stringByAppendingPathComponent:@"AddOns"];
#endif
		
		sRootPaths = [[NSArray alloc] initWithObjects:[self builtInPath], app_addon_path, nix_path, appsupport_path, nil];
	}
	
	return sRootPaths;
}


+ (NSString *)builtInPath
{
#if OOLITE_WINDOWS
	/*	[[NSBundle mainBundle] resourcePath] causes complaints under Windows,
		because we don't have a properly-built bundle.
	*/
	return @"Resources";
#else
	return [[NSBundle mainBundle] resourcePath];
#endif
}


+ (NSArray *)pathsWithAddOns
{
	if (sSearchPaths != nil)  return sSearchPaths;
	
	[sErrors release];
	sErrors = nil;
	
	NSFileManager			*fmgr = [NSFileManager defaultManager];
	NSArray					*rootPaths = nil;
	NSEnumerator			*pathEnum = nil;
	NSString				*root = nil;
	NSDirectoryEnumerator	*dirEnum = nil;
	NSString				*subPath = nil;
	NSString				*path = nil;
	BOOL					isDirectory;
	
	rootPaths = [self rootPaths];
	sSearchPaths = [rootPaths mutableCopy];
	
	// Iterate over root paths
	for (pathEnum = [rootPaths objectEnumerator]; (root = [pathEnum nextObject]); )
	{
		// Iterate over each root path's contents
		if ([fmgr fileExistsAtPath:root isDirectory:&isDirectory] && isDirectory)
		{
			for (dirEnum = [fmgr enumeratorAtPath:root]; (subPath = [dirEnum nextObject]); )
			{
				// Check if it's a directory
				path = [root stringByAppendingPathComponent:subPath];
				if ([fmgr fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory)
				{
					// If it is, is it an OXP?
					if ([[[path pathExtension] lowercaseString] isEqualToString:@"oxp"])
					{
						[self checkPotentialPath:path :sSearchPaths];
					}
					else
					{
						// If not, don't search subdirectories
						[dirEnum skipDescendents];
					}
				}
			}
		}
	}
	
	for (pathEnum = [sExternalPaths objectEnumerator]; (path = [pathEnum nextObject]); )
	{
		[self checkPotentialPath:path :sSearchPaths];
	}
	
	OOLog(@"searchPaths.dumpAll", @"---> OXP search paths:\n%@", sSearchPaths);
	[self checkCacheUpToDateForPaths:sSearchPaths];
	
	return sSearchPaths;
}


+ (NSArray *)paths
{
	return sUseAddOns ? [self pathsWithAddOns] : (NSArray *)[NSArray arrayWithObject:[self builtInPath]];
}


+ (BOOL)useAddOns
{
	return sUseAddOns;
}


+ (void)setUseAddOns:(BOOL)useAddOns
{
	useAddOns = (useAddOns != 0);
	if (sUseAddOns != useAddOns)
	{
		sUseAddOns = useAddOns;
		[self checkCacheUpToDateForPaths:[self paths]];
	}
}


+ (void) addExternalPath:(NSString *)path
{
	if (sSearchPaths == nil)  sSearchPaths = [[NSMutableArray alloc] init];
	if (![sSearchPaths containsObject:path])
	{
		[sSearchPaths addObject:path];
		
		if (sExternalPaths == nil)  sExternalPaths = [[NSMutableArray alloc] init];
		[sExternalPaths addObject:path];
	}
}


+ (NSEnumerator *)pathEnumerator
{
	return [[self paths] objectEnumerator];
}


+ (NSEnumerator *)reversePathEnumerator
{
	return [[self paths] reverseObjectEnumerator];
}


// Given a path to an assumed OXP (or other location where files are permissible), check for a requires.plist and add to search paths if acceptable.
+ (void)checkPotentialPath:(NSString *)path :(NSMutableArray *)searchPaths
{
	NSDictionary			*requirements = nil;
	BOOL					requirementsMet;
	
	requirements = OODictionaryFromFile([path stringByAppendingPathComponent:@"requires.plist"]);
	requirementsMet = [self areRequirementsFulfilled:requirements forOXP:path];
	
	if (requirementsMet)  [searchPaths addObject:path];
	else
	{
		NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
		OOLog(@"oxp.versionMismatch", @"OXP %@ is incompatible with version %@ of Oolite.", path, version);
		[self addErrorWithKey:@"oxp-is-incompatible" param1:[path lastPathComponent] param2:version];
	}
}


+ (BOOL) areRequirementsFulfilled:(NSDictionary*)requirements forOXP:(NSString *)path
{
	BOOL				OK = YES;
	NSString			*requiredVersion = nil;
	NSString			*maxVersion = nil;
	unsigned			conditionsHandled = 0;
	static NSArray		*ooVersionComponents = nil;
	NSArray				*oxpVersionComponents = nil;
	
	if (requirements == nil)  return YES;
	
	if (ooVersionComponents == nil)
	{
		ooVersionComponents = ComponentsFromVersionString([[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]);
		[ooVersionComponents retain];
	}
	
	// Check "version" (minimum version)
	if (OK)
	{
		// Not stringForKey:, because we need to be able to complain about non-strings.
		requiredVersion = [requirements objectForKey:@"version"];
		if (requiredVersion != nil)
		{
			++conditionsHandled;
			if ([requiredVersion isKindOfClass:[NSString class]])
			{
				oxpVersionComponents = ComponentsFromVersionString(requiredVersion);
				if (NSOrderedAscending == CompareVersions(ooVersionComponents, oxpVersionComponents))  OK = NO;
			}
			else
			{
				OOLog(@"requirements.wrongType", @"Expected requires.plist entry \"%@\" to be string, but got %@ in OXP %@.", @"version", [requirements class], [path lastPathComponent]);
				OK = NO;
			}
		}
	}
	
	// Check "max_version" (minimum max_version)
	if (OK)
	{
		// Not stringForKey:, because we need to be able to complain about non-strings.
		maxVersion = [requirements objectForKey:@"max_version"];
		if (maxVersion != nil)
		{
			++conditionsHandled;
			if ([maxVersion isKindOfClass:[NSString class]])
			{
				oxpVersionComponents = ComponentsFromVersionString(maxVersion);
				if (NSOrderedDescending == CompareVersions(ooVersionComponents, oxpVersionComponents))  OK = NO;
			}
			else
			{
				OOLog(@"requirements.wrongType", @"Expected requires.plist entry \"%@\" to be string, but got %@ in OXP %@.", @"max_version", [requirements class], [path lastPathComponent]);
				OK = NO;
			}
		}
	}
	
	if (OK && conditionsHandled < [requirements count])
	{
		// There are unknown requirement keys - don't support. NOTE: this check was not made pre 1.69!
		OOLog(@"requirements.unknown", @"requires.plist for OXP %@ contains unknown keys, rejecting.", [path lastPathComponent]);
		OK = NO;
	}
	
	return OK;
}


+ (void) addErrorWithKey:(NSString *)descriptionKey param1:(id)param1 param2:(id)param2
{
	if (descriptionKey != nil)
	{
		if (sErrors == nil)  sErrors = [[NSMutableArray alloc] init];
		[sErrors addObject:[NSArray arrayWithObjects:descriptionKey, param1 ?: (id)@"", param2 ?: (id)@"", nil]];
	}
}


+ (void)checkCacheUpToDateForPaths:(NSArray *)searchPaths
{
	/*	Check if caches are up to date.
		The strategy is to use a two-entry cache. One entry is an array
		containing the search paths, the other an array of modification dates
		(in the same order). If either fails to match the correct settings,
		we delete both.
	*/
	OOCacheManager		*cacheMgr = [OOCacheManager sharedCache];
	NSFileManager		*fmgr = [NSFileManager defaultManager];
	BOOL				upToDate = YES;
	id					oldPaths = nil;
	NSMutableArray		*modDates = nil;
	NSEnumerator		*pathEnum = nil;
	NSString			*path = nil;
	id					modDate = nil;
	
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"always-flush-cache"])
	{
		OOLog(kOOLogCacheExplicitFlush, @"Cache explicitly flushed with always-flush-cache preference. Rebuilding from scratch.");
		upToDate = NO;
	}
	
	if (upToDate && [[UNIVERSE gameView] pollShiftKey])
	{
		OOLog(kOOLogCacheExplicitFlush, @"Cache explicitly flushed with shift key. Rebuilding from scratch.");
		upToDate = NO;
	}
	
	oldPaths = [cacheMgr objectForKey:kOOCacheKeySearchPaths inCache:kOOCacheSearchPathModDates];
	if (upToDate && ![oldPaths isEqual:searchPaths])
	{
		// OXPs added/removed
		if (oldPaths != nil) OOLog(kOOLogCacheStalePaths, @"Cache is stale (search paths have changed). Rebuilding from scratch.");
		upToDate = NO;
	}
	
	// Build modification date list. (We need this regardless of whether the search paths matched.)
	
	modDates = [NSMutableArray arrayWithCapacity:[searchPaths count]];
	for (pathEnum = [searchPaths objectEnumerator]; (path = [pathEnum nextObject]); )
	{
		modDate = [[fmgr fileAttributesAtPath:path traverseLink:YES] objectForKey:NSFileModificationDate];
		if (modDate != nil)
		{
			// Converts to double because I'm not sure the cache can deal with dates under GNUstep.
			modDate = [NSNumber numberWithDouble:[modDate timeIntervalSince1970]];
			[modDates addObject:modDate];
		}
	}
		
	if (upToDate && ![[cacheMgr objectForKey:kOOCacheKeyModificationDates inCache:kOOCacheSearchPathModDates] isEqual:modDates])
	{
		OOLog(kOOLogCacheStaleDates, @"Cache is stale (modification dates have changed). Rebuilding from scratch.");
		upToDate = NO;
	}
	
	if (!upToDate)
	{
		[cacheMgr clearAllCaches];
		[cacheMgr setObject:searchPaths forKey:kOOCacheKeySearchPaths inCache:kOOCacheSearchPathModDates];
		[cacheMgr setObject:modDates forKey:kOOCacheKeyModificationDates inCache:kOOCacheSearchPathModDates];
	}
	else OOLog(kOOLogCacheUpToDate, @"Data cache is up to date.");
}


+ (NSDictionary *)dictionaryFromFilesNamed:(NSString *)fileName
								  inFolder:(NSString *)folderName
								  andMerge:(BOOL) mergeFiles
{
	return [ResourceManager dictionaryFromFilesNamed:fileName inFolder:folderName mergeMode:mergeFiles ? MERGE_BASIC : MERGE_NONE cache:YES];
}


+ (NSDictionary *)dictionaryFromFilesNamed:(NSString *)fileName
								  inFolder:(NSString *)folderName
								 mergeMode:(OOResourceMergeMode)mergeMode
									 cache:(BOOL)cache
{
	id				result = nil;
	NSMutableArray	*results = nil;
	NSString		*cacheKey = nil;
	NSString		*mergeType = nil;
	OOCacheManager	*cacheMgr = [OOCacheManager sharedCache];
	NSEnumerator	*enumerator = nil;
	NSString		*path = nil;
	NSString		*dictPath = nil;
	NSDictionary	*dict = nil;
	
	if (fileName == nil)  return nil;
	
	switch (mergeMode)
	{
		case MERGE_NONE:
			mergeType = @"none";
			break;
		
		case MERGE_BASIC:
			mergeType = @"basic";
			break;
		
		case MERGE_SMART:
			mergeType = @"smart";
			break;
		
		default:
			OOLog(kOOLogParameterError, @"Unknown dictionary merge mode %u for %@. (This is an internal programming error, please report it.)", fileName, mergeMode);
			return nil;
	}
	
	if (cache)
	{
	
		if (folderName != nil)
		{
			cacheKey = [NSString stringWithFormat:@"%@/%@ merge:%@", folderName, fileName, mergeType];
		}
		else
		{
			cacheKey = [NSString stringWithFormat:@"%@ merge:%@", fileName, mergeType];
		}
		result = [cacheMgr objectForKey:cacheKey inCache:@"dictionaries"];
		if (result != nil)  return result;
	}
	
	if (mergeMode == MERGE_NONE)
	{
		// Find "last" matching dictionary
		for (enumerator = [ResourceManager reversePathEnumerator]; (path = [enumerator nextObject]); )
		{
			if (folderName != nil)
			{
				dictPath = [[path stringByAppendingPathComponent:folderName] stringByAppendingPathComponent:fileName];
				dict = OODictionaryFromFile(dictPath);
				if (dict != nil)  break;
			}
			dictPath = [path stringByAppendingPathComponent:fileName];
			dict = OODictionaryFromFile(dictPath);
			if (dict != nil)  break;
		}
		result = dict;
	}
	else
	{
		// Find all matching dictionaries
		results = [NSMutableArray array];
		for (enumerator = [ResourceManager pathEnumerator]; (path = [enumerator nextObject]); )
		{
			dictPath = [path stringByAppendingPathComponent:fileName];
			dict = OODictionaryFromFile(dictPath);
			if (dict != nil)  [results addObject:dict];
			if (folderName != nil)
			{
				dictPath = [[path stringByAppendingPathComponent:folderName] stringByAppendingPathComponent:fileName];
				dict = OODictionaryFromFile(dictPath);
				if (dict != nil)  [results addObject:dict];
			}
		}
		
		if ([results count] == 0)  return nil;
		
		// Merge result
		result = [NSMutableDictionary dictionary];
		
		for (enumerator = [results objectEnumerator]; (dict = [enumerator nextObject]); )
		{
			if (mergeMode == MERGE_SMART)  [result mergeEntriesFromDictionary:dict];
			else  [result addEntriesFromDictionary:dict];
		}
		result = [[result copy] autorelease];	// Make immutable
	}
	
	if (cache && result != nil)  [cacheMgr setObject:result forKey:cacheKey inCache:@"dictionaries"];
	
	return result;
}


+ (NSArray *) arrayFromFilesNamed:(NSString *)fileName inFolder:(NSString *)folderName andMerge:(BOOL) mergeFiles
{
	id				result = nil;
	NSMutableArray	*results = nil;
	NSString		*cacheKey = nil;
	OOCacheManager	*cache = [OOCacheManager sharedCache];
	NSEnumerator	*enumerator = nil;
	NSString		*path = nil;
	NSString		*arrayPath = nil;
	NSMutableArray	*array = nil;
	NSArray			*arrayNonEditable = nil;
	
	if (fileName == nil)  return nil;
	
	cacheKey = [NSString stringWithFormat:@"%@%@ merge:%@", (folderName != nil) ? [folderName stringByAppendingString:@"/"] : (NSString *)@"", fileName, mergeFiles ? @"yes" : @"no"];
	result = [cache objectForKey:cacheKey inCache:@"arrays"];
	if (result != nil)  return result;
	
	if (!mergeFiles)
	{
		// Find "last" matching array
		for (enumerator = [ResourceManager reversePathEnumerator]; (path = [enumerator nextObject]); )
		{
			if (folderName != nil)
			{
				arrayPath = [[path stringByAppendingPathComponent:folderName] stringByAppendingPathComponent:fileName];
				arrayNonEditable = OOArrayFromFile(arrayPath);
				if (arrayNonEditable != nil)  break;
			}
			arrayPath = [path stringByAppendingPathComponent:fileName];
			arrayNonEditable = OOArrayFromFile(arrayPath);
			if (arrayNonEditable != nil)  break;
		}
		result = arrayNonEditable;
	}
	else
	{
		// Find all matching arrays
		results = [NSMutableArray array];
		for (enumerator = [ResourceManager pathEnumerator]; (path = [enumerator nextObject]); )
		{
			arrayPath = [path stringByAppendingPathComponent:fileName];
			array = [[OOArrayFromFile(arrayPath) mutableCopy] autorelease];
			if (array != nil) [results addObject:array];
	
			// Special handling for arrays merging. Currently, equipment.plist only gets its objects merged.
			// A lookup index is required. For the equipment.plist items, this is the index corresponging to the
			// EQ_* string, which describes the role of an equipment item and is unique.
			if ([array count] != 0 && [[array objectAtIndex:0] isKindOfClass:[NSArray class]])
			{
				if ([[fileName lowercaseString] isEqualToString:@"equipment.plist"])
					[self handleEquipmentListMerging:results forLookupIndex:3]; // Index 3 is the role string (EQ_*).
			}
			if (folderName != nil)
			{
				arrayPath = [[path stringByAppendingPathComponent:folderName] stringByAppendingPathComponent:fileName];
				array = [[OOArrayFromFile(arrayPath) mutableCopy] autorelease];
				if (array != nil)  [results addObject:array];
				
				if ([array count] != 0 && [[array objectAtIndex:0] isKindOfClass:[NSArray class]])
				{
					if ([[fileName lowercaseString] isEqualToString:@"equipment.plist"])
						[self handleEquipmentListMerging:results forLookupIndex:3]; // Index 3 is the role string (EQ_*).
				}
			}
		}
		
		if ([results count] == 0)  return nil;
		
		// Merge result
		result = [NSMutableArray array];
		
		for (enumerator = [results objectEnumerator]; (array = [enumerator nextObject]); )
		{
			[result addObjectsFromArray:array];
		}
		result = [[result copy] autorelease];	// Make immutable
	}
	
	if (result != nil)  [cache setObject:result forKey:cacheKey inCache:@"arrays"];
	
	return [NSArray arrayWithArray:result];
}


// A method for handling merging of arrays. Currently used with the equipment.plist entries.
// The arrayToProcess array is scanned for repetitions of the item at lookup index location and, if found,
// the latest entry replaces the earliest.
+ (void) handleEquipmentListMerging: (NSMutableArray *)arrayToProcess forLookupIndex:(unsigned)lookupIndex
{
	unsigned i,j,k;
	NSMutableArray *refArray = [arrayToProcess objectAtIndex:[arrayToProcess count] - 1];
	
	// Any change to arrayRef will directly modify arrayToProcess.
	
	for (i = 0; i < [refArray count]; i++)
	{
		for (j = 0; j < [arrayToProcess count] - 1; j++)
		{
			for (k=0; k < [[arrayToProcess objectAtIndex:j] count] - 1; k++)
			{
				id processValue = [[[arrayToProcess objectAtIndex:j] objectAtIndex:k] objectAtIndex:lookupIndex defaultValue:nil];
				id refValue = [[refArray objectAtIndex:i] objectAtIndex:lookupIndex defaultValue:nil];
				
				if ([processValue isEqual:refValue])
				{
					[[arrayToProcess objectAtIndex:j] replaceObjectAtIndex:k withObject:[refArray objectAtIndex:i]];
					[refArray removeObjectAtIndex:i];
				}
			}
		}
	}
	// arrayToProcess has been processed at this point. Any necessary merging has been done.
}


+ (NSDictionary *) whitelistDictionary
{
	static id				whitelistDictionary = nil;
	NSString				*path = nil;
	
	if (whitelistDictionary == nil)
	{
		path = [[[ResourceManager builtInPath] stringByAppendingPathComponent:@"Config"] stringByAppendingPathComponent:@"whitelist.plist"];
		whitelistDictionary = [NSDictionary dictionaryWithContentsOfFile:path];
		if (whitelistDictionary == nil)  whitelistDictionary = [NSNull null];
		
		[whitelistDictionary retain];
	}
	
	if (whitelistDictionary == [NSNull null])  return nil;
	return whitelistDictionary;
}


+ (NSString *) pathForFileNamed:(NSString *)fileName inFolder:(NSString *)folderName
{
	NSString		*result = nil;
	NSString		*cacheKey = nil;
	OOCacheManager	*cache = [OOCacheManager sharedCache];
	NSEnumerator	*pathEnum = nil;
	NSString		*path = nil;
	NSString		*filePath = nil;
	NSFileManager	*fmgr = nil;
	
	if (fileName == nil)  return nil;
	
	if (folderName != nil)  cacheKey = [NSString stringWithFormat:@"%@/%@", folderName, fileName];
	else  cacheKey = fileName;
	result = [cache objectForKey:cacheKey inCache:@"resolved paths"];
	if (result != nil)  return result;
	
	// Search for file
	fmgr = [NSFileManager defaultManager];
	for (pathEnum = [[ResourceManager paths] reverseObjectEnumerator]; (path = [pathEnum nextObject]); )
	{
		filePath = [[path stringByAppendingPathComponent:folderName] stringByAppendingPathComponent:fileName];
		if ([fmgr fileExistsAtPath:filePath])
		{
			result = filePath;
			break;
		}
		
		filePath = [path stringByAppendingPathComponent:fileName];
		if ([fmgr fileExistsAtPath:filePath])
		{
			result = filePath;
			break;
		}
	}
	
	if (result != nil)
	{
		OOLog(@"resourceManager.foundFile", @"Found %@/%@ at %@", folderName, fileName, filePath);
		[cache setPruneThreshold:500 forCache:@"resolved paths"];
		[cache setObject:result forKey:cacheKey inCache:@"resolved paths"];
	}
	return result;
}


+ (id) retrieveFileNamed:(NSString *)fileName inFolder:(NSString *)folderName cache:(NSMutableDictionary **)ioCache key:(NSString *)key class:(Class)class
{
	id				result = nil;
	NSString		*path = nil;
	
	if (ioCache)
	{
		if (key == nil)  key = [NSString stringWithFormat:@"%@:%@", folderName, fileName];
		if (*ioCache != nil)
		{
			// return the cached object, if any
			result = [*ioCache objectForKey:key];
			if (result)  return result;
		}
	}
	
	path = [self pathForFileNamed:fileName inFolder:folderName];
	if (path != nil)  result = [[[class alloc] initWithContentsOfFile:path] autorelease];
	
	if (result != nil && ioCache != NULL)
	{
		if (*ioCache == nil)  *ioCache = [[NSMutableDictionary alloc] init];
		[*ioCache setObject:result forKey:key];
	}
	
	return result;
}


+ (OOMusic *) ooMusicNamed:(NSString *)fileName inFolder:(NSString *)folderName
{
	return [self retrieveFileNamed:fileName
						  inFolder:folderName
							 cache:NULL	// Don't cache music objects; minimizing latency isn't really important.
							   key:[NSString stringWithFormat:@"OOMusic:%@:%@", folderName, fileName]
							 class:[OOMusic class]];
}


+ (OOSound *) ooSoundNamed:(NSString *)fileName inFolder:(NSString *)folderName
{
	return [self retrieveFileNamed:fileName
						  inFolder:folderName
							 cache:&sound_cache
							   key:[NSString stringWithFormat:@"OOSound:%@:%@", folderName, fileName]
							 class:[OOSound class]];
}

+ (NSString *) stringFromFilesNamed:(NSString *)fileName inFolder:(NSString *)folderName
{
	return [self retrieveFileNamed:fileName
						  inFolder:folderName
							 cache:&string_cache
							   key:nil
							 class:[NSString class]];
}


+ (NSDictionary *)loadScripts
{
	NSMutableDictionary			*loadedScripts = nil;
	NSArray						*results = nil;
	NSArray						*paths = nil;
	NSEnumerator				*pathEnum = nil;
	NSString					*path = nil;
	NSEnumerator				*scriptEnum = nil;
	OOScript					*script = nil;
	NSString					*name = nil;
	NSAutoreleasePool			*pool = nil;
	
	loadedScripts = [NSMutableDictionary dictionary];
	paths = [ResourceManager paths];
	for (pathEnum = [paths objectEnumerator]; (path = [pathEnum nextObject]); )
	{
		pool = [[NSAutoreleasePool alloc] init];
		
		NS_DURING
			results = [OOScript worldScriptsAtPath:[path stringByAppendingPathComponent:@"Config"]];
			if (results == nil) results = [OOScript worldScriptsAtPath:path];
			if (results != nil)
			{
				for (scriptEnum = [results objectEnumerator]; (script = [scriptEnum nextObject]); )
				{
					name = [script name];
					if (name != nil)  [loadedScripts setObject:script forKey:name];
					else  OOLog(@"script.load.unnamed", @"Discarding anonymous script %@", script);
				}
			}
		NS_HANDLER
			OOLog(@"script.load.exception", @"***** %s encountered exception %@ (%@) while trying to load script from %@ -- ignoring this location.", __FUNCTION__, [localException name], [localException reason], path);
			// Ignore exception and keep loading other scripts.
		NS_ENDHANDLER
		
		[pool release];
	}
	
	if (OOLogWillDisplayMessagesInClass(@"script.load.world.listAll"))
	{
		unsigned count = [loadedScripts count];
		if (count != 0)
		{
			NSMutableArray		*displayNames = nil;
			NSEnumerator		*scriptEnum = nil;
			OOScript			*script = nil;
			NSString			*displayString = nil;
			
			displayNames = [NSMutableArray arrayWithCapacity:count];
			
			for (scriptEnum = [loadedScripts objectEnumerator]; (script = [scriptEnum nextObject]); )
			{
				[displayNames addObject:[script displayName]];
			}
			
			displayString = [[displayNames sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)] componentsJoinedByString:@", "];
			OOLog(@"script.load.world.listAll", @"Loaded %u world scripts: %@", count, displayString);
		}
		else
		{
			OOLog(@"script.load.world.listAll", @"*** No world scripts loaded.");
		}
	}
	
	return loadedScripts;
}


+ (BOOL) writeDiagnosticData:(NSData *)data toFileNamed:(NSString *)name
{
	NSString			*basePath = nil;
	
	if (data == nil || name == nil)  return NO;
	
	basePath = [self diagnosticFileLocation];
	if (basePath == nil)  return NO;
	
	return [data writeToFile:[basePath stringByAppendingPathComponent:name] atomically:YES];
}


+ (BOOL)directoryExists:(NSString *)inPath create:(BOOL)inCreate
{
	BOOL				exists, directory;
	NSFileManager		*fmgr =  [NSFileManager defaultManager];
	
	exists = [fmgr fileExistsAtPath:inPath isDirectory:&directory];
	
	if (exists && !directory)
	{
		OOLog(@"resourceManager.write.buildPath.failed", @"Expected %@ to be a folder, but it is a file.", inPath);
		return NO;
	}
	if (!exists)
	{
		if (!inCreate) return NO;
		if (![fmgr createDirectoryAtPath:inPath attributes:nil])
		{
			OOLog(@"resourceManager.write.buildPath.failed", @"Could not create folder %@.", inPath);
			return NO;
		}
	}
	
	return YES;
}


+ (NSString *) diagnosticFileLocation
{
	return OOLogHandlerGetLogBasePath();
}

@end
