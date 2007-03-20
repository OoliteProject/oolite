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


static NSString * const kOOLogDumpSearchPaths			= @"searchPaths.dumpAll";
static NSString * const kOOLogCacheUpToDate				= @"dataCache.upToDate";
static NSString * const kOOLogCacheStalePaths			= @"dataCache.rebuild.pathsChanged";
static NSString * const kOOLogCacheStaleDates			= @"dataCache.rebuild.datesChanged";
static NSString * const kOOCacheSearchPathModDates		= @"search path modification dates";
static NSString * const kOOCacheKeySearchPaths			= @"search paths";
static NSString * const kOOCacheKeyModificationDates	= @"modification dates";


extern NSDictionary* parseScripts(NSString* script);

@implementation ResourceManager

static  NSMutableArray* saved_paths;
static  NSMutableArray* paths_to_load;
static  NSString* errors;

- (id) init
{
	self = [super init];
	always_include_addons = YES;
	paths = [[ResourceManager paths] retain];
	errors = nil;
	return self;
}

- (id) initIncludingAddOns: (BOOL) include_addons;
{
	self = [super init];
	always_include_addons = include_addons;
	paths = [[ResourceManager paths] retain];
	errors = nil;
	return self;
}

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

- (void) dealloc
{
	if (paths)	[paths release];
	
//	if (dictionary_cache)	[dictionary_cache release];
//	if (array_cache)		[array_cache release];
//	if (image_cache)		[image_cache release];
//	if (sound_cache)		[sound_cache release];
	
	[super dealloc];
}

+ (NSString *) errors
{
	return errors;
}

+ (NSMutableArray *) paths
{
	return [ResourceManager pathsUsingAddOns:always_include_addons];
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


+ (NSMutableArray *) pathsUsingAddOns:(BOOL) include_addons
{
	// check if we need to clear the caches
	if (always_include_addons != include_addons)
	{
		// clear the caches
		if (dictionary_cache)	[dictionary_cache release];
		if (array_cache)		[array_cache release];
		if (image_cache)		[image_cache release];
		if (sound_cache)		[sound_cache release];
		if (string_cache)		[string_cache release];
		if (movie_cache)		[movie_cache release];
		dictionary_cache = nil;
		array_cache = nil;
		image_cache = nil;
		sound_cache = nil;
		string_cache = nil;
		movie_cache = nil;
		// set flag for further accesses
		always_include_addons = include_addons;
		//
		[saved_paths release];
		saved_paths = nil;
	}
	//
	int i;
	if (saved_paths)
		return saved_paths;
	if (errors)
	{
		[errors release];
		errors = nil;
	}
	
	NSFileManager *fmgr = [NSFileManager defaultManager];
	
#ifdef WIN32
	NSString	*app_path = @"oolite.app/Contents/Resources";
	NSString	*app_addon_path = @"AddOns";
	NSString	*appsupport_path=nil;
	NSString	*nix_path=nil;
#else
	NSString*	app_path = [[[[NSBundle mainBundle] bundlePath]
								stringByAppendingPathComponent:@"Contents"]
								stringByAppendingPathComponent:@"Resources"];
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
	//
	// set up the default locations to look for expansion packs
	NSArray*	extra_paths = [NSArray arrayWithObjects: app_addon_path, appsupport_path, nix_path, nil];
	//
	NSMutableArray *file_paths = [NSMutableArray arrayWithCapacity:16];
	//
	[file_paths addObject: app_path];
	[file_paths addObjectsFromArray: extra_paths];
	//
	if (include_addons)
	{
		NSMutableArray*	possibleExpansionPaths = [NSMutableArray arrayWithCapacity: 16];
		//
		// check the default locations for expansion packs..
		for (i = 0; i < [extra_paths count]; i++)
		{
			NSString*		addon_path = (NSString*)[extra_paths objectAtIndex: i];
			NSArray*		possibleExpansions = [fmgr directoryContentsAtPath: addon_path];
			int j;
			for (j = 0; j < [possibleExpansions count]; j++)
			{
				NSString*	item = (NSString *)[possibleExpansions objectAtIndex: j];
				if (([[item pathExtension] isEqual:@"oxp"])||([[item pathExtension] isEqual:@"oolite_expansion_pack"]))
				{
					BOOL dir_test = NO;
					NSString*	possibleExpansionPath = [addon_path stringByAppendingPathComponent:item];
					[fmgr fileExistsAtPath:possibleExpansionPath isDirectory:&dir_test];
					if (dir_test)
						[possibleExpansionPaths addObject:possibleExpansionPath];
				}
			}
		}
		//
		if (paths_to_load)
			[possibleExpansionPaths addObjectsFromArray:paths_to_load];	// pre-checked as directories with the correct file extension
		//
		for (i = 0; i < [possibleExpansionPaths count]; i++)
		{
			NSString* possibleExpansionPath = (NSString *)[possibleExpansionPaths objectAtIndex:i];
			NSString* requiresPath = [possibleExpansionPath stringByAppendingPathComponent:@"requires.plist"];
			BOOL require_test = YES;
			BOOL failed_parsing = NO;
			// check for compatibility
			if ([fmgr fileExistsAtPath:requiresPath])
			{
				NSDictionary* requires_dic = [NSDictionary dictionaryWithContentsOfFile:requiresPath];
					
				require_test = [ResourceManager areRequirementsFulfilled:requires_dic];
			}
			if (require_test)
				[file_paths addObject:possibleExpansionPath];
			else
			{
				NSString* version = (NSString *)[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
				// NSBeep(); // AppKit
				if (!failed_parsing)
				{
					NSString* old_errors = errors;
					errors = [[NSString alloc] initWithFormat:@"%@\n\t'%@' requirements property list could not be parsed",old_errors, [possibleExpansionPath lastPathComponent]];
					[old_errors release];
				}
				else
				{
					NSLog(@"ERROR %@ is incompatible with this version %@ of Oolite",possibleExpansionPath,version);
					if (!errors)
						errors = [[NSString alloc] initWithFormat:@"\t'%@' is incompatible with version %@ of Oolite",[possibleExpansionPath lastPathComponent],version];
					else
					{
						NSString* old_errors = errors;
						errors = [[NSString alloc] initWithFormat:@"%@\n\t'%@' is incompatible with version %@ of Oolite",old_errors,[possibleExpansionPath lastPathComponent],version];
						[old_errors release];
					}
				}
			}
		}
	}
	//
	if (!saved_paths)
		saved_paths =[file_paths retain];
	
	OOLog(kOOLogDumpSearchPaths, @"---> searching paths:\n%@", file_paths);
	
	[self checkCacheUpToDateForPaths:file_paths];
	
	return file_paths;
}

+ (BOOL) areRequirementsFulfilled:(NSDictionary*) requirements
{
	if (!requirements)
		return YES;
	if ([requirements objectForKey:@"version"])
	{
		NSString* version = (NSString *)[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
		if ([version isLessThan:[requirements objectForKey:@"version"]])
			return NO;
	}
	return YES;
}

+ (void) addExternalPath:(NSString *)filename
{
	int i;
	if (!filename)
		return;
	if (!saved_paths)
		saved_paths = [[NSMutableArray alloc] initWithObjects: filename, nil];	//retained
	else
	{
		for (i = 0; i < [saved_paths count]; i++)
			if ([[saved_paths objectAtIndex:i] isEqual:filename])
				return;
		[saved_paths addObject:filename];
	}
	if (!paths_to_load)
		paths_to_load = [saved_paths retain];
//	NSLog(@"DEBUG HERE:::: paths_to_load = %@", paths_to_load);
}

+ (NSDictionary *) dictionaryFromFilesNamed:(NSString *)filename inFolder:(NSString *)foldername andMerge:(BOOL) mergeFiles
{
	return [ResourceManager dictionaryFromFilesNamed:filename inFolder:foldername andMerge:mergeFiles smart:NO];
}

+ (NSDictionary *) dictionaryFromFilesNamed:(NSString *)filename inFolder:(NSString *)foldername andMerge:(BOOL) mergeFiles smart:(BOOL) smartMerge
{
	NSMutableArray *results = [NSMutableArray arrayWithCapacity:16];
	NSMutableArray *fpaths = [ResourceManager paths];
	int i;
	if (!filename)
		return nil;
	
	NSString* dict_key = [NSString stringWithFormat:@"%@:%@", foldername, filename];
	if (!dictionary_cache)
		dictionary_cache = [[NSMutableDictionary alloc] initWithCapacity:32];
	if ([dictionary_cache objectForKey:dict_key])
	{
		return [NSDictionary dictionaryWithDictionary:(NSDictionary *)[dictionary_cache objectForKey:dict_key]];	// return the cached dictionary
	}
	
	for (i = 0; i < [fpaths count]; i++)
	{
		NSString *filepath = [(NSString *)[fpaths objectAtIndex:i] stringByAppendingPathComponent:filename];
		if ([[NSFileManager defaultManager] fileExistsAtPath:filepath])
		{
			NSDictionary* found_dic = [NSDictionary dictionaryWithContentsOfFile:filepath];

			if (found_dic)
				[results addObject:found_dic];
			else
				NSLog(@"ERROR ***** could not parse %@ as a NSDictionary.", filepath);
		}
		if (foldername)
		{
			filepath = [[(NSString *)[fpaths objectAtIndex:i] stringByAppendingPathComponent:foldername] stringByAppendingPathComponent:filename];
			if ([[NSFileManager defaultManager] fileExistsAtPath:filepath])
			{
				NSDictionary* found_dic = [NSDictionary dictionaryWithContentsOfFile:filepath];
				
				if (found_dic)
					[results addObject:found_dic];
				else
					NSLog(@"ERROR ***** could not parse %@ as a NSDictionary.", filepath);
			}
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
	if (result)
		[dictionary_cache setObject:result forKey:dict_key];
	
//	NSLog(@"DEBUG ResourceManager dictionary_cache keys:\n%@", [dictionary_cache allKeys]);
		
	return [NSDictionary dictionaryWithDictionary:result];
}

+ (NSArray *) arrayFromFilesNamed:(NSString *)filename inFolder:(NSString *)foldername andMerge:(BOOL) mergeFiles
{
	NSMutableArray *results = [NSMutableArray arrayWithCapacity:16];
	NSMutableArray *fpaths = [ResourceManager paths];
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
		if ([[NSFileManager defaultManager] fileExistsAtPath:filepath])
		{
			NSArray* found_array = [NSArray arrayWithContentsOfFile:filepath];

			if (found_array)
				[results addObject:found_array];
			else
				NSLog(@"ERROR ***** could not parse %@ as a NSArray.", filepath);
		}
//			[results addObject:[NSArray arrayWithContentsOfFile:filepath]];
		if (foldername)
		{
			filepath = [[(NSString *)[fpaths objectAtIndex:i] stringByAppendingPathComponent:foldername] stringByAppendingPathComponent:filename];
			
			if ([[NSFileManager defaultManager] fileExistsAtPath:filepath])
			{
				NSArray* found_array = [NSArray arrayWithContentsOfFile:filepath];
					
				if (found_array)
					[results addObject:found_array];
				else
					NSLog(@"ERROR ***** could not parse %@ as a NSArray.", filepath);
			}
//				[results addObject:[NSArray arrayWithContentsOfFile:filepath]];
		}
	}
	if ([results count] == 0)
		return nil;
	
	// got results we may want to cache
	//
	//NSLog(@"---> ResourceManager found %d file(s) with name '%@' (in folder '%@')", [results count], filename, foldername);
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


+ (id) retrieveFileNamed:(NSString *)inFileName inFolder:(NSString *)inFolderName cache:(NSMutableDictionary **)ioCache key:(NSString *)inKey class:(Class)inClass;
{
	OOMusic			*result = nil;
	NSString		*foundPath = nil;
	NSMutableArray	*fpaths;
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
		
		//NSLog(@"looking for oos file: %@", filepath);
		if ([[NSFileManager defaultManager] fileExistsAtPath:filepath])
		{
			// load and compile oos script
			NSLog(@"trying to load and parse %@", filepath);
			NSString *script = [NSString stringWithContentsOfFile:filepath];
			NSDictionary *scriptDict = parseScripts(script);
			if (scriptDict) {
				//NSLog(@"parsed ok, adding to results");
				[results addObject:scriptDict];
			}
		}
		else
		{
			filepath = [[filepath stringByDeletingPathExtension] stringByAppendingPathExtension:@"plist"];
			//NSLog(@"oos not found, looking for plist file: %@", filepath);
			// All this code replicated from dictionaryFromFileNamed because that method
			// will traverse all possible locations and any oos files that co-exist with
			// plist files will probably get their entries overwritten.
			//
			// This can be simplified if we make a rule that it is a configuration error
			// that isn't handled if there is a script.oos and script.plist file in
			// the same place. But that probably isn't realistic.
			if ([[NSFileManager defaultManager] fileExistsAtPath:filepath])
			{
				NSDictionary* found_dic = [NSDictionary dictionaryWithContentsOfFile:filepath];

				if (found_dic)
					[results addObject:found_dic];
				else
					NSLog(@"ERROR ***** could not parse %@ as a NSDictionary.", filepath);
			}
		}
		if (foldername)
		{
			xfilepath = [[(NSString *)[fpaths objectAtIndex:i] stringByAppendingPathComponent:foldername] stringByAppendingPathComponent:filename];
			filepath = [[xfilepath stringByDeletingPathExtension] stringByAppendingPathExtension:@"oos"];
			//NSLog(@"looking for oos file: %@", filepath);
			if ([[NSFileManager defaultManager] fileExistsAtPath:filepath])
			{
				// load and compile oos script
				NSLog(@"trying to load and compile %@", filepath);
				NSString *script = [NSString stringWithContentsOfFile:filepath];
				NSDictionary *scriptDict = parseScripts(script);
				if (scriptDict) {
					//NSLog(@"parsed ok, adding to results");
					[results addObject:scriptDict];
				}
			}
			else
			{
				filepath = [[filepath stringByDeletingPathExtension] stringByAppendingPathExtension:@"plist"];
				//NSLog(@"oos not found, looking for plist file: %@", filepath);
				if ([[NSFileManager defaultManager] fileExistsAtPath:filepath])
				{
					NSDictionary* found_dic = [NSDictionary dictionaryWithContentsOfFile:filepath];

					if (found_dic)
						[results addObject:found_dic];
					else
						NSLog(@"ERROR ***** could not parse %@ as a NSDictionary.", filepath);
				}
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

//	NSLog(@"DEBUG ResourceManager dictionary_cache keys:\n%@", [dictionary_cache allKeys]);

	return [NSDictionary dictionaryWithDictionary:result];
}


@end
