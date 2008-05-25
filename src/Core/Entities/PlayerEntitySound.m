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
static OOSoundSource		*sHyperspaceSoundSource;
static OOSoundSource		*sInterfaceBeepSource;
static OOSoundSource		*sEcmSource;
static OOSoundSource		*sBreakPatternSource;
static OOSoundSource		*sBuySellSource;


@implementation PlayerEntity (Sound)

- (void) setUpSound
{
	[self destroySound];
	
	missileSound =		[[ResourceManager ooSoundNamed:@"missile.ogg" inFolder:@"Sounds"] retain];
	
	afterburner1Sound =	[[ResourceManager ooSoundNamed:@"afterburner1.ogg" inFolder:@"Sounds"] retain];
	afterburner2Sound =	[[ResourceManager ooSoundNamed:@"afterburner2.ogg" inFolder:@"Sounds"] retain];
	
	witchAbortSound =	[[ResourceManager ooSoundNamed:@"witchabort.ogg" inFolder:@"Sounds"] retain];
	
	fuelScoopSound =	[[ResourceManager ooSoundNamed:@"scoop.ogg" inFolder:@"Sounds"] retain];
	
	refPoint = [[OOSoundReferencePoint alloc] init];
	
	sInterfaceBeepSource = [[OOSoundSource alloc] init];
	sBreakPatternSource = [[OOSoundSource alloc] init];
	sEcmSource = [[OOSoundSource alloc] init];
	sHyperspaceSoundSource = [[OOSoundSource alloc] init];
	sBuySellSource = [[OOSoundSource alloc] init];
	
	sWarningSoundPool = [[OOSoundSourcePool alloc] initWithCount:kWarningPoolSize minRepeatTime:0];
	sWeaponSoundPool = [[OOSoundSourcePool alloc] initWithCount:kWeaponPoolSize minRepeatTime:0];
	sDamageSoundPool = [[OOSoundSourcePool alloc] initWithCount:kDamagePoolSize minRepeatTime:0.1];	// Repeat time limit is to avoid playing a scrape sound every frame on glancing scrapes. This does limit the number of laser hits that can be played in a furrball, though; maybe lasers and scrapes should use different pools.
}


- (void) destroySound
{
	[missileSound release];
	missileSound = nil;
	
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
	
	[sInterfaceBeepSource release];
	sInterfaceBeepSource = nil;
	[sBreakPatternSource release];
	sBreakPatternSource = nil;
	[sEcmSource release];
	sEcmSource = nil;
	[sHyperspaceSoundSource release];
	sHyperspaceSoundSource = nil;
	[sBuySellSource release];
	sBuySellSource = nil;
	
	[sWarningSoundPool release];
	sWarningSoundPool = nil;
	[sWeaponSoundPool release];
	sWeaponSoundPool = nil;
	[sDamageSoundPool release];
	sDamageSoundPool = nil;
}


- (void) playInterfaceBeep:(NSString *)beepKey
{
	[sInterfaceBeepSource playSound:[OOSound soundWithCustomSoundKey:beepKey]];
}


- (BOOL) isBeeping
{
	return [sInterfaceBeepSource isPlaying];
}


- (void) boop
{
	[self playInterfaceBeep:@"[general-boop]"];
}


- (void) playIdentOn
{
	[self playInterfaceBeep:@"[ident-on]"];
}


- (void) playIdentOff
{
	[self playInterfaceBeep:@"[ident-off]"];
}


- (void) playIdentLockedOn
{
	[self playInterfaceBeep:@"[ident-locked-on]"];
}


- (void) playMissileArmed
{
	[self playInterfaceBeep:@"[missile-armed]"];
}


- (void) playMineArmed
{
	[self playInterfaceBeep:@"[mine-armed]"];
}


- (void) playMissileSafe
{
	[self playInterfaceBeep:@"[missile-safe]"];
}


- (void) playMissileLockedOn
{
	[self playInterfaceBeep:@"[missile-locked-on]"];
}


- (void) playNextMissileSelected
{
	[self playInterfaceBeep:@"[next-missile-selected]"];
}


- (void) playCargoJettisioned
{
	[self playInterfaceBeep:@"[cargo-jettisoned]"];
}


- (void) playAutopilotOn
{
	[self playInterfaceBeep:@"[autopilot-on]"];
}


- (void) playAutopilotOff
{
	[self playInterfaceBeep:@"[autopilot-off]"];
}


- (void) playAutopilotOutOfRange
{
	[self playInterfaceBeep:@"[autopilot-out-of-range]"];
}


- (void) playAutopilotCannotDockWithTarget
{
	[self playInterfaceBeep:@"[autopilot-cannot-dock-with-target]"];
}


- (void) playSaveOverwriteYes
{
	[self playInterfaceBeep:@"[save-overwrite-yes]"];
}


- (void) playSaveOverwriteNo
{
	[self playInterfaceBeep:@"[save-overwrite-no]"];
}


- (void) playHoldFull
{
	[self playInterfaceBeep:@"[hold-full]"];
}


- (void) playJumpMassLocked
{
	[self playInterfaceBeep:@"[jump-mass-locked]"];
}


- (void) playTargetLost
{
	[self playInterfaceBeep:@"[target-lost]"];
}


- (void) playNoTargetInMemory
{
	[self playInterfaceBeep:@"[no-target-in-memory]"];
}


- (void) playTargetSwitched
{
	[self playInterfaceBeep:@"[target-switched]"];
}


- (void) playHyperspaceNoTarget
{
	[self playInterfaceBeep:@"[witch-no-target]"];
}


- (void) playHyperspaceNoFuel
{
	[self playInterfaceBeep:@"[witch-no-fuel]"];
}


- (void) playHyperspaceBlocked
{
	[self playInterfaceBeep:@"[witch-blocked-by-@]"];
}


- (void) playCloakingDeviceOn
{
	[self playInterfaceBeep:@"[cloaking-device-on]"];
}


- (void) playCloakingDeviceOff
{
	[self playInterfaceBeep:@"[cloaking-device-off]"];
}


- (void) playMenuNavigationUp
{
	[self playInterfaceBeep:@"[menu-navigation-up]"];
}


- (void) playMenuNavigationDown
{
	[self playInterfaceBeep:@"[menu-navigation-down]"];
}


- (void) playMenuNavigationNot
{
	[self playInterfaceBeep:@"[menu-navigation-not]"];
}


- (void) playMenuPagePrevious
{
	[self playInterfaceBeep:@"[menu-next-page]"];
}


- (void) playMenuPageNext
{
	[self playInterfaceBeep:@"[menu-previous-page]"];
}


- (void) playDismissedReportScreen
{
	[self playInterfaceBeep:@"[dismissed-report-screen]"];
}


- (void) playDismissedMissionScreen
{
	[self playInterfaceBeep:@"[dismissed-mission-screen]"];
}


- (void) playChangedOption
{
	[self playInterfaceBeep:@"[changed-option]"];
}


- (void) playCloakingDeviceInsufficientEnergy
{
	[self playInterfaceBeep:@"[cloaking-device-insufficent-energy]"];
}


- (void) playBuyCommodity
{
	[sBuySellSource playCustomSoundWithKey:@"[buy-commodity]"];
}


- (void) playBuyShip
{
	[sBuySellSource playCustomSoundWithKey:@"[buy-ship]"];
}


- (void) playSellCommodity
{
	[sBuySellSource playCustomSoundWithKey:@"[sell-commodity]"];
}


- (void) playCantBuyCommodity
{
	[sBuySellSource playCustomSoundWithKey:@"[could-not-buy-commodity]"];
}


- (void) playCantSellCommodity
{
	[sBuySellSource playCustomSoundWithKey:@"[could-not-sell-commodity]"];
}


- (void) playCantBuyShip
{
	[sBuySellSource playCustomSoundWithKey:@"[could-not-buy-ship]"];
}


- (void) playStandardHyperspace
{
	[sHyperspaceSoundSource playCustomSoundWithKey:@"[hyperspace-countdown-begun]"];
}


- (void) playGalacticHyperspace
{
	[sHyperspaceSoundSource playCustomSoundWithKey:@"[galactic-hyperspace-countdown-begun]"];
}


- (void) playHyperspaceAborted
{
	[sHyperspaceSoundSource playCustomSoundWithKey:@"[hyperspace-countdown-aborted]"];
}


- (void) playHitByECMSound
{
	if (![sEcmSource isPlaying]) [sEcmSource playCustomSoundWithKey:@"[player-hit-by-ecm]"];
}


- (void) playFiredECMSound
{
	if (![sEcmSource isPlaying]) [sEcmSource playCustomSoundWithKey:@"[player-fired-ecm]"];
}


- (void) playLaunchFromStation
{
	[sBreakPatternSource playCustomSoundWithKey:@"[player-launch-from-station]"];
}


- (void) playDockWithStation
{
	[sBreakPatternSource playCustomSoundWithKey:@"[player-dock-with-station]"];
}


- (void) playExitWitchspace
{
	[sBreakPatternSource playCustomSoundWithKey:@"[player-exit-witchspace]"];
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
