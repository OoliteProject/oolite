/*

OOEntityWithDrawable.m

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


#import "OOEntityWithDrawable.h"
#import "OODrawable.h"
#import "Universe.h"
#import "ShipEntity.h"
#import "OOVisualEffectEntity.h"

@implementation OOEntityWithDrawable

- (void)dealloc
{
	[drawable release];
	drawable = nil;
	
	[super dealloc];
}


- (OODrawable *)drawable
{
	return drawable;
}


- (void)setDrawable:(OODrawable *)inDrawable
{
	if (inDrawable != drawable)
	{
		[drawable autorelease];
		drawable = [inDrawable retain];
		[drawable setBindingTarget:self];
		
		collision_radius = [drawable collisionRadius];
		no_draw_distance = [drawable maxDrawDistance];
		boundingBox = [drawable boundingBox];
	}
}


- (double)findCollisionRadius
{
	return [drawable collisionRadius];
}


- (void) drawImmediate:(bool)immediate translucent:(bool)translucent
{
	if (no_draw_distance < cam_zero_distance)
	{
		// Don't draw.
		return;
	}
	
	if (no_draw_distance != INFINITY && ![self isImmuneToBreakPatternHide])
	{ 
		// (always draw sky, always draw break patterns)
		if (![self isSubEntity]) 
		{
			GLfloat clipradius = collision_radius;
			if ([self isShip])
			{
				ShipEntity* shipself = (ShipEntity*)self;
				clipradius = [shipself frustumRadius];
			}
			else if ([self isVisualEffect])
			{
				OOVisualEffectEntity* veself = (OOVisualEffectEntity*)self;
				clipradius = [veself frustumRadius];
			}
			if (![UNIVERSE viewFrustumIntersectsSphereAt:position withRadius:clipradius])
			{
				return;
			}
		} 
		else 
		{
			// check correct sub-entity position
			if (![UNIVERSE viewFrustumIntersectsSphereAt:[self absolutePositionForSubentity] withRadius:[self collisionRadius]])
			{
				return;
			}
		}
	}	

	if ([UNIVERSE wireframeGraphics])  OOGLWireframeModeOn();
		
	if (translucent)  [drawable renderTranslucentParts];
	else  [drawable renderOpaqueParts];
	
	if ([UNIVERSE wireframeGraphics])  OOGLWireframeModeOff();
}


#ifndef NDEBUG
- (NSSet *) allTextures
{
	return [[self drawable] allTextures];
}
#endif

@end
