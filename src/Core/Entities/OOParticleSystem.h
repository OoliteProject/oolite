/*

OOParticleSystem.h


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

#import "OOTypes.h"
#import "OOMaths.h"

@class OOTexture, OOColor;


enum
{
	kFragmentBurstMaxParticles		= 64,
	kBigFragmentBurstMaxParticles	= 16
};


@interface OOParticleSystem: Entity
{
@protected
	Vector			_particlePosition[kFragmentBurstMaxParticles];
	Vector			_particleVelocity[kFragmentBurstMaxParticles];
	GLfloat			_particleColor[kFragmentBurstMaxParticles][4];
	GLfloat			_particleSize[kFragmentBurstMaxParticles];
	unsigned		_count;
	
	unsigned		_particleType;
	
	OOTimeDelta		_timePassed, _duration;
}

/*	Initialize particle effect with particles flying out randomly.
	Initiali _particleSize[] is equal to speed.
 */
- (id) initWithPosition:(Vector)position
			   velocity:(Vector)velocity
				  count:(unsigned)count
			   minSpeed:(unsigned)minSpeed
			   maxSpeed:(unsigned)maxSpeed
			   duration:(OOTimeDelta)duration
			  baseColor:(GLfloat[4])baseColor;

@end


@interface OOSmallFragmentBurstEntity: OOParticleSystem

+ (id) fragmentBurstFrom:(Vector)fragPosition size:(GLfloat)size;

@end


@interface OOBigFragmentBurstEntity: OOParticleSystem
{
@private
	GLfloat			_baseSize;
}

+ (id) fragmentBurstFrom:(Vector)fragPosition size:(GLfloat)size;

@end
