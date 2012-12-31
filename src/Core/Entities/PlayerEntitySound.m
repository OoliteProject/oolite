/*

PlayerEntitySound.m

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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
	kBuySellSourcePoolSize	= 4,
	kWarningPoolSize		= 6,
	kWeaponPoolSize			= 3,
	kDamagePoolSize			= 4,
	kMiscPoolSize			= 2
};


static OOSoundSourcePool	*sWarningSoundPool;
static OOSoundSourcePool	*sWeaponSoundPool;
static OOSoundSourcePool	*sDamageSoundPool;
static OOSoundSourcePool	*sMiscSoundPool;
static OOSoundSource		*sHyperspaceSoundSource;
static OOSoundSource		*sInterfaceBeepSource;
static OOSoundSource		*sEcmSource;
static OOSoundSource		*sBreakPatternSource;
static OOSoundSourcePool	*sBuySellSourcePool;
static OOSoundSource		*sAfterburnerSources[2];


@implementation PlayerEntity (Sound)

- (void) setUpSound
{
	[self destroySound];
	
	sInterfaceBeepSource = [[OOSoundSource alloc] init];
	sBreakPatternSource = [[OOSoundSource alloc] init];
	sEcmSource = [[OOSoundSource alloc] init];
	sHyperspaceSoundSource = [[OOSoundSource alloc] init];
	
	sBuySellSourcePool = [[OOSoundSourcePool alloc] initWithCount:kBuySellSourcePoolSize minRepeatTime:0.0];
	sWarningSoundPool = [[OOSoundSourcePool alloc] initWithCount:kWarningPoolSize minRepeatTime:0.0];
	sWeaponSoundPool = [[OOSoundSourcePool alloc] initWithCount:kWeaponPoolSize minRepeatTime:0.0];
	sDamageSoundPool = [[OOSoundSourcePool alloc] initWithCount:kDamagePoolSize minRepeatTime:0.1];	// Repeat time limit is to avoid playing a scrape sound every frame on glancing scrapes. This does limit the number of laser hits that can be played in a furrball, though; maybe lasers and scrapes should use different pools.
	sMiscSoundPool = [[OOSoundSourcePool alloc] initWithCount:kMiscPoolSize minRepeatTime:0.0];
	
	// Two sources with the same sound are used to simulate looping.
	OOSound *afterburnerSound = [ResourceManager ooSoundNamed:@"afterburner1.ogg" inFolder:@"Sounds"];
	sAfterburnerSources[0] = [[OOSoundSource alloc] initWithSound:afterburnerSound];
	sAfterburnerSources[1] = [[OOSoundSource alloc] initWithSound:afterburnerSound];
}


- (void) destroySound
{
	DESTROY(sInterfaceBeepSource);
	DESTROY(sBreakPatternSource);
	DESTROY(sEcmSource);
	DESTROY(sHyperspaceSoundSource);
	
	DESTROY(sBuySellSourcePool);
	DESTROY(sWarningSoundPool);
	DESTROY(sWeaponSoundPool);
	DESTROY(sDamageSoundPool);
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


- (void) playNextEquipmentSelected
{
	[self playInterfaceBeep:@"[next-equipment-selected]"];
}


- (void) playNextMissileSelected
{
	[self playInterfaceBeep:@"[next-missile-selected]"];
}


- (void) playWeaponsOnline
{
	[self playInterfaceBeep:@"[weapons-online]"];
}


- (void) playWeaponsOffline
{
	[self playInterfaceBeep:@"[weapons-offline]"];
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

- (void) playHyperspaceDistanceTooGreat
{
	[self playInterfaceBeep:@"[witch-too-far]"];
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


- (void) updateFuelScoopSoundWithInterval:(OOTimeDelta)delta_t
{
	static double scoopSoundPlayTime = 0.0;
	scoopSoundPlayTime -= delta_t;
	if (scoopSoundPlayTime < 0.0)
	{
		if(![sInterfaceBeepSource isPlaying])
		{
			[self playInterfaceBeep:@"[scoop]"];
			scoopSoundPlayTime = 0.5;
		}
		else scoopSoundPlayTime = 0.0;
	}
	if (![self scoopOverride])
	{
		scoopSoundPlayTime = 0.0;
	}
}


// time delay method for playing afterburner sounds
// this overlaps two sounds each 2 seconds long, but with a 0.75s
// crossfade
- (void) updateAfterburnerSound
{
	static uint8_t which = 0;
	
	if (!afterburner_engaged)				// end the loop cycle
	{
		afterburnerSoundLooping = NO;
	}
	
	if (afterburnerSoundLooping)
	{
		[sAfterburnerSources[which] play];
		which = !which;
		
		[self performSelector:@selector(updateAfterburnerSound)
				   withObject:NULL
				   afterDelay:1.25];	// and swap sounds in 1.25s time
	}
}


- (void) startAfterburnerSound
{
	if (!afterburnerSoundLooping)
	{
		afterburnerSoundLooping = YES;
		[self updateAfterburnerSound];
	}
}


- (void) stopAfterburnerSound
{
	// Do nothing, stop is detected in updateAfterburnerSound
}


- (void) playCloakingDeviceInsufficientEnergy
{
	[self playInterfaceBeep:@"[cloaking-device-insufficent-energy]"];
}


- (void) playBuyCommodity
{
	[sBuySellSourcePool playSoundWithKey:@"[buy-commodity]"];
}


- (void) playBuyShip
{
	[sBuySellSourcePool playSoundWithKey:@"[buy-ship]"];
}


- (void) playSellCommodity
{
	[sBuySellSourcePool playSoundWithKey:@"[sell-commodity]"];
}


- (void) playCantBuyCommodity
{
	[sBuySellSourcePool playSoundWithKey:@"[could-not-buy-commodity]"];
}


- (void) playCantSellCommodity
{
	[sBuySellSourcePool playSoundWithKey:@"[could-not-sell-commodity]"];
}


- (void) playCantBuyShip
{
	[sBuySellSourcePool playSoundWithKey:@"[could-not-buy-ship]"];
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


- (void) playWitchjumpBlocked
{
	[sWarningSoundPool playSoundWithKey:@"[witch-blocked-by-@]" priority:1.3];
}


- (void) playWitchjumpDistanceTooGreat
{
	[sWarningSoundPool playSoundWithKey:@"[witch-too-far]" priority:1.3];
}


- (void) playWitchjumpInsufficientFuel
{
	[sWarningSoundPool playSoundWithKey:@"[witch-no-fuel]" priority:1.3];
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


- (void) playWeaponOverheated
{
	[sWeaponSoundPool playSoundWithKey:@"[weapon-overheat]" overlap:NO];
}


- (void) playMissileLaunched
{
	[sWeaponSoundPool playSoundWithKey:@"[missile-launched]"];
}


- (void) playMineLaunched
{
	[sWeaponSoundPool playSoundWithKey:@"[mine-launched]"];
}


- (void) playEnergyBombFired
{
	[sWeaponSoundPool playSoundWithKey:@"[energy-bomb-fired]" priority:2.0];
}


- (void) playEscapePodScooped
{
	[sMiscSoundPool playSoundWithKey:@"[escape-pod-scooped]"];
}


- (void) playAegisCloseToPlanet
{
	[sMiscSoundPool playSoundWithKey:@"[aegis-planet]"];
}


- (void) playAegisCloseToStation
{
	[sMiscSoundPool playSoundWithKey:@"[aegis-station]"];
}


- (void) playGameOver
{
	[sMiscSoundPool playSoundWithKey:@"[game-over]"];
}


- (void) playLegacyScriptSound:(NSString *)key
{
	[sMiscSoundPool playSoundWithKey:key priority:1.1];
}

@end
