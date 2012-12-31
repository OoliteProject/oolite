/*

OOSparkEntity.m


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

#import "OOSparkEntity.h"
#import "Universe.h"
#import "PlayerEntity.h"
#import "OOColor.h"


@interface OOSparkEntity (Private)

- (void) performUpdate:(OOTimeDelta)delta_t;

@end


@implementation OOSparkEntity

- (id) initWithPosition:(Vector)pos
			   velocity:(Vector)vel
			   duration:(OOTimeDelta)duration
				   size:(float)size
				  color:(OOColor *)color
{
	if ((self = [super initWithDiameter:size]))
	{
		[self setPosition:pos];
		[self setVelocity:vel];
		_duration = _timeRemaining = duration;
		[self setCollisionRadius:2.0];
		
		[color getRed:&_baseRGBA[0] green:&_baseRGBA[1] blue:&_baseRGBA[2] alpha:&_baseRGBA[3]];
		[self performUpdate:0];	// Handle colour mixing and such.
	}
	
	return self;
}


- (void) update:(OOTimeDelta)delta_t
{
	[super update:delta_t];
	[self performUpdate:delta_t];
}


- (void) performUpdate:(OOTimeDelta)delta_t
{
	_timeRemaining -= delta_t;
	
	float mix = OOClamp_0_1_f(_timeRemaining / _duration);
	
	// Fade towards red while fading out.
	_colorComponents[0] = mix * _baseRGBA[0] + (1.0f - mix);
	_colorComponents[1] = mix * _baseRGBA[1];
	_colorComponents[2] = mix * _baseRGBA[2];
	_colorComponents[3] = mix * _baseRGBA[3];
	
	// Disappear when gone.
	if (mix == 0)  [UNIVERSE removeEntity:self];
}

@end
