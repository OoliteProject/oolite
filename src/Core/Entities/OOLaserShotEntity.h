/*

OOLaserShotEntity.h

Entity subclass implementing GIANT SPACE LAZORS.


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

#import "ShipEntity.h"
#import "OOTypes.h"
#import "OOMaths.h"

@class OOColor;


@interface OOLaserShotEntity: Entity
{
@private
	GLfloat					_color[4];
	OOTimeDelta				_lifetime;
	GLfloat					_range;
	Vector					_offset;
	Quaternion				_relOrientation;
}

+ (instancetype) laserFromShip:(ShipEntity *)ship direction:(OOWeaponFacing)direction offset:(Vector)offset;

- (void) setColor:(OOColor *)color;

- (void) setRange:(GLfloat)range;

@end
