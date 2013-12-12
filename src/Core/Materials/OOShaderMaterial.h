/*

OOShaderMaterial.h

Managers a combination of a shader program, textures and uniforms.


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

#import "OOBasicMaterial.h"
#import "OOWeakReference.h"
#import "OOMaths.h"


#if OO_SHADERS


@class OOShaderProgram, OOTexture;


enum
{
	// Conversion settings for uniform bindings
	kOOUniformConvertClamp			= 0x0001U,
	kOOUniformConvertNormalize		= 0x0002U,
	kOOUniformConvertToMatrix		= 0x0004U,
	kOOUniformBindToSuperTarget		= 0x0008U,
	
	kOOUniformConvertDefaults		= kOOUniformConvertToMatrix | kOOUniformBindToSuperTarget
};
typedef uint16_t OOUniformConvertOptions;


@interface OOShaderMaterial: OOBasicMaterial
{
@private
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
		fragment_shader		name of fragment shader file.
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
+ (instancetype) shaderMaterialWithName:(NSString *)name
						  configuration:(NSDictionary *)configuration
								 macros:(NSDictionary *)macros
						  bindingTarget:(id<OOWeakReferenceSupport>)target;

- (id) initWithName:(NSString *)name
	  configuration:(NSDictionary *)configuration
			 macros:(NSDictionary *)macros
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
		* OOMatrix.
		* OOColor.
	
	The "convert" flag has different meanings for different types:
		* For int, float or NSNumber, it clamps to the range [0..1].
		* For Vector, it normalizes.
		* For Quaternion, it converts to a rotation matrix (instead of a vector).
	
	NOTE: this method *does not* check against the whitelist. See
	-bindSafeUniform:toObject:propertyNamed:convertOptions: below.
*/
- (BOOL) bindUniform:(NSString *)uniformName
			toObject:(id<OOWeakReferenceSupport>)target
			property:(SEL)selector
	  convertOptions:(OOUniformConvertOptions)options;

/*	Bind a uniform to a property of an object.
	
	This is similar to -bindUniform:toObject:property:convertOptions:, except
	that it checks against OOUniformBindingPermitted().
*/
- (BOOL) bindSafeUniform:(NSString *)uniformName
				toObject:(id<OOWeakReferenceSupport>)target
		   propertyNamed:(NSString *)property
		  convertOptions:(OOUniformConvertOptions)options;

/*	Set a uniform value.
*/
- (void) setUniform:(NSString *)uniformName intValue:(int)value;
- (void) setUniform:(NSString *)uniformName floatValue:(float)value;
- (void) setUniform:(NSString *)uniformName vectorValue:(GLfloat[4])value;
- (void) setUniform:(NSString *)uniformName vectorObjectValue:(id)value;	// Array of four numbers, or something that can be OOVectorFromObject()ed.
- (void) setUniform:(NSString *)uniformName quaternionValue:(Quaternion)value asMatrix:(BOOL)asMatrix;

/*	Add constant uniforms. Same format as uniforms dictionary of configuration
	parameter to -initWithConfiguration:macros:. The target parameter is used
	for bindings.
	
	Additionally, the target may implement the following method, used to seed
	any random bindings:
		- (uint32_t) randomSeedForShaders;
*/
-(void) addUniformsFromDictionary:(NSDictionary *)uniformDefs withBindingTarget:(id<OOWeakReferenceSupport>)target;

@end


@interface NSObject (ShaderBindingHierarchy)

/*	Informal protocol for objects to "forward" their shader bindings up a
	hierarchy (for instance, subentities to parent entities).
*/
- (id<OOWeakReferenceSupport>) superShaderBindingTarget;

@end


enum
{
	/*	ID of vertex attribute used for tangents. A fixed ID is used for
		simplicty.
		NOTE: on Nvidia hardware, attribute 15 is aliased to
		gl_MultiTexCoord7. This is not expected to become a problem.
	*/
	kTangentAttributeIndex = 15
};


/*	OOUniformBindingPermitted()
	
	Predicate determining whether a given property may be used as a binding.
	Client code is responsible for implementing this.
*/
BOOL OOUniformBindingPermitted(NSString *propertyName, id bindingTarget);


@interface NSObject (OOShaderMaterialTargetOptional)

- (uint32_t) randomSeedForShaders;

@end


// Material specifier dictionary keys.
extern NSString * const kOOVertexShaderSourceKey;
extern NSString * const kOOVertexShaderNameKey;
extern NSString * const kOOFragmentShaderSourceKey;
extern NSString * const kOOFragmentShaderNameKey;
extern NSString * const kOOTexturesKey;
extern NSString * const kOOTextureObjectsKey;
extern NSString * const kOOUniformsKey;
extern NSString * const kOOIsSynthesizedMaterialConfigurationKey;
extern NSString * const kOOIsSynthesizedMaterialMacrosKey;

#endif // OO_SHADERS
