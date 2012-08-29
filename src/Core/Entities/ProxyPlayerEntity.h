/*

ProxyPlayerEntity.h

Ship entity which, in some respects, emulates a PlayerShip. In particular, at
this time it implements the extra shader bindable methods of PlayerShip.


Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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


@interface ProxyPlayerEntity: ShipEntity
{
@private
	float					_fuelLeakRate;
	GLfloat					_dialForwardShield;
	GLfloat					_dialAftShield;
	OOMissileStatus			_missileStatus;
	OOFuelScoopStatus		_fuelScoopStatus;
	OOCompassMode			_compassMode;
	OOAlertCondition		_alertCondition;
	NSUInteger				_trumbleCount;
	unsigned				_massLocked: 1,
							_atHyperspeed: 1,
							_dialIdentEngaged: 1;
}

- (void) copyValuesFromPlayer:(PlayerEntity *)player;


// Default: 0
- (float) fuelLeakRate;
- (void) setFuelLeakRate:(float)value;

// Default: NO
- (BOOL) massLocked;
- (void) setMassLocked:(BOOL)value;

// Default: NO
- (BOOL) atHyperspeed;
- (void) setAtHyperspeed:(BOOL)value;

// Default: 1
- (GLfloat) dialForwardShield;
- (void) setDialForwardShield:(GLfloat)value;

// Default: 1
- (GLfloat) dialAftShield;
- (void) setDialAftShield:(GLfloat)value;

// Default: MISSILE_STATUS_SAFE
- (OOMissileStatus) dialMissileStatus;
- (void) setDialMissileStatus:(OOMissileStatus)value;

// Default: SCOOP_STATUS_NOT_INSTALLED or SCOOP_STATUS_OKAY depending on equipment.
- (OOFuelScoopStatus) dialFuelScoopStatus;
- (void) setDialFuelScoopStatus:(OOFuelScoopStatus)value;

// Default: COMPASS_MODE_BASIC or COMPASS_MODE_PLANET depending on equipment.
- (OOCompassMode) compassMode;
- (void) setCompassMode:(OOCompassMode)value;

// Default: NO
- (BOOL) dialIdentEngaged;
- (void) setDialIdentEngaged:(BOOL)value;

// Default: ALERT_CONDITION_DOCKED
- (OOAlertCondition) alertCondition;
- (void) setAlertCondition:(OOAlertCondition)condition;

// Default: 0
- (NSUInteger) trumbleCount;
- (void) setTrumbleCount:(NSUInteger)value;

@end


@interface Entity (ProxyPlayer)

// True for PlayerEntity or ProxyPlayerEntity.
- (BOOL) isPlayerLikeShip;

@end
