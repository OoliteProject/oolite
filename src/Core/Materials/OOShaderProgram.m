/*

OOShaderProgram.m


Copyright (C) 2007-2012 Jens Ayton

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

#import "OOOpenGLExtensionManager.h"

#if OO_SHADERS

#import "OOShaderProgram.h"
#import "OOFunctionAttributes.h"
#import "OOStringParsing.h"
#import "ResourceManager.h"
#import "OOOpenGLExtensionManager.h"
#import "OOMacroOpenGL.h"
#import "OOCollectionExtractors.h"
#import "OODebugFlags.h"


static NSMutableDictionary		*sShaderCache = nil;
static OOShaderProgram			*sActiveProgram = nil;


static BOOL GetShaderSource(NSString *fileName, NSString *shaderType, NSString *prefix, NSString **outResult);
static NSString *GetGLSLInfoLog(GLhandleARB shaderObject);


@interface OOShaderProgram (OOPrivate)

- (id)initWithVertexShaderSource:(NSString *)vertexSource
			fragmentShaderSource:(NSString *)fragmentSource
					prefixString:(NSString *)prefixString
					  vertexName:(NSString *)vertexName
					fragmentName:(NSString *)fragmentName
			   attributeBindings:(NSDictionary *)attributeBindings
							 key:(NSString *)key;

- (void) bindAttributes:(NSDictionary *)attributeBindings;

@end


@implementation OOShaderProgram

+ (id) shaderProgramWithVertexShader:(NSString *)vertexShaderSource
					  fragmentShader:(NSString *)fragmentShaderSource
					vertexShaderName:(NSString *)vertexShaderName
				  fragmentShaderName:(NSString *)fragmentShaderName
							  prefix:(NSString *)prefixString			// String prepended to program source (both vs and fs)
				   attributeBindings:(NSDictionary *)attributeBindings	// Maps vertex attribute names to "locations".
							cacheKey:(NSString *)cacheKey
{
	OOShaderProgram			*result = nil;
	
	if ([prefixString length] == 0)  prefixString = nil;
	
	// Use cache to avoid creating duplicate shader programs -- saves on GPU resources and potentially state changes.
	// FIXME: probably needs to respond to graphics resets.
	result = [[sShaderCache objectForKey:cacheKey] pointerValue];
	
	if (result == nil)
	{
		// No cached program; create one...
		result = [[OOShaderProgram alloc] initWithVertexShaderSource:vertexShaderSource
												fragmentShaderSource:fragmentShaderSource
														prefixString:prefixString
														  vertexName:vertexShaderName
														fragmentName:fragmentShaderName
												   attributeBindings:attributeBindings
																 key:cacheKey];
		[result autorelease];
		
		if (result != nil && cacheKey != nil)
		{
			// ...and add it to the cache.
			if (sShaderCache == nil)  sShaderCache = [[NSMutableDictionary alloc] init];
			[sShaderCache setObject:[NSValue valueWithPointer:result] forKey:cacheKey];	// Use NSValue so dictionary doesn't retain program
		}
	}
	
	return result;
}


+ (id)shaderProgramWithVertexShaderName:(NSString *)vertexShaderName
					 fragmentShaderName:(NSString *)fragmentShaderName
								 prefix:(NSString *)prefixString
					  attributeBindings:(NSDictionary *)attributeBindings
{
	NSString				*cacheKey = nil;
	OOShaderProgram			*result = nil;
	NSString				*vertexSource = nil;
	NSString				*fragmentSource = nil;
	
	if ([prefixString length] == 0)  prefixString = nil;
	
	// Use cache to avoid creating duplicate shader programs -- saves on GPU resources and potentially state changes.
	// FIXME: probably needs to respond to graphics resets.
	cacheKey = [NSString stringWithFormat:@"vertex:%@\nfragment:%@\n----\n%@", vertexShaderName, fragmentShaderName, prefixString ?: (NSString *)@""];
	result = [[sShaderCache objectForKey:cacheKey] pointerValue];
	
	if (result == nil)
	{
		// No cached program; create one...
		if (!GetShaderSource(vertexShaderName, @"vertex", prefixString, &vertexSource))  return nil;
		if (!GetShaderSource(fragmentShaderName, @"fragment", prefixString, &fragmentSource))  return nil;
		result = [[OOShaderProgram alloc] initWithVertexShaderSource:vertexSource
												fragmentShaderSource:fragmentSource
														prefixString:prefixString
														  vertexName:vertexShaderName
														fragmentName:fragmentShaderName
												   attributeBindings:attributeBindings
																 key:cacheKey];
		
		if (result != nil)
		{
			// ...and add it to the cache.
			[result autorelease];
			if (sShaderCache == nil)  sShaderCache = [[NSMutableDictionary alloc] init];
			[sShaderCache setObject:[NSValue valueWithPointer:result] forKey:cacheKey];	// Use NSValue so dictionary doesn't retain program
		}
	}
	
	return result;
}


- (void)dealloc
{
	OO_ENTER_OPENGL();
	
#ifndef NDEBUG
	if (EXPECT_NOT(sActiveProgram == self))
	{
		OOLog(@"shader.dealloc.imbalance", @"***** OOShaderProgram deallocated while active, indicating a retain/release imbalance. Expect imminent crash.");
		[OOShaderProgram applyNone];
	}
#endif
	
	if (key != nil)
	{
		[sShaderCache removeObjectForKey:key];
		[key release];
	}
	
	OOGL(glDeleteObjectARB(program));
	
	[super dealloc];
}


- (void)apply
{
	OO_ENTER_OPENGL();
	
	if (sActiveProgram != self)
	{
		[sActiveProgram release];
		sActiveProgram = [self retain];
		OOGL(glUseProgramObjectARB(program));
	}
}


+ (void)applyNone
{
	OO_ENTER_OPENGL();
	
	if (sActiveProgram != nil)
	{
		[sActiveProgram release];
		sActiveProgram = nil;
		OOGL(glUseProgramObjectARB(NULL_SHADER));
	}
}


- (GLhandleARB)program
{
	return program;
}

@end


static BOOL ValidateShaderObject(GLhandleARB object, NSString *name)
{
	GLint		type, subtype = 0, status;
	GLenum		statusType;
	NSString	*subtypeString = nil;
	NSString	*actionString = nil;
	
	OO_ENTER_OPENGL();
	
	OOGL(glGetObjectParameterivARB(object, GL_OBJECT_TYPE_ARB, &type));
	BOOL linking = type == GL_PROGRAM_OBJECT_ARB;
	
	if (linking)
	{
		subtypeString = @"shader program";
		actionString = @"linking";
		statusType = GL_OBJECT_LINK_STATUS_ARB;
	}
	else
	{
		// FIXME
		OOGL(glGetObjectParameterivARB(object, GL_OBJECT_SUBTYPE_ARB, &subtype));
		switch (subtype)
		{
			case GL_VERTEX_SHADER_ARB:
				subtypeString = @"vertex shader";
				break;
				
			case GL_FRAGMENT_SHADER_ARB:
				subtypeString = @"fragment shader";
				break;
				
#if GL_EXT_geometry_shader4
			case GL_GEOMETRY_SHADER_EXT:
				subtypeString = @"geometry shader";
				break;
#endif
				
			default:
				subtypeString = [NSString stringWithFormat:@"<unknown shader type 0x%.4X>", subtype];
		}
		actionString = @"compilation";
		statusType = GL_OBJECT_COMPILE_STATUS_ARB;
	}
	
	OOGL(glGetObjectParameterivARB(object, statusType, &status));
	if (status == GL_FALSE)
	{
		NSString *msgClass = [NSString stringWithFormat:@"shader.%@.failure", linking ? @"link" : @"compile"];
		OOLogERR(msgClass, @"GLSL %@ %@ failed for %@:\n>>>>> GLSL log:\n%@\n", subtypeString, actionString, name, GetGLSLInfoLog(object));
		return NO;
	}
	
#ifndef NDEBUG
	if (gDebugFlags & DEBUG_SHADER_VALIDATION && 0)
	{
		OOGL(glValidateProgramARB(object));
		OOGL(glGetObjectParameterivARB(object, GL_OBJECT_VALIDATE_STATUS_ARB, &status));
		if (status == GL_FALSE)
		{
			NSString *msgClass = [NSString stringWithFormat:@"shader.%@.validationFailure", linking ? @"link" : @"compile"];
			OOLogWARN(msgClass, @"GLSL %@ %@ failed for %@:\n>>>>> GLSL log:\n%@\n", subtypeString, @"validation", name, GetGLSLInfoLog(object));
			return NO;
		}
	}
#endif
	
	return YES;
}


@implementation OOShaderProgram (OOPrivate)

- (id)initWithVertexShaderSource:(NSString *)vertexSource
			fragmentShaderSource:(NSString *)fragmentSource
					prefixString:(NSString *)prefixString
					  vertexName:(NSString *)vertexName
					fragmentName:(NSString *)fragmentName
			   attributeBindings:(NSDictionary *)attributeBindings
							 key:(NSString *)inKey
{
	BOOL					OK = YES;
	const GLcharARB			*sourceStrings[3] = { "", "#line 0\n", NULL };
	GLhandleARB				vertexShader = NULL_SHADER;
	GLhandleARB				fragmentShader = NULL_SHADER;
	
	OO_ENTER_OPENGL();
	
	self = [super init];
	if (self == nil)  OK = NO;
	
	if (OK && vertexSource == nil && fragmentSource == nil)  OK = NO;	// Must have at least one shader!
	
	if (OK && prefixString != nil)
	{
		sourceStrings[0] = [prefixString UTF8String];
	}
	
	if (OK && vertexSource != nil)
	{
		// Compile vertex shader.
		OOGL(vertexShader = glCreateShaderObjectARB(GL_VERTEX_SHADER_ARB));
		if (vertexShader != NULL_SHADER)
		{
			sourceStrings[2] = [vertexSource UTF8String];
			OOGL(glShaderSourceARB(vertexShader, 3, sourceStrings, NULL));
			OOGL(glCompileShaderARB(vertexShader));
			
			OK = ValidateShaderObject(vertexShader, vertexName);
		}
		else  OK = NO;
	}
	
	if (OK && fragmentSource != nil)
	{
		// Compile fragment shader.
		OOGL(fragmentShader = glCreateShaderObjectARB(GL_FRAGMENT_SHADER_ARB));
		if (fragmentShader != NULL_SHADER)
		{
			sourceStrings[2] = [fragmentSource UTF8String];
			OOGL(glShaderSourceARB(fragmentShader, 3, sourceStrings, NULL));
			OOGL(glCompileShaderARB(fragmentShader));
			
			OK = ValidateShaderObject(fragmentShader, fragmentName);
		}
		else  OK = NO;
	}
	
	if (OK)
	{
		// Link shader.
		OOGL(program = glCreateProgramObjectARB());
		if (program != NULL_SHADER)
		{
			if (vertexShader != NULL_SHADER)  OOGL(glAttachObjectARB(program, vertexShader));
			if (fragmentShader != NULL_SHADER)  OOGL(glAttachObjectARB(program, fragmentShader));
			[self bindAttributes:attributeBindings];
			OOGL(glLinkProgramARB(program));
			
			OK = ValidateShaderObject(program, [NSString stringWithFormat:@"%@/%@", vertexName, fragmentName]);
		}
		else  OK = NO;
	}
	
	if (OK)
	{
		key = [inKey copy];
	}
	
	if (vertexShader != NULL_SHADER)  OOGL(glDeleteObjectARB(vertexShader));
	if (fragmentShader != NULL_SHADER)  OOGL(glDeleteObjectARB(fragmentShader));
	
	if (!OK)
	{
		if (self != nil && program != NULL_SHADER)
		{
			OOGL(glDeleteObjectARB(program));
			program = NULL_SHADER;
		}
		
		[self release];
		self = nil;
	}
	return self;
}


- (void) bindAttributes:(NSDictionary *)attributeBindings
{
	OO_ENTER_OPENGL();
	
	NSString				*attrKey = nil;
	NSEnumerator			*keyEnum = nil;
	
	for (keyEnum = [attributeBindings keyEnumerator]; (attrKey = [keyEnum nextObject]); )
	{
		OOGL(glBindAttribLocationARB(program, [attributeBindings oo_unsignedIntForKey:attrKey], [attrKey UTF8String]));
	}
}

@end


/*	Attempt to load fragment or vertex shader source from a file.
	Returns YES if source was loaded or no shader was specified, and NO if an
	external shader was specified but could not be found.
*/
static BOOL GetShaderSource(NSString *fileName, NSString *shaderType, NSString *prefix, NSString **outResult)
{
	NSString				*result = nil;
	NSArray					*extensions = nil;
	NSEnumerator			*extEnum = nil;
	NSString				*extension = nil;
	NSString				*nameWithExtension = nil;
	
	if (fileName == nil)  return YES;	// It's OK for one or the other of the shaders to be undefined.
	
	result = [ResourceManager stringFromFilesNamed:fileName inFolder:@"Shaders"];
	if (result == nil)
	{
		extensions = [NSArray arrayWithObjects:shaderType, [shaderType substringToIndex:4], nil];	// vertex and vert, or fragment and frag
		
		// Futureproofing -- in future, we may wish to support automatic selection between supported shader languages.
		if (![fileName pathHasExtensionInArray:extensions])
		{
			for (extEnum = [extensions objectEnumerator]; (extension = [extEnum nextObject]); )
			{
				nameWithExtension = [fileName stringByAppendingPathExtension:extension];
				result = [ResourceManager stringFromFilesNamed:nameWithExtension
													  inFolder:@"Shaders"];
				if (result != nil) break;
			}
		}
		if (result == nil)
		{
			OOLog(kOOLogFileNotFound, @"GLSL ERROR: failed to find fragment program %@.", fileName);
			return NO;
		}
	}
	/*	
	if (result != nil && prefix != nil)
	{
		result = [prefix stringByAppendingString:result];
	}
	*/
	if (outResult != NULL) *outResult = result;
	return YES;
}


static NSString *GetGLSLInfoLog(GLhandleARB shaderObject)
{
	GLint					length;
	GLcharARB				*log = NULL;
	NSString				*result = nil;
	
	OO_ENTER_OPENGL();
	
	if (EXPECT_NOT(shaderObject == NULL_SHADER))  return nil;
	
	OOGL(glGetObjectParameterivARB(shaderObject, GL_OBJECT_INFO_LOG_LENGTH_ARB, &length));
	log = malloc(length);
	if (log == NULL)
	{
		length = 1024;
		log = malloc(length);
		if (log == NULL)  return @"<out of memory>";
	}
	OOGL(glGetInfoLogARB(shaderObject, length, NULL, log));
	
	result = [NSString stringWithUTF8String:log];
	if (result == nil)  result = [[[NSString alloc] initWithBytes:log length:length - 1 encoding:NSISOLatin1StringEncoding] autorelease];
	free(log);
	
	return result;
}

#endif // OO_SHADERS
