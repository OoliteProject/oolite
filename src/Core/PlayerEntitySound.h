//
//  PlayerEntity (Sound).h
//  Oolite
//
//  Created by Jens Ayton on 2005-11-21.
//  Copyright 2005 __MyCompanyName__. All rights reserved.
//

#import "PlayerEntity.h"


enum
{
	kInterfaceBeep_Beep				= 1UL,
	kInterfaceBeep_Boop,
	kInterfaceBeep_Buy,
	kInterfaceBeep_Sell
};


@interface PlayerEntity (Sound)

- (void)setUpSound;
- (void)destroySound;

- (void)beep;
- (void)boop;
- (void)playInterfaceBeep:(unsigned)inInterfaceBeep;
- (BOOL)isBeeping;

- (void)playECMSound;
- (void)stopECMSound;

- (void)playBreakPattern;

@end
