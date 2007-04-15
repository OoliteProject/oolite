/*

OOBasicMaterial.h

Material using basic OpenGL properties. Normal materials
(OOSingleTextureMaterial, OOShaderMaterial) are subclasses of this. It may be
desireable to have a material which does not use normal GL material
properties, in which case it should be based on OOMaterial directly.

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

#import "OOMaterial.h"
#import "OOColor.h"


@interface OOBasicMaterial: OOMaterial
{
	// Colours
	GLfloat					diffuse[4],		// Default: { 0.8, 0.8, 0.8, 1.0 }
							specular[4],	// Default: { 0.0, 0.0, 0.0, 1.0 }
							ambient[4],		// Default: { 0.2, 0.2, 0.2, 1.0 }
							emission[4];	// Default: { 0.0, 0.0, 0.0, 1.0 }
	
	// Specular exponent
	uint8_t					shininess;		// Default: 0.0
	BOOL					smooth;			// Default: YES
}

/*	Initialize with default values:
		diffuse		{ 0.8, 0.8, 0.8, 1.0 }
		specular	{ 0.0, 0.0, 0.0, 1.0 }
		ambient		{ 0.2, 0.2, 0.2, 1.0 }
		emission	{ 0.0, 0.0, 0.0, 1.0 }
		shininess	0
		smooth		YES
*/
- (id)init;

/*	Initialize with dictionary. Accepted keys:
		diffuse		colour description
		specular	colour description
		ambient		colour description
		emission	colour description
		shininess	integer
		smooth		boolean (probably not useful to expose to users, since
					normals won't automagically be adjusted)
	
	"Colour description" refers to anything +[OOColor colorWithDescription:]
	will accept.
*/
- (id)initWithConfiguration:(NSDictionary *)configuration;

- (OOColor *)diffuseColor;
- (void)setDiffuseColor:(OOColor *)color;
- (void)setAmbientAndDiffuseColor:(OOColor *)color;
- (OOColor *)specularColor;
- (void)setSpecularColor:(OOColor *)color;
- (OOColor *)ambientColor;
- (void)setAmbientColor:(OOColor *)color;
- (OOColor *)emmisionColor;
- (void)setEmissionColor:(OOColor *)color;

- (void)getDiffuseComponents:(GLfloat[4])outComponents;
- (void)setDiffuseComponents:(const GLfloat[4])components;
- (void)setAmbientAndDiffuseComponents:(const GLfloat[4])components;
- (void)getSpecularComponents:(GLfloat[4])outComponents;
- (void)setSpecularComponents:(const GLfloat[4])components;
- (void)getAmbientComponents:(GLfloat[4])outComponents;
- (void)setAmbientComponents:(const GLfloat[4])components;
- (void)getEmissionComponents:(GLfloat[4])outComponents;
- (void)setEmissionComponents:(const GLfloat[4])components;

- (void)setDiffuseRed:(GLfloat)r green:(GLfloat)g blue:(GLfloat)b alpha:(GLfloat)a;
- (void)setAmbientAndDiffuseRed:(GLfloat)r green:(GLfloat)g blue:(GLfloat)b alpha:(GLfloat)a;
- (void)setSpecularRed:(GLfloat)r green:(GLfloat)g blue:(GLfloat)b alpha:(GLfloat)a;
- (void)setAmbientRed:(GLfloat)r green:(GLfloat)g blue:(GLfloat)b alpha:(GLfloat)a;
- (void)setEmissionRed:(GLfloat)r green:(GLfloat)g blue:(GLfloat)b alpha:(GLfloat)a;

- (uint8_t)shininess;
- (void)setShininess:(uint8_t)value;	// Clamped to [0, 128]

- (BOOL)smooth;
- (void)setSmooth:(BOOL)value;

@end
