//
//  OODisplay.m
//  Oolite
//
//  Created by Jens Ayton on 2007-12-08.
//  Copyright 2007-2010 Jens Ayton. All rights reserved.
//

#import "OODisplay.h"

#if OOLITE_SDL
#import "OODisplaySDL.h"
#define OODisplayImpl OODisplaySDL
#elif OOLITE_MAC_OS_X
#import "OODisplayMacOSX.h"
#define OODisplayImpl OODisplayMacOSX
#else
#error Unknown system, don't know what implementation of OODisplay to use.
#endif


NSString * const kOODisplayAddedNotification			= @"org.aegidian.oolite OODisplay displayAdded";
NSString * const kOODisplayRemovedNotification			= @"org.aegidian.oolite OODisplay displayRemoved";
NSString * const kOODisplaySettingsChangedNotification	= @"org.aegidian.oolite OODisplay displayConfigurationChanged";
NSString * const kOODisplayOrderChangedNotification		= @"org.aegidian.oolite OODisplay displayOrderChanged";


@implementation OODisplay

- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:nil name:nil object:self];
	[super dealloc];
}


+ (NSArray *) allDisplays
{
	return [OODisplayImpl allDisplays];
}


+ (OODisplay *) mainDisplay
{
	NSArray					*all = nil;
	OODisplay				*mainDisplay = nil;
	
	all = [self allDisplays];
	if ([all count] != 0)  mainDisplay = [all objectAtIndex:0];
	return mainDisplay;
}


- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"\"%@\"", [self name]];
}


- (NSString *) name
{
	OOLogGenericSubclassResponsibility();
	return nil;
}


- (NSArray *) modes
{
	OOLogGenericSubclassResponsibility();
	return nil;
}


- (OODisplayMode *) currentMode
{
	unsigned index = [self indexOfCurrentMode];
	if (index == NSNotFound)  return nil;
	return [[self modes] objectAtIndex:index];
}


- (unsigned) indexOfCurrentMode
{
	OOLogGenericSubclassResponsibility();
	return NSNotFound;
}


- (NSDictionary *) matchingDictionary
{
	OOLogGenericSubclassResponsibility();
	return nil;
}


+ (id) displayForMatchingDictionary:(NSDictionary *)dictionary
{
	id				result = nil;
	
	if (dictionary != nil)  result = [OODisplayImpl displayForMatchingDictionary:dictionary];
	if (result == nil)  result = [self mainDisplay];
	
	return nil;
}

@end
