//
//  OODisplayMacOSX.h
//  Oolite
//
//  Created by Jens Ayton on 2007-12-08.
//  Copyright 2007-2011 Jens Ayton. All rights reserved.
//

#import "OODisplay.h"
#import <ApplicationServices/ApplicationServices.h>


@interface OODisplayMacOSX: OODisplay
{
	CGDirectDisplayID		_displayID;
	NSString				*_name;
	NSArray					*_modes;
	float					_aspectRatio;
}

/*	The aspect ratio of the screen, or buest guesstimate, based on aspect
	ratio of largest non-stretched mode. Used to calculate pixel aspect ratios
	for modes.
	
	Note: 4:3 CRTs tend to have non-4:3 modes like 1152x870 (192:145). However,
	these can typically be adjusted to squarish pixel ratio with screen
	controls, so may or may not be stretched. The OS reports these as non-
	stretched, so we report an aspect ratio of 1.0.
*/
- (float) aspectRatio;

@end
