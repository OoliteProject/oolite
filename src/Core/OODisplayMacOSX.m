//
//  OODisplayMacOSX.m
//  Oolite
//
//  Created by Jens Ayton on 2007-12-08.
//  Copyright 2007 Jens Ayton. All rights reserved.
//

#import "OODisplayMacOSX.h"
#import "OOFunctionAttributes.h"
#import "OODisplayModeMacOSX.h"
#import <IOKit/graphics/IOGraphicsLib.h>


static NSMutableArray		*sDisplayList = nil;
static NSMutableDictionary	*sDisplayIDToDisplay = nil;
static BOOL					sCallbackInstalled = NO;


@interface OODisplayMacOSX (PrivateDisplayManagement)

+ (void) buildDisplayTable;
+ (void) updateDisplayList;
+ (void) invalidateDisplayList;
+ (void) installCallback;

+ (id) addDisplayWithDisplayID:(CGDirectDisplayID)displayID;
+ (void) removeDisplay:(OODisplayMacOSX *)display;

+ (void) displayWithID:(CGDirectDisplayID)displayID reconfiguredWithChangeFlags:(CGDisplayChangeSummaryFlags)flags;

+ (OODisplayMacOSX *) displayWithDisplayID:(CGDirectDisplayID)ID;

@end


@interface OODisplayMacOSX (Private)

- (id) initWithDisplayID:(CGDirectDisplayID)displayID;

- (CGDirectDisplayID) displayID;

- (NSDictionary *) ioKitInfoWithFlags:(IOOptionBits)flags;
- (NSString *) determineName;

- (void) buildModeList;

@end


static void DisplayReconfigurationCallBack(CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags, void *userInfo);

OOINLINE id DisplayIDKey(CGDirectDisplayID displayID)
{
	/// CGDirectDisplayID changed from opaque pointer to 32-bit integer for Leopard
	return [NSNumber numberWithUnsignedInt:(unsigned int)displayID];
}


@implementation OODisplayMacOSX

+ (NSArray *) allDisplays
{
	// If we don't have a list, build one.
	if (sDisplayIDToDisplay == nil)  [self buildDisplayTable];
	if (sDisplayList == nil)  [self updateDisplayList];
	
	if (!sCallbackInstalled)
	{
		[self installCallback];
	}
	
	return sDisplayList;
}


- (void) dealloc
{
	[_name release];
	[_modes makeObjectsPerformSelector:@selector(invalidate)];	// Ensure modes don't have back references to display, in case they're retained somewhere else.
	[_modes release];
	
	[super dealloc];
}


- (NSString *) name
{
	if (_name == nil)  _name = [[self determineName] retain];
	return _name;
}


- (NSArray *) modes
{
	if (_modes == nil)  [self buildModeList];
	
	return _modes;
}


- (unsigned) indexOfCurrentMode
{
	NSEnumerator			*modeEnum = nil;
	OODisplayModeMacOSX		*mode = nil;
	NSDictionary			*modeDict = nil;
	unsigned				i = 0;
	
	modeDict = (NSDictionary *)CGDisplayCurrentMode(_displayID);
	for (modeEnum = [[self modes] objectEnumerator]; (mode = [modeEnum nextObject]); )
	{
		if ([mode matchesModeDictionary:modeDict])  return i;
		i++;
	}
	
	return NSNotFound;
}


- (NSDictionary *) matchingDictionary
{
	NSMutableDictionary		*result = nil;
	NSDictionary			*ioKitMatchingDict = nil;
	
	result = [NSMutableDictionary dictionary];
	ioKitMatchingDict = [self ioKitInfoWithFlags:kIODisplayMatchingInfo];
	if (ioKitMatchingDict != nil)  [result setObject:ioKitMatchingDict forKey:@"mac-iokit-matching-dict"];
	
	return result;
}


+ (id) displayForMatchingDictionary:(NSDictionary *)dictionary
{
	return nil;
}


- (float) aspectRatio
{
	NSEnumerator			*modeEnum = nil;
	OODisplayModeMacOSX		*mode = nil;
	
	if (_aspectRatio == 0.0)
	{
		// Calculate aspect ratio as (total) aspect ratio of largest mode.
		for (modeEnum = [[self modes] reverseObjectEnumerator]; (mode = [modeEnum nextObject]); )
		{
			if (![mode isStretched])  break;
		}
		
		if (mode != nil)
		{
			_aspectRatio = (float)[mode width] / (float)[mode height];
		}
		else
		{
			// Fallback, could potentially happen if all modes are stretched (which would be silly, but hey).
			_aspectRatio = 1.0;
		}
	}
	
	return _aspectRatio;
}

@end


@implementation OODisplayMacOSX (Private)

- (id) initWithDisplayID:(CGDirectDisplayID)displayID
{
	self = [super init];
	if (self != nil)
	{
		_displayID = displayID;
	}
	
	return self;
}


- (CGDirectDisplayID) displayID
{
	return _displayID;
}


- (NSString *) determineName
{
	NSString				*result = nil;
	NSDictionary			*info = nil;
	NSDictionary			*names = nil;
	
#if !defined __LP64__ && MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_4
	// Old method, deprecated in 10.4, not available in 64-bit, but I trust it more.
	OSStatus			err;
	Str255				str255Name;
	
	// Get name of monitor. This cast to a different type from a different API
	// has been declared safe on the mac-games-dev list in times of yore.
	err = DMGetNameByAVID((DisplayIDType)_displayID, 0, str255Name);
	if (err == noErr && str255Name[0] != 0)
	{
		result = (NSString *)CFStringCreateWithPascalString(kCFAllocatorDefault, str255Name, CFStringGetSystemEncoding());
		[result autorelease];
	}
#endif
	
	if (result == nil)
	{
		// kIODisplayOnlyPreferredName	= 0x00000200, not declared in 10.3.9 SDK
		// Causes best-match name (by language) to be used
		info = [self ioKitInfoWithFlags:0x00000200];
		if (info != nil)
		{
			names = [info objectForKey:@kDisplayProductName];
			if ([names count] > 0)
			{
				result = [[names allValues] objectAtIndex:0];
			}
		}
	}
	
	if (result == nil)
	{
		result = [NSString stringWithFormat:@"Display ID %u", _displayID];
	}
	
	return result;
}


- (NSDictionary *) ioKitInfoWithFlags:(IOOptionBits)flags
{
	io_service_t			servicePort;
	NSDictionary			*info = nil;
	
	servicePort = CGDisplayIOServicePort(_displayID);
	if (MACH_PORT_VALID(servicePort))
	{
		info = (NSDictionary *)IODisplayCreateInfoDictionary(servicePort, flags);
		[info autorelease];
	}
	
	return info;
}


- (void) buildModeList
{
	NSArray							*modeDicts = nil;
	NSEnumerator					*modeEnum = nil;
	NSDictionary					*modeDict = nil;
	NSMutableArray					*result = nil;
	OODisplayModeMacOSX				*mode = nil;
	
	modeDicts = (NSArray *)CGDisplayAvailableModes(_displayID);
	result = [NSMutableArray arrayWithCapacity:[modeDict count]];
	
	for (modeEnum = [modeDicts objectEnumerator]; (modeDict = [modeEnum nextObject]); )
	{
		mode = [[OODisplayModeMacOSX alloc] initForDisplay:self modeDictionary:modeDict];
		if (mode != nil)
		{
			[result addObject:mode];
			[mode release];
		}
	}
	
	[result sortUsingSelector:@selector(compare:)];
	_modes = [result copy];
}

@end


@implementation OODisplayMacOSX (PrivateDisplayManagement)

+ (void) buildDisplayTable
{
	CGDisplayErr			err = kCGErrorSuccess;
	CGDisplayCount			i, count;
	
	[sDisplayIDToDisplay release];
	sDisplayIDToDisplay = nil;
	[self invalidateDisplayList];
	
	// Find out how many displays there are.
	err = CGGetActiveDisplayList(0, NULL, &count);
	if (err == kCGErrorSuccess)
	{
		// Get the list.
		CGDirectDisplayID displayIDs[count];
		err = CGGetActiveDisplayList(count, displayIDs, &count);
		
		if (err == kCGErrorSuccess)
		{
			// Build list of OODisplayMacOSXs.
			sDisplayIDToDisplay = [[NSMutableDictionary alloc] initWithCapacity:count];
			
			for (i = 0; i != count; ++i)
			{
				[self addDisplayWithDisplayID:displayIDs[i]];
			}
		}
	}
	
	if (err != kCGErrorSuccess)
	{
		OOLog(@"display.buildTable.failed", @"Failed to build display table with CGDirectDisplay error %li.", (long)err);
	}
}


+ (void) updateDisplayList
{
	/*	Create list of displays, in order specified by CGDirectDisplay.
		This is a separate method because order is invalidated when a new
		display is added.
	*/
	CGDisplayErr			err = kCGErrorSuccess;
	CGDisplayCount			i, count;
	OODisplayMacOSX			*display = nil;
	
	[self invalidateDisplayList];
	if (sDisplayIDToDisplay == nil)  return;
	
	// Find out how many displays there are.
	err = CGGetActiveDisplayList(0, NULL, &count);
	if (err == kCGErrorSuccess)
	{
		// Get the list.
		CGDirectDisplayID displayIDs[count];
		err = CGGetActiveDisplayList(count, displayIDs, &count);
		
		if (err == kCGErrorSuccess)
		{
			// Build list of OODisplayMacOSXs.
			sDisplayList = [[NSMutableArray alloc] initWithCapacity:count];
			
			for (i = 0; i != count; ++i)
			{
				display = [self displayWithDisplayID:displayIDs[i]];
				if (display != nil)
				{
					[sDisplayList addObject:display];
				}
			}
		}
	}
	
	if (err != kCGErrorSuccess)
	{
		// Fallback: arbitrary order.
		sDisplayList = [[sDisplayIDToDisplay allValues] mutableCopy];
	}
}


+ (void) invalidateDisplayList
{
	[sDisplayList release];
	sDisplayList = nil;
}


+ (void) installCallback
{
	CGDisplayRegisterReconfigurationCallback(DisplayReconfigurationCallBack, NULL);
	sCallbackInstalled = YES;
}


+ (id) addDisplayWithDisplayID:(CGDirectDisplayID)displayID
{
	OODisplayMacOSX			*display = nil;
	
	display = [self displayWithDisplayID:displayID];
	if (display != nil)
	{
		OOLog(@"display.add.inconsistency", @"Internal display management error: attempt to add a display ID that already exists.");
	}
	else
	{
		// Update by-ID table
		display = [[self alloc] initWithDisplayID:displayID];
		[display autorelease];
		[sDisplayIDToDisplay setObject:display forKey:DisplayIDKey(displayID)];
		
		// Force ordered list to be updated lazily
		[self invalidateDisplayList];
	}
	return display;
}


+ (void) removeDisplay:(OODisplayMacOSX *)display
{
	if (display == nil)  return;
	
	if (display != [self displayWithDisplayID:[display displayID]])
	{
		OOLog(@"display.add.inconsistency", @"Internal display management error: attempt to remove a display that doesn't exist.");
	}
	else
	{
		// Update by-ID table
		[sDisplayList removeObject:display];
		
		// Update ordered list immediately, since removing doesn't change order of remaining entries.
		[sDisplayIDToDisplay removeObjectForKey:DisplayIDKey([display displayID])];
	}
}


+ (void) displayWithID:(CGDirectDisplayID)displayID reconfiguredWithChangeFlags:(CGDisplayChangeSummaryFlags)flags
{
	OODisplayMacOSX			*display = nil;
	
	OOLog(@"", @"Display %p (%@) reconfigured with flags: 0x%X", displayID, [self displayWithDisplayID:displayID], flags);
	
	NS_DURING
		if (flags & kCGDisplayAddFlag)
		{
			display = [self addDisplayWithDisplayID:displayID];
			[[NSNotificationCenter defaultCenter] postNotificationName:kOODisplayAddedNotification
																object:display];
		}
		if (flags & kCGDisplayRemoveFlag)
		{
			display = [self displayWithDisplayID:displayID];
			if (display != nil)
			{
				[[display retain] autorelease];
				[self removeDisplay:display];
				[[NSNotificationCenter defaultCenter] postNotificationName:kOODisplayRemovedNotification
																	object:display];
			}
		}
		if (flags & kCGDisplaySetModeFlag)
		{
			display = [self displayWithDisplayID:displayID];
			if (display != nil)
			{
				[[NSNotificationCenter defaultCenter] postNotificationName:kOODisplaySettingsChangedNotification
																	object:display];
			}
		}
		if (flags & kCGDisplaySetMainFlag)
		{
			[self invalidateDisplayList];
			[[NSNotificationCenter defaultCenter] postNotificationName:kOODisplayOrderChangedNotification
																object:nil];
		}
	NS_HANDLER
		OOLog(@"display.notify.exception", @"Squelching %@ exception posted during display configuration change notification: %@", [localException name], [localException reason]);
	NS_ENDHANDLER
}


+ (OODisplayMacOSX *) displayWithDisplayID:(CGDirectDisplayID)displayID
{
	return [sDisplayIDToDisplay objectForKey:DisplayIDKey(displayID)];
}

@end


static void DisplayReconfigurationCallBack(CGDirectDisplayID displayID, CGDisplayChangeSummaryFlags flags, void *userInfo)
{
	[OODisplayMacOSX displayWithID:displayID reconfiguredWithChangeFlags:flags];
}
