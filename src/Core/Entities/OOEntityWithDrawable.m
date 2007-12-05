/*

OOEntityWithDrawable.m

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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


@implementation OOEntityWithDrawable

- (void)dealloc
{
	[drawable release];
	
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


- (GLfloat)findCollisionRadius
{
	return [drawable collisionRadius];
}


- (Geometry *)geometry
{
	return [drawable geometry];
}


- (void)drawEntity:(BOOL)immediate :(BOOL)translucent
{
	if (no_draw_distance < zero_distance)
	{
		// Don't draw.
		return;
	}
	
	if ([UNIVERSE wireframeGraphics])  GLDebugWireframeModeOn();
		
	if (translucent)  [drawable renderTranslucentParts];
	else  [drawable renderOpaqueParts];
	
	if ([UNIVERSE wireframeGraphics])  GLDebugWireframeModeOff();
}

@end
