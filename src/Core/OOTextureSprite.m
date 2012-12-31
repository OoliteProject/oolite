/*

OOTextureSprite.m

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

#import "OOTextureSprite.h"
#import "OOTexture.h"
#import "OOMaths.h"
#import "OOMacroOpenGL.h"


@implementation OOTextureSprite

- (id)initWithTexture:(OOTexture *)inTexture
{
	return [self initWithTexture:inTexture size:[inTexture originalDimensions]];
}


- (id)initWithTexture:(OOTexture *)inTexture size:(NSSize)spriteSize
{
	if (inTexture == nil)
	{
		[self release];
		return nil;
	}
	
	self = [super init];
	if (self != nil)
	{
		texture = [inTexture retain];
		size = spriteSize;
	}
	return self;
}


- (void)dealloc
{
	[texture release];
	
	[super dealloc];
}

- (NSSize)size
{
	return size;
}


- (void) blitToX:(float)x Y:(float)y Z:(float)z alpha:(float)a
{
	OO_ENTER_OPENGL();
	OOSetOpenGLState(OPENGL_STATE_OVERLAY);
	
	a = OOClamp_0_1_f(a);
	OOGL(glEnable(GL_TEXTURE_2D));
	OOGL(glColor4f(1.0, 1.0, 1.0, a));
	
	// Note that the textured Quad is drawn ACW from the top left.
	
	[texture apply];
	OOGLBEGIN(GL_QUADS);
		glTexCoord2f(0.0, 0.0);
		glVertex3f(x, y+size.height, z);
		
		glTexCoord2f(0.0, 1.0);
		glVertex3f(x, y, z);
		
		glTexCoord2f(1.0, 1.0);
		glVertex3f(x+size.width, y, z);
		
		glTexCoord2f(1.0, 0.0);
		glVertex3f(x+size.width, y+size.height, z);
	OOGLEND();
	
	OOGL(glDisable(GL_TEXTURE_2D));
	
	OOVerifyOpenGLState();
}


- (void) blitCentredToX:(float)x Y:(float)y Z:(float)z alpha:(float)a
{
	float	xs = x - size.width / 2.0;
	float	ys = y - size.height / 2.0;
	[self blitToX:xs Y:ys Z:z alpha:a];
}


- (void) blitBackgroundCentredToX:(float)x Y:(float)y Z:(float)z alpha:(float)a
{
	// Without distance, coriolis stations would be rendered behind the background image.
	// Set an arbitrary value for distance, might not be sufficient for really huge ships.
	float	distance = 512.0f;
	
	size.width *= distance; size.height *= distance;
	[self blitCentredToX:x Y:y Z:z * distance alpha:a];
	size.width /= distance; size.height /= distance;
}

@end
