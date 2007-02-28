/*

PlayerEntitySound.m
Created by Jens Ayton on 2005-05-01.

For Oolite
Copyright (C) 2005  Giles C Williams and Jens Ayton

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#import "PlayerEntitySound.h"
#import "OOSound.h"
#import "OOSoundSource.h"
#import "ResourceManager.h"


/*
	If BEEP_MODE is 0, playing two identical beeps (i.e. beep twice, or boop twice) will result in
	that beep being played twice in a row. If it is 1, the playing beep will be interrupted. If it
	is 2, two beeps will play at once with the CA implementation (and interfaceBeepSource will be
	unused).
*/
#define BEEP_MODE			1


@implementation PlayerEntity (Sound)

- (void)setUpSound
{
	#ifdef HAVE_SOUND
		[self destroySound];
		
		beepSound =			[[ResourceManager ooSoundNamed:@"beep.ogg" inFolder:@"Sounds"] retain];
		boopSound =			[[ResourceManager ooSoundNamed:@"boop.ogg" inFolder:@"Sounds"] retain];
		weaponSound =		[[ResourceManager ooSoundNamed:@"laser.ogg" inFolder:@"Sounds"] retain];
		weaponHitSound =	[[ResourceManager ooSoundNamed:@"laserhits.ogg" inFolder:@"Sounds"] retain];
		missileSound =		[[ResourceManager ooSoundNamed:@"missile.ogg" inFolder:@"Sounds"] retain];
		damageSound =		[[ResourceManager ooSoundNamed:@"hit.ogg" inFolder:@"Sounds"] retain];
		scrapeDamageSound = [[ResourceManager ooSoundNamed:@"hullbang.ogg" inFolder:@"Sounds"] retain];
		destructionSound =  [[ResourceManager ooSoundNamed:@"bigbang.ogg" inFolder:@"Sounds"] retain];
		breakPatternSound = [[ResourceManager ooSoundNamed:@"breakpattern.ogg" inFolder:@"Sounds"] retain];
		//
		ecmSound =			[[ResourceManager ooSoundNamed:@"ecm.ogg" inFolder:@"Sounds"] retain];
		buySound =			[[ResourceManager ooSoundNamed:@"buy.ogg" inFolder:@"Sounds"] retain];
		sellSound =			[[ResourceManager ooSoundNamed:@"sell.ogg" inFolder:@"Sounds"] retain];
		warningSound =		[[ResourceManager ooSoundNamed:@"warning.ogg" inFolder:@"Sounds"] retain];
		afterburner1Sound =	[[ResourceManager ooSoundNamed:@"afterburner1.ogg" inFolder:@"Sounds"] retain];
		afterburner2Sound =	[[ResourceManager ooSoundNamed:@"afterburner2.ogg" inFolder:@"Sounds"] retain];
		//
		witchAbortSound =	[[ResourceManager ooSoundNamed:@"witchabort.ogg" inFolder:@"Sounds"] retain];
		//
		fuelScoopSound =	[[ResourceManager ooSoundNamed:@"scoop.ogg" inFolder:@"Sounds"] retain];
		
		themeMusic =		[[ResourceManager ooMusicNamed:@"OoliteTheme.ogg" inFolder:@"Music"] retain];
		missionMusic =		[[ResourceManager ooMusicNamed:@"OoliteTheme.ogg" inFolder:@"Music"] retain];
		dockingMusic =		[[ResourceManager ooMusicNamed:@"BlueDanube.ogg" inFolder:@"Music"] retain];
		
		refPoint = [[OOSoundReferencePoint alloc] init];
		interfaceBeepSource = [[OOSoundSource alloc] init];
		breakPatternSource = [[OOSoundSource alloc] init];
		ecmSource = [[OOSoundSource alloc] init];
	#endif
}


- (void)destroySound
{
	#ifdef HAVE_SOUND
		[beepSound release];
		beepSound = nil;
		[boopSound release];
		boopSound = nil;
		[weaponSound release];
		weaponSound = nil;
		[weaponHitSound release];
		weaponHitSound = nil;
		[damageSound release];
		damageSound = nil;
		[scrapeDamageSound release];
		scrapeDamageSound = nil;
		[destructionSound release];
		destructionSound = nil;
		[breakPatternSound release];
		breakPatternSound = nil;
		
		[ecmSound release];
		ecmSound = nil;
		[buySound release];
		buySound = nil;
		[sellSound release];
		sellSound = nil;
		[warningSound release];
		warningSound = nil;
		[afterburner1Sound release];
		afterburner1Sound = nil;
		[afterburner2Sound release];
		afterburner2Sound = nil;
		
		[witchAbortSound release];
		witchAbortSound = nil;
		
		[fuelScoopSound release];
		fuelScoopSound = nil;
		
		
		[themeMusic release];
		themeMusic = nil;
		[missionMusic release];
		missionMusic = nil;
		[dockingMusic release];
		dockingMusic = nil;
		
		[refPoint release];
		refPoint = nil;
		[interfaceBeepSource release];
		interfaceBeepSource = nil;
		[ecmSource release];
		ecmSource = nil;
		[breakPatternSource release];
		breakPatternSource = nil;
	#endif
}


- (void)beep
{
	[self playInterfaceBeep:kInterfaceBeep_Beep];
}


- (void)boop
{
	[self playInterfaceBeep:kInterfaceBeep_Boop];
}


- (void)playInterfaceBeep:(unsigned)inInterfaceBeep
{
	#ifdef HAVE_SOUND
		OOSound					*sound = nil;
		
		switch (inInterfaceBeep)
		{
			case kInterfaceBeep_Beep:
				sound = beepSound;
				break;
			
			case kInterfaceBeep_Boop:
				sound = boopSound;
				break;
			
			case kInterfaceBeep_Buy:
				sound = buySound;
				break;
			
			case kInterfaceBeep_Sell:
				sound = sellSound;
				break;
			
			default:
				NSLog(@"Invalid beep selector: %u", inInterfaceBeep);
		}
		
		#if BEEP_MODE == 0
			[interfaceBeepSource playOrRepeatSound:sound];
		#elif BEEP_MODE == 1
			[interfaceBeepSource playSound:sound];
		#elif BEEP_MODE == 2
			[sound play];
		#else
			#error Unknown BEEP_MODE
		#endif
	#endif
}


- (BOOL)isBeeping
{
	#ifdef HAVE_SOUND
		return [interfaceBeepSource isPlaying];
	#else
		return NO;
	#endif
}


- (void)playECMSound
{
	#ifdef HAVE_SOUND
		if (![ecmSource isPlaying]) [ecmSource playSound:ecmSound];
	#endif
}


- (void)stopECMSound
{
	#ifdef HAVE_SOUND
		[ecmSource stop];
	#endif
}


- (void)playBreakPattern
{
	#ifdef HAVE_SOUND
		[breakPatternSource playSound:breakPatternSound];
	#endif
}

@end
