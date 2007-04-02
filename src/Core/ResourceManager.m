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
NSMutableDictionary*	dictionary_cache;
NSMutableDictionary*	array_cache;
NSMutableDictionary*	image_cache;
NSMutableDictionary*	sound_cache;
NSMutableDictionary*	string_cache;
NSMutableDictionary*	movie_cache;
#ifdef GNUSTEP
NSMutableDictionary*	surface_cache;
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


+ (id) retrieveFileNamed:(NSString *)inFileName inFolder:(NSString *)inFolderName cache:(NSMutableDictionary **)ioCache key:(NSString *)inKey class:(Class)inClass
{
	OOMusic			*result = nil;
	NSString		*foundPath = nil;
	NSArray			*fpaths;
	int				i;
	
	if (!inFileName) return nil;
	
	if (ioCache)
	{
		if (!inKey) inKey = [NSString stringWithFormat:@"%@:%@", inFolderName, inFileName];
		if (!*ioCache) *ioCache = [[NSMutableDictionary alloc] initWithCapacity:32];
		else
		{
			// return the cached object, if any
			result = [*ioCache objectForKey:inKey];
			if (result) return result;
		}
	}
	
	fpaths = [ResourceManager paths];
	
	for (i = 0; i < [fpaths count]; i++)
	{
		NSString *filepath = [(NSString *)[fpaths objectAtIndex:i] stringByAppendingPathComponent:inFileName];
		if ([[NSFileManager defaultManager] fileExistsAtPath:filepath])
		{
			foundPath = filepath;
		}
		if (inFolderName)
		{
			filepath = [[(NSString *)[fpaths objectAtIndex:i] stringByAppendingPathComponent:inFolderName] stringByAppendingPathComponent:inFileName];
			if ([[NSFileManager defaultManager] fileExistsAtPath:filepath])
			{
				foundPath = filepath;
			}
		}
	}
	
	if (foundPath) result = [[[inClass alloc] initWithContentsOfFile:foundPath] autorelease];
	if (result && ioCache)
	{
		[(*ioCache) setObject:result forKey:inKey];
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


#ifndef GNUSTEP

+ (NSImage *) imageNamed:(NSString *)filename inFolder:(NSString *)foldername
{
	return [self retrieveFileNamed:filename
				 inFolder:foldername
				 cache:&image_cache
				 key:nil
				 class:[NSImage class]];
}

#endif

+ (NSString *) stringFromFilesNamed:(NSString *)filename inFolder:(NSString *)foldername
{
	return [self retrieveFileNamed:filename
				 inFolder:foldername
				 cache:&string_cache
				 key:nil
				 class:[NSString class]];
}

#ifdef GNUSTEP
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


#if OLD_SCRIPT_CODE

+ (NSDictionary *) loadScripts
{
	NSMutableArray *results = [NSMutableArray arrayWithCapacity:16];
	NSMutableArray *fpaths = [ResourceManager paths];
	NSString *foldername = [NSString stringWithString:@"Config"];
	NSString *filename = [NSString stringWithString:@"script.plist"];

	int i;

	NSString* dict_key = [NSString stringWithFormat:@"%@:%@", foldername, filename];
	if (!dictionary_cache)
		dictionary_cache = [[NSMutableDictionary alloc] initWithCapacity:32];
	if ([dictionary_cache objectForKey:dict_key])
	{
		return [NSDictionary dictionaryWithDictionary:(NSDictionary *)[dictionary_cache objectForKey:dict_key]];	// return the cached dictionary
	}

	for (i = 0; i < [fpaths count]; i++)
	{
		NSString *xfilepath = [(NSString *)[fpaths objectAtIndex:i] stringByAppendingPathComponent:filename];
		NSString *filepath = [NSMutableString stringWithString:xfilepath];

		filepath = [[filepath stringByDeletingPathExtension] stringByAppendingPathExtension:@"oos"];
		
		if ([[NSFileManager defaultManager] fileExistsAtPath:filepath])
		{
			// load and compile oos script
			NSLog(@"trying to load and parse %@", filepath);
			NSString *script = [NSString stringWithContentsOfFile:filepath];
			NSDictionary *scriptDict = ParseOOSScripts(script);
			if (scriptDict)  [results addObject:scriptDict];
		}
		else
		{
			filepath = [[filepath stringByDeletingPathExtension] stringByAppendingPathExtension:@"plist"];
			// All this code replicated from dictionaryFromFileNamed because that method
			// will traverse all possible locations and any oos files that co-exist with
			// plist files will probably get their entries overwritten.
			//
			// This can be simplified if we make a rule that it is a configuration error
			// that isn't handled if there is a script.oos and script.plist file in
			// the same place. But that probably isn't realistic.
			NSDictionary* found_dic = OODictionaryFromFile(filepath);
			if (found_dic)  [results addObject:found_dic];
		}
		if (foldername)
		{
			xfilepath = [[(NSString *)[fpaths objectAtIndex:i] stringByAppendingPathComponent:foldername] stringByAppendingPathComponent:filename];
			filepath = [[xfilepath stringByDeletingPathExtension] stringByAppendingPathExtension:@"oos"];
			if ([[NSFileManager defaultManager] fileExistsAtPath:filepath])
			{
				// load and compile oos script
				NSLog(@"trying to load and compile %@", filepath);
				NSString *script = [NSString stringWithContentsOfFile:filepath];
				NSDictionary *scriptDict = ParseOOSScripts(script);
				if (scriptDict) {
					[results addObject:scriptDict];
				}
			}
			else
			{
				filepath = [[filepath stringByDeletingPathExtension] stringByAppendingPathExtension:@"plist"];
				NSDictionary* found_dic = OODictionaryFromFile(filepath);
				if (found_dic)  [results addObject:found_dic];
			}
		}
	}
	if ([results count] == 0)
		return nil;

	// got results we may want to cache
	//
	NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:128];
	for (i = 0; i < [results count]; i++)
	{
		[result addEntriesFromDictionary:(NSDictionary *)[results objectAtIndex:i]];
	}
	//
	if (result) {
		[dictionary_cache setObject:result forKey:dict_key];
	}

	return [NSDictionary dictionaryWithDictionary:result];
}

#else

// New OOScript-based code. Result is dictionary of names -> OOScripts.

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

#endif

@end
