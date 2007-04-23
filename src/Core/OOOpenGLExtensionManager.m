/*

OOOpenGLExtensionManager.m

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

#import "OOOpenGLExtensionManager.h"
#import "OOLogging.h"
#import "OOFunctionAttributes.h"
#import <stdlib.h>


static NSString * const kOOLogOpenGLShaderSupport		= @"rendering.opengl.shader.support";


static OOOpenGLExtensionManager *sSingleton = nil;


// Read integer from string, advancing string to end of read data.
static unsigned IntegerFromString(const GLubyte **ioString);


@interface OOOpenGLExtensionManager (OOPrivate)

#ifndef NO_SHADERS
- (void)checkShadersSupported;
#endif NO_SHADERS

@end



@implementation OOOpenGLExtensionManager

- (id)init
{
	NSString			*extensionString = nil;
	NSArray				*components = nil;
	const GLubyte		*versionString = nil, *curr = nil;
	
	self = [super init];
	if (self != nil)
	{
		lock = [[NSLock alloc] init];
		
		extensionString = [NSString stringWithUTF8String:(char *)glGetString(GL_EXTENSIONS)];
		components = [extensionString componentsSeparatedByString:@" "];
		extensions = [[NSSet alloc] initWithArray:components];
		
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
		
		OOLog(@"rendering.opengl.version", @"OpenGL renderer version: %u.%u.%u (\"%s\")\nVendor: %@\nRenderer: %@", major, minor, release, versionString, vendor, renderer);
		OOLog(@"rendering.opengl.extensions", @"OpenGL extensions (%u):\n%@", [extensions count], extensionString);
		
		if (major <= 1 && minor <= 1)
		{
			/*	Ensure we have OpenGL 1.1 or later (basic stuff like
				glBindTexture(), glDrawArrays()).
				We probably have implicit requirements for later versions, but
				I don't feel like auditing.
				-- Ahruman
			*/
			OOLog(@"rendering.opengl.version.insufficient", @"***** Oolite requires OpenGL version 1.1 or later.");
			[NSException raise:@"OoliteOpenGLTooOldException"
						format:@"Oolite requires at least OpenGL 1.1. You have %u.%u (\"%s\").", major, minor, versionString];
		}
		
#if OOLITE_WINDOWS
#if GL_ARB_vertex_buffer_object
		if ([self haveExtension:@"GL_ARB_vertex_buffer_object"])
		{
			glBindBufferARB = (PFNGLBINDBUFFERARBPROC)wglGetProcAddress("glBindBufferARB");
			glGenBuffersARB = (PFNGLGENBUFFERSARBPROC)wglGetProcAddress("glGenBuffersARB");
			glBufferDataARB = (PFNGLBUFFERDATAARBPROC)wglGetProcAddress("glBufferDataARB");
		}
#endif
		
#if GL_APPLE_vertex_array_object
		if ([self haveExtension:@"GL_APPLE_vertex_array_object"])
		{
			glBindBufferARB = (PFNGLBINDBUFFERARBPROC)wglGetProcAddress("glBindBufferARB");
			glGenBuffersARB = (PFNGLGENBUFFERSARBPROC)wglGetProcAddress("glGenBuffersARB");
			glBufferDataARB = (PFNGLBUFFERDATAARBPROC)wglGetProcAddress("glBufferDataARB");
		}
#endif
#endif
		
#ifndef NO_SHADERS
		[self checkShadersSupported];
#endif
	}
	return self;
}


- (void)dealloc
{
	[extensions release];
	[lock release];
	
	[super dealloc];
}


+ (id)sharedManager
{
	// NOTE: assumes single-threaded first access. See header.
	if (sSingleton == nil)  [[self alloc] init];
	return sSingleton;
}


- (BOOL)haveExtension:(NSString *)extension
{
// NSSet is documented as thread-safe under OS X, but I'm not sure about GNUstep. -- Ahruman
#if !OOLITE_MAC_OS_X
	[lock lock];
#endif
	
	BOOL result = [extensions containsObject:extension];
	
#if !OOLITE_MAC_OS_X
	[lock lock];
#endif
	
	return result;
}


- (BOOL)shadersSupported
{
#ifndef NO_SHADERS
	return shadersAvailable;
#endif
}


- (unsigned)majorVersionNumber
{
	return major;
}


- (unsigned)minorVersionNumber
{
	return minor;
}


- (unsigned)releaseVersionNumber
{
	return release;
}


- (void)getVersionMajor:(unsigned *)outMajor minor:(unsigned *)outMinor release:(unsigned *)outRelease
{
	if (outMajor != NULL)  *outMajor = major;
	if (outMinor != NULL)  *outMinor = minor;
	if (outRelease != NULL)  *outRelease = release;
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


#ifndef NO_SHADERS

- (void)checkShadersSupported
{
	shadersAvailable = NO;
	
	if (major <= 1 && minor < 5)
	{
		OOLog(kOOLogOpenGLShaderSupport, @"Shaders will not be used (OpenGL version < 1.5).");
		return;
	}
	
	const NSString		*requiredExtension[] = 
						{
							@"GL_ARB_multitexture",
							@"GL_ARB_shader_objects",
							@"GL_ARB_shading_language_100",
							@"GL_ARB_fragment_shader",
							@"GL_ARB_vertex_shader",
							@"GL_ARB_fragment_program",
							@"GL_ARB_vertex_program",
							nil	// sentinel - don't remove!
						};
	NSString			**required = NULL;
	
	for (required = requiredExtension; *required != nil; ++required)
	{
		if (![self haveExtension:*required])
		{
			OOLog(kOOLogOpenGLShaderSupport, @"Shaders will not be used (OpenGL extension %@ is not available).", *required);
			return;
		}
	}
	
#if OOLITE_WINDOWS
	glGetObjectParameterivARB = (PFNGLGETOBJECTPARAMETERIVARBPROC)wglGetProcAddress("glGetObjectParameterivARB");
	glCreateShaderObjectARB = (PFNGLCREATESHADEROBJECTARBPROC)wglGetProcAddress("glCreateShaderObjectARB");
	glGetInfoLogARB = (PFNGLGETINFOLOGARBPROC)wglGetProcAddress("glGetInfoLogARB");
	glCreateProgramObjectARB = (PFNGLCREATEPROGRAMOBJECTARBPROC)wglGetProcAddress("glCreateProgramObjectARB");
	glAttachObjectARB = (PFNGLATTACHOBJECTARBPROC)wglGetProcAddress("glAttachObjectARB");
	glDeleteObjectARB = (PFNGLDELETEOBJECTARBPROC)wglGetProcAddress("glDeleteObjectARB");
	glLinkProgramARB = (PFNGLLINKPROGRAMARBPROC)wglGetProcAddress("glLinkProgramARB");
	glCompileShaderARB = (PFNGLCOMPILESHADERARBPROC)wglGetProcAddress("glCompileShaderARB");
	glShaderSourceARB = (PFNGLSHADERSOURCEARBPROC)wglGetProcAddress("glShaderSourceARB");
	glUseProgramObjectARB = (PFNGLUSEPROGRAMOBJECTARBPROC)wglGetProcAddress("glUseProgramObjectARB");
	glActiveTextureARB = (PFNGLACTIVETEXTUREARBPROC)wglGetProcAddress("glActiveTextureARB");
	glGetUniformLocationARB = (PFNGLGETUNIFORMLOCATIONARBPROC)wglGetProcAddress("glGetUniformLocationARB");
	glUniform1iARB = (PFNGLUNIFORM1IARBPROC)wglGetProcAddress("glUniform1iARB");
	glUniform1fARB = (PFNGLUNIFORM1FARBPROC)wglGetProcAddress("glUniform1fARB");
#endif
	
	shadersAvailable = YES;
}
#endif

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


- (unsigned)retainCount
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


#if OOLITE_WINDOWS && !defined(NO_SHADERS)

void OOBadOpenGLExtensionUsed(void)
{
	OOLog(@"rendering.opengl.badExtension", @"***** An uninitialized OpenGL extension function has been called, terminating. This is a serious error, please report it. *****");
	exit(EXIT_FAILURE);
}

#endif
