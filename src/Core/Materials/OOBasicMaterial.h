/*

OOBasicMaterial.h

Material using basic OpenGL properties. Normal materials
(OOSingleTextureMaterial, OOShaderMaterial) are subclasses of this. It may be
desireable to have a material which does not use normal GL material
properties, in which case it should be based on OOMaterial directly.


Copyright (C) 2007-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOMaterial.h"
#import "OOColor.h"


@interface OOBasicMaterial: OOMaterial
{
@private
	NSString				*materialName;
	
	// Colours
	GLfloat					diffuse[4],
							specular[4],
							ambient[4],
							emission[4];
	
	// Specular exponent
	uint8_t					shininess;		// Default: 0.0
}

/*	Initialize with default values (historical Olite defaults, not GL defaults):
		diffuse		{ 1.0, 1.0, 1.0, 1.0 }
		specular	{ 0.0, 0.0, 0.0, 1.0 }
		ambient		{ 1.0, 1.0, 1.0, 1.0 }
		emission	{ 0.0, 0.0, 0.0, 1.0 }
		shininess	0
*/
- (id)initWithName:(NSString *)name;

/*	Initialize with dictionary. Accepted keys:
		diffuse		colour description
		specular	colour description
		ambient		colour description
		emission	colour description
		shininess	integer
	
	"Colour description" refers to anything +[OOColor colorWithDescription:]
	will accept.
*/
- (id)initWithName:(NSString *)name configuration:(NSDictionary *)configuration;

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


/*	For subclasses: return true to permit specular settings, false to deny
	them. By default, this is ![UNIVERSE reducedDetail].
*/
- (BOOL) permitSpecular;

@end
