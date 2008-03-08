/*

PlayerEntitySound.m

Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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
#import "ResourceManager.h"
#import "Universe.h"
#import "OOSoundSourcePool.h"


/*
	If BEEP_MODE is 0, playing two identical beeps (i.e. beep twice, or boop twice) will result in
	that beep being played twice in a row. If it is 1, the playing beep will be interrupted. If it
	is 2, two beeps will play at once with the CA implementation (and interfaceBeepSource will be
	unused).
*/
#define BEEP_MODE			1


// Sizes of sound source pools
enum
{
	kWarningPoolSize		= 2,
	kWeaponPoolSize			= 2,
	kDamagePoolSize			= 4
};


static OOSoundSourcePool	*sWarningSoundPool;
static OOSoundSourcePool	*sWeaponSoundPool;
static OOSoundSourcePool	*sDamageSoundPool;


@implementation PlayerEntity (Sound)

- (void) setUpSound
{
	[self destroySound];
	
	beepSound =			[[ResourceManager ooSoundNamed:@"beep.ogg" inFolder:@"Sounds"] retain];
	boopSound =			[[ResourceManager ooSoundNamed:@"boop.ogg" inFolder:@"Sounds"] retain];
	missileSound =		[[ResourceManager ooSoundNamed:@"missile.ogg" inFolder:@"Sounds"] retain];
	
	buySound =			[[ResourceManager ooSoundNamed:@"buy.ogg" inFolder:@"Sounds"] retain];
	sellSound =			[[ResourceManager ooSoundNamed:@"sell.ogg" inFolder:@"Sounds"] retain];
	afterburner1Sound =	[[ResourceManager ooSoundNamed:@"afterburner1.ogg" inFolder:@"Sounds"] retain];
	afterburner2Sound =	[[ResourceManager ooSoundNamed:@"afterburner2.ogg" inFolder:@"Sounds"] retain];
	
	witchAbortSound =	[[ResourceManager ooSoundNamed:@"witchabort.ogg" inFolder:@"Sounds"] retain];
	
	fuelScoopSound =	[[ResourceManager ooSoundNamed:@"scoop.ogg" inFolder:@"Sounds"] retain];
	
	refPoint = [[OOSoundReferencePoint alloc] init];
	interfaceBeepSource = [[OOSoundSource alloc] init];
	breakPatternSource = [[OOSoundSource alloc] init];
	ecmSource = [[OOSoundSource alloc] init];
	
	sWarningSoundPool = [[OOSoundSourcePool alloc] initWithCount:kWarningPoolSize minRepeatTime:0];
	sWeaponSoundPool = [[OOSoundSourcePool alloc] initWithCount:kWeaponPoolSize minRepeatTime:0];
	sDamageSoundPool = [[OOSoundSourcePool alloc] initWithCount:kDamagePoolSize minRepeatTime:0.1];	// Repeat time limit is to avoid playing a scrape sound every frame on glancing scrapes. This does limit the number of laser hits that can be played in a furrball, though; maybe lasers and scrapes should use different pools.
}


- (void) destroySound
{
	[beepSound release];
	beepSound = nil;
	[boopSound release];
	boopSound = nil;
	[buySound release];
	buySound = nil;
	[sellSound release];
	sellSound = nil;
	[afterburner1Sound release];
	afterburner1Sound = nil;
	[afterburner2Sound release];
	afterburner2Sound = nil;
	
	[witchAbortSound release];
	witchAbortSound = nil;
	
	[fuelScoopSound release];
	fuelScoopSound = nil;
	
	[refPoint release];
	refPoint = nil;
	[interfaceBeepSource release];
	interfaceBeepSource = nil;
	[ecmSource release];
	ecmSource = nil;
	[breakPatternSource release];
	breakPatternSource = nil;
	
	[sWarningSoundPool release];
	sWarningSoundPool = nil;
	[sWeaponSoundPool release];
	sWeaponSoundPool = nil;
	[sDamageSoundPool release];
	sDamageSoundPool = nil;
}


- (void) beep
{
	[self playInterfaceBeep:kInterfaceBeep_Beep];
}


- (void) boop
{
	[self playInterfaceBeep:kInterfaceBeep_Boop];
}


- (void) playInterfaceBeep:(unsigned)inInterfaceBeep
{
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
			OOLog(@"sound.invalidBeep", @"Invalid beep selector: %u", inInterfaceBeep);
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
}


- (BOOL) isBeeping
{
	return [interfaceBeepSource isPlaying];
}


- (void) playHitByECMSound
{
	if (![ecmSource isPlaying]) [ecmSource playCustomSoundWithKey:@"[player-hit-by-ecm]"];
}


- (void) playFiredECMSound
{
	if (![ecmSource isPlaying]) [ecmSource playCustomSoundWithKey:@"[player-fired-ecm]"];
}


- (void) playLaunchFromStation
{
	[breakPatternSource playCustomSoundWithKey:@"[player-launch-from-station]"];
}


- (void) playDockWithStation
{
	[breakPatternSource playCustomSoundWithKey:@"[player-dock-with-station]"];
}


- (void) playExitWitchspace
{
	[breakPatternSource playCustomSoundWithKey:@"[player-exit-witchspace]"];
}


- (void) playHostileWarning
{
	[sWarningSoundPool playSoundWithKey:@"[hostile-warning]" priority:1];
}


- (void) playAlertConditionRed
{
	[sWarningSoundPool playSoundWithKey:@"[alert-condition-red]" priority:2];
}


- (void) playIncomingMissile
{
	[sWarningSoundPool playSoundWithKey:@"[incoming-missile]" priority:3];
}


- (void) playEnergyLow
{
	[sWarningSoundPool playSoundWithKey:@"[energy-low]" priority:0.5];
}


- (void) playDockingDenied
{
	[sWarningSoundPool playSoundWithKey:@"[autopilot-denied]" priority:1];
}


- (void) playWitchjumpFailure
{
	[sWarningSoundPool playSoundWithKey:@"[witchdrive-failure]" priority:1.5];
}


- (void) playWitchjumpMisjump
{
	[sWarningSoundPool playSoundWithKey:@"[witchdrive-malfunction]" priority:1.5];
}


- (void) playFuelLeak
{
	[sWarningSoundPool playSoundWithKey:@"[fuel-leak]" priority:0.5];
}


- (void) playShieldHit
{
	[sDamageSoundPool playSoundWithKey:@"[player-hit-by-weapon]"];
}


- (void) playDirectHit
{
	[sDamageSoundPool playSoundWithKey:@"[player-direct-hit]"];
}


- (void) playScrapeDamage
{
	[sDamageSoundPool playSoundWithKey:@"[player-scrape-damage]"];
}


- (void) playLaserHit:(BOOL)hit
{
	if (hit)
	{
		[sWeaponSoundPool playSoundWithKey:@"[player-laser-hit]" priority:1 expiryTime:0.05];
	}
	else
	{
		[sWeaponSoundPool playSoundWithKey:@"[player-laser-miss]" priority:1 expiryTime:0.05];
	}
}

@end
