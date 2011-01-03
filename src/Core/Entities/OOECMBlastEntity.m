/*

OOECMBlastEntity.m


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

#import "OOECMBlastEntity.h"
#import "Universe.h"
#import "ShipEntity.h"
#import "OOEntityFilterPredicate.h"


// NOTE: these values are documented for scripting, be careful about changing them.
#define ECM_EFFECT_DURATION		2.0
#define ECM_PULSE_COUNT			4
#define ECM_PULSE_INTERVAL		(ECM_EFFECT_DURATION / (double)ECM_PULSE_COUNT)

#define ECM_DEBUG_DRAW			0


#if ECM_DEBUG_DRAW
#import "OODebugGLDrawing.h"
#endif


@implementation OOECMBlastEntity

- (id) initFromShip:(ShipEntity *)ship
{
	if (ship == nil)
	{
		DESTROY(self);
	}
	else if ((self = [super init]))
	{
		_blastsRemaining = ECM_PULSE_COUNT;
		_nextBlast = ECM_PULSE_INTERVAL;
		
		[self setPosition:[ship position]];
		
		[self setStatus:STATUS_EFFECT];
		[self setScanClass:CLASS_NO_DRAW];
	}
	
	return self;
}


- (void) update:(OOTimeDelta)delta_t
{
	_nextBlast -= delta_t;
	
	if (_nextBlast <= 0.0)
	{
		// Do ECM stuff.
		double radius = OOClamp_0_1_d((double)(ECM_PULSE_COUNT - _blastsRemaining + 1) * 1.0 / (double)ECM_PULSE_COUNT);
		radius *= SCANNER_MAX_RANGE;
		_blastsRemaining--;
		
		NSArray *targets = [UNIVERSE findEntitiesMatchingPredicate:IsShipPredicate
														 parameter:NULL
														   inRange:radius
														  ofEntity:self];
		OOUInteger i, count = [targets count];
		if (count > 0)
		{
			NSNumber *ecmPulsesRemaining = [NSNumber numberWithInt:_blastsRemaining];
			
			for (i = 0; i < count; i++)
			{
				[[targets objectAtIndex:i] doScriptEvent:@"shipHitByECM"
											withArgument:ecmPulsesRemaining
											 andReactToAIMessage:@"ECM"];
			}
		}
		_nextBlast += ECM_PULSE_INTERVAL;
		
		if (_blastsRemaining == 0)  [UNIVERSE removeEntity:self];
	}
}


- (void) drawEntity:(BOOL)immediate :(BOOL)translucent
{
#if ECM_DEBUG_DRAW && OO_DEBUG
	OODebugDrawPoint(kZeroVector, [OOColor cyanColor]);
#endif
	// Else do nothing, we're invisible!
}


- (BOOL) isECMBlast
{
	return YES;
}

@end


@implementation Entity (OOECMBlastEntity)

- (BOOL) isECMBlast
{
	return NO;
}

@end
