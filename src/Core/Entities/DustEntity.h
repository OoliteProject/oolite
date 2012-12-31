/*

DustEntity.h

Entity representing a number of dust particles.

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

#import "Entity.h"
#import "OOOpenGLExtensionManager.h"
#import "OOTexture.h"

#define DUST_SCALE			2000
#define DUST_N_PARTICLES	600

@class OOColor, OOShaderProgram, OOShaderUniform;


@interface DustEntity: Entity
{
@private
	OOColor				*dust_color;
	Vector				vertices[DUST_N_PARTICLES * 2];
	GLushort			indices[DUST_N_PARTICLES * 2];
	GLfloat				color_fv[4];
	OOTexture     *texture;
	bool          hasPointSprites;
	
#if OO_SHADERS
	GLfloat				warpinessAttr[DUST_N_PARTICLES * 2];
	OOShaderProgram		*shader;
	NSArray				*uniforms;
	uint8_t				shaderMode;
#endif
}

- (void) setDustColor:(OOColor *) color;
- (OOColor *) dustColor;

@end
