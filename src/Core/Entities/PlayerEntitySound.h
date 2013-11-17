/*

PlayerEntitySound.h

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

#import "PlayerEntity.h"

@interface PlayerEntity (Sound)

- (void) setUpSound;
- (void) destroySound;

// Interface sounds; only one at a time
- (BOOL) isBeeping;
- (void) playIdentOn;
- (void) playIdentOff;
- (void) playIdentLockedOn;
- (void) playMissileArmed;
- (void) playMineArmed;
- (void) playMissileSafe;
- (void) playMissileLockedOn;
- (void) playWeaponsOnline;
- (void) playWeaponsOffline;
- (void) playNextEquipmentSelected;
- (void) playNextMissileSelected;
- (void) playCargoJettisioned;
- (void) playAutopilotOn;
- (void) playAutopilotOff;
- (void) playAutopilotOutOfRange;
- (void) playAutopilotCannotDockWithTarget;
- (void) playSaveOverwriteYes;
- (void) playSaveOverwriteNo;
- (void) playHoldFull;
- (void) playJumpMassLocked;
- (void) playTargetLost;
- (void) playNoTargetInMemory;
- (void) playTargetSwitched;
- (void) playCloakingDeviceOn;
- (void) playCloakingDeviceOff;
- (void) playCloakingDeviceInsufficientEnergy;
- (void) playMenuNavigationUp;
- (void) playMenuNavigationDown;
- (void) playMenuNavigationNot;
- (void) playMenuPagePrevious;
- (void) playMenuPageNext;
- (void) playDismissedReportScreen;
- (void) playDismissedMissionScreen;
- (void) playChangedOption;

- (void) updateFuelScoopSoundWithInterval:(OOTimeDelta)delta_t;

- (void) startAfterburnerSound;
- (void) stopAfterburnerSound;

// Buy/sell get their own source.
- (void) playBuyCommodity;
- (void) playBuyShip;
- (void) playSellCommodity;
- (void) playCantBuyCommodity;
- (void) playCantSellCommodity;
- (void) playCantBuyShip;

// Hyperspace alert sounds; logically hyperspace sounds, but played on the interface sound source.
- (void) playHyperspaceNoTarget;
- (void) playHyperspaceNoFuel;
- (void) playHyperspaceBlocked;
- (void) playHyperspaceDistanceTooGreat;


/*	Hyperspace sounds; only one at a time. These get their own pool since
	people might want something longer than beeps and boops (e.g. the existing
	hyperspace countdown one). Hyperspace-related alert sounds are with the
	normal interface sounds.
*/
- (void) playStandardHyperspace;
- (void) playGalacticHyperspace;
- (void) playHyperspaceAborted;

// ECM; only one at a time
- (void) playHitByECMSound;
- (void) playFiredECMSound;

- (void) playLaunchFromStation;
- (void) playDockWithStation;
- (void) playExitWitchspace;

// Warning sounds
- (void) playHostileWarning;
- (void) playAlertConditionRed;
- (void) playIncomingMissile:(Vector)missileVector;
- (void) playEnergyLow;
- (void) playDockingDenied;
- (void) playWitchjumpFailure;
- (void) playWitchjumpMisjump;
- (void) playWitchjumpBlocked;
- (void) playWitchjumpDistanceTooGreat;
- (void) playWitchjumpInsufficientFuel;
- (void) playFuelLeak;

// Damage sounds
- (void) playShieldHit:(Vector)attackVector;
- (void) playDirectHit:(Vector)attackVector;
- (void) playScrapeDamage:(Vector)attackVector;

// Weapon sounds
- (void) playLaserHit:(BOOL)hit offset:(Vector)weaponOffset;
- (void) playWeaponOverheated:(Vector)weaponOffset;
- (void) playMissileLaunched:(Vector)weaponOffset;
- (void) playMineLaunched:(Vector)weaponOffset;

// Miscellaneous sounds
- (void) playEscapePodScooped;
- (void) playAegisCloseToPlanet;
- (void) playAegisCloseToStation;
- (void) playGameOver;

- (void) playLegacyScriptSound:(NSString *)key;

@end
