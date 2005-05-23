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
	int i;
	if (saved_paths)
		return saved_paths;
	if (errors)
	{
		[errors release];
		errors = nil;
	}
	
	NSString	*app_path = [[[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Contents"] stringByAppendingPathComponent:@"Resources"];
	NSString	*addon_path = [[[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"AddOns"];
	NSMutableArray *file_paths = [NSMutableArray arrayWithCapacity:16];
	[file_paths addObject:app_path];
	if (include_addons)
	{
		[file_paths addObject:addon_path];
		//
		NSArray*		possibleExpansions = [[NSFileManager defaultManager] directoryContentsAtPath:addon_path];
		NSMutableArray*	possibleExpansionPaths = [NSMutableArray arrayWithCapacity:[possibleExpansions count]];
		for (i = 0; i < [possibleExpansions count]; i++)
		{
			NSString*	item = (NSString *)[possibleExpansions objectAtIndex:i];
			if (([[item pathExtension] isEqual:@"oxp"])||([[item pathExtension] isEqual:@"oolite_expansion_pack"]))
			{
				BOOL dir_test;
				NSString*	possibleExpansionPath = [addon_path stringByAppendingPathComponent:item];
				[[NSFileManager defaultManager] fileExistsAtPath:possibleExpansionPath isDirectory:&dir_test];
				if (dir_test)
					[possibleExpansionPaths addObject:possibleExpansionPath];
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
			// check for compatibility
			if ([[NSFileManager defaultManager] fileExistsAtPath:requiresPath])
				require_test = [ResourceManager areRequirementsFulfilled:[NSDictionary dictionaryWithContentsOfFile:requiresPath]];
			if (require_test)
				[file_paths addObject:possibleExpansionPath];	// it made it in!
			else
			{
				NSString* version = (NSString *)[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
				NSBeep();
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
		return [NSDictionary dictionaryWithDictionary:(NSDictionary *)[dictionary_cache objectForKey:dict_key]];	// return the cached dictionary
	
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
	//NSLog(@"---> ResourceManager found %d file(s) with name '%@' (in folder '%@')", [results count], filename, foldername);
	if (!mergeFiles)
		return [NSDictionary dictionaryWithDictionary:(NSDictionary *)[results objectAtIndex:[results count] - 1]];
	NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:128];
	for (i = 0; i < [results count]; i++)
		[result addEntriesFromDictionary:(NSDictionary *)[results objectAtIndex:i]];
		
	if (result)
		[dictionary_cache setObject:result forKey:dict_key];
		
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
	//NSLog(@"---> ResourceManager found %d file(s) with name '%@' (in folder '%@')", [results count], filename, foldername);
	if (!mergeFiles)
		return [NSArray arrayWithArray:(NSArray *)[results objectAtIndex:[results count] - 1]];
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:128];
	for (i = 0; i < [results count]; i++)
		[result addObjectsFromArray:(NSArray *)[results objectAtIndex:i]];
		
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
	NSString *finalFilename;
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

@end
