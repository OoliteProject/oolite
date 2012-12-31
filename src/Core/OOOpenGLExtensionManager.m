/*

OOOpenGLExtensionManager.m


Copyright (C) 2007-2013 Jens Ayton and contributors

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
#import "OOLogging.h"
#import "OOFunctionAttributes.h"
#include <stdlib.h>
#import "NSThreadOOExtensions.h"

#import "ResourceManager.h"
#import "OOCollectionExtractors.h"
#import "OORegExpMatcher.h"
#import "OOConstToString.h"


/*	OpenGL version required, currently 1.1 or later (basic stuff like
	glBindTexture(), glDrawArrays()). We probably have implicit requirements
	for later versions, but I don't feel like auditing.
	-- Ahruman
*/
enum
{
	kMinMajorVersion				= 1,
	kMinMinorVersion				= 1
};


#if OOLITE_WINDOWS
/*	Define the function pointers for the OpenGL extensions used in the game
	(required for Windows only).
*/
static void OOBadOpenGLExtensionUsed(void) GCC_ATTR((noreturn, used));

#if OO_SHADERS

PFNGLUSEPROGRAMOBJECTARBPROC			glUseProgramObjectARB			= (PFNGLUSEPROGRAMOBJECTARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLGETUNIFORMLOCATIONARBPROC			glGetUniformLocationARB			= (PFNGLGETUNIFORMLOCATIONARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLUNIFORM1IARBPROC					glUniform1iARB					= (PFNGLUNIFORM1IARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLUNIFORM1FARBPROC					glUniform1fARB					= (PFNGLUNIFORM1FARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLUNIFORMMATRIX4FVARBPROC			glUniformMatrix4fvARB			= (PFNGLUNIFORMMATRIX4FVARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLUNIFORM4FVARBPROC					glUniform4fvARB					= (PFNGLUNIFORM4FVARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLGETOBJECTPARAMETERIVARBPROC		glGetObjectParameterivARB		= (PFNGLGETOBJECTPARAMETERIVARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLCREATESHADEROBJECTARBPROC			glCreateShaderObjectARB			= (PFNGLCREATESHADEROBJECTARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLGETINFOLOGARBPROC					glGetInfoLogARB					= (PFNGLGETINFOLOGARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLCREATEPROGRAMOBJECTARBPROC			glCreateProgramObjectARB		= (PFNGLCREATEPROGRAMOBJECTARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLATTACHOBJECTARBPROC				glAttachObjectARB				= (PFNGLATTACHOBJECTARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLDELETEOBJECTARBPROC				glDeleteObjectARB				= (PFNGLDELETEOBJECTARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLLINKPROGRAMARBPROC					glLinkProgramARB				= (PFNGLLINKPROGRAMARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLCOMPILESHADERARBPROC				glCompileShaderARB				= (PFNGLCOMPILESHADERARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLSHADERSOURCEARBPROC				glShaderSourceARB				= (PFNGLSHADERSOURCEARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLUNIFORM2FVARBPROC					glUniform2fvARB					= (PFNGLUNIFORM2FVARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLBINDATTRIBLOCATIONARBPROC			glBindAttribLocationARB			= (PFNGLBINDATTRIBLOCATIONARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLENABLEVERTEXATTRIBARRAYARBPROC		glEnableVertexAttribArrayARB	= (PFNGLENABLEVERTEXATTRIBARRAYARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLVERTEXATTRIBPOINTERARBPROC			glVertexAttribPointerARB		= (PFNGLVERTEXATTRIBPOINTERARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLDISABLEVERTEXATTRIBARRAYARBPROC	glDisableVertexAttribArrayARB	= (PFNGLDISABLEVERTEXATTRIBARRAYARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLVALIDATEPROGRAMARBPROC			glValidateProgramARB			= (PFNGLVALIDATEPROGRAMARBPROC)&OOBadOpenGLExtensionUsed;
#endif

#if OO_SHADERS || OO_MULTITEXTURE
PFNGLACTIVETEXTUREARBPROC				glActiveTextureARB				= (PFNGLACTIVETEXTUREARBPROC)&OOBadOpenGLExtensionUsed;
#endif

#if OO_MULTITEXTURE
PFNGLCLIENTACTIVETEXTUREARBPROC			glClientActiveTextureARB		= (PFNGLCLIENTACTIVETEXTUREARBPROC)&OOBadOpenGLExtensionUsed;
#endif

#if OO_USE_VBO
PFNGLGENBUFFERSARBPROC					glGenBuffersARB					= (PFNGLGENBUFFERSARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLDELETEBUFFERSARBPROC				glDeleteBuffersARB				= (PFNGLDELETEBUFFERSARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLBINDBUFFERARBPROC					glBindBufferARB					= (PFNGLBINDBUFFERARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLBUFFERDATAARBPROC					glBufferDataARB					= (PFNGLBUFFERDATAARBPROC)&OOBadOpenGLExtensionUsed;
#endif

#if OO_USE_FBO
PFNGLGENFRAMEBUFFERSEXTPROC				glGenFramebuffersEXT			= (PFNGLGENFRAMEBUFFERSEXTPROC)&OOBadOpenGLExtensionUsed;
PFNGLBINDFRAMEBUFFEREXTPROC				glBindFramebufferEXT			= (PFNGLBINDFRAMEBUFFEREXTPROC)&OOBadOpenGLExtensionUsed;
PFNGLGENRENDERBUFFERSEXTPROC			glGenRenderbuffersEXT			= (PFNGLGENRENDERBUFFERSEXTPROC)&OOBadOpenGLExtensionUsed;
PFNGLBINDRENDERBUFFEREXTPROC			glBindRenderbufferEXT			= (PFNGLBINDRENDERBUFFEREXTPROC)&OOBadOpenGLExtensionUsed;
PFNGLRENDERBUFFERSTORAGEEXTPROC			glRenderbufferStorageEXT		= (PFNGLRENDERBUFFERSTORAGEEXTPROC)&OOBadOpenGLExtensionUsed;
PFNGLFRAMEBUFFERRENDERBUFFEREXTPROC		glFramebufferRenderbufferEXT	= (PFNGLFRAMEBUFFERRENDERBUFFEREXTPROC)&OOBadOpenGLExtensionUsed;
PFNGLFRAMEBUFFERTEXTURE2DEXTPROC		glFramebufferTexture2DEXT		= (PFNGLFRAMEBUFFERTEXTURE2DEXTPROC)&OOBadOpenGLExtensionUsed;
PFNGLCHECKFRAMEBUFFERSTATUSEXTPROC		glCheckFramebufferStatusEXT		= (PFNGLCHECKFRAMEBUFFERSTATUSEXTPROC)&OOBadOpenGLExtensionUsed;
PFNGLDELETEFRAMEBUFFERSEXTPROC			glDeleteFramebuffersEXT			= (PFNGLDELETEFRAMEBUFFERSEXTPROC)&OOBadOpenGLExtensionUsed;
PFNGLDELETERENDERBUFFERSEXTPROC			glDeleteRenderbuffersEXT		= (PFNGLDELETERENDERBUFFERSEXTPROC)&OOBadOpenGLExtensionUsed;
#endif
#endif


static NSString * const kOOLogOpenGLShaderSupport		= @"rendering.opengl.shader.support";


static OOOpenGLExtensionManager *sSingleton = nil;


// Read integer from string, advancing string to end of read data.
static unsigned IntegerFromString(const GLubyte **ioString);


@interface OOOpenGLExtensionManager (OOPrivate)

#if OO_SHADERS
- (void)checkShadersSupported;
#endif

#if OO_USE_VBO
- (void)checkVBOSupported;
#endif

#if OO_USE_FBO
- (void)checkFBOSupported;
#endif

#if GL_ARB_texture_env_combine
- (void)checkTextureCombinersSupported;
#endif

- (NSDictionary *) lookUpPerGPUSettingsWithVersionString:(NSString *)version extensionsString:(NSString *)extensionsStr;

@end


static NSArray *ArrayOfExtensions(NSString *extensionString)
{
	NSArray *components = [extensionString componentsSeparatedByString:@" "];
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:[components count]];
	NSEnumerator *extEnum = nil;
	NSString *extStr = nil;
	for (extEnum = [components objectEnumerator]; (extStr = [extEnum nextObject]); )
	{
		if ([extStr length] > 0)  [result addObject:extStr];
	}
	return result;
}


@implementation OOOpenGLExtensionManager

- (id)init
{
	self = [super init];
	if (self != nil)
	{
#if OOOPENGLEXTMGR_LOCK_SET_ACCESS
		lock = [[NSLock alloc] init];
		[lock setName:@"OOOpenGLExtensionManager extension set lock"];
#endif
		
		[self reset];
	}
	
	return self;
}


- (void) reset
{
	const GLubyte		*versionString = NULL, *curr = NULL;
	
	DESTROY(extensions);
	DESTROY(vendor);
	DESTROY(renderer);
	
	NSString *extensionsStr = [NSString stringWithUTF8String:(char *)glGetString(GL_EXTENSIONS)];
	extensions = [[NSSet alloc] initWithArray:ArrayOfExtensions(extensionsStr)];
	
	vendor = [[NSString alloc] initWithUTF8String:(const char *)glGetString(GL_VENDOR)];
	renderer = [[NSString alloc] initWithUTF8String:(const char *)glGetString(GL_RENDERER)];
	
	versionString = glGetString(GL_VERSION);
	if (versionString != NULL)
	{
		/*	String is supposed to be "major.minorFOO" or
		 "major.minor.releaseFOO" where FOO is an empty string or
		 a string beginning with space.
		 */
		curr = versionString;
		major = IntegerFromString(&curr);
		if (*curr == '.')
		{
			curr++;
			minor = IntegerFromString(&curr);
		}
		if (*curr == '.')
		{
			curr++;
			release = IntegerFromString(&curr);
		}
	}
	
	/*	For aesthetic reasons, cause the ResourceManager to initialize its
	 search paths here. If we don't, the search path dump ends up in
	 the middle of the OpenGL stuff.
	 */
	[ResourceManager paths];
	
	OOLog(@"rendering.opengl.version", @"OpenGL renderer version: %u.%u.%u (\"%s\"). Vendor: \"%@\". Renderer: \"%@\".", major, minor, release, versionString, vendor, renderer);
	OOLog(@"rendering.opengl.extensions", @"OpenGL extensions (%lu):\n%@", [extensions count], [[extensions allObjects] componentsJoinedByString:@", "]);
	
	if (![self versionIsAtLeastMajor:kMinMajorVersion minor:kMinMinorVersion])
	{
		OOLog(@"rendering.opengl.version.insufficient", @"***** Oolite requires OpenGL version %u.%u or later.", kMinMajorVersion, kMinMinorVersion);
		[NSException raise:@"OoliteOpenGLTooOldException"
					format:@"Oolite requires at least OpenGL %u.%u. You have %u.%u (\"%s\").", kMinMajorVersion, kMinMinorVersion, major, minor, versionString];
	}
	
	NSString *versionStr = [[[NSString alloc] initWithUTF8String:(const char *)versionString] autorelease];
	NSDictionary *gpuConfig = [self lookUpPerGPUSettingsWithVersionString:versionStr extensionsString:extensionsStr];
	
#if OO_SHADERS
	[self checkShadersSupported];
	
	if (shadersAvailable)
	{
		defaultShaderSetting = OOShaderSettingFromString([gpuConfig oo_stringForKey:@"default_shader_level"
																   defaultValue:@"SHADERS_FULL"]);
		maximumShaderSetting = OOShaderSettingFromString([gpuConfig oo_stringForKey:@"maximum_shader_level"
																   defaultValue:@"SHADERS_FULL"]);
		if (maximumShaderSetting <= SHADERS_OFF)
		{
			shadersAvailable = NO;
			maximumShaderSetting = SHADERS_NOT_SUPPORTED;
			OOLog(kOOLogOpenGLShaderSupport, @"Shaders will not be used (disallowed for GPU type \"%@\").", [gpuConfig oo_stringForKey:@"name" defaultValue:renderer]);
		}
		if (maximumShaderSetting < defaultShaderSetting)
		{
			defaultShaderSetting = maximumShaderSetting;
		}
		
		if (shadersAvailable)
		{
			OOLog(kOOLogOpenGLShaderSupport, @"Shaders are supported.");
		}
	}
	else
	{
		defaultShaderSetting = SHADERS_NOT_SUPPORTED;
		maximumShaderSetting = SHADERS_NOT_SUPPORTED;
	}
	
	GLint texImageUnitOverride = [gpuConfig oo_intForKey:@"texture_image_units" defaultValue:textureImageUnitCount];
	if (texImageUnitOverride < textureImageUnitCount)  textureImageUnitCount = MAX(texImageUnitOverride, 0);
#endif
	
#if OO_USE_VBO
	[self checkVBOSupported];
#endif
#if OO_USE_FBO
	[self checkFBOSupported];
#endif
#if OO_MULTITEXTURE
	[self checkTextureCombinersSupported];
	GLint texUnitOverride = [gpuConfig oo_intForKey:@"texture_units" defaultValue:textureUnitCount];
	if (texUnitOverride < textureUnitCount)  textureUnitCount = MAX(texUnitOverride, 0);
#endif
	
	usePointSmoothing = [gpuConfig oo_boolForKey:@"smooth_points" defaultValue:YES];
	useLineSmoothing = [gpuConfig oo_boolForKey:@"smooth_lines" defaultValue:YES];
	useDustShader = [gpuConfig oo_boolForKey:@"use_dust_shader" defaultValue:YES];
}


- (void)dealloc
{
	if (sSingleton == self)  sSingleton = nil;
	
#if OOOPENGLEXTMGR_LOCK_SET_ACCESS
	[lock release];
#endif
	DESTROY(extensions);
	DESTROY(vendor);
	DESTROY(renderer);
	
	[super dealloc];
}


+ (OOOpenGLExtensionManager *)sharedManager
{
	// NOTE: assumes single-threaded first access. See header.
	if (sSingleton == nil)  sSingleton = [[self alloc] init];
	return sSingleton;
}


- (BOOL)haveExtension:(NSString *)extension
{
// NSSet is documented as thread-safe under OS X, but I'm not sure about GNUstep. -- Ahruman
#if OOOPENGLEXTMGR_LOCK_SET_ACCESS
	[lock lock];
#endif
	
	BOOL result = [extensions containsObject:extension];
	
#if OOOPENGLEXTMGR_LOCK_SET_ACCESS
	[lock unlock];
#endif
	
	return result;
}


- (BOOL)shadersSupported
{
#if OO_SHADERS
	return shadersAvailable;
#else
	return NO;
#endif
}


- (OOShaderSetting)defaultShaderSetting
{
#if OO_SHADERS
	return defaultShaderSetting;
#else
	return SHADERS_NOT_SUPPORTED;
#endif
}


- (OOShaderSetting)maximumShaderSetting
{
#if OO_SHADERS
	return maximumShaderSetting;
#else
	return SHADERS_NOT_SUPPORTED;
#endif
}


- (GLint)textureImageUnitCount
{
#if OO_SHADERS
	return textureImageUnitCount;
#else
	return 0;
#endif
}


- (BOOL)vboSupported
{
#if OO_USE_VBO
	return vboSupported;
#else
	return NO;
#endif
}


- (BOOL)fboSupported
{
#if OO_USE_FBO
	return fboSupported;
#else
	return NO;
#endif
}


- (BOOL)textureCombinersSupported
{
#if OO_MULTITEXTURE
	return textureCombinersSupported;
#else
	return NO;
#endif
}


- (GLint)textureUnitCount
{
#if OO_MULTITEXTURE
	return textureUnitCount;
#else
	return 0;
#endif
}


- (NSUInteger)majorVersionNumber
{
	return major;
}


- (NSUInteger)minorVersionNumber
{
	return minor;
}


- (NSUInteger)releaseVersionNumber
{
	return release;
}


- (void)getVersionMajor:(unsigned *)outMajor minor:(unsigned *)outMinor release:(unsigned *)outRelease
{
	if (outMajor != NULL)  *outMajor = major;
	if (outMinor != NULL)  *outMinor = minor;
	if (outRelease != NULL)  *outRelease = release;
}


- (BOOL) versionIsAtLeastMajor:(unsigned)maj minor:(unsigned)min
{
	return major > maj || (major == maj && minor >= min);
}


- (NSString *) vendorString
{
	return vendor;
}


- (NSString *) rendererString
{
	return renderer;
}


- (BOOL) usePointSmoothing
{
	return usePointSmoothing;
}


- (BOOL) useLineSmoothing
{
	return useLineSmoothing;
}


- (BOOL) useDustShader
{
	return useDustShader;
}

@end


static unsigned IntegerFromString(const GLubyte **ioString)
{
	if (EXPECT_NOT(ioString == NULL))  return 0;
	
	unsigned		result = 0;
	const GLubyte	*curr = *ioString;
	
	while ('0' <= *curr && *curr <= '9')
	{
		result = result * 10 + *curr++ - '0';
	}
	
	*ioString = curr;
	return result;
}


@implementation OOOpenGLExtensionManager (OOPrivate)


#if OO_SHADERS

- (void)checkShadersSupported
{
	shadersAvailable = NO;
	
	NSString * const requiredExtension[] = 
						{
							@"GL_ARB_shading_language_100",
							@"GL_ARB_fragment_shader",
							@"GL_ARB_vertex_shader",
							@"GL_ARB_multitexture",
							@"GL_ARB_shader_objects",
							nil	// sentinel - don't remove!
						};
	NSString * const *required = NULL;
	
	for (required = requiredExtension; *required != nil; ++required)
	{
		if (![self haveExtension:*required])
		{
			OOLog(kOOLogOpenGLShaderSupport, @"Shaders will not be used (OpenGL extension %@ is not available).", *required);
			return;
		}
	}
	
#if OOLITE_WINDOWS
	glGetObjectParameterivARB	=	(PFNGLGETOBJECTPARAMETERIVARBPROC)wglGetProcAddress("glGetObjectParameterivARB");
	glCreateShaderObjectARB		=	(PFNGLCREATESHADEROBJECTARBPROC)wglGetProcAddress("glCreateShaderObjectARB");
	glGetInfoLogARB				=	(PFNGLGETINFOLOGARBPROC)wglGetProcAddress("glGetInfoLogARB");
	glCreateProgramObjectARB	=	(PFNGLCREATEPROGRAMOBJECTARBPROC)wglGetProcAddress("glCreateProgramObjectARB");
	glAttachObjectARB			=	(PFNGLATTACHOBJECTARBPROC)wglGetProcAddress("glAttachObjectARB");
	glDeleteObjectARB			=	(PFNGLDELETEOBJECTARBPROC)wglGetProcAddress("glDeleteObjectARB");
	glLinkProgramARB			=	(PFNGLLINKPROGRAMARBPROC)wglGetProcAddress("glLinkProgramARB");
	glCompileShaderARB			=	(PFNGLCOMPILESHADERARBPROC)wglGetProcAddress("glCompileShaderARB");
	glShaderSourceARB			=	(PFNGLSHADERSOURCEARBPROC)wglGetProcAddress("glShaderSourceARB");
	glUseProgramObjectARB		=	(PFNGLUSEPROGRAMOBJECTARBPROC)wglGetProcAddress("glUseProgramObjectARB");
	glActiveTextureARB			=	(PFNGLACTIVETEXTUREARBPROC)wglGetProcAddress("glActiveTextureARB");
	glGetUniformLocationARB		=	(PFNGLGETUNIFORMLOCATIONARBPROC)wglGetProcAddress("glGetUniformLocationARB");
	glUniform1iARB				=	(PFNGLUNIFORM1IARBPROC)wglGetProcAddress("glUniform1iARB");
	glUniform1fARB				=	(PFNGLUNIFORM1FARBPROC)wglGetProcAddress("glUniform1fARB");
	glUniformMatrix4fvARB		=	(PFNGLUNIFORMMATRIX4FVARBPROC)wglGetProcAddress("glUniformMatrix4fvARB");
	glUniform4fvARB				=	(PFNGLUNIFORM4FVARBPROC)wglGetProcAddress("glUniform4fvARB");
	glUniform2fvARB				=	(PFNGLUNIFORM2FVARBPROC)wglGetProcAddress("glUniform2fvARB");
	glBindAttribLocationARB		=	(PFNGLBINDATTRIBLOCATIONARBPROC)wglGetProcAddress("glBindAttribLocationARB");
	glEnableVertexAttribArrayARB =	(PFNGLENABLEVERTEXATTRIBARRAYARBPROC)wglGetProcAddress("glEnableVertexAttribArrayARB");
	glVertexAttribPointerARB	=	(PFNGLVERTEXATTRIBPOINTERARBPROC)wglGetProcAddress("glVertexAttribPointerARB");
	glDisableVertexAttribArrayARB =	(PFNGLDISABLEVERTEXATTRIBARRAYARBPROC)wglGetProcAddress("glDisableVertexAttribArrayARB");
	glValidateProgramARB		=	(PFNGLVALIDATEPROGRAMARBPROC)wglGetProcAddress("glValidateProgramARB");
#endif
	
	glGetIntegerv(GL_MAX_TEXTURE_IMAGE_UNITS_ARB, &textureImageUnitCount);
	
	shadersAvailable = YES;
}
#endif


#if OO_USE_VBO
- (void)checkVBOSupported
{
	vboSupported = NO;
	
	if ([self versionIsAtLeastMajor:1 minor:5] || [self haveExtension:@"GL_ARB_vertex_buffer_object"])
	{
		vboSupported = YES;
	}
	
#if OOLITE_WINDOWS
	if (vboSupported)
	{
		glGenBuffersARB = (PFNGLGENBUFFERSARBPROC)wglGetProcAddress("glGenBuffersARB");
		glDeleteBuffersARB = (PFNGLDELETEBUFFERSARBPROC)wglGetProcAddress("glDeleteBuffersARB");
		glBindBufferARB = (PFNGLBINDBUFFERARBPROC)wglGetProcAddress("glBindBufferARB");
		glBufferDataARB = (PFNGLBUFFERDATAARBPROC)wglGetProcAddress("glBufferDataARB");
	}
#endif
}
#endif


#if OO_USE_FBO
- (void)checkFBOSupported
{
	fboSupported = NO;
	
	if ([self haveExtension:@"GL_EXT_framebuffer_object"])
	{
		fboSupported = YES;
	}
	
#if OOLITE_WINDOWS
	if (fboSupported)
	{
		glGenFramebuffersEXT = (PFNGLGENFRAMEBUFFERSEXTPROC)wglGetProcAddress("glGenFramebuffersEXT");
		glBindFramebufferEXT = (PFNGLBINDFRAMEBUFFEREXTPROC)wglGetProcAddress("glBindFramebufferEXT");
		glGenRenderbuffersEXT = (PFNGLGENRENDERBUFFERSEXTPROC)wglGetProcAddress("glGenRenderbuffersEXT");
		glBindRenderbufferEXT = (PFNGLBINDRENDERBUFFEREXTPROC)wglGetProcAddress("glBindRenderbufferEXT");
		glRenderbufferStorageEXT = (PFNGLRENDERBUFFERSTORAGEEXTPROC)wglGetProcAddress("glRenderbufferStorageEXT");
		glFramebufferRenderbufferEXT = (PFNGLFRAMEBUFFERRENDERBUFFEREXTPROC)wglGetProcAddress("glFramebufferRenderbufferEXT");
		glFramebufferTexture2DEXT = (PFNGLFRAMEBUFFERTEXTURE2DEXTPROC)wglGetProcAddress("glFramebufferTexture2DEXT");
		glCheckFramebufferStatusEXT = (PFNGLCHECKFRAMEBUFFERSTATUSEXTPROC)wglGetProcAddress("glCheckFramebufferStatusEXT");
		glDeleteFramebuffersEXT = (PFNGLDELETEFRAMEBUFFERSEXTPROC)wglGetProcAddress("glDeleteFramebuffersEXT");
		glDeleteRenderbuffersEXT = (PFNGLDELETERENDERBUFFERSEXTPROC)wglGetProcAddress("glDeleteRenderbuffersEXT");
	}
#endif
}
#endif


#if OO_MULTITEXTURE
- (void)checkTextureCombinersSupported
{
	textureCombinersSupported = [self haveExtension:@"GL_ARB_texture_env_combine"];
	
	if (textureCombinersSupported)
	{
		OOGL(glGetIntegerv(GL_MAX_TEXTURE_UNITS_ARB, &textureUnitCount));
		
#if OOLITE_WINDOWS
		// Duplicated in checkShadersSupported. but that's not really a problem.
		glActiveTextureARB = (PFNGLACTIVETEXTUREARBPROC)wglGetProcAddress("glActiveTextureARB");
		
		glClientActiveTextureARB = (PFNGLCLIENTACTIVETEXTUREARBPROC)wglGetProcAddress("glClientActiveTextureARB");
#endif
	}
	else
	{
		textureUnitCount = 1;
	}

}
#endif


// regexps may be a single string or an array of strings (in which case results are ANDed).
static BOOL CheckRegExps(NSString *string, id regexps)
{
	if (regexps == nil)  return YES;	// No restriction == match.
	if ([regexps isKindOfClass:[NSString class]])
	{
		return [string oo_matchesRegularExpression:regexps];
	}
	if ([regexps isKindOfClass:[NSArray class]])
	{
		NSEnumerator *regexpEnum = nil;
		NSString *regexp = nil;
		
		for (regexpEnum = [regexps objectEnumerator]; (regexp = [regexpEnum nextObject]); )
		{
			if (EXPECT_NOT(![regexp isKindOfClass:[NSString class]]))
			{
				// Invalid type -- match fails.
				return NO;
			}
			
			if (![string oo_matchesRegularExpression:regexp])  return NO;
		}
		return YES;
	}
	
	// Invalid type -- match fails.
	return NO;
}


NSComparisonResult CompareGPUSettingsByPriority(id a, id b, void *context)
{
	NSString		*keyA = a;
	NSString		*keyB = b;
	NSDictionary	*configurations = context;
	NSDictionary	*dictA = [configurations oo_dictionaryForKey:keyA];
	NSDictionary	*dictB = [configurations oo_dictionaryForKey:keyB];
	double			precedenceA = [dictA oo_doubleForKey:@"precedence" defaultValue:1];
	double			precedenceB = [dictB oo_doubleForKey:@"precedence" defaultValue:1];
	
	if (precedenceA > precedenceB)  return NSOrderedAscending;
	if (precedenceA < precedenceB)  return NSOrderedDescending;
	
	return [keyA caseInsensitiveCompare:keyB];
}


- (NSDictionary *) lookUpPerGPUSettingsWithVersionString:(NSString *)versionStr extensionsString:(NSString *)extensionsStr
{
	NSDictionary *configurations = [ResourceManager dictionaryFromFilesNamed:@"gpu-settings.plist"
																	inFolder:@"Config"
																	andMerge:YES];
	
	NSArray *keys = [[configurations allKeys] sortedArrayUsingFunction:CompareGPUSettingsByPriority context:configurations];
	
	NSEnumerator *keyEnum = nil;
	NSString *key = nil;
	NSDictionary *config = nil;
	
	for (keyEnum = [keys objectEnumerator]; (key = [keyEnum nextObject]); )
	{
		config = [configurations oo_dictionaryForKey:key];
		if (EXPECT_NOT(config == nil))  continue;
		
		NSDictionary *match = [config oo_dictionaryForKey:@"match"];
		NSString *expr = nil;
		
		expr = [match objectForKey:@"vendor"];
		if (!CheckRegExps(vendor, expr))  continue;
		
		expr = [match oo_stringForKey:@"renderer"];
		if (!CheckRegExps(renderer, expr))  continue;
		
		expr = [match oo_stringForKey:@"version"];
		if (!CheckRegExps(versionStr, expr))  continue;
		
		expr = [match oo_stringForKey:@"extensions"];
		if (!CheckRegExps(extensionsStr, expr))  continue;
		
		OOLog(@"rendering.opengl.gpuSpecific", @"Matched GPU configuration \"%@\".", key);
		return config;
	}
	
	return [NSDictionary dictionary];
}

@end


@implementation OOOpenGLExtensionManager (Singleton)

/*	Canonical singleton boilerplate.
	See Cocoa Fundamentals Guide: Creating a Singleton Instance.
	See also +sharedManager above.
	
	// NOTE: assumes single-threaded first access.
*/

+ (id)allocWithZone:(NSZone *)inZone
{
	if (sSingleton == nil)
	{
		sSingleton = [super allocWithZone:inZone];
		return sSingleton;
	}
	return nil;
}


- (id)copyWithZone:(NSZone *)inZone
{
	return self;
}


- (id)retain
{
	return self;
}


- (NSUInteger)retainCount
{
	return UINT_MAX;
}


- (void)release
{}


- (id)autorelease
{
	return self;
}

@end


#if OOLITE_WINDOWS

static void OOBadOpenGLExtensionUsed(void)
{
	OOLog(@"rendering.opengl.badExtension", @"***** An uninitialized OpenGL extension function has been called, terminating. This is a serious error, please report it. *****");
	exit(EXIT_FAILURE);
}

#endif
