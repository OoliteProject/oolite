/*

ResourceManager.m

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

#import "ResourceManager.h"
#import "NSScannerOOExtensions.h"
#import "NSMutableDictionaryOOExtensions.h"
#import "OOSound.h"
#import "OOCacheManager.h"
#import "Universe.h"
#import "OOStringParsing.h"
#import "OOPListParsing.h"

#import "OOJSScript.h"
#import "OOPListScript.h"

#define kOOLogUnconvertedNSLog @"unclassified.ResourceManager"


static NSString * const kOOLogCacheUpToDate				= @"dataCache.upToDate";
static NSString * const kOOLogCacheStalePaths			= @"dataCache.rebuild.pathsChanged";
static NSString * const kOOLogCacheStaleDates			= @"dataCache.rebuild.datesChanged";
static NSString * const kOOCacheSearchPathModDates		= @"search path modification dates";
static NSString * const kOOCacheKeySearchPaths			= @"search paths";
static NSString * const kOOCacheKeyModificationDates	= @"modification dates";


extern NSDictionary* ParseOOSScripts(NSString* script);


@interface ResourceManager (OOPrivate)

+ (void)checkPotentialPath:(NSString *)path :(NSMutableArray *)searchPaths;
+ (BOOL)areRequirementsFulfilled:(NSDictionary*)requirements forOXP:(NSString *)path;
+ (void)addError:(NSString *)error;
+ (void)checkCacheUpToDateForPaths:(NSArray *)searchPaths;

@end


static NSMutableArray	*sSearchPaths;
static BOOL				sUseAddOns = YES;
static NSMutableArray	*sExternalPaths;
static NSMutableString	*errors;

// caches allow us to load any given file once only
//
static NSMutableDictionary*	dictionary_cache;
static NSMutableDictionary*	array_cache;
static NSMutableDictionary*	sound_cache;
static NSMutableDictionary*	string_cache;
static NSMutableDictionary*	genericPathCache;
#if OOLITE_MAC_OS_X && !OOLITE_SDL
static NSMutableDictionary*	image_cache;
#elif OOLITE_SDL
static NSMutableDictionary*	surface_cache;
#endif


@implementation ResourceManager

+ (NSString *) errors
{
	return errors;
}


+ (NSArray *)rootPaths
{
	static NSArray			*sRootPaths = nil;
	
	if (sRootPaths == nil)
	{
		#ifdef WIN32
			NSString	*app_addon_path = @"AddOns";
			NSString	*appsupport_path=nil;
			NSString	*nix_path=nil;
		#else
			NSString*	app_addon_path = [[[[NSBundle mainBundle] bundlePath]
										stringByDeletingLastPathComponent]
										stringByAppendingPathComponent:@"AddOns"];
			NSString*	appsupport_path = [[[[NSHomeDirectory()
											stringByAppendingPathComponent:@"Library"]
											stringByAppendingPathComponent:@"Application Support"]
											stringByAppendingPathComponent:@"Oolite"]
											stringByAppendingPathComponent:@"AddOns"];
			NSString*	nix_path = [[NSHomeDirectory()
									stringByAppendingPathComponent:@".Oolite"]
									stringByAppendingPathComponent:@"AddOns"];
		#endif
			
		sRootPaths = [[NSArray alloc] initWithObjects:[self builtInPath], app_addon_path, appsupport_path, nix_path, nil];
	}
	
	return sRootPaths;
}


+ (NSString *)builtInPath
{
	#ifdef WIN32
		return @"oolite.app/Resources";
	#else
		static NSString *sBuiltInPath = nil;
		
		if (sBuiltInPath == nil)
		{
			sBuiltInPath = [[[[[NSBundle mainBundle] bundlePath]
								stringByAppendingPathComponent:@"Contents"]
								stringByAppendingPathComponent:@"Resources"] retain];
		}
		
		return sBuiltInPath;
	#endif
}


+ (NSArray *)pathsWithAddOns
{
	if (sSearchPaths != nil)  return sSearchPaths;
	
	[errors release];
	errors = nil;
	
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
	return sUseAddOns ? [self pathsWithAddOns] : [NSArray arrayWithObject:[self builtInPath]];
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
	if (!sSearchPaths == nil)  sSearchPaths = [[NSMutableArray alloc] init];
	if (![sSearchPaths containsObject:path])
	{
		[sSearchPaths addObject:path];
		
		if (sExternalPaths == nil)  sExternalPaths = [[NSMutableArray alloc] init];
		[sExternalPaths addObject:path];
	}
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
		OOLog(@"oxp.versionMismatch", @"ERROR: OXP %@ is incompatible with version %@ of Oolite.", path, version);
		[self addError:[NSString stringWithFormat:@"\t'%@' is incompatible with version %@ of Oolite", [path lastPathComponent], version]];
	}
}


+ (BOOL) areRequirementsFulfilled:(NSDictionary*)requirements forOXP:(NSString *)path
{
	BOOL				result = YES;
	NSString			*requiredVersion;
	
	if (requirements == nil)  return YES;
	
	if (result)
	{
		requiredVersion = [requirements objectForKey:@"version"];
		if (requiredVersion != nil)
		{
			if ([requiredVersion isKindOfClass:[NSString class]])
			{
				static NSArray	*ooVersionComponents = nil;
				NSArray			*oxpVersionComponents = nil;
				
				if (ooVersionComponents == nil)
				{
					ooVersionComponents = ComponentsFromVersionString([[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]);
				}
				
				oxpVersionComponents = ComponentsFromVersionString([requirements objectForKey:@"version"]);
				if (NSOrderedAscending == CompareVersions(ooVersionComponents, oxpVersionComponents))  result = NO;
			}
			else
			{
				OOLog(@"plist.wrongType", @"Expected requires.plist entry \"version\" to be string, but got %@ in OXP %@.", [requirements class], [path lastPathComponent]);
				result = NO;
			}
		}
	}
	
	return result;
}


+ (void)addError:(NSString *)error
{
	if (error != nil)
	{
		if (errors)
		{
			[errors appendFormat:@"\n%@", error];
		}
		else
		{
			errors = [error mutableCopy];
		}
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
	
	oldPaths = [cacheMgr objectForKey:kOOCacheKeySearchPaths inCache:kOOCacheSearchPathModDates];
	if (![oldPaths isEqual:searchPaths])
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


+ (NSDictionary *) dictionaryFromFilesNamed:(NSString *)filename inFolder:(NSString *)foldername andMerge:(BOOL) mergeFiles
{
	return [ResourceManager dictionaryFromFilesNamed:filename inFolder:foldername andMerge:mergeFiles smart:NO];
}


+ (NSDictionary *) dictionaryFromFilesNamed:(NSString *)filename inFolder:(NSString *)foldername andMerge:(BOOL) mergeFiles smart:(BOOL) smartMerge
{
	NSMutableArray	*results = [NSMutableArray arrayWithCapacity:16];
	NSArray			*fpaths = [ResourceManager paths];
	int i;
	if (!filename)
		return nil;
	
	NSString* dict_key = [NSString stringWithFormat:@"%@:%@", foldername, filename];
	if (!dictionary_cache)
		dictionary_cache = [[NSMutableDictionary alloc] initWithCapacity:32];
	if ([dictionary_cache objectForKey:dict_key])
	{
		return [[[dictionary_cache objectForKey:dict_key] copy] autorelease];	// return the cached dictionary
	}
	
	for (i = 0; i < [fpaths count]; i++)
	{
		NSString *filepath = [(NSString *)[fpaths objectAtIndex:i] stringByAppendingPathComponent:filename];
		
		NSDictionary* found_dic = OODictionaryFromFile(filepath);
		if (found_dic)  [results addObject:found_dic];
		if (foldername)
		{
			filepath = [[(NSString *)[fpaths objectAtIndex:i] stringByAppendingPathComponent:foldername] stringByAppendingPathComponent:filename];
			NSDictionary* found_dic = OODictionaryFromFile(filepath);
			if (found_dic)  [results addObject:found_dic];
		}
	}
	if ([results count] == 0)
		return nil;
		
	// got results we may want to cache
	//
	NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:128];
	if (!mergeFiles)
	{
		[result addEntriesFromDictionary:(NSDictionary *)[results objectAtIndex:[results count] - 1]];// the last loaded file
	}
	else
	{
		for (i = 0; i < [results count]; i++)
		{
			if (smartMerge)
				[result mergeEntriesFromDictionary:(NSDictionary *)[results objectAtIndex:i]];
			else
				[result addEntriesFromDictionary:(NSDictionary *)[results objectAtIndex:i]];
		}
	}	
	//
	if (result)  [dictionary_cache setObject:result forKey:dict_key];
		
	return [NSDictionary dictionaryWithDictionary:result];
}

+ (NSArray *) arrayFromFilesNamed:(NSString *)filename inFolder:(NSString *)foldername andMerge:(BOOL) mergeFiles
{
	NSMutableArray	*results = [NSMutableArray arrayWithCapacity:16];
	NSArray			*fpaths = [ResourceManager paths];
	int i;
	if (!filename)
		return nil;

	NSString* array_key = [NSString stringWithFormat:@"%@:%@", foldername, filename];
	if (!array_cache)
		array_cache = [[NSMutableDictionary alloc] initWithCapacity:32];
	if ([array_cache objectForKey:array_key])
		return [NSArray arrayWithArray:(NSArray *)[array_cache objectForKey:array_key]];	// return the cached array
	
	for (i = 0; i < [fpaths count]; i++)
	{
		NSString *filepath = [(NSString *)[fpaths objectAtIndex:i] stringByAppendingPathComponent:filename];
		
		NSArray* found_array = OOArrayFromFile(filepath);
		if (found_array)  [results addObject:found_array];
		
		if (foldername)
		{
			filepath = [[(NSString *)[fpaths objectAtIndex:i] stringByAppendingPathComponent:foldername] stringByAppendingPathComponent:filename];
			
			NSArray* found_array = OOArrayFromFile(filepath);
			if (found_array)  [results addObject:found_array];
		}
	}
	if ([results count] == 0)
		return nil;
	
	// got results we may want to cache
	//
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:128];
	if (!mergeFiles)
	{
		[result addObjectsFromArray:(NSArray *)[results objectAtIndex:[results count] - 1]];	// last loaded file
	}
	else
	{
		for (i = 0; i < [results count]; i++)
			[result addObjectsFromArray:(NSArray *)[results objectAtIndex:i]];
	}	
	if (result)
		[array_cache setObject:result forKey:array_key];
	
	return [NSArray arrayWithArray:result];
}


+ (NSString *) pathForFileNamed:(NSString *)fileName inFolder:(NSString *)folderName
{
	NSString		*key = nil;
	NSString		*result = nil;
	NSEnumerator	*pathEnum = nil;
	NSString		*path = nil;
	NSString		*filePath = nil;
	NSFileManager	*fmgr = nil;
	
	if (fileName == nil)  return nil;
	
	key = [NSString stringWithFormat:@"%@:%@", folderName, fileName];
	if (genericPathCache != nil)
	{
		// return the cached object, if any
		result = [genericPathCache objectForKey:key];
		if (result)  return result;
	}
	
	// Search for file
	fmgr = [NSFileManager defaultManager];
	for (pathEnum = [[ResourceManager paths] objectEnumerator]; (path = [pathEnum nextObject]); )
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
		if (genericPathCache == nil)  genericPathCache = [[NSMutableDictionary alloc] init];
		[genericPathCache setObject:result forKey:key];
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
	
	if (result != nil && ioCache != nil)
	{
		if (*ioCache == nil)  *ioCache = [[NSMutableDictionary alloc] init];
		[*ioCache setObject:result forKey:key];
	}
	
	return result;
}


+ (OOMusic *) ooMusicNamed:(NSString *)filename inFolder:(NSString *)foldername
{
	return [self retrieveFileNamed:filename
				 inFolder:foldername
				 cache:&sound_cache
				 key:[NSString stringWithFormat:@"OOMusic:%@:%@", foldername, filename]
				 class:[OOMusic class]];
}


+ (OOSound *) ooSoundNamed:(NSString *)filename inFolder:(NSString *)foldername
{
	return [self retrieveFileNamed:filename
				 inFolder:foldername
				 cache:&sound_cache
				 key:[NSString stringWithFormat:@"OOSound:%@:%@", foldername, filename]
				 class:[OOSound class]];
}

+ (NSString *) stringFromFilesNamed:(NSString *)filename inFolder:(NSString *)foldername
{
	return [self retrieveFileNamed:filename
				 inFolder:foldername
				 cache:&string_cache
				 key:nil
				 class:[NSString class]];
}


#if OOLITE_MAC_OS_X && !OOLITE_SDL

+ (NSImage *) imageNamed:(NSString *)filename inFolder:(NSString *)foldername
{
	return [self retrieveFileNamed:filename
				 inFolder:foldername
				 cache:&image_cache
				 key:nil
				 class:[NSImage class]];
}

#elif OOLITE_SDL

+ (SDLImage *) surfaceNamed:(NSString *)filename inFolder:(NSString *)foldername
{
	SDLImage *result = 0;
	SDL_Surface *surface;
	NSMutableArray *fpaths = [ResourceManager paths];
	NSString *finalFilename=nil;
	int i, r;
	r = 0;
	if (!filename)
		return 0;

	NSString* image_key = [NSString stringWithFormat:@"%@:%@", foldername, filename];
	if (!surface_cache)
		surface_cache = [[NSMutableDictionary alloc] initWithCapacity:32];
	if ([surface_cache objectForKey:image_key])
		return (SDLImage *)[surface_cache objectForKey:image_key];

	for (i = 0; i < [fpaths count]; i++)
	{
		NSString *filepath = [(NSString *)[fpaths objectAtIndex:i] stringByAppendingPathComponent:filename];
		if ([[NSFileManager defaultManager] fileExistsAtPath:filepath])
		{
			//if (surface != 0)
			//	SDL_FreeSurface(surface);
			//surface = IMG_Load([filepath cString]);
			finalFilename = [NSString stringWithString: filepath];
			r++;
		}
		if (foldername)
		{
			filepath = [[(NSString *)[fpaths objectAtIndex:i] stringByAppendingPathComponent:foldername] stringByAppendingPathComponent:filename];
			if ([[NSFileManager defaultManager] fileExistsAtPath:filepath])
			{
				//if (surface != 0)
				//	SDL_FreeSurface(surface);
				//surface = IMG_Load([filepath cString]);
				finalFilename = [NSString stringWithString: filepath];
				r++;
			}
		}
	}

	if (finalFilename != nil)
	{
		surface = IMG_Load([finalFilename cString]);
		result = [[SDLImage alloc] initWithSurface: surface];
		[surface_cache setObject:result forKey:image_key];
	}

	return result;
}

#endif


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

@end
