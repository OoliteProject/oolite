/*

DustEntity.h
Created by Giles Williams on 2004-04-03.

Entity representing a number of dust particles.

For Oolite
Copyright (C) 2004  Giles C Williams

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

#import <Foundation/Foundation.h>

#import "Entity.h"

#define DUST_SCALE			2000
#define DUST_N_PARTICLES	600

@class Entity, OOColor;

@interface DustEntity : Entity
{
	OOColor *dust_color;
	GLfloat color_fv[4];
}

- (void) setDustColor:(OOColor *) color;
- (OOColor *) dust_color;

@end
