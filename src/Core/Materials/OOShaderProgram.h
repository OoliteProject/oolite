/*

OOShaderProgram.h

Encapsulates a vertex + fragment shader combo. In general, this should only be
used though OOShaderMaterial. The point of this separation is that more than
one OOShaderMaterial can use the same OOShaderProgram.


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


#import <Foundation/Foundation.h>
#import "OOOpenGL.h"
#import "OOOpenGLExtensionManager.h"

#if OO_SHADERS


@interface OOShaderProgram: NSObject
{
@private
	GLhandleARB						program;
	NSString						*key;
}

+ (id) shaderProgramWithVertexShader:(NSString *)vertexShaderSource
					  fragmentShader:(NSString *)fragmentShaderSource
					vertexShaderName:(NSString *)vertexShaderName
				  fragmentShaderName:(NSString *)fragmentShaderName
							  prefix:(NSString *)prefixString			// String prepended to program source (both vs and fs)
				   attributeBindings:(NSDictionary *)attributeBindings	// Maps vertex attribute names to "locations".
							cacheKey:(NSString *)cacheKey;

// Loads a shader from a file, caching and sharing shader program instances.
+ (id) shaderProgramWithVertexShaderName:(NSString *)vertexShaderName
					  fragmentShaderName:(NSString *)fragmentShaderName
								  prefix:(NSString *)prefixString			// String prepended to program source (both vs and fs)
					   attributeBindings:(NSDictionary *)attributeBindings;	// Maps vertex attribute names to "locations".

- (void) apply;
+ (void) applyNone;

- (GLhandleARB) program;

@end

#endif // OO_SHADERS
