//
//  OODisplayModeSDL.m
//  DisplayTest
//
//  Created by Jens Ayton on 2007-12-30.
//  Copyright 2007-2010 Jens Ayton. All rights reserved.
//

#import "OODisplayModeSDL.h"
#import "OODisplaySDL.h"


@implementation OODisplayModeSDL

- (id) initWithDisplay:(OODisplaySDL *)display
				 width:(unsigned)width
				height:(unsigned)height
				 depth:(unsigned)depth
{
	self = [super init];
	if (self != nil)
	{
		_display = display; // Not retained
		_width = width;
		_height = height;
		_depth = depth;
	}
	return self;
}


- (void) dealloc
{
	[self invalidate];
	
	[super dealloc];
}


- (BOOL) isEqual:(id)other
{
	if (self == other)  return YES;
	if (![other isKindOfClass:[OODisplayModeSDL class]])  return NO;
	
	if (![[self display] isEqual:[(OODisplayModeSDL *)other display]])  return NO;
	if ([self width] != [other width])  return NO;
	if ([self height] != [other height])  return NO;
	if ([self bitDepth] != [other bitDepth])  return NO;
	
	return YES;
}


- (OODisplay *) display
{
	return _display;
}


- (unsigned) width
{
	return _width;
}


- (unsigned) height
{
	return _height;
}


- (unsigned) bitDepth
{
	return _depth;
}


- (float) refreshRate
{
	return 0;
}


- (void) invalidate
{
	// _display is not retained.
	_display = nil;
	_width = _height = _depth = 0;
}

@end
