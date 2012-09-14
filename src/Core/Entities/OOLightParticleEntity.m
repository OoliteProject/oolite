/*

OOLightParticleEntity.m


Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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


@interface OOLightParticleEntity (Private)

+ (void) resetGraphicsState;

@end


@implementation OOLightParticleEntity

- (id) initWithDiameter:(float)diameter
{
	if ((self = [super init]))
	{
		_diameter = diameter;
		no_draw_distance = pow(diameter / 2.0, M_SQRT2) * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR;
		no_draw_distance *= [UNIVERSE reducedDetail] ? PARTICLE_DISTANCE_SCALE_LOW : PARTICLE_DISTANCE_SCALE_HIGH;
		
		_colorComponents[0] = 1.0f;
		_colorComponents[1] = 1.0f;
		_colorComponents[2] = 1.0f;
		_colorComponents[3] = 1.0f;
		
		[self setScanClass:CLASS_NO_DRAW];
		[self setStatus:STATUS_EFFECT];
	}
	
	return self;
}


- (float) diameter
{
	return _diameter;
}


- (void) setDiameter:(float)diameter
{
	_diameter = diameter;
}


- (void) setColor:(OOColor *)color
{
	[color getRed:&_colorComponents[0] green:&_colorComponents[1] blue:&_colorComponents[2] alpha:&_colorComponents[3]];
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
	cam_zero_distance = [[self owner] camZeroDistance];
	if (no_draw_distance <= cam_zero_distance)  return;
	
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
	if (!translucent) return;
	if ([UNIVERSE breakPatternHide] && ![self isImmuneToBreakPatternHide])
	{
		Entity *father = [self owner];
		while (father != nil && father != NO_TARGET)
		{
			if (![father isSubEntity])  break;
			father = [father owner];
		}
		if (![father isImmuneToBreakPatternHide])
		{
			return;
		}
	}
	if (no_draw_distance <= cam_zero_distance)  return;
	
	OO_ENTER_OPENGL();
		
	OOGL(glPushAttrib(GL_COLOR_BUFFER_BIT | GL_ENABLE_BIT));
	OOGL(glEnable(GL_BLEND));
	OOGL(glBlendFunc(GL_SRC_ALPHA, GL_ONE));
	
	OOGL(glEnable(GL_TEXTURE_2D));
	
	GLfloat distanceAttenuation = cam_zero_distance / no_draw_distance;
	distanceAttenuation = 1.0 - distanceAttenuation;
	GLfloat components[4] = { _colorComponents[0], _colorComponents[1], _colorComponents[2], _colorComponents[3] * distanceAttenuation };
	OOGL(glColor4fv(components));
	
	OOGL(glTexEnvfv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_COLOR, components));
	OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_BLEND));
	[[self texture] apply];
	
	OOViewID viewDir = [UNIVERSE viewDirection];
	if (viewDir != VIEW_GUI_DISPLAY)  GLMultOOMatrix([PLAYER drawRotationMatrix]);
	
	/*	NOTE: nominal diameter is actual radius, because of the black border
		in the texture. However, the offset along the view axis is not
		affected by the border and needs to be scaled.
		-- Ahruman 2009-12-20
	*/
	float viewOffset = _diameter * 0.5f;
	
	OOGLBEGIN(GL_QUADS);
	switch (viewDir)
	{
		case VIEW_FORWARD:
		case VIEW_GUI_DISPLAY:
			glTexCoord2f(0.0, 1.0);
			glVertex3f(-_diameter, -_diameter, -viewOffset);
			
			glTexCoord2f(1.0, 1.0);
			glVertex3f(_diameter, -_diameter, -viewOffset);
			
			glTexCoord2f(1.0, 0.0);
			glVertex3f(_diameter, _diameter, -viewOffset);
			
			glTexCoord2f(0.0, 0.0);
			glVertex3f(-_diameter, _diameter, -viewOffset);
			break;
			
		case VIEW_AFT:
			glTexCoord2f(0.0, 1.0);
			glVertex3f(_diameter, -_diameter, viewOffset);
			
			glTexCoord2f(1.0, 1.0);
			glVertex3f(-_diameter, -_diameter, viewOffset);
			
			glTexCoord2f(1.0, 0.0);
			glVertex3f(-_diameter, _diameter, viewOffset);
			
			glTexCoord2f(0.0, 0.0);
			glVertex3f(_diameter, _diameter, viewOffset);
			break;
			
		case VIEW_STARBOARD:
			glTexCoord2f(0.0, 1.0);
			glVertex3f(-viewOffset, -_diameter, _diameter);
			
			glTexCoord2f(1.0, 1.0);
			glVertex3f(-viewOffset, -_diameter, -_diameter);
			
			glTexCoord2f(1.0, 0.0);
			glVertex3f(-viewOffset, _diameter, -_diameter);
			
			glTexCoord2f(0.0, 0.0);
			glVertex3f(-viewOffset, _diameter, _diameter);
			break;
			
		case VIEW_PORT:
			glTexCoord2f(0.0, 1.0);
			glVertex3f(viewOffset, -_diameter, -_diameter);
			
			glTexCoord2f(1.0, 1.0);
			glVertex3f(viewOffset, -_diameter, _diameter);
			
			glTexCoord2f(1.0, 0.0);
			glVertex3f(viewOffset, _diameter, _diameter);
			
			glTexCoord2f(0.0, 0.0);
			glVertex3f(viewOffset, _diameter, -_diameter);
			break;
			
		case VIEW_CUSTOM:
			{
				PlayerEntity *player = PLAYER;
				Vector vi = [player customViewRightVector];		vi.x *= _diameter;	vi.y *= _diameter;	vi.z *= _diameter;
				Vector vj = [player customViewUpVector];		vj.x *= _diameter;	vj.y *= _diameter;	vj.z *= _diameter;
				Vector vk = [player customViewForwardVector];	vk.x *= viewOffset;	vk.y *= viewOffset;	vk.z *= viewOffset;
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
			glVertex3f(-_diameter, -_diameter, -_diameter);
			
			glTexCoord2f(1.0, 1.0);
			glVertex3f(_diameter, -_diameter, -_diameter);
			
			glTexCoord2f(1.0, 0.0);
			glVertex3f(_diameter, _diameter, -_diameter);
			
			glTexCoord2f(0.0, 0.0);
			glVertex3f(-_diameter, _diameter, -_diameter);
			break;
	}
	OOGLEND();
	
	OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE));
	OOGL(glPopAttrib());
}


- (OOTexture *) texture
{
	return [OOLightParticleEntity defaultParticleTexture];
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


+ (OOTexture *) defaultParticleTexture
{
	if (sBlobTexture == nil)  [self setUpTexture];
	return sBlobTexture;
}


+ (void) resetGraphicsState
{
	[sBlobTexture release];
	sBlobTexture = nil;
}


- (BOOL) isEffect
{
	return YES;
}


#ifndef NDEBUG
- (NSSet *) allTextures
{
	return [NSSet setWithObject:[self texture]];
}
#endif

@end
