/*

OOEntityWithDrawable.h

Abstract intermediate class for entities which use an OODrawable to render.

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

#import "Entity.h"

@class OODrawable;

// Methods that must be supported by subentities, regardless of type.
@protocol OOSubEntity

- (void) rescaleBy:(GLfloat)factor;

// Separate drawing path for subentities of ships.
- (void) drawSubEntityImmediate:(bool)immediate translucent:(bool)translucent;

@end


@protocol OOHUDBeaconIcon;

// Methods that must be supported by entities with beacons, regardless of type.
@protocol OOBeaconEntity

- (NSComparisonResult) compareBeaconCodeWith:(Entity <OOBeaconEntity>*) other;
- (NSString *) beaconCode;
- (void) setBeaconCode:(NSString *)bcode;
- (BOOL) isBeacon;
- (id <OOHUDBeaconIcon>) beaconDrawable;
- (Entity <OOBeaconEntity> *) prevBeacon;
- (Entity <OOBeaconEntity> *) nextBeacon;
- (void) setPrevBeacon:(Entity <OOBeaconEntity> *)beaconShip;
- (void) setNextBeacon:(Entity <OOBeaconEntity> *)beaconShip;
- (BOOL) isJammingScanning;

@end



@interface OOEntityWithDrawable: Entity
{
@private
	OODrawable				*drawable;
}

- (OODrawable *)drawable;
- (void)setDrawable:(OODrawable *)drawable;

@end
