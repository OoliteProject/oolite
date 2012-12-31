/*

OOLightParticleEntity.h

Simple particle-type effect entity. Draws a billboard with additive blending.


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

#import "Entity.h"

@class OOTexture, OOColor;


@interface OOLightParticleEntity: Entity
{
@protected
	GLfloat					_colorComponents[4];
	float					_diameter;
}

- (id) initWithDiameter:(float)diameter;

- (float) diameter;
- (void) setDiameter:(float)diameter;

- (void) setColor:(OOColor *)color;
- (void) setColor:(OOColor *)color alpha:(GLfloat)alpha;

/*	For subclasses that don't want the default blur texture.
	NOTE: such subclasses must deal with the OOGraphicsResetManager. Also,
	OOLightParticleEntity assumes the texture is twice as big as the nominal
	size of the particle (with a black border for anti-aliasing purposes).
*/
- (OOTexture *) texture;

+ (void) setUpTexture;
+ (OOTexture *) defaultParticleTexture;


- (void) drawSubEntityImmediate:(bool)immediate translucent:(bool)translucent;

@end
