//
//  OODisplaySDL.m
//  DisplayTest
//
//  Created by Jens Ayton on 2007-12-30.
//  Copyright 2007-2011 Jens Ayton. All rights reserved.
//

#import "OODisplaySDL.h"
#import "OODisplayModeSDL.h"
#import "OOCollectionExtractors.h"
#import <SDL/SDL_video.h>


// SDL doesn't have a concept of multiple displays, so we only need one.
static OODisplaySDL		*sDisplay = nil;


@interface OODisplaySDL (Private)

- (void) buildModeList;

@end


@implementation OODisplaySDL

+ (NSArray *) allDisplays
{
	return [NSArray arrayWithObject:[self mainDisplay]];
}


+ (OODisplay *) mainDisplay
{
	if (sDisplay == nil)  sDisplay = [[OODisplaySDL alloc] init];
	return sDisplay;
}


- (void) dealloc
{
	if (sDisplay == self)  sDisplay = nil;
	[_modes makeObjectsPerformSelector:@selector(invalidate)];	// Ensure modes don't have back references to display, in case they're retained somewhere else.
	[_modes release];
	
	[super dealloc];
}


- (NSString *) name
{
	return @"Display";
}


- (NSArray *) modes
{
	if (_modes == nil)  [self buildModeList];
	return _modes;
}


- (unsigned) indexOfCurrentMode
{
	NSEnumerator		*modeEnum = nil;
	OODisplayModeSDL	*mode = nil;
	const SDL_VideoInfo	*info = NULL;
	unsigned			i = 0;
	
	info = SDL_GetVideoInfo();
	if (info == NULL)  return NSNotFound;
	
	for (modeEnum = [[self modes] objectEnumerator]; (mode = [modeEnum nextObject]); )
	{
		if ([mode width] == info->current_w &&
			[mode height] == info->current_h &&
			[mode bitDepth] == info->vfmt->BitsPerPixel)
		{
			return i;
		}
		i++;
	}
	
	return NSNotFound;
}


- (NSDictionary *) matchingDictionary
{
	return [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:@"sdl-main-display"];
}


+ (id) displayForMatchingDictionary:(NSDictionary *)dictionary
{
	if ([dictionary boolForKey:@"sdl-main-display"])  return [self mainDisplay];
	return nil;
}

@end


@implementation OODisplaySDL (Private)

- (void) buildModeList
{
	/*	SDL doesn't provide a way to enumerate all display modes. Instead, it
		provides a way to enumerate rectangles given a pixel format. It also
		doesn't provide a way to find valid pixel formats (which are rather
		comprehensive descriptions). This is so very, very stupid.
	*/
	SDL_Rect			**rawRects = NULL;
	unsigned			i, j;
	NSMutableArray		*modes = nil;
	OODisplayModeSDL	*mode = nil;
	const unsigned		depths[] = {8, 16, 32};
	const unsigned		depthCount = ARRAY_LENGTH(depths);
	const SDL_VideoInfo	*info = NULL;
	NSMutableArray		*rects = nil;
	NSSize				size;
	
	modes = [NSMutableArray array];
	
	rawRects = SDL_ListModes(NULL, SDL_FULLSCREEN);
	if (rawRects != NULL && rawRects != (SDL_Rect **)-1)
	{
		// First, copy the list because SDL_VideoModeOK() may have clobbered it.
		rects = [NSMutableArray array];
		for (i = 0; rawRects[i]; ++i)
		{
			size = NSMakeSize(rawRects[i]->w, rawRects[i]->h);
			[rects addObject:[NSValue valueWithSize:size]];
		}
		
		for (i = 0; i != [rects count]; ++i)
		{
			size = [[rects objectAtIndex:i] sizeValue];
			
			for (j = 0; j != depthCount; ++j)
			{
				if (SDL_VideoModeOK(size.width, size.height, depths[j], SDL_FULLSCREEN | SDL_OPENGL))
				{
					mode = [[OODisplayModeSDL alloc] initWithDisplay:self
															   width:size.width
															  height:size.height
															   depth:depths[j]];
					[modes addObject:mode];
					[mode release];
				}
			}
		}
	}
	
	if ([modes count] == 0)
	{
		// No modes found; assume screen's current settings constitute a mode.
		info = SDL_GetVideoInfo();
		if (info != nil)
		{
			mode = [[OODisplayModeSDL alloc] initWithDisplay:self
													   width:info->current_w
													  height:info->current_h
													   depth:info->vfmt->BitsPerPixel];
			[modes addObject:mode];
			[mode release];
		}
	}
	
	[modes sortUsingSelector:@selector(compare:)];
	_modes = [modes copy];
}

@end
