/*

OOShaderMaterial.h

Managers a combination of a shader program, textures and uniforms.

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


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2007 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOBasicMaterial.h"
#import "OOWeakReference.h"


#ifndef NO_SHADERS

@class OOShaderProgram, OOTexture;


enum
{
	// Conversion settings for uniform bindings
	kOOUniformConvertClamp			= 0x0001U,
	kOOUniformConvertNormalize		= 0x0002U,
	kOOUniformConvertToMatrix		= 0x0004U,
	
	kOOUniformConvertDefaults		= kOOUniformConvertToMatrix
};
typedef uint16_t OOUniformConvertOptions;


@interface OOShaderMaterial: OOBasicMaterial
{
	OOShaderProgram					*shaderProgram;
	NSMutableDictionary				*uniforms;
	
	uint32_t						texCount;
	OOTexture						**textures;
	
	OOWeakReference					*bindingTarget;
}

+ (BOOL)configurationDictionarySpecifiesShaderMaterial:(NSDictionary *)configuration;

/*	Set up an OOShaderMaterial.
	
	Configuration should be a dictionary equivalent to an entry in a
	shipdata.plist "shaders" dictionary. Specifically, keys OOShaderMaterial
	will look for are currently:
		textures			array of texture file names.
		vertex_shader		name of vertex shader file.
		glsl-vertex			vertex shader source (if no vertex_shader).
		fragment_shader		name of fragment shader file.
		glsl-fragment		fragment shader source (if no fragment_shader).
		glsl				fragment shader source (if no glsl-fragment).
		uniforms			dictionary of uniforms. Values are either reals or
							dictionaries containing:
			type			"int", "texture" or "float"
			value			number
	
	Macros is a dictionary which is converted to macro definitions and
	prepended to shader source code. It should be used to specify the
	availability if uniforms you tend to register, and other macros such as
	bug fix identifiers. For example, the
	dictionary:
		{ "OO_ENGINE_LEVEL" = 1; }
	
	will be transformed into:
		#define OO_ENGINE_LEVEL 1
*/
+ (id)shaderMaterialWithName:(NSString *)name
			   configuration:(NSDictionary *)configuration
					  macros:(NSDictionary *)macros
			 defaultBindings:(NSDictionary *)defaults
			   bindingTarget:(id<OOWeakReferenceSupport>)target;

- (id)initWithName:(NSString *)name
	 configuration:(NSDictionary *)configuration
			macros:(NSDictionary *)macros
   defaultBindings:(NSDictionary *)defaults
	 bindingTarget:(id<OOWeakReferenceSupport>)target;

/*	Bind a uniform to a property of an object.
	
	SelectorName should specify a method of source which returns the desired
	value; it will be called every time -apply is, assuming uniformName is
	used in the shader. (If not, OOShaderMaterial will not track the binding.)
	
	A bound method must not take any parameters, and must return one of the
	following types:
		* Any integer or float type.
		* NSNumber.
		* Vector.
		* Quaternion.
		* Matrix.
		* OOColor.
	
	The "convert" flag has different meanings for different types:
		* For int, float or NSNumber, it clamps to the range [0..1].
		* For Vector, it normalizes.
		* For Quaternion, it converts to a rotation matrix (instead of a vector).
*/
- (void)bindUniform:(NSString *)uniformName
		   toObject:(id<OOWeakReferenceSupport>)target
		   property:(SEL)selector
	 convertOptions:(OOUniformConvertOptions)options;

/*	Set a uniform value.
*/
- (void)setUniform:(NSString *)uniformName intValue:(int)value;
- (void)setUniform:(NSString *)uniformName floatValue:(float)value;

/*	Add constant uniforms. Same format as uniforms dictionary of configuration
	parameter to -initWithConfiguration:macros:. The target parameter is used
	for bindings.
*/
-(void)addUniformsFromDictionary:(NSDictionary *)uniformDefs withBindingTarget:(id<OOWeakReferenceSupport>)target;

@end

#endif // NO_SHADERS
