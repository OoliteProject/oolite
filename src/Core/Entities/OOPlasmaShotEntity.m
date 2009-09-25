/*

OOPlasmaShotEntity.m


Oolite
Copyright (C) 2004-2009 Giles C Williams and contributors

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

#import "OOPlasmaShotEntity.h"
#import "Universe.h"
#import "PlayerEntity.h"
#import "OOColor.h"


#define kPlasmaShotSize				12.0f
#define kPlasmaShotActivationDelay	0.05f


/*	If nonzero, plasma shots fade with distance. Bits of this were in the old
	ParticleEntity code, but I think it was disabled on purpose.
	-- Ahruman 2009-09-25
*/
#define PLASMA_ATTENUATION 0


@implementation OOPlasmaShotEntity

- (id) initWithPosition:(Vector)inPosition
			   velocity:(Vector)inVelocity
				 energy:(float)inEnergy
			   duration:(OOTimeDelta)duration
				  color:(OOColor *)color
{
	if ((self = [super initWithSize:NSMakeSize(kPlasmaShotSize, kPlasmaShotSize)]))
	{
		[self setPosition:inPosition];
		[self setVelocity:inVelocity];
		[self setCollisionRadius:2.0];
		
		[self setColor:color ? color : [OOColor redColor]];
		_colorComponents[3] = 1.0f;
		
		[self setEnergy:inEnergy];
		_duration = duration;
	}
	
	return self;
}


- (void) dealloc
{
	[super dealloc];
}


- (void) setColor:(OOColor *)color
{
	float alpha;
	[color getGLRed:&_colorComponents[0] green:&_colorComponents[1] blue:&_colorComponents[2] alpha:&alpha];
}


- (BOOL) canCollide
{
	return [UNIVERSE getTime] > [self spawnTime] + kPlasmaShotActivationDelay;
}


- (BOOL) checkCloseCollisionWith:(Entity *)other
{
	return ([other rootShipEntity] != [self owner]) && ![other isParticle];
}


- (void) update:(double)delta_t
{
	OOTimeDelta lifeTime = [UNIVERSE getTime] - [self spawnTime];
	
#if PLASMA_ATTENUATION
	float attenuation = OOClamp_0_1_f(1.0f - lifeTime / _duration);
#else
	const float attenuation = 1.0f;
#endif
	
	OOUInteger i, count = [collidingEntities count];
	for (i = 0; i < count; i++)
	{
		Entity *e = (Entity *)[collidingEntities objectAtIndex:i];
		if ([e rootShipEntity] != [self owner])
		{
			[e takeEnergyDamage:[self energy] * attenuation
						   from:self
					  becauseOf:[self owner]];
			
			// FIXME: spawn an explosion particle.
#if 0
			[self setVelocity:kZeroVector];
			[self setColor:[OOColor redColor]];
			[self setSize:NSMakeSize(64.0,64.0)];
			duration = 2.0;
			time_counter = 0.0;
			particle_type = PARTICLE_EXPLOSION;
#else
			[UNIVERSE removeEntity:self];
#endif
		}
	}
	
	[self setPosition:vector_add([self position], vector_multiply_scalar([self velocity], delta_t))];
	
#if PLASMA_ATTENUATION
	_colorComponents[3] = attenuation;
#endif
	
	if (lifeTime > _duration)  [UNIVERSE removeEntity:self];
}

@end
