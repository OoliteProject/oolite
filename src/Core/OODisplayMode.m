//
//  OODisplayMode.m
//  Oolite
//
//  Created by Jens Ayton on 2007-12-08.
//  Copyright 2007-2010 Jens Ayton. All rights reserved.
//

#import "OODisplayMode.h"


@interface OODisplayMode (Private)

- (unsigned) sortFlagBits;

@end


@implementation OODisplayMode

- (NSString *) descriptionComponents
{
	return [self userDescription];
}


- (OODisplay *) display
{
	OOLogGenericSubclassResponsibility();
	return nil;
}


- (NSString *) userDescription
{
	NSMutableString		*result = nil;
	NSSize				dimensions;
	float				refresh;
	NSMutableArray		*misc;
	
	dimensions = [self dimensions];
	result = [NSMutableString stringWithFormat:@"%u x %u", (unsigned)dimensions.width, (unsigned)dimensions.height];
	
	refresh = [self refreshRate];
	if (refresh > 0.0f)  [result appendFormat:@", %.3g Hz"];
	
	misc = [NSMutableArray array];
	if ([self isStretched])  [misc addObject:@"stretched"];
	if ([self isInterlaced])  [misc addObject:@"interlaced"];
	if ([self isTV])  [misc addObject:@"TV"];
	if ([misc count] > 0)  [result appendFormat:@" (%@)", [misc componentsJoinedByString:@", "]];
	
	return result;
}


- (unsigned) width
{
	OOLogGenericSubclassResponsibility();
	return 0;
}


- (unsigned) height
{
	OOLogGenericSubclassResponsibility();
	return 0;
}


- (unsigned) bitDepth
{
	OOLogGenericSubclassResponsibility();
	return 0;
}


- (float) refreshRate
{
	return 0.0f;
}


- (BOOL) isStretched
{
	return NO;
}


- (float) aspectRatio
{
	return 1.0f;
}


- (BOOL) isInterlaced
{
	return NO;
}


- (BOOL) isTV
{
	return NO;
}


- (BOOL) requiresConfirmation
{
	return NO;
}


- (BOOL) isOKForWindowedMode
{
	return YES;
}


- (BOOL) isOKForFullScreenMode
{
	return YES;
}

@end


@implementation OODisplayMode (Utilities)

- (NSComparisonResult) compare:(id)other
{
	if (![other isKindOfClass:[OODisplayMode class]])  return NSOrderedSame;
	
	// First criterion: area. Screens with larger areas are listed later.
	float myArea = [self pixelArea], otherArea = [other pixelArea];
	if (myArea < otherArea)  return NSOrderedAscending;
	if (myArea > otherArea)  return NSOrderedDescending;
	
	// Second criterion: flags.
	unsigned myFlags = [self sortFlagBits], otherFlags = [other sortFlagBits];
	if (myFlags < otherFlags)  return NSOrderedAscending;
	if (myFlags > otherFlags)  return NSOrderedDescending;
	
	// Third criterion: refresh rate.
	float myRefreshRate = [self refreshRate], otherRefreshRate = [other refreshRate];
	if (myRefreshRate < otherRefreshRate)  return NSOrderedAscending;
	if (myRefreshRate > otherRefreshRate)  return NSOrderedDescending;
	
	// Fouth criterion: display depth.
	unsigned myDepth = [self bitDepth], otherDepth = [other bitDepth];
	if (myDepth < otherDepth)  return NSOrderedAscending;
	if (myDepth > otherDepth)  return NSOrderedDescending;
	
	return NSOrderedSame;
}


- (NSSize) dimensions
{
	return NSMakeSize([self width], [self height]);
}


- (float) pixelArea
{
	NSSize dimensions = [self dimensions];
	return dimensions.width * dimensions.height;
}

@end


@implementation OODisplayMode (Private)

- (unsigned) sortFlagBits
{
	// Return flags packed into an int for -compare:.
	unsigned			result = 0;
	
	if ([self isStretched])  result |= 0x01;
	if ([self isInterlaced])  result |= 0x02;
	if ([self isTV])  result |= 0x04;
	
	return result;
}

@end
