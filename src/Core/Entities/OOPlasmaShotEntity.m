/*

OOPlasmaShotEntity.m


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

#import "OOPlasmaShotEntity.h"
#import "Universe.h"
#import "PlayerEntity.h"
#import "OOColor.h"
#import "OOPlasmaBurstEntity.h"


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
	if ((self = [super initWithDiameter:kPlasmaShotSize]))
	{
		[self setPosition:inPosition];
		[self setVelocity:inVelocity];
		[self setCollisionRadius:2.0];
		
		[self setColor:color alpha:1.0];
		_colorComponents[3] = 1.0f;
		
		[self setEnergy:inEnergy];
		_duration = duration;
	}
	
	return self;
}


- (BOOL) canCollide
{
	return [UNIVERSE getTime] > [self spawnTime] + kPlasmaShotActivationDelay;
}


- (BOOL) checkCloseCollisionWith:(Entity *)other
{
	return ([other rootShipEntity] != [self owner]) && ![other isEffect];
}


- (void) update:(double)delta_t
{
	[super update:delta_t];
	[super applyVelocityWithTimeDelta:delta_t];
	
	OOTimeDelta lifeTime = [self timeElapsedSinceSpawn];
	
#if PLASMA_ATTENUATION
	float attenuation = OOClamp_0_1_f(1.0f - lifeTime / _duration);
#else
	const float attenuation = 1.0f;
#endif
	
	NSUInteger i, count = [collidingEntities count];
	for (i = 0; i < count; i++)
	{
		Entity *e = (Entity *)[collidingEntities objectAtIndex:i];
		if ([e rootShipEntity] != [self owner])
		{
			[e takeEnergyDamage:[self energy] * attenuation
						   from:self
					  becauseOf:[self owner]];
			[UNIVERSE removeEntity:self];
			
			// Spawn a plasma burst.
			OOPlasmaBurstEntity *burst = [[OOPlasmaBurstEntity alloc] initWithPosition:[self position]];
			[UNIVERSE addEntity:burst];
			[burst release];
		}
	}
	
#if PLASMA_ATTENUATION
	_colorComponents[3] = attenuation;
#endif
	
	if (lifeTime > _duration)  [UNIVERSE removeEntity:self];
}

@end
