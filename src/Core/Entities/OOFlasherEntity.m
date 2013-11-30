/*

OOFlasherEntity.m


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

#import "OOFlasherEntity.h"
#import "Universe.h"
#import "PlayerEntity.h"
#import "OOColor.h"
#import "OOCollectionExtractors.h"
#import "NSDictionaryOOExtensions.h"


@interface OOFlasherEntity (Internal)

- (void) setUpColors:(NSArray *)colorSpecifiers;
- (void) getCurrentColorComponents;

@end


@implementation OOFlasherEntity

+ (instancetype) flasherWithDictionary:(NSDictionary *)dictionary
{
	return [[[OOFlasherEntity alloc] initWithDictionary:dictionary] autorelease];
}


- (id) initWithDictionary:(NSDictionary *)dictionary
{
	float size = [dictionary oo_floatForKey:@"size" defaultValue:1.0f];
	
	if ((self = [super initWithDiameter:size]))
	{
		_frequency = [dictionary oo_floatForKey:@"frequency" defaultValue:1.0f] * 2.0f;
		_phase = [dictionary oo_floatForKey:@"phase" defaultValue:0.0f];
		_brightfraction = [dictionary oo_floatForKey:@"bright_fraction" defaultValue:0.5f];

		[self setUpColors:[dictionary oo_arrayForKey:@"colors"]];
		[self getCurrentColorComponents];
		
		[self setActive:[dictionary oo_boolForKey:@"initially_on" defaultValue:YES]];
	}
	return self;
}


- (void) dealloc
{
	[_colors release];
	
	[super dealloc];
}


- (void) setUpColors:(NSArray *)colorSpecifiers
{
	NSMutableArray *colors = [NSMutableArray arrayWithCapacity:[colorSpecifiers count]];
	id specifier = nil;
	NSEnumerator *specEnum = [colorSpecifiers objectEnumerator];
	while ((specifier = [specEnum nextObject]))
	{
		[colors addObject:[OOColor colorWithDescription:specifier saturationFactor:0.75f]];
	}
	
	_colors = [colors copy];
}


- (void) getCurrentColorComponents
{
	[self setColor:[_colors objectAtIndex:_activeColor] alpha:_colorComponents[3]];
}


- (BOOL) isActive
{
	return _active;
}


- (void) setActive:(BOOL)active
{
	_active = !!active;
}


- (OOColor *) color
{
	return [OOColor colorWithRed:_colorComponents[0]
						   green:_colorComponents[1]
							blue:_colorComponents[2]
						   alpha:_colorComponents[3]];
}


- (float) frequency
{
	return _frequency;
}


- (void) setFrequency:(float)frequency
{
	_frequency = frequency;
}


- (float) phase
{
	return _phase;
}


- (void) setPhase:(float)phase
{
	_phase = phase;
}


- (float) fraction
{
	return _brightfraction;
}


- (void) setFraction:(float)fraction
{
	_brightfraction = fraction;
}


- (void) update:(OOTimeDelta) delta_t
{
	[super update:delta_t];
	
	_time += delta_t;

	if (_frequency != 0)
	{
		float wave = sin(_frequency * M_PI * (_time + _phase));
		NSUInteger count = [_colors count];
		if (count > 1 && wave < 0) 
		{
			if (!_justSwitched && wave > _wave)	// don't test for wave >= _wave - could give wrong results with very low frequencies
			{
				_justSwitched = YES;
				++_activeColor;
				_activeColor %= count;	//_activeColor = ++_activeColor % count; is potentially undefined operation
				[self setColor:[_colors objectAtIndex:_activeColor]];
			}
		}
		else if (_justSwitched)
		{
			_justSwitched = NO;
		}

		float threshold = cos(_brightfraction * M_PI);
		
		float brightness = _brightfraction;
		if (wave > threshold)
		{
			brightness = _brightfraction + (((1-_brightfraction)/(1-threshold))*(wave-threshold));
		}
		else if (wave < threshold)
		{
			brightness = _brightfraction + ((_brightfraction/(threshold+1))*(wave-threshold));
		}

		_colorComponents[3] = brightness;
		
		_wave = wave;
	}
	else
	{
		_colorComponents[3] = 1.0;
	}
}


- (void) drawImmediate:(bool)immediate translucent:(bool)translucent
{
	if (_active)
	{
		[super drawImmediate:immediate translucent:translucent];
	}
}


- (void) drawSubEntityImmediate:(bool)immediate translucent:(bool)translucent
{
	if (_active)
	{
		[super drawSubEntityImmediate:immediate translucent:translucent];
	}
}


- (BOOL) isFlasher
{
	return YES;
}


- (double)findCollisionRadius
{
	return [self diameter] / 2.0;
}


- (void) rescaleBy:(GLfloat)factor
{
	[self setDiameter:[self diameter] * factor];
}

@end


@implementation Entity (OOFlasherEntityExtensions)

- (BOOL) isFlasher
{
	return NO;
}

@end
