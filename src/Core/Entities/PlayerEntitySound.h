/*

PlayerEntitySound.h

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

#import "PlayerEntity.h"


enum
{
	kInterfaceBeep_Beep				= 1UL,
	kInterfaceBeep_Boop,
	kInterfaceBeep_Buy,
	kInterfaceBeep_Sell
};


@interface PlayerEntity (Sound)

- (void) setUpSound;
- (void) destroySound;

- (void) beep;
- (void) boop;
- (void) playInterfaceBeep:(unsigned)inInterfaceBeep;
- (BOOL) isBeeping;

- (void) playHitByECMSound;
- (void) playFiredECMSound;

- (void) playLaunchFromStation;
- (void) playDockWithStation;
- (void) playExitWitchspace;

// Warning sounds
- (void) playHostileWarning;
- (void) playAlertConditionRed;
- (void) playIncomingMissile;
- (void) playEnergyLow;
- (void) playDockingDenied;
- (void) playWitchjumpFailure;
- (void) playWitchjumpMisjump;
- (void) playFuelLeak;

// Damage sounds
- (void) playShieldHit;
- (void) playDirectHit;
- (void) playScrapeDamage;

// Weapon sounds
- (void) playLaserHit:(BOOL)hit;

@end
