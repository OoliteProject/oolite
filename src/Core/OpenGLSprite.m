/*

OpenGLSprite.m

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

#import "OpenGLSprite.h"
#import "OOTexture.h"


@implementation OpenGLSprite

- (id)initWithTexture:(OOTexture *)inTexture
{
	return [self initWithTexture:inTexture size:[inTexture dimensions]];
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


- (void)blitToX:(float)x Y:(float)y Z:(float)z Alpha:(float)a
{
    if (a < 0.0)
        a = 0.0;	// clamp the alpha value
    if (a > 1.0)
        a = 1.0;	// clamp the alpha value
    glEnable(GL_TEXTURE_2D);
    glColor4f(1.0, 1.0, 1.0, a);
    
    // Note that the textured Quad is drawn ACW from the Top Left
    
    glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
	[texture apply];
    glBegin(GL_QUADS);
	
    glTexCoord2f(0.0, 0.0);
    glVertex3f(x, y+size.height, z);
	
    glTexCoord2f(0.0, 1.0);
    glVertex3f(x, y, z);
	
    glTexCoord2f(1.0, 1.0);
    glVertex3f(x+size.width, y, z);

    glTexCoord2f(1.0, 0.0);
    glVertex3f(x+size.width, y+size.height, z);
	
    glEnd();
    glDisable(GL_TEXTURE_2D);
}

- (void)blitCentredToX:(float)x Y:(float)y Z:(float)z Alpha:(float)a
{
    float	xs = x - size.width / 2.0;
    float	ys = y - size.height / 2.0;
    [self blitToX:xs Y:ys Z:z Alpha:a];
}

@end
