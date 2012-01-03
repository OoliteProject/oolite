//
//  OODisplayModeMacOSX.m
//  DisplayTest
//
//  Created by Jens Ayton on 2007-12-08.
//  Copyright 2007-2012 Jens Ayton. All rights reserved.
//

#import "OODisplayModeMacOSX.h"
#import "OODisplayMacOSX.h"
#import "OOCollectionExtractors.h"


@interface OODisplayModeMacOSX (Private)

- (id) internalModeID;

@end


@implementation OODisplayModeMacOSX

- (id) initForDisplay:(OODisplayMacOSX *)display modeDictionary:(NSDictionary *)modeDict
{
	self = [super init];
	if (self != nil)
	{
		_display = display;	// Not retained.
		_mode = [modeDict retain];
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
	if (![other isKindOfClass:[OODisplayModeMacOSX class]])  return NO;
	
	if (![[self display] isEqual:[(OODisplayModeMacOSX *)other display]])  return NO;
	if (![[self internalModeID] isEqual:[other internalModeID]])  return NO;
	
	return YES;
}


- (OODisplay *) display
{
	return _display;
}


- (unsigned) width
{
	return [_mode unsignedIntForKey:(NSString *)kCGDisplayWidth];
}


- (unsigned) height
{
	return [_mode unsignedIntForKey:(NSString *)kCGDisplayHeight];
}


- (unsigned) bitDepth
{
	return [_mode unsignedIntForKey:(NSString *)kCGDisplayBitsPerPixel];
}


- (float) refreshRate
{
	return [_mode floatForKey:(NSString *)kCGDisplayRefreshRate];
}


- (BOOL) isStretched
{
	return [_mode boolForKey:(NSString *)kCGDisplayModeIsStretched];
}


- (float) aspectRatio
{
	return [_display aspectRatio] / ((float)[self width] / (float)[self height]);
}


- (BOOL) isInterlaced
{
	return [_mode boolForKey:(NSString *)kCGDisplayModeIsInterlaced];
}


- (BOOL) isTV
{
	return [_mode boolForKey:(NSString *)kCGDisplayModeIsTelevisionOutput];
}


- (BOOL) requiresConfirmation
{
	return ![_mode boolForKey:(NSString *)kCGDisplayModeIsSafeForHardware];
}


- (BOOL) isOKForWindowedMode
{
	return [_mode boolForKey:(NSString *)kCGDisplayModeUsableForDesktopGUI];
}


- (NSDictionary *) modeDictionary
{
	return _mode;
}


- (void) invalidate
{
	// _display is not retained.
	_display = nil;
	[_mode release];
	_mode = nil;
}


- (BOOL) matchesModeDictionary:(NSDictionary *)modeDict
{
	return [[self internalModeID] isEqual:[modeDict objectForKey:(NSString *)kCGDisplayMode]];
}

@end


@implementation OODisplayModeMacOSX (Private)

- (id) internalModeID
{
	return [_mode objectForKey:(NSString *)kCGDisplayMode];
}

@end