/*

OOShaderMaterial.h

Managers a combination of a shader program, textures and uniforms. Ought to be
a subclass of a hypothetical OOMaterial.

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
#import "OOWeakReference.h"


#ifndef NO_SHADERS

@class OOShaderProgram;


@interface OOShaderMaterial: OOMaterial
{
	OOShaderProgram					*shaderProgram;
	NSMutableDictionary				*uniforms;
	GLuint							*textures;
	GLuint							texCount;
}

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
			type			"int" or "float"
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
+ (id)shaderWithConfiguration:(NSDictionary *)configuration macros:(NSDictionary *)macros bindingTarget:(id<OOWeakReferenceSupport>)object;
- (id)initWithConfiguration:(NSDictionary *)configuration macros:(NSDictionary *)macros bindingTarget:(id<OOWeakReferenceSupport>)object;

/*	Bind a uniform to a property of an object.
	
	SelectorName should specify a method of source which returns the desired
	value; it will be called every time -apply is, assuming uniformName is
	used in the shader. (If not, OOShaderMaterial will not track the binding.)
	
	A bound method must return a (signed or unsigned) char, short, int, long,
	float or double, and not take any parameters. It will be set as a (signed)
	int or a float as appropriate. TODO: support GLSL vector types, and
	binding of Vectors and Quaternions.
*/
- (void)bindUniform:(NSString *)uniformName
		   toObject:(id<OOWeakReferenceSupport>)target
		   property:(SEL)selector
			clamped:(BOOL)clamped;

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
