/*

OOEnvironmentCubeMap.m


Copyright (C) 2010-2012 Jens Ayton

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

#import "OOEnvironmentCubeMap.h"
#import "OOTexture.h"
#import "OOTextureInternal.h"
#import "MyOpenGLView.h"
#import "OOPixMap.h"
#import "OOMacroOpenGL.h"

#import "Universe.h"
#import "PlayerEntity.h"
#import "SkyEntity.h"
#import "OOSunEntity.h"
#import "OOPlanetEntity.h"
#import "OODrawable.h"
#import "OOEntityFilterPredicate.h"


#if OO_USE_FBO && OO_TEXTURE_CUBE_MAP

@interface OOEnvironmentCubeMap (Private)

- (void) setUp;

- (void) renderOnePassWithSky:(OODrawable *)sky sun:(OOSunEntity *)sun planets:(NSArray *)planets;

@end


@implementation OOEnvironmentCubeMap

- (id) initWithSideLength:(GLuint)size
{
	if (![[OOOpenGLExtensionManager sharedManager] fboSupported] || !OOCubeMapsAvailable())
	{
		[self release];
		return nil;
	}
	
	if ((self = [super init]))
	{
		_size = size;
	}
	
	return self;
}


- (void) dealloc
{
	[self forceRebind];
	
	[super dealloc];
}


- (void) render
{
	if (_textureName == 0)  [self setUp];
	
	OO_ENTER_OPENGL();
	
	// Save stuff.
	OOGL(glPushAttrib(GL_VIEWPORT_BIT | GL_ENABLE_BIT));
	OOGL(glMatrixMode(GL_MODELVIEW));
	OOGL(glPushMatrix());
	
	OOGL(glMatrixMode(GL_PROJECTION));
	OOGL(glPushMatrix());
	
	OOGL(glViewport(0, 0, _size, _size));
	OOGL(glScalef(-1.0, 1.0, 1.0));   // flip left and right
	
	/*	TODO: once confirmed working (and rendering everything in the right
		orientation), replace with glLoadMatrix and the following:
		1 0 0 0
		0 1 0 0
		0 0 -1 -2
		0 0 -1 0
		
		...and appropriate rotations thereof.
	*/
	
	OOGL(glLoadIdentity());
	OOGL(gluPerspective(90.0, 1.0, 1.0, MAX_CLEAR_DEPTH));
	
	OODrawable *sky = [[UNIVERSE nearestEntityMatchingPredicate:HasClassPredicate parameter:[SkyEntity class] relativeToEntity:nil] drawable];
	OOSunEntity *sun = [UNIVERSE sun];
	NSArray *planets = [UNIVERSE planets];
	
	unsigned i;
	Vector centers[6] = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } };
	Vector ups[6] = { { 0, -1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 }, { 0, -1, 0 }, { 0, -1, 0 } };
	
	for (i = 0; i < 6; i++)
	{
		OOGL(glPushMatrix());
		Vector center = centers[i];
		Vector up = ups[i];
		OOGL(gluLookAt(0, 0, 0, center.x, center.y, center.z, up.x, up.y, up.z));
		
		OOGL(glMatrixMode(GL_MODELVIEW));
		OOGL(glPushMatrix());
		
		OOGL(glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, _fbos[i]));
		[self renderOnePassWithSky:sky sun:sun planets:planets];
		
		OOGL(glPopMatrix());
		OOGL(glMatrixMode(GL_PROJECTION));
		OOGL(glPopMatrix());
	}
	
	OOGL(glMatrixMode(GL_PROJECTION));
	OOGL(glPopMatrix());
	OOGL(glMatrixMode(GL_MODELVIEW));
	OOGL(glPopMatrix());
	OOGL(glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0));
	OOGL(glPopAttrib());
}


- (void) renderOnePassWithSky:(OODrawable *)sky sun:(OOSunEntity *)sun planets:(NSArray *)planets
{
	OO_ENTER_OPENGL();
	
	OOGL(glClearColor(0.0f, 0.0f, 0.0f, 1.0f));
	OOGL(glClearDepth(MAX_CLEAR_DEPTH));
	OOGL(glClear(_planets ? GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT : GL_COLOR_BUFFER_BIT));
	
	OOGL(glDepthMask(GL_FALSE));
	[sky renderOpaqueParts];
	OOGL(glDepthMask(GL_TRUE));
	
	OOGL(glLoadIdentity());
	GLTranslateOOVector(vector_flip([PLAYER position]));
	
	NSEnumerator	*planetEnum = nil;
	OOPlanetEntity	*planet = nil;
	for (planetEnum = [planets objectEnumerator]; (planet = [planetEnum nextObject]); )
	{
		OOGL(glPushMatrix());
		GLTranslateOOVector([planet position]);
#if NEW_PLANETS
		[[planet drawable] renderOpaqueParts];
#else
		[planet drawUnconditionally];
#endif
		OOGL(glPopMatrix());
	}
	
	OOGL(glPushMatrix());
	GLTranslateOOVector([sun position]);
	[sun drawUnconditionally];
	OOGL(glPopMatrix());
}

- (void) setUp
{
	OO_ENTER_OPENGL();
	
	if (_textureName != 0)  return;
	_planets = [UNIVERSE reducedDetail];
	
	OOGL(glGenTextures(1, &_textureName));
	OOGL(glBindTexture(GL_TEXTURE_CUBE_MAP, _textureName));
	OOGL(glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE));
	OOGL(glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE));
	OOGL(glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE));
	OOGL(glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAG_FILTER, GL_LINEAR));
	OOGL(glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, GL_LINEAR));
	
	OOGL(glGenFramebuffersEXT(6, _fbos));
	OOGL(glGenRenderbuffersEXT(6, _depthBuffers));
	
	unsigned i;
	for (i = 0; i < 6; i++)
	{
		GLenum textarget = GL_TEXTURE_CUBE_MAP_POSITIVE_X + i;
		
		OOGL(glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, _fbos[i]));
		
		OOGL(glBindRenderbufferEXT(GL_RENDERBUFFER_EXT, _depthBuffers[i]));
		OOGL(glRenderbufferStorageEXT(GL_RENDERBUFFER_EXT, GL_DEPTH_COMPONENT, _size, _size));
		OOGL(glFramebufferRenderbufferEXT(GL_FRAMEBUFFER_EXT, GL_DEPTH_ATTACHMENT_EXT, GL_RENDERBUFFER_EXT, _depthBuffers[i]));
		
		OOGL(glTexImage2D(textarget, 0, GL_RGBA8, _size, _size, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL));
		OOGL(glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, textarget, _textureName, 0));
	}
	
#ifndef NDEBUG
	GLenum status;
	OOGL(status = glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT));
	if (status != GL_FRAMEBUFFER_COMPLETE_EXT)
	{
		OOLogERR(@"environmentCube.fbo.setup.failed", @"Failed to set up FBO for environment cube map - status is %u.", status);
		DESTROY(self);
	}
	
	OOCheckOpenGLErrors(@"after setting up environment cube map FBO");
#endif
	OOGL(glBindTexture(GL_TEXTURE_CUBE_MAP, 0));
	OOGL(glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0));
	OOGL(glBindRenderbufferEXT(GL_RENDERBUFFER_EXT, 0));
}


// OOTexture stuff.

- (void) apply
{
	OO_ENTER_OPENGL();
	OOGL(glBindTexture(GL_TEXTURE_CUBE_MAP, _textureName));
}


- (NSSize) dimensions
{
	return NSMakeSize(_size, _size);
}


- (void) forceRebind
{
	OO_ENTER_OPENGL();
	if (_textureName == 0)  return;
	
	OOGL(glDeleteTextures(1, &_textureName));
	_textureName = 0;
	
	OOGL(glDeleteFramebuffersEXT(6, _fbos));
	OOGL(glDeleteRenderbuffersEXT(6, _depthBuffers));
}


- (BOOL) isCubeMap
{
	return YES;
}


- (struct OOPixMap) copyPixMapRepresentation
{
	OOPixMap pixmap = OOAllocatePixMap(_size, _size * 6, 4, 0, 0);
	if (!OOIsValidPixMap(pixmap))  return kOONullPixMap;
	
	OO_ENTER_OPENGL();
	
	unsigned i;
	for (i = 0; i < 6; i++)
	{
		OOGL(glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, _fbos[i]));
		OOGL(glReadBuffer(GL_COLOR_ATTACHMENT0_EXT));
		uint8_t *target = pixmap.pixels;
		target += pixmap.rowBytes * _size * i;
		OOGL(glReadPixels(0, 0, _size, _size, GL_RGBA, GL_UNSIGNED_BYTE, target));
	}
	
	OOGL(glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0));
	return pixmap;
}

@end

#endif
