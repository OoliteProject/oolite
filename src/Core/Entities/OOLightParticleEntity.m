/*

OOLightParticleEntity.m


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

#import "OOLightParticleEntity.h"
#import "Universe.h"
#import "PlayerEntity.h"
#import "OOTexture.h"
#import "OOColor.h"
#import "OOCollectionExtractors.h"
#import "OOFunctionAttributes.h"
#import "OOMacroOpenGL.h"
#import "OOGraphicsResetManager.h"


static OOTexture *sBlobTexture = nil;


@interface OOLightParticleEntity (Internal)

+ (void) setUpTexture;
+ (void) resetGraphicsState;

@end


@implementation OOLightParticleEntity

- (id) initWithSize:(NSSize)size
{
	if ((self = [super init]))
	{
		_size = size;
		_colorComponents[0] = 1.0f;
		_colorComponents[1] = 1.0f;
		_colorComponents[2] = 1.0f;
		_colorComponents[3] = 1.0f;
	}
	
	return self;
}


- (NSSize) size
{
	return _size;
}


- (void) drawSubEntity:(BOOL)immediate :(BOOL)translucent
{
	if (!translucent)  return;
	
	// FIXME: check distance.
	
	OO_ENTER_OPENGL();
	
	Entity *father = [self owner];
	Entity *last = nil;
	Vector abspos = position;
	
	while (father != nil && father != last && father != NO_TARGET)
	{
		OOMatrix rM = [father drawRotationMatrix];
		abspos = vector_add(OOVectorMultiplyMatrix(abspos, rM), [father position]);
		last = father;
		
		if (![father isSubEntity])  break;
		father = [father owner];
	}
	
	OOMatrix temp_matrix = OOMatrixLoadGLMatrix(GL_MODELVIEW_MATRIX);
	OOGL(glPopMatrix());  OOGL(glPushMatrix());  // restore zero!
	GLTranslateOOVector(abspos);	// move to absolute position
	
	[self drawEntity:immediate :translucent];
	
	GLLoadOOMatrix(temp_matrix);
}


- (void) drawEntity:(BOOL)immediate :(BOOL)translucent
{
	if (!translucent)  return;
	
	// FIXME: check distance.
	
	OO_ENTER_OPENGL();
		
	OOGL(glPushAttrib(GL_COLOR_BUFFER_BIT | GL_ENABLE_BIT));
	OOGL(glEnable(GL_BLEND));
	OOGL(glBlendFunc(GL_SRC_ALPHA, GL_ONE));
	
	OOGL(glEnable(GL_TEXTURE_2D));
	OOGL(glColor4fv(_colorComponents));
	OOGL(glTexEnvfv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_COLOR, _colorComponents));
	OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_BLEND));
	[[self texture] apply];
	
	OOViewID viewDir = [UNIVERSE viewDirection];
	if (viewDir != VIEW_GUI_DISPLAY)  GLMultOOMatrix([[PlayerEntity sharedPlayer] drawRotationMatrix]);
	
	GLfloat	xx = 0.5 * _size.width;
	GLfloat	yy = 0.5 * _size.height;
	
	OOGLBEGIN(GL_QUADS);
	switch (viewDir)
	{
		case VIEW_FORWARD:
		case VIEW_GUI_DISPLAY:
			glTexCoord2f(0.0, 1.0);
			glVertex3f(-xx, -yy, -xx);
			
			glTexCoord2f(1.0, 1.0);
			glVertex3f(xx, -yy, -xx);
			
			glTexCoord2f(1.0, 0.0);
			glVertex3f(xx, yy, -xx);
			
			glTexCoord2f(0.0, 0.0);
			glVertex3f(-xx, yy, -xx);
			break;
			
		case VIEW_AFT:
			glTexCoord2f(0.0, 1.0);
			glVertex3f(xx, -yy, xx);
			
			glTexCoord2f(1.0, 1.0);
			glVertex3f(-xx, -yy, xx);
			
			glTexCoord2f(1.0, 0.0);
			glVertex3f(-xx, yy, xx);
			
			glTexCoord2f(0.0, 0.0);
			glVertex3f(xx, yy, xx);
			break;
			
		case VIEW_STARBOARD:
			glTexCoord2f(0.0, 1.0);
			glVertex3f(-xx, -yy, xx);
			
			glTexCoord2f(1.0, 1.0);
			glVertex3f(-xx, -yy, -xx);
			
			glTexCoord2f(1.0, 0.0);
			glVertex3f(-xx, yy, -xx);
			
			glTexCoord2f(0.0, 0.0);
			glVertex3f(-xx, yy, xx);
			break;
			
		case VIEW_PORT:
			glTexCoord2f(0.0, 1.0);
			glVertex3f(xx, -yy, -xx);
			
			glTexCoord2f(1.0, 1.0);
			glVertex3f(xx, -yy, xx);
			
			glTexCoord2f(1.0, 0.0);
			glVertex3f(xx, yy, xx);
			
			glTexCoord2f(0.0, 0.0);
			glVertex3f(xx, yy, -xx);
			break;
			
		case VIEW_CUSTOM:
			{
				PlayerEntity *player = [PlayerEntity sharedPlayer];
				Vector vi = [player customViewRightVector];		vi.x *= xx;	vi.y *= xx;	vi.z *= xx;
				Vector vj = [player customViewUpVector];		vj.x *= yy;	vj.y *= yy;	vj.z *= yy;
				Vector vk = [player customViewForwardVector];	vk.x *= xx;	vk.y *= xx;	vk.z *= xx;
				glTexCoord2f(0.0, 1.0);
				glVertex3f(-vi.x -vj.x -vk.x, -vi.y -vj.y -vk.y, -vi.z -vj.z -vk.z);
				glTexCoord2f(1.0, 1.0);
				glVertex3f(+vi.x -vj.x -vk.x, +vi.y -vj.y -vk.y, +vi.z -vj.z -vk.z);
				glTexCoord2f(1.0, 0.0);
				glVertex3f(+vi.x +vj.x -vk.x, +vi.y +vj.y -vk.y, +vi.z +vj.z -vk.z);
				glTexCoord2f(0.0, 0.0);
				glVertex3f(-vi.x +vj.x -vk.x, -vi.y +vj.y -vk.y, -vi.z +vj.z -vk.z);
			}
			break;
			
		default:
			glTexCoord2f(0.0, 1.0);
			glVertex3f(-xx, -yy, -xx);
			
			glTexCoord2f(1.0, 1.0);
			glVertex3f(xx, -yy, -xx);
			
			glTexCoord2f(1.0, 0.0);
			glVertex3f(xx, yy, -xx);
			
			glTexCoord2f(0.0, 0.0);
			glVertex3f(-xx, yy, -xx);
			break;
	}
	OOGLEND();
	
	OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE));
	OOGL(glPopAttrib());
}


- (OOTexture *) texture
{
	if (sBlobTexture == nil)  [OOLightParticleEntity setUpTexture];
	return sBlobTexture;
}


+ (void) setUpTexture
{
	if (sBlobTexture == nil)
	{
		sBlobTexture = [[OOTexture textureWithName:@"blur256.png" inFolder:@"Textures"] retain];
		[[OOGraphicsResetManager sharedManager] registerClient:(id<OOGraphicsResetClient>)[OOLightParticleEntity class]];
	}
}


+ (void) resetGraphicsState
{
	[sBlobTexture release];
	sBlobTexture = nil;
}

@end
