/*
	
	OOConcreteTexture.m
	
	Copyright (C) 2007-2012 Jens Ayton and contributors
	
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

#import "OOTextureInternal.h"
#import "OOConcreteTexture.h"

#import "OOTextureLoader.h"

#import "OOCollectionExtractors.h"
#import "Universe.h"
#import "ResourceManager.h"
#import "OOOpenGLExtensionManager.h"
#import "OOMacroOpenGL.h"
#import "OOCPUInfo.h"
#import "OOPixMap.h"

#ifndef NDEBUG
#import "OOTextureGenerator.h"
#endif


#if OOLITE_BIG_ENDIAN
#define RGBA_IMAGE_TYPE GL_UNSIGNED_INT_8_8_8_8_REV
#elif OOLITE_LITTLE_ENDIAN
#define RGBA_IMAGE_TYPE GL_UNSIGNED_BYTE
#else
#error Neither OOLITE_BIG_ENDIAN nor OOLITE_LITTLE_ENDIAN is defined as nonzero!
#endif


@interface OOConcreteTexture (Private)

- (void)setUpTexture;
- (void)uploadTexture;
- (void)uploadTextureDataWithMipMap:(BOOL)mipMap format:(OOTextureDataFormat)format;
#if OO_TEXTURE_CUBE_MAP
- (void) uploadTextureCubeMapDataWithMipMap:(BOOL)mipMap format:(OOTextureDataFormat)format;
#endif

- (GLenum) glTextureTarget;

#if OOTEXTURE_RELOADABLE
- (BOOL) isReloadable;
#endif

@end


static BOOL DecodeFormat(OOTextureDataFormat format, uint32_t options, GLenum *outFormat, GLenum *outInternalFormat, GLenum *outType);


@implementation OOConcreteTexture

- (id) initWithLoader:(OOTextureLoader *)loader
				  key:(NSString *)key
			  options:(uint32_t)options
		   anisotropy:(GLfloat)anisotropy
			  lodBias:(GLfloat)lodBias
{
	if (loader == nil)
	{
		[self release];
		return nil;
	}
	
	self = [super init];
	if (EXPECT_NOT(self == nil))  return nil;
	
	_loader = [loader retain];
	_options = options;
	
#if GL_EXT_texture_filter_anisotropic
	_anisotropy = OOClamp_0_1_f(anisotropy) * gOOTextureInfo.anisotropyScale;
#endif
#if GL_EXT_texture_lod_bias
	_lodBias = lodBias;
#endif
	
#ifndef NDEBUG
	if ([loader isKindOfClass:[OOTextureGenerator class]])
	{
		_name = [[NSString alloc] initWithFormat:@"<%@>", [loader class]];
	}
#endif
	
	_key = [key copy];
	
	[self addToCaches];
	
	return self;
}


- (id)initWithPath:(NSString *)path
			   key:(NSString *)key
		   options:(uint32_t)options
		anisotropy:(float)anisotropy
		   lodBias:(GLfloat)lodBias
{
	OOTextureLoader *loader = [OOTextureLoader loaderWithPath:path options:options];
	if (loader == nil)
	{
		[self release];
		return nil;
	}
	
	if ((self = [self initWithLoader:loader key:key options:options anisotropy:anisotropy lodBias:lodBias]))
	{
#if OOTEXTURE_RELOADABLE
		_path = [path retain];
#endif
	}
	
	return self;
}


- (void)dealloc
{
#ifndef NDEBUG
	OOLog(_trace ? @"texture.allocTrace.dealloc" : @"texture.dealloc", @"Deallocating and uncaching texture %p", self);
#endif
	
#if OOTEXTURE_RELOADABLE
	DESTROY(_path);
#endif
	
	if (_loaded)
	{
		if (_textureName != 0)
		{
			OO_ENTER_OPENGL();
			OOGL(glDeleteTextures(1, &_textureName));
			_textureName = 0;
		}
		free(_bytes);
		_bytes = NULL;
	}
	
#ifndef OOTEXTURE_NO_CACHE
	[self removeFromCaches];
	[_key autorelease];
	_key = nil;
#endif
	
	DESTROY(_loader);
	
#ifndef NDEBUG
	DESTROY(_name);
#endif
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	NSString				*stateDesc = nil;
	
	if (_loaded)
	{
		if (_valid)
		{
			stateDesc = [NSString stringWithFormat:@"%u x %u", _width, _height];
		}
		else
		{
			stateDesc = @"LOAD ERROR";
		}
	}
	else
	{
		stateDesc = @"loading";
	}
	
	return [NSString stringWithFormat:@"%@, %@", _key, stateDesc];
}


- (NSString *) shortDescriptionComponents
{
	return _key;
}


#ifndef NDEBUG
- (NSString *) name
{
	if (_name != nil)  return _name;
	
#if OOTEXTURE_RELOADABLE
	NSString *name = [_path lastPathComponent];
#else
	NSString *name = [[[[self cacheKey] componentsSeparatedByString:@":"] objectAtIndex:0] lastPathComponent];
#endif
	
	NSString *channelSuffix = nil;
	switch (_options & kOOTextureExtractChannelMask)
	{
		case kOOTextureExtractChannelR:
			channelSuffix = @":r";
			break;
			
		case kOOTextureExtractChannelG:
			channelSuffix = @":g";
			break;
			
		case kOOTextureExtractChannelB:
			channelSuffix = @":b";
			break;
			
		case kOOTextureExtractChannelA:
			channelSuffix = @":a";
			break;
	}
	
	if (channelSuffix != nil)  name = [name stringByAppendingString:channelSuffix];
	
	return name;
}
#endif


- (void)apply
{
	OO_ENTER_OPENGL();
	
	if (EXPECT_NOT(!_loaded))  [self setUpTexture];
	else if (EXPECT_NOT(!_uploaded))  [self uploadTexture];
	else  OOGL(glBindTexture([self glTextureTarget], _textureName));
	
#if GL_EXT_texture_lod_bias
	if (gOOTextureInfo.textureLODBiasAvailable)  OOGL(glTexEnvf(GL_TEXTURE_FILTER_CONTROL_EXT, GL_TEXTURE_LOD_BIAS_EXT, _lodBias));
#endif
}


- (void)ensureFinishedLoading
{
	if (!_loaded)  [self setUpTexture];
}


- (BOOL) isFinishedLoading
{
	return _loaded || [_loader isReady];
}


- (NSString *) cacheKey
{
	return _key;
}


- (NSSize)dimensions
{
	[self ensureFinishedLoading];
	
	return NSMakeSize(_width, _height);
}


- (NSSize) originalDimensions
{
	[self ensureFinishedLoading];
	
	return NSMakeSize(_originalWidth, _originalHeight);
}


- (BOOL) isMipMapped
{
	[self ensureFinishedLoading];
	
	return _mipLevels != 0;
}


- (struct OOPixMap) copyPixMapRepresentation
{
	[self ensureFinishedLoading];
	
	OOPixMap				px = kOONullPixMap;
	
	if (_bytes != NULL)
	{
		// If possible, just copy our existing buffer.
		px = OOMakePixMap(_bytes, _width, _height, _format, 0, 0);
		px = OODuplicatePixMap(px, 0);
	}
#if OOTEXTURE_RELOADABLE
	else
	{
		// Otherwise, read it back from OpenGL.
		OO_ENTER_OPENGL();
		
		GLenum format, internalFormat, type;
		if (!DecodeFormat(_format, _options, &format, &internalFormat, &type))
		{
			return kOONullPixMap;
		}
		
		if (![self isCubeMap])
		{
			
			px = OOAllocatePixMap(_width, _height, _format, 0, 0);
			if (!OOIsValidPixMap(px))  return kOONullPixMap;
			
			glGetTexImage(GL_TEXTURE_2D, 0, format, type, px.pixels);
		}
#if OO_TEXTURE_CUBE_MAP
		else
		{
			px = OOAllocatePixMap(_width, _width * 6, _format, 0, 0);
			if (!OOIsValidPixMap(px))  return kOONullPixMap;
			uint8_t *pixels = px.pixels;
			
			unsigned i;
			for (i = 0; i < 6; i++)
			{
				glGetTexImage(GL_TEXTURE_CUBE_MAP_POSITIVE_X + i, 0, format, type, pixels);
				pixels += OOPixMapBytesPerPixelForFormat(_format) * _width * _width;
			}
		}
#endif
	}
#endif
	
	return px;
}


- (BOOL) isRectangleTexture
{
#if GL_EXT_texture_rectangle
	return _isRectTexture;
#else
	return NO;
#endif
}


- (BOOL) isCubeMap
{
#if OO_TEXTURE_CUBE_MAP
	return _isCubeMap;
#else
	return NO;
#endif
}


- (NSSize)texCoordsScale
{
#if GL_EXT_texture_rectangle
	if (_loaded)
	{
		if (!_isRectTexture)
		{
			return NSMakeSize(1.0f, 1.0f);
		}
		else
		{
			return NSMakeSize(_width, _height);
		}
	}
	else
	{
		// Not loaded
		if (!_options & kOOTextureAllowRectTexture)
		{
			return NSMakeSize(1.0f, 1.0f);
		}
		else
		{
			// Finishing may clear the rectangle texture flag (if the texture turns out to be POT)
			[self ensureFinishedLoading];
			return [self texCoordsScale];
		}
	}
#else
	return NSMakeSize(1.0f, 1.0f);
#endif
}


- (GLint)glTextureName
{
	[self ensureFinishedLoading];
	
	return _textureName;
}

@end


@implementation OOConcreteTexture (Private)

- (void)setUpTexture
{
	OOPixMap		pm;
	
	// This will block until loading is completed, if necessary.
	if ([_loader getResult:&pm format:&_format originalWidth:&_originalWidth originalHeight:&_originalHeight])
	{
		_bytes = pm.pixels;
		_width = pm.width;
		_height = pm.height;
		
#if OO_TEXTURE_CUBE_MAP
		if (_options & kOOTextureAllowCubeMap && _height == _width * 6 && gOOTextureInfo.cubeMapAvailable)
		{
			_isCubeMap = YES;
		}
#endif
		
#if !defined(NDEBUG) && OOTEXTURE_RELOADABLE
		if (_trace)
		{
			static unsigned dumpID = 0;
			NSString *name = [NSString stringWithFormat:@"tex dump %u \"%@\"", ++dumpID,[self name]];
			OOLog(@"texture.trace.dump", @"Dumped traced texture %@ to \'%@.png\'", self, name);
			OODumpPixMap(pm, name);
		}
#endif
		
		[self uploadTexture];
	}
	else
	{
		_textureName = 0;
		_valid = NO;
		_uploaded = YES;
	}
	
	_loaded = YES;
	
	DESTROY(_loader);
}


- (void) uploadTexture
{
	GLint					filter;
	BOOL					mipMap = NO;
	
	OO_ENTER_OPENGL();
	
	if (!_uploaded)
	{
		GLenum texTarget = [self glTextureTarget];
		
		OOGL(glGenTextures(1, &_textureName));
		OOGL(glBindTexture(texTarget, _textureName));
		
		// Select wrap mode
		GLint clampMode = gOOTextureInfo.clampToEdgeAvailable ? GL_CLAMP_TO_EDGE : GL_CLAMP;
		GLint wrapS = (_options & kOOTextureRepeatS) ? GL_REPEAT : clampMode;
		GLint wrapT = (_options & kOOTextureRepeatT) ? GL_REPEAT : clampMode;
		
#if OO_TEXTURE_CUBE_MAP
		if (texTarget == GL_TEXTURE_CUBE_MAP)
		{
			wrapS = wrapT = clampMode;
			OOGL(glTexParameteri(texTarget, GL_TEXTURE_WRAP_R, clampMode));
		}
#endif
		
		OOGL(glTexParameteri(texTarget, GL_TEXTURE_WRAP_S, wrapS));
		OOGL(glTexParameteri(texTarget, GL_TEXTURE_WRAP_T, wrapT));
		
		// Select min filter
		filter = _options & kOOTextureMinFilterMask;
		if (filter == kOOTextureMinFilterNearest)  filter = GL_NEAREST;
		else if (filter == kOOTextureMinFilterMipMap)
		{
			mipMap = YES;
			filter = GL_LINEAR_MIPMAP_LINEAR;
		}
		else  filter = GL_LINEAR;
		OOGL(glTexParameteri(texTarget, GL_TEXTURE_MIN_FILTER, filter));
		
#if GL_EXT_texture_filter_anisotropic
		if (gOOTextureInfo.anisotropyAvailable && mipMap && 1.0 < _anisotropy)
		{
			OOGL(glTexParameterf(texTarget, GL_TEXTURE_MAX_ANISOTROPY_EXT, _anisotropy));
		}
#endif
		
		// Select mag filter
		filter = _options & kOOTextureMagFilterMask;
		if (filter == kOOTextureMagFilterNearest)  filter = GL_NEAREST;
		else  filter = GL_LINEAR;
		OOGL(glTexParameteri(texTarget, GL_TEXTURE_MAG_FILTER, filter));
		
	//	if (gOOTextureInfo.clientStorageAvailable)  EnableClientStorage();
		
		if (texTarget == GL_TEXTURE_2D)
		{
			[self uploadTextureDataWithMipMap:mipMap format:_format];
			OOLog(@"texture.upload", @"Uploaded texture %u (%ux%u pixels, %@)", _textureName, _width, _height, _key);
		}
#if OO_TEXTURE_CUBE_MAP
		else if (texTarget == GL_TEXTURE_CUBE_MAP)
		{
			[self uploadTextureCubeMapDataWithMipMap:mipMap format:_format];
			OOLog(@"texture.upload", @"Uploaded cube map texture %u (%ux%ux6 pixels, %@)", _textureName, _width, _width, _key);
		}
#endif
		else
		{
			[NSException raise:NSInternalInconsistencyException format:@"Unhandled texture target 0x%X.", texTarget];
		}
		
		_valid = YES;
		_uploaded = YES;
		
#if OOTEXTURE_RELOADABLE
		if ([self isReloadable])
		{
			free(_bytes);
			_bytes = NULL;
		}
#endif
	}
}


- (void)uploadTextureDataWithMipMap:(BOOL)mipMap format:(OOTextureDataFormat)format
{
	GLenum					glFormat = 0, internalFormat = 0, type = 0;
	unsigned				w = _width,
							h = _height,
							level = 0;
	char					*bytes = _bytes;
	uint8_t					components = OOTextureComponentsForFormat(format);
	
	OO_ENTER_OPENGL();
	
	if (!DecodeFormat(format, _options, &glFormat, &internalFormat, &type))  return;
	
	while (0 < w && 0 < h)
	{
		OOGL(glTexImage2D(GL_TEXTURE_2D, level++, internalFormat, w, h, 0, glFormat, type, bytes));
		if (!mipMap)  return;
		bytes += w * components * h;
		w >>= 1;
		h >>= 1;
	}
	
	// Note: we only reach here if (mipMap).
	_mipLevels = level - 1;
	OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, _mipLevels));
}


#if OO_TEXTURE_CUBE_MAP
- (void) uploadTextureCubeMapDataWithMipMap:(BOOL)mipMap format:(OOTextureDataFormat)format
{
	OO_ENTER_OPENGL();
	
	GLenum glFormat = 0, internalFormat = 0, type = 0;
	if (!DecodeFormat(format, _options, &glFormat, &internalFormat, &type))  return;
	uint8_t components = OOTextureComponentsForFormat(format);
	
	// Calculate stride between cube map sides.
	size_t sideSize = _width * _width * components;
	if (mipMap)
	{
		sideSize = sideSize * 4 / 3;
		sideSize = (sideSize + 15) & ~15;
	}
	
	unsigned side;
	for (side = 0; side < 6; side++)
	{
		char *bytes = _bytes;
		bytes += side * sideSize;
		
		unsigned w = _width, level = 0;
		
		while (0 < w)
		{
			OOGL(glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + side, level++, internalFormat, w, w, 0, glFormat, type, bytes));
			if (!mipMap)  break;
			bytes += w * w * components;
			w >>= 1;
		}
	}
}
#endif


- (GLenum) glTextureTarget
{
	GLenum texTarget = GL_TEXTURE_2D;
#if OO_TEXTURE_CUBE_MAP
	if (_isCubeMap)
	{
		texTarget = GL_TEXTURE_CUBE_MAP;
	}
#endif
	return texTarget;
}


- (void) forceRebind
{
	if (_loaded && _uploaded && _valid)
	{
		OO_ENTER_OPENGL();
		
		_uploaded = NO;
		OOGL(glDeleteTextures(1, &_textureName));
		_textureName = 0;
		
#if OOTEXTURE_RELOADABLE
		if ([self isReloadable])
		{
			OOLog(@"texture.reload", @"Reloading texture %@", self);
			
			free(_bytes);
			_bytes = NULL;
			_loaded = NO;
			_uploaded = NO;
			_valid = NO;
			
			_loader = [[OOTextureLoader loaderWithPath:_path options:_options] retain];
		}
#endif
	}
}


#if OOTEXTURE_RELOADABLE

- (BOOL) isReloadable
{
	return _path != nil;
}

#endif

@end


static BOOL DecodeFormat(OOTextureDataFormat format, uint32_t options, GLenum *outFormat, GLenum *outInternalFormat, GLenum *outType)
{
	NSCParameterAssert(outFormat != NULL && outInternalFormat != NULL && outType != NULL);
	
	switch (format)
	{
		case kOOTextureDataRGBA:
			*outFormat = GL_RGBA;
			*outInternalFormat = GL_RGBA;
			*outType = RGBA_IMAGE_TYPE;
			return YES;
			
		case kOOTextureDataGrayscale:
			if (options & kOOTextureAlphaMask)
			{
				*outFormat = GL_ALPHA;
				*outInternalFormat = GL_ALPHA8;
			}
			else
			{
				*outFormat = GL_LUMINANCE;
				*outInternalFormat = GL_LUMINANCE8;
			}
			*outType = GL_UNSIGNED_BYTE;
			return YES;
			
		case kOOTextureDataGrayscaleAlpha:
			*outFormat = GL_LUMINANCE_ALPHA;
			*outInternalFormat = GL_LUMINANCE8_ALPHA8;
			*outType = GL_UNSIGNED_BYTE;
			return YES;
			
		default:
			OOLog(kOOLogParameterError, @"Unexpected texture format %u.", format);
			return NO;
	}
}
