/*

OOShaderUniform.h

Manages a uniform variable for OOShaderMaterial.


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

#import "OOShaderMaterial.h"

#if OO_SHADERS


#import "OOMaths.h"

@class OOColor;


@interface OOShaderUniform: NSObject
{
@private
	NSString					*name;
	GLint						location;
	uint8_t						isBinding: 1,
								// flags that apply only to bindings:
								isActiveBinding: 1,
								convertClamp: 1,
								convertNormalize: 1,
								convertToMatrix: 1,
								bindToSuper: 1;
	uint8_t						type;
	union
	{
		GLint						constInt;
		GLfloat						constFloat;
		GLfloat						constVector[4];
		OOMatrix					constMatrix;
		struct
		{
			OOWeakReference				*object;
			SEL							selector;
			IMP							method;
		}							binding;
	}							value;
}

- (id)initWithName:(NSString *)uniformName shaderProgram:(OOShaderProgram *)shaderProgram intValue:(GLint)constValue;
- (id)initWithName:(NSString *)uniformName shaderProgram:(OOShaderProgram *)shaderProgram floatValue:(GLfloat)constValue;
- (id)initWithName:(NSString *)uniformName shaderProgram:(OOShaderProgram *)shaderProgram vectorValue:(GLfloat[4])constValue;
- (id)initWithName:(NSString *)uniformName shaderProgram:(OOShaderProgram *)shaderProgram colorValue:(OOColor *)constValue;	// Converted to vector
- (id)initWithName:(NSString *)uniformName shaderProgram:(OOShaderProgram *)shaderProgram quaternionValue:(Quaternion)constValue asMatrix:(BOOL)asMatrix;	// Converted to vector (in xyzw order, not wxyz!) or rotation matrix.
- (id)initWithName:(NSString *)uniformName shaderProgram:(OOShaderProgram *)shaderProgram matrixValue:(OOMatrix)constValue;

/*	"Convert" has different meanings for different types.
	For float and int types, it clamps to the range [0, 1].
	For vector types, it normalizes.
	For quaternions, it converts to rotation matrix (instead of vec4).
*/
- (id)initWithName:(NSString *)uniformName
	 shaderProgram:(OOShaderProgram *)shaderProgram
	 boundToObject:(id<OOWeakReferenceSupport>)target
		  property:(SEL)selector
	convertOptions:(OOUniformConvertOptions)options;

- (void)apply;

- (void)setBindingTarget:(id<OOWeakReferenceSupport>)target;

@end

#endif // OO_SHADERS
