/*

OOLight.h

Class to manage light sources, and bind them to OpenGL lights.
Currently only handles point lights.


Copyright (C) 2008-2012 Jens Ayton

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

#import "OOCocoa.h"
#import "OOOpenGL.h"
#import "OOColor.h"
#import "OOMaths.h"


typedef uint8_t OOLightIndex;

enum
{
	kOOLightNotBound			= 0xFF
};


@interface OOLight: NSObject
{
@private
	OORGBAComponents		_ambient;
	OORGBAComponents		_diffuse;
	OORGBAComponents		_specular;
	Vector					_position;
	BOOL					_dirty;
	OOLightIndex			_bound;
}

- (id) initWithAmbient:(OOColor *)ambient
			   diffuse:(OOColor *)diffuse
			  specular:(OOColor *)specular;

- (id) initWithAmbientRGBA:(OORGBAComponents)ambient
			   diffuseRGBA:(OORGBAComponents)diffuse
			  specularRGBA:(OORGBAComponents)specular;

// Bind OOLights to GL lights
- (void) bindToLight:(OOLightIndex)lightNumber;
- (BOOL) bound;
- (OOLightIndex) boundLight;
- (void) unbindLight;
+ (void) unbindLight:(OOLightIndex)lightNumber;
+ (OOLight *) boundLight:(OOLightIndex)lightNumber;
+ (void) unbindAllLights;

+ (void) updateLights;

// Light modification
- (Vector) position;
- (void) setPosition:(Vector)position;

- (OOColor *) ambient;
- (OORGBAComponents) ambientRGBA;
- (void) setAmbient:(OOColor *)color;
- (void) setAmbientRGBA:(OORGBAComponents)components;

- (OOColor *) diffuse;
- (OORGBAComponents) diffuseRGBA;
- (void) setDiffuse:(OOColor *)color;
- (void) setDiffuseRGBA:(OORGBAComponents)components;

- (OOColor *) specular;
- (OORGBAComponents) specularRGBA;
- (void) setSpecular:(OOColor *)color;
- (void) setSpecularRGBA:(OORGBAComponents)components;

@end
