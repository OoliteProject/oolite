//
//  OODisplayModeSDL.h
//  DisplayTest
//
//  Created by Jens Ayton on 2007-12-30.
//  Copyright 2007 Jens Ayton. All rights reserved.
//

#import "OODisplayMode.h"

@class OODisplaySDL;


@interface OODisplayModeSDL: OODisplayMode
{
	OODisplaySDL			*_display;
	unsigned				_width,
							_height,
							_depth;
}

- (id) initWithDisplay:(OODisplaySDL *)display
				 width:(unsigned)width
				height:(unsigned)height
				 depth:(unsigned)depth;

- (void) invalidate;

@end
