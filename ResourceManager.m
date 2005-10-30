//
//  ResourceManager.m
//  Oolite
//
/*
 *
 *  Oolite
 *
 *  Created by Giles Williams on Sat Apr 03 2004.
 *  Copyright (c) 2004 for aegidian.org. All rights reserved.
 *

Copyright (c) 2004, Giles C Williams
All rights reserved.

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Noncommercial. You may not use this work for commercial purposes.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/

#import "ResourceManager.h"
#import "ScannerExtension.h"
#ifdef GNUSTEP
#import "Comparison.h"
#import "OOSound.h"
#import "OOMusic.h"
#endif


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
	int i, j;
	if (saved_paths)
		return saved_paths;
	if (errors)
	{
		[errors release];
		errors = nil;
	}
	
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
			NSArray*		possibleExpansions = [[NSFileManager defaultManager] directoryContentsAtPath: addon_path];
			for (j = 0; j < [possibleExpansions count]; j++)
			{
				NSString*	item = (NSString *)[possibleExpansions objectAtIndex: j];
				if (([[item pathExtension] isEqual:@"oxp"])||([[item pathExtension] isEqual:@"oolite_expansion_pack"]))
				{
					BOOL dir_test = NO;
					NSString*	possibleExpansionPath = [addon_path stringByAppendingPathComponent:item];
					[[NSFileManager defaultManager] fileExistsAtPath:possibleExpansionPath isDirectory:&dir_test];
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
			if ([[NSFileManager defaultManager] fileExistsAtPath:requiresPath])
			{
				NSDictionary* requires_dic = [NSDictionary dictionaryWithContentsOfFile:requiresPath];
				
				// FIX FOR WINDOWS GNUSTEP NOT PARSING XML PLISTS
				NS_DURING
					if (!requires_dic)	// try parsing it using our home-grown XML parser
						requires_dic = (NSDictionary*)[ResourceManager parseXMLPropertyList:[NSString stringWithContentsOfFile:requiresPath]];
				NS_HANDLER
					if ([[localException name] isEqual: OOLITE_EXCEPTION_XML_PARSING_FAILURE])	// note it happened here 
					{
						NSLog(@"***** [ResourceManager pathsUsingAddOns:] encountered exception : %@ : %@ *****",[localException name], [localException reason]);
						NSLog(@"***** ignoring this path from now on *****",[localException name], [localException reason]);
						failed_parsing = YES;
					}
					else
						[localException raise];
				NS_ENDHANDLER
					
				require_test = [ResourceManager areRequirementsFulfilled:requires_dic];
			}
			if (require_test)
				[file_paths addObject:possibleExpansionPath];
			else
			{
				NSString* version = (NSString *)[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
				NSBeep();
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
	//
	NSLog(@"---> searching paths:\n%@", [file_paths description]);
	//
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
			
			// FIX FOR WINDOWS GNUSTEP NOT PARSING XML PLISTS
			NS_DURING
				if (!found_dic)	// try parsing it using our home-grown XML parser
					found_dic = (NSDictionary*)[ResourceManager parseXMLPropertyList:[NSString stringWithContentsOfFile:filepath]];
			NS_HANDLER
				if ([[localException name] isEqual: OOLITE_EXCEPTION_XML_PARSING_FAILURE])	// note it happened here 
				{
					NSLog(@"***** [ResourceManager dictionaryFromFilesNamed:::] encountered exception : %@ : %@ *****",[localException name], [localException reason]);
				}
				else
					[localException raise];
			NS_ENDHANDLER

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
			
				// FIX FOR WINDOWS GNUSTEP NOT PARSING XML PLISTS
				NS_DURING
					if (!found_dic)	// try parsing it using our home-grown XML parser
						found_dic = (NSDictionary*)[ResourceManager parseXMLPropertyList:[NSString stringWithContentsOfFile:filepath]];
				NS_HANDLER
					if ([[localException name] isEqual: OOLITE_EXCEPTION_XML_PARSING_FAILURE])	// note it happened here 
					{
						NSLog(@"***** [ResourceManager dictionaryFromFilesNamed:::] encountered exception : %@ : %@ *****",[localException name], [localException reason]);
					}
					else
						[localException raise];
				NS_ENDHANDLER

				
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
			[result addEntriesFromDictionary:(NSDictionary *)[results objectAtIndex:i]];
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
			
			// FIX FOR WINDOWS GNUSTEP NOT PARSING XML PLISTS
			NS_DURING
				if (!found_array)	// try parsing it using our home-grown XML parser
					found_array = (NSArray*)[ResourceManager parseXMLPropertyList:[NSString stringWithContentsOfFile:filepath]];
			NS_HANDLER
				if ([[localException name] isEqual: OOLITE_EXCEPTION_XML_PARSING_FAILURE])	// note it happened here 
				{
					NSLog(@"***** [ResourceManager arrayFromFilesNamed:::] encountered exception : %@ : %@ *****",[localException name], [localException reason]);
				}
				else
					[localException raise];
			NS_ENDHANDLER

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
				
				// FIX FOR WINDOWS GNUSTEP NOT PARSING XML PLISTS
				NS_DURING
					if (!found_array)	// try parsing it using our home-grown XML parser
						found_array = (NSArray*)[ResourceManager parseXMLPropertyList:[NSString stringWithContentsOfFile:filepath]];
				NS_HANDLER
					if ([[localException name] isEqual: OOLITE_EXCEPTION_XML_PARSING_FAILURE])	// note it happened here 
					{
						NSLog(@"***** [ResourceManager arrayFromFilesNamed:::] encountered exception : %@ : %@ *****",[localException name], [localException reason]);
					}
					else
						[localException raise];
				NS_ENDHANDLER
					
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

+ (NSSound *) soundNamed:(NSString *)filename inFolder:(NSString *)foldername
{
	NSSound *result = nil;
	NSMutableArray *fpaths = [ResourceManager paths];
	int i, r;
	r = 0;
	if (!filename)
		return nil;

	NSString* sound_key = [NSString stringWithFormat:@"%@:%@", foldername, filename];
	if (!sound_cache)
		sound_cache = [[NSMutableDictionary alloc] initWithCapacity:32];
	if ([sound_cache objectForKey:sound_key])
		return (NSSound *)[sound_cache objectForKey:sound_key];	// return the cached sound
	
	for (i = 0; i < [fpaths count]; i++)
	{
		NSString *filepath = [(NSString *)[fpaths objectAtIndex:i] stringByAppendingPathComponent:filename];
		if ([[NSFileManager defaultManager] fileExistsAtPath:filepath])
		{
#ifdef GNUSTEP
         result = [[[OOSound alloc] initWithContentsOfFile:filepath byReference:NO] autorelease];
#else    
			result = [[[NSSound alloc] initWithContentsOfFile:filepath byReference:NO] autorelease];
#endif         
			r++;
		}
		if (foldername)
		{
			filepath = [[(NSString *)[fpaths objectAtIndex:i] stringByAppendingPathComponent:foldername] stringByAppendingPathComponent:filename];
			//NSLog(@".... checking filepath '%@' for Sounds", filepath);
			if ([[NSFileManager defaultManager] fileExistsAtPath:filepath])
			{
#ifdef GNUSTEP
				result = [[[OOSound alloc] initWithContentsOfFile:filepath byReference:NO] autorelease];
#else            
				result = [[[NSSound alloc] initWithContentsOfFile:filepath byReference:NO] autorelease];
#endif            
				r++;
			}
		}
	}
	
	if (result)
		[sound_cache setObject:result forKey:sound_key];
	
	//NSLog(@"---> ResourceManager found %d file(s) with name '%@' (in folder '%@')", r, filename, foldername);
	return result;
}

+ (NSImage *) imageNamed:(NSString *)filename inFolder:(NSString *)foldername
{
	NSImage *result = nil;
	NSMutableArray *fpaths = [ResourceManager paths];
	int i, r;
	r = 0;
	if (!filename)
		return nil;

	NSString* image_key = [NSString stringWithFormat:@"%@:%@", foldername, filename];
	if (!image_cache)
		image_cache = [[NSMutableDictionary alloc] initWithCapacity:32];
	if ([image_cache objectForKey:image_key])
		return (NSImage *)[image_cache objectForKey:image_key];	// return the cached image
	
	for (i = 0; i < [fpaths count]; i++)
	{
		NSString *filepath = [(NSString *)[fpaths objectAtIndex:i] stringByAppendingPathComponent:filename];
		if ([[NSFileManager defaultManager] fileExistsAtPath:filepath])
		{
			result = [[[NSImage alloc] initWithContentsOfFile:filepath] autorelease];
			r++;
		}
		if (foldername)
		{
			filepath = [[(NSString *)[fpaths objectAtIndex:i] stringByAppendingPathComponent:foldername] stringByAppendingPathComponent:filename];
			if ([[NSFileManager defaultManager] fileExistsAtPath:filepath])
			{
				result = [[[NSImage alloc] initWithContentsOfFile:filepath] autorelease];
				r++;
			}
		}
	}
	
	if (result)
		[image_cache setObject:result forKey:image_key];
	//NSLog(@"---> ResourceManager found %d file(s) with name '%@' (in folder '%@')", r, filename, foldername);
	return result;
}

+ (NSString *) stringFromFilesNamed:(NSString *)filename inFolder:(NSString *)foldername
{
	NSString *result = nil;
	NSMutableArray *fpaths = [ResourceManager paths];
	int i, r;
	r = 0;
	if (!filename)
		return nil;

	NSString* string_key = [NSString stringWithFormat:@"%@:%@", foldername, filename];
	if (!string_cache)
		string_cache = [[NSMutableDictionary alloc] initWithCapacity:32];
	if ([string_cache objectForKey:string_key])
		return (NSString *)[string_cache objectForKey:string_key];	// return the cached string
	
	for (i = 0; i < [fpaths count]; i++)
	{
		NSString *filepath = [(NSString *)[fpaths objectAtIndex:i] stringByAppendingPathComponent:filename];
		if ([[NSFileManager defaultManager] fileExistsAtPath:filepath])
		{
			result = [NSString stringWithContentsOfFile:filepath];
			r++;
		}
		if (foldername)
		{
			filepath = [[(NSString *)[fpaths objectAtIndex:i] stringByAppendingPathComponent:foldername] stringByAppendingPathComponent:filename];
			if ([[NSFileManager defaultManager] fileExistsAtPath:filepath])
			{
				result = [NSString stringWithContentsOfFile:filepath];
				r++;
			}
		}
	}
	
	if (result)
		[string_cache setObject:result forKey:string_key];
	//NSLog(@"---> ResourceManager found %d file(s) with name '%@' (in folder '%@')", r, filename, foldername);
	return result;
}

#ifdef GNUSTEP
+ (OOMusic *) movieFromFilesNamed:(NSString *)filename inFolder:(NSString *)foldername
{
	OOMusic *result = nil;
	NSMutableArray *fpaths = [ResourceManager paths];
	int i, r;
	r = 0;
	if (!filename)
		return nil;

	NSString* movie_key = [NSString stringWithFormat:@"%@:%@", foldername, filename];
	if (!movie_cache)
		movie_cache = [[NSMutableDictionary alloc] initWithCapacity:32];
	if ([movie_cache objectForKey:movie_key])
		return (id)[movie_cache objectForKey:movie_key];	// return the cached movie
	
	for (i = 0; i < [fpaths count]; i++)
	{
		NSString *filepath = [(NSString *)[fpaths objectAtIndex:i] stringByAppendingPathComponent:filename];
		if ([[NSFileManager defaultManager] fileExistsAtPath:filepath])
			result = [[OOMusic alloc] initWithContentsOfFile:filepath];
		if (foldername)
		{
			filepath = [[(NSString *)[fpaths objectAtIndex:i] stringByAppendingPathComponent:foldername] stringByAppendingPathComponent:filename];
			if ([[NSFileManager defaultManager] fileExistsAtPath:filepath])
			{
				//NSLog(@"DEBUG ResourceManager found %@ at %@",filename,filepath);
				if (result)
					[result release];
				result = [[OOMusic alloc] initWithContentsOfFile:filepath];
			}
		}
	}
	//NSLog(@"---> ResourceManager found %d file(s) with name '%@' (in folder '%@')", r, filename, foldername);
	
	if (result)
		[movie_cache setObject:result forKey:movie_key];

	return [result autorelease];
}

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

#else
+ (NSMovie *) movieFromFilesNamed:(NSString *)filename inFolder:(NSString *)foldername
{
	NSMovie *result = nil;
	NSMutableArray *fpaths = [ResourceManager paths];
	int i, r;
	r = 0;
	if (!filename)
		return nil;

	NSString* movie_key = [NSString stringWithFormat:@"%@:%@", foldername, filename];
	if (!movie_cache)
		movie_cache = [[NSMutableDictionary alloc] initWithCapacity:32];
	if ([movie_cache objectForKey:movie_key])
		return (NSMovie *)[movie_cache objectForKey:movie_key];	// return the cached movie
	
	for (i = 0; i < [fpaths count]; i++)
	{
		NSString *filepath = [(NSString *)[fpaths objectAtIndex:i] stringByAppendingPathComponent:filename];
		if ([[NSFileManager defaultManager] fileExistsAtPath:filepath])
			result = [[NSMovie alloc] initWithURL:[NSURL fileURLWithPath: filepath] byReference: NO];
		if (foldername)
		{
			filepath = [[(NSString *)[fpaths objectAtIndex:i] stringByAppendingPathComponent:foldername] stringByAppendingPathComponent:filename];
			if ([[NSFileManager defaultManager] fileExistsAtPath:filepath])
			{
				//NSLog(@"DEBUG ResourceManager found %@ at %@",filename,filepath);
				if (result)
					[result release];
				result = [[NSMovie alloc] initWithURL:[NSURL fileURLWithPath: filepath] byReference: NO];
			}
		}
	}
	//NSLog(@"---> ResourceManager found %d file(s) with name '%@' (in folder '%@')", r, filename, foldername);
	
	if ((result == nil)&&([filename hasSuffix:@"ogg"]))
	{
		// look for an alternative .mid file
		NSString *midifilename = [[filename stringByDeletingPathExtension] stringByAppendingPathExtension:@"mid"];
		result =[[ResourceManager movieFromFilesNamed:midifilename inFolder:foldername] retain];
	}
	
	if (result)
		[movie_cache setObject:result forKey:movie_key];
	
	return [result autorelease];
}
#endif

+ (NSMutableArray *) scanTokensFromString:(NSString*) values
{
	NSMutableArray* result = [NSMutableArray arrayWithCapacity:8];
	NSScanner* scanner = [NSScanner scannerWithString:values];
	NSCharacterSet* space_set = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	NSString* token;
	while (![scanner isAtEnd])
	{
		[scanner ooliteScanCharactersFromSet:space_set intoString:(NSString * *)nil];
		if ([scanner ooliteScanUpToCharactersFromSet:space_set intoString:&token])
			[result addObject:[NSString stringWithString:token]];
	}
	return result;
}

+ (NSString *) decodeString:(NSString*) encodedString
{
	if ([encodedString rangeOfString:@"&"].location == NSNotFound)
		return encodedString;
	//
	NSMutableString* result = [NSMutableString stringWithString:encodedString];
	//
	[result replaceOccurrencesOfString:@"&amp;"		withString:@"&"		options:NSCaseInsensitiveSearch range:NSMakeRange(0, [result length])];
	[result replaceOccurrencesOfString:@"&lt;"		withString:@"<"		options:NSCaseInsensitiveSearch range:NSMakeRange(0, [result length])];
	[result replaceOccurrencesOfString:@"&gt;"		withString:@">"		options:NSCaseInsensitiveSearch range:NSMakeRange(0, [result length])];
	[result replaceOccurrencesOfString:@"&apos;"	withString:@"'"		options:NSCaseInsensitiveSearch range:NSMakeRange(0, [result length])];
	[result replaceOccurrencesOfString:@"&quot;"	withString:@"\""	options:NSCaseInsensitiveSearch range:NSMakeRange(0, [result length])];
	//
	return result;
}

+ (OOXMLElement) parseOOXMLElement:(NSScanner*) scanner upTo:(NSString*)closingTag
{
	OOXMLElement	result, element;
	element.tag = nil;
	element.content = nil;
	result.tag = nil;
	result.content = nil;
	NSMutableArray* elements = [NSMutableArray arrayWithCapacity:4];	// arbitrarily choose 4
	BOOL done = NO;
	while ((!done)&&(![scanner isAtEnd]))
	{
		NSString* preamble;
		BOOL foundPreamble = [scanner scanUpToString:@"<" intoString:&preamble];
		BOOL foundOpenBracket = [scanner scanString:@"<" intoString:(NSString * *)nil];
		if (!foundOpenBracket)
		{
//			NSLog(@"XML >>>>> no '<' found.");
			//
			// no openbracket found
			if (foundPreamble)
			{
//				NSLog(@"XML >>>>> Returning preamble=\"%@\"", preamble);
				// return the text we got instead
				element.tag = nil;
				element.content = [ResourceManager decodeString:preamble];
			}
			else
			{
//				NSLog(@"XML >>>>> Returning \"\"");
				// no preamble, return an empty string
				element.tag = nil;
				element.content = @"";
			}
		}
		else
		{
//			NSLog(@"XML >>>>> '<' found.");
			//
			NSString* tag;
			// look for closing '>'
			int openBracketLocation = [scanner scanLocation];
			BOOL foundTag = [scanner scanUpToString:@">" intoString:&tag];
			BOOL foundCloseBracket = [scanner scanString:@">" intoString:(NSString * *)nil];
			if (!foundCloseBracket)
			{
				// ERROR no closing bracket for tag
				NSException* myException = [NSException
					exceptionWithName: OOLITE_EXCEPTION_XML_PARSING_FAILURE
					reason: [NSString stringWithFormat:@"Tag without closing bracket: \"%@\"", tag]
					userInfo: nil];
				[myException raise];
				result.tag = nil;
				result.content = nil;
				return result;
			}
			if (!foundTag)
			{
				// ERROR empty tag
				NSException* myException = [NSException
					exceptionWithName: OOLITE_EXCEPTION_XML_PARSING_FAILURE
					reason: [NSString stringWithFormat:@"Empty tag \"<>\" encountered.", tag]
					userInfo: nil];
				[myException raise];
				result.tag = nil;
				result.content = nil;
				return result;
			}
			//
//			NSLog(@"XML >>>>> '>' found. tag = <%@>", tag);
			//
			// okay we have a < tag >
			//
			if ([tag hasPrefix:@"!"]||[tag hasPrefix:@"?"]||[tag hasSuffix:@"/"])
			{
				if ([tag hasPrefix:@"!--"])
				{
					// it's a comment
					[scanner setScanLocation:openBracketLocation + 3];
					NSString* comment;
//					BOOL foundComment = [scanner scanUpToString:@"-->" intoString:&comment];
					[scanner scanUpToString:@"-->" intoString:&comment];
					BOOL foundEndComment = [scanner scanString:@"-->" intoString:(NSString * *)nil];
					if (!foundEndComment)
					{
						// ERROR comment without closing -->
						NSException* myException = [NSException
							exceptionWithName: OOLITE_EXCEPTION_XML_PARSING_FAILURE
							reason: [NSString stringWithFormat:@"No closing --> for comment", tag]
							userInfo: nil];
						[myException raise];
						result.tag = nil;
						result.content = nil;
						return result;
					}
					else
					{
						// got a well formed comment so...
//						if (foundComment)
//							NSLog(@"XML >>>>> Comment \"%@\"", comment);
						element.tag = nil;
						element.content = nil;	// ignore the comment
					}
				}
				else
				{
					// it's a singleton
					NSArray* tagbits = [ResourceManager scanTokensFromString:tag];
					// lowercase first 'word' of the tag - with entities decoded
					tag = [ResourceManager decodeString:[(NSString*)[tagbits objectAtIndex:0] lowercaseString]];
					element.tag = tag;
					element.content = tagbits;
				}
			}
			else
			{
				if ([tag hasPrefix:@"/"])
				{
					// it's a closing tag
					if ([tag hasSuffix:closingTag])
					{
						element.tag = nil;
						if (foundPreamble)
							element.content = [ResourceManager decodeString:preamble];
						else
							element.content = nil;
						done = YES;
					}
					else
					{
						// ERROR closing tag without opening tag
						NSException* myException = [NSException
							exceptionWithName: OOLITE_EXCEPTION_XML_PARSING_FAILURE
							reason: [NSString stringWithFormat:@"Closing tag \"<%@>\" without opening tag.", tag]
							userInfo: nil];
						[myException raise];
						result.tag = nil;
						result.content = nil;
						return result;
					}
				}
				else
				{
					// at this point we have an opening tag for some content
					// so we'll recursively parse the rest of the text
					NSArray* tagbits = [ResourceManager scanTokensFromString:tag];
					if (![tagbits count])
					{
						// ERROR empty opening tag
						NSException* myException = [NSException
							exceptionWithName: OOLITE_EXCEPTION_XML_PARSING_FAILURE
							reason: [NSString stringWithFormat:@"Empty tag encountered.", tag]
							userInfo: nil];
						[myException raise];
						result.tag = nil;
						result.content = nil;
						return result;
					}
					// lowercase first 'word' of the tag - with entities decoded
					tag = [ResourceManager decodeString:[(NSString*)[tagbits objectAtIndex:0] lowercaseString]];
					//
					OOXMLElement inner_element = [ResourceManager parseOOXMLElement:scanner upTo:tag];
					element.tag = inner_element.tag;
//					if ([inner_element.content isKindOfClass:[NSArray class]])
//					{
//						NSArray* inner_element_array = (NSArray*)inner_element.content;
//						if ([inner_element_array count] == 1)
//							inner_element.content = [inner_element_array objectAtIndex:0];
//					}
					element.content = inner_element.content;
				}
			}
		}
		// we reach here with element set so we need to add it in to the elements array
		if ((element.tag)&&(element.content))
		{
			[elements addObject:[NSArray arrayWithObjects: element.tag, element.content, nil]];
		}
	}
	
	// all done!
	result.tag = closingTag;
	if ([elements count])
		result.content = elements;
	else
		result.content = element.content;
		
//	NSLog(@"DEBUG XML found '%@' = '%@'", result.tag, result.content);
	
	return result;
}

+ (NSObject*) parseXMLPropertyList:(NSString*)xmlString
{
	NSScanner* scanner = [NSScanner scannerWithString:xmlString];
	OOXMLElement xml;
	NS_DURING
		xml = [ResourceManager parseOOXMLElement:scanner upTo:@"ROOT"];
	NS_HANDLER
		if ([[localException name] isEqual: OOLITE_EXCEPTION_XML_PARSING_FAILURE])	// note it happened here 
		{
			NSLog(@"***** [ResourceManager parseXMLPropertyList:] encountered exception : %@ : %@ *****",[localException name], [localException reason]);
		}
		[localException raise];
	NS_ENDHANDLER
	if (!xml.content)
		return nil;
	if (![xml.content isKindOfClass:[NSArray class]])
		return nil;
	NSArray* elements = (NSArray*)xml.content;
	int n_elements = [elements count];
	int i;
	for (i = 0; i < n_elements; i++)
	{
		NSArray* element = (NSArray*)[elements objectAtIndex:i];
		NSString* tag = (NSString*)[element objectAtIndex:0];
		NSObject* content = [element objectAtIndex:1];
//		NSLog(@"DEBUG XML found '%@' = %@", tag, content);
		if ([tag isEqual:@"plist"])
		{
			if ([content isKindOfClass:[NSArray class]])
			{
				NSArray* plist = (NSArray*)[(NSArray*)content objectAtIndex:0];
//				NSString* plistTag = (NSString*)[plist objectAtIndex:0];
//				NSLog(@"DEBUG XML found plist containing '%@'", plistTag);
				return [ResourceManager objectFromXMLElement:plist];
			}
		}
	}
	// with a well formed plist we should not reach here!
	return nil;
}

+ (NSObject*) objectFromXMLElement:(NSArray*) xmlElement
{
//	NSLog(@"XML DEBUG trying to get an NSObject out of %@", xmlElement);
	//
	if ([xmlElement count] != 2)
	{
		// bad xml element
		NSException* myException = [NSException
			exceptionWithName: OOLITE_EXCEPTION_XML_PARSING_FAILURE
			reason: [NSString stringWithFormat:@"Bad XMLElement %@ passed to objectFromXMLElement:", xmlElement]
			userInfo: nil];
		[myException raise];
		return nil;
	}
	NSString* tag = (NSString*)[xmlElement objectAtIndex:0];
	NSObject* content = [xmlElement objectAtIndex:1];
	//
	if ([tag isEqual:@"true/"])
		return [ResourceManager trueFromXMLContent:content];
	if ([tag isEqual:@"false/"])
		return [ResourceManager falseFromXMLContent:content];
	//
	if ([tag isEqual:@"real"])
		return [ResourceManager realFromXMLContent:content];
	//
	if ([tag isEqual:@"integer"])
		return [ResourceManager integerFromXMLContent:content];
	//
	if ([tag isEqual:@"string"])
		return [ResourceManager stringFromXMLContent:content];
	if ([tag isEqual:@"string/"])
		return @"";
	//
	if ([tag isEqual:@"date"])
		return [ResourceManager dateFromXMLContent:content];
	//
	if ([tag isEqual:@"data"])
		return [ResourceManager dataFromXMLContent:content];
	//
	if ([tag isEqual:@"array"])
		return [ResourceManager arrayFromXMLContent:content];
	if ([tag isEqual:@"array/"])
		return [NSArray arrayWithObjects:nil];
	//
	if ([tag isEqual:@"dict"])
		return [ResourceManager dictionaryFromXMLContent:content];
	if ([tag isEqual:@"dict/"])
		return [NSDictionary dictionaryWithObjectsAndKeys:nil];
	//
	if ([tag isEqual:@"key"])
		return [ResourceManager stringFromXMLContent:content];
	//
	return nil;
}

+ (NSNumber*) trueFromXMLContent:(NSObject*) xmlContent
{
	return [NSNumber numberWithBool:YES];
}

+ (NSNumber*) falseFromXMLContent:(NSObject*) xmlContent
{
	return [NSNumber numberWithBool:NO];
}

+ (NSNumber*) realFromXMLContent:(NSObject*) xmlContent
{
	if ([xmlContent isKindOfClass:[NSString class]])
	{
		return [NSNumber numberWithDouble:[(NSString*)xmlContent doubleValue]];
	}
	return nil;
}

+ (NSNumber*) integerFromXMLContent:(NSObject*) xmlContent
{
	if ([xmlContent isKindOfClass:[NSString class]])
	{
		return [NSNumber numberWithInt:[(NSString*)xmlContent intValue]];
	}
	return nil;
}

+ (NSString*) stringFromXMLContent:(NSObject*) xmlContent
{
	if ([xmlContent isKindOfClass:[NSString class]])
	{
		return (NSString*)xmlContent;
	}
	return nil;
}

+ (NSDate*) dateFromXMLContent:(NSObject*) xmlContent
{
	if ([xmlContent isKindOfClass:[NSString class]])
	{
		return [NSDate dateWithString:(NSString*)xmlContent];
	}
	return nil;
}

+ (NSData*) dataFromXMLContent:(NSObject*) xmlContent
{
	// we don't use this for Oolite
	if ([xmlContent isKindOfClass:[NSString class]])
	{
		// we're going to decode the string from base64
		NSString* base64String = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
		NSMutableData* resultingData = [NSMutableData dataWithLength:0];
		NSString* dataString = (NSString *)xmlContent;
		char bytes3[3];
		int n_64Chars;
		int tripletValue;
		int n_chars = [dataString length];
		int i = 0;
		while (i < n_chars)
		{
			n_64Chars = 0;
			tripletValue = 0;
			while ((n_64Chars < 4)&(i < n_chars))
			{
				int b64 = [base64String rangeOfString:[dataString substringWithRange:NSMakeRange(i,1)]].location;
				if (b64 != NSNotFound)
				{
					tripletValue *= 64;
					tripletValue += (b64 & 63);
					n_64Chars++;
				}
				i++;
			}
			while (n_64Chars < 4)	//shouldn't need to pad, but we do just in case
			{
				tripletValue *= 64;
				n_64Chars++;
			}
			bytes3[0] = (tripletValue & 0xff0000) >> 16; 
			bytes3[1] = (tripletValue & 0xff00) >> 8; 
			bytes3[2] = (tripletValue & 0xff);
			[resultingData appendBytes:(const void *)bytes3 length:3];
		}
		return [NSData dataWithData:resultingData];
	}
	return nil;
}

+ (NSArray*) arrayFromXMLContent:(NSObject*) xmlContent
{
	if ([xmlContent isKindOfClass:[NSArray class]])
	{
		NSArray* xmlElementArray = (NSArray*)xmlContent;
		int n_objects = [xmlElementArray count];
		NSMutableArray* result = [NSMutableArray arrayWithCapacity:n_objects];
		int i;
		for (i = 0; i < n_objects; i++)
		{
			NSArray* xmlElement = [xmlElementArray objectAtIndex:i];
			NSObject* object = [ResourceManager objectFromXMLElement:xmlElement];
			if (object)
				[result addObject:object];
			else
				return nil;
		}
		return [NSArray arrayWithArray:result];
	}
	return nil;
}

+ (NSDictionary*) dictionaryFromXMLContent:(NSObject*) xmlContent
{
	if ([xmlContent isKindOfClass:[NSArray class]])
	{
		NSArray* xmlElementArray = (NSArray*)xmlContent;
		int n_objects = [xmlElementArray count];
		if (n_objects & 1)
			return nil;	// must be an even number of objects in the array
		NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity: n_objects / 2];
		int i;
		for (i = 0; i < n_objects; i += 2)
		{
			NSArray* keyXmlElement = [xmlElementArray objectAtIndex:i];
			NSObject* key = [ResourceManager objectFromXMLElement:keyXmlElement];
			NSArray* objectXmlElement = [xmlElementArray objectAtIndex:i + 1];
			NSObject* object = [ResourceManager objectFromXMLElement:objectXmlElement];
			if (key && object)
			{
				[result setObject:object forKey:key];
			}
			else
				return nil;
		}
		return [NSDictionary dictionaryWithDictionary:result];
	}
	return nil;
}

+ (NSString*) stringFromGLFloats: (GLfloat*) float_array : (int) n_floats
{
	NSMutableString* result = [NSMutableString stringWithCapacity:256];
	int i;
	for ( i = 0; i < n_floats ; i++)
		[result appendFormat:@"%f ", float_array[i]];
	return result;
}

+ (void) GLFloatsFromString: (NSString*) float_string: (GLfloat*) float_array
{
	NSArray* tokens = [ResourceManager scanTokensFromString:float_string];
	int i;
	int n_tokens = [tokens count];
	for (i = 0; i < n_tokens; i++)
		float_array[i] = [[tokens objectAtIndex:i] floatValue];
}

+ (NSString*) stringFromNSPoint: (NSPoint) point
{
	return [NSString stringWithFormat:@"%f %f", point.x, point.y];
}

+ (NSPoint) NSPointFromString: (NSString*) point_string
{
	NSArray* tokens = [ResourceManager scanTokensFromString:point_string];
	int n_tokens = [tokens count];
	if (n_tokens != 2)
		return NSMakePoint( 0.0, 0.0);
	return NSMakePoint( [[tokens objectAtIndex:0] floatValue], [[tokens objectAtIndex:1] floatValue]);
}

@end
