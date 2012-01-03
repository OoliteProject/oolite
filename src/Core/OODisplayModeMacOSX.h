//
//  OODisplayModeMacOSX.h
//  DisplayTest
//
//  Created by Jens Ayton on 2007-12-08.
//  Copyright 2007-2012 Jens Ayton. All rights reserved.
//

#import "OODisplayMode.h"

@class OODisplayMacOSX;


@interface OODisplayModeMacOSX: OODisplayMode
{
	OODisplayMacOSX			*_display;
	NSDictionary			*_mode;
}

- (id) initForDisplay:(OODisplayMacOSX *)display modeDictionary:(NSDictionary *)modeDict;
- (void) invalidate;

// Used to find current mode.
- (BOOL) matchesModeDictionary:(NSDictionary *)modeDict;

@end
