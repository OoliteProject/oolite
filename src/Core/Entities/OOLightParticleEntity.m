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


#define PARTICLE_DISTANCE_SCALE_LOW		12.0
#define PARTICLE_DISTANCE_SCALE_HIGH	36.0


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
		double radius = fmax(size.width, size.height);
		no_draw_distance = pow(radius, M_SQRT2) * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR;
		no_draw_distance *= [UNIVERSE reducedDetail] ? PARTICLE_DISTANCE_SCALE_LOW : PARTICLE_DISTANCE_SCALE_HIGH;
		
		_colorComponents[0] = 1.0f;
		_colorComponents[1] = 1.0f;
		_colorComponents[2] = 1.0f;
		_colorComponents[3] = 1.0f;
		
		[self setScanClass:CLASS_NO_DRAW];
	}
	
	return self;
}


- (NSSize) size
{
	return _size;
}


- (void) setColor:(OOColor *)color
{
	[color getGLRed:&_colorComponents[0] green:&_colorComponents[1] blue:&_colorComponents[2] alpha:&_colorComponents[3]];
}


- (void) setColor:(OOColor *)color alpha:(GLfloat)alpha
{
	[self setColor:color];
	_colorComponents[3] = alpha;
}


- (void) drawSubEntity:(BOOL)immediate :(BOOL)translucent
{
	if (!translucent)  return;
	
	/*	TODO: someone will inevitably build a ship so big that individual
		zero_distances are necessary for flashers, if they haven't already.
		-- Ahruman 2009-09-20
	*/
	zero_distance = [[self owner] zeroDistance];
	if (no_draw_distance <= zero_distance)  return;
	
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
	if (!translucent || [UNIVERSE breakPatternHide])  return;
	if (no_draw_distance <= zero_distance)  return;
	
	OO_ENTER_OPENGL();
		
	OOGL(glPushAttrib(GL_COLOR_BUFFER_BIT | GL_ENABLE_BIT));
	OOGL(glEnable(GL_BLEND));
	OOGL(glBlendFunc(GL_SRC_ALPHA, GL_ONE));
	
	OOGL(glEnable(GL_TEXTURE_2D));
	
	GLfloat distanceAttenuation = zero_distance / no_draw_distance;
	distanceAttenuation = 1.0 - distanceAttenuation;
	GLfloat components[4] = { _colorComponents[0], _colorComponents[1], _colorComponents[2], _colorComponents[3] * distanceAttenuation };
	OOGL(glColor4fv(components));
	
	OOGL(glTexEnvfv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_COLOR, components));
	OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_BLEND));
	[[self texture] apply];
	
	OOViewID viewDir = [UNIVERSE viewDirection];
	if (viewDir != VIEW_GUI_DISPLAY)  GLMultOOMatrix([[PlayerEntity sharedPlayer] drawRotationMatrix]);
	
	/*	NOTE: these previously halved the size because they're half-size
		offsets, but since we use a texture with a border for anti-aliasing
		purposes, that scaling is no longer desired.
		-- Ahruman 2009-09-25
	*/
	GLfloat	xx = _size.width;
	GLfloat	yy = _size.height;
	
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
		sBlobTexture = [[OOTexture textureWithName:@"oolite-particle-blur.png"
										  inFolder:@"Textures"
										   options:kOOTextureMinFilterMipMap | kOOTextureMagFilterLinear | kOOTextureAlphaMask
										anisotropy:kOOTextureDefaultAnisotropy / 2.0
										   lodBias:0.0] retain];
		[[OOGraphicsResetManager sharedManager] registerClient:(id<OOGraphicsResetClient>)[OOLightParticleEntity class]];
	}
}


+ (void) resetGraphicsState
{
	[sBlobTexture release];
	sBlobTexture = nil;
}

@end
