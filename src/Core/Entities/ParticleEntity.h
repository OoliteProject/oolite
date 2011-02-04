/*

ParticleEntity.h

Entity subclass implementing a variety of special effects.

Oolite
Copyright (C) 2004-2011 Giles C Williams and contributors

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

#import "OOSelfDrawingEntity.h"

#import "Universe.h"
#import "OOMaths.h"


#define SUPPORT_BILLBOARD 0


@class OOTexture;


@interface ParticleEntity: OOSelfDrawingEntity
{
	OOTexture		*texture;
	
	OOColor			*color;
	GLfloat			color_fv[4];
	
	GLfloat			alpha;
	OOTimeDelta		time_counter;
	
	OOTimeDelta		duration;
	OOTimeDelta		activation_time;
	double			growth_rate;
	
	GLfloat			ring_inner_radius, ring_outer_radius;
	
	int				particle_type;
		
	NSSize			size;
}

- (id) initEnergyMineFromShip:(ShipEntity *) ship;
- (id) initHyperringFromShip:(ShipEntity *) ship;
- (id) initFragburstSize:(GLfloat) fragSize fromPosition:(Vector) fragPos;
- (id) initBurst2Size:(GLfloat) burstSize fromPosition:(Vector) fragPos;
#if SUPPORT_BILLBOARD
- (id) initBillboard:(NSSize) billSize withTexture:(NSString*) textureFile;
#endif

- (void) setColor:(OOColor *) a_color;

- (void) setDuration:(double) dur;
- (void) setSize:(NSSize) siz;
- (NSSize) size;


@end


@interface Entity (OOParticleExtensions)

- (BOOL)isParticle;

@end
