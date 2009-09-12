/*

OOFlasherEntity.m


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

#import "OOFlasherEntity.h"
#import "Universe.h"
#import "PlayerEntity.h"
#import "OOColor.h"
#import "OOCollectionExtractors.h"


@interface OOFlasherEntity (Internal)

- (void) setUpColors:(NSArray *)colorSpecifiers;
- (void) getCurrentColorComponents;

@end


@implementation OOFlasherEntity

+ (id) flasherWithDictionary:(NSDictionary *)dictionary
{
	return [[[OOFlasherEntity alloc] initWithDictionary:dictionary] autorelease];
}


- (id) initWithDictionary:(NSDictionary *)dictionary
{
	float size = [dictionary oo_floatForKey:@"size" defaultValue:1.0f];
	
	if ((self = [super initWithSize:NSMakeSize(size, size)]))
	{
		_frequency = [dictionary oo_floatForKey:@"frequency" defaultValue:1.0f] * 2.0f;
		_phase = [dictionary oo_floatForKey:@"phase" defaultValue:0.0f];
		
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


#ifndef NDEBUG
- (void) setStatus:(OOEntityStatus)stat
{
	if (stat != STATUS_COCKPIT_DISPLAY)
	{
		OOLog(@"flasher.status", @"Status set to %u", stat);
	}

	[super setStatus:stat];
}
#endif


- (void) setUpColors:(NSArray *)colorSpecifiers
{
	NSMutableArray *colors = [NSMutableArray arrayWithCapacity:[colorSpecifiers count]];
	id specifier = nil;
	NSEnumerator *specEnum = [colorSpecifiers objectEnumerator];
	while ((specifier = [specEnum nextObject]))
	{
		[colors addObject:[OOColor colorWithDescription:specifier]];
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


- (void) update:(OOTimeDelta) delta_t
{
	[super update:delta_t];
	
	_time += delta_t;
	_colorComponents[3] = 0.5 * sin(_frequency * M_PI * (_time + _phase)) + 0.5;
}


- (void) drawEntity:(BOOL)immediate :(BOOL)translucent
{
	if (_active)
	{
		[super drawEntity:immediate :translucent];
	}
}


- (BOOL) isFlasher
{
	return YES;
}


- (double)findCollisionRadius
{
	NSSize size = [self size];
	return fmax(size.width, size.height);
}

@end


@implementation Entity (OOFlasherEntityExtensions)

- (BOOL) isFlasher
{
	return NO;
}

@end
