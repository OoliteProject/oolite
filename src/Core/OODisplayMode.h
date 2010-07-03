//
//  OODisplayMode.h
//  Oolite
//
//  Created by Jens Ayton on 2007-12-08.
//  Copyright 2007-2010 Jens Ayton. All rights reserved.
//

#import "OOCocoa.h"

@class OODisplay;


@interface OODisplayMode: NSObject

- (OODisplay *) display;

- (NSString *) userDescription;

- (unsigned) width;
- (unsigned) height;
- (unsigned) bitDepth;
- (float) refreshRate;

- (BOOL) isStretched;
- (float) aspectRatio;			// Pixel aspect ratio, or stretch factor. For a non-stretched mode, 1.0. For a 4:3 mode on an 8:5 screen, (8/5)/(4/3) = (8*3)/(4*5) = 24/20 = 6/5.

- (BOOL) isInterlaced;
- (BOOL) isTV;

- (BOOL) requiresConfirmation;	// if YES, it is not safe to switch to this mode without a confirmation alert and automatic reset dance.

- (BOOL) isOKForWindowedMode;
- (BOOL) isOKForFullScreenMode;

@end


@interface OODisplayMode (Utilities)

- (NSComparisonResult) compare:(id)other;

- (NSSize) dimensions;
- (float) pixelArea;

@end
