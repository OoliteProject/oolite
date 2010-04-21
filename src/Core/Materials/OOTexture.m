/*
	
	OOTexture.m
	
	Oolite
	Copyright (C) 2004-2009 Giles C Williams and contributors
	
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
	
	Copyright (C) 2007-2009 Jens Ayton
	
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

#import "OOTexture.h"
#import "OONullTexture.h"
#import "OOTextureLoader.h"
#import "OOTextureGenerator.h"
#import "OOCollectionExtractors.h"
#import "Universe.h"
#import "ResourceManager.h"
#import "OOOpenGLExtensionManager.h"
#import "OOMacroOpenGL.h"
#import "OOCPUInfo.h"
#import "OOCache.h"
#import "OOPixMap.h"


/*	Texture caching:
	two parallel caching mechanisms are used. sInUseTextures tracks all live
	texture objects, without retaining them (using NSValues to refer to the
	objects). sRecentTextures tracks up to kRecentTexturesCount textures which
	have been used recently, and retains them.
	
	This means that the number of live texture objects will never fall below
	80% of kRecentTexturesCount (80% comes from the behaviour of OOCache), but
	old textures will eventually be released. If the number of active textures
	exceeds kRecentTexturesCount, all of them will be reusable through
	sInUseTextures, but only a most-recently-fetched subset will be kept
	around by the cache when the number drops.
	
	Note that any texture in sRecentTextures will also be in sInUseTextures,
	but not necessarily vice versa.
*/
enum
{
	kRecentTexturesCount		= 50
};

static NSMutableDictionary	*sInUseTextures = nil;
static OOCache				*sRecentTextures = nil;


static BOOL		sCheckedExtensions = NO;


#if OOLITE_BIG_ENDIAN
#define RGBA_IMAGE_TYPE GL_UNSIGNED_INT_8_8_8_8_REV
#elif OOLITE_LITTLE_ENDIAN
#define RGBA_IMAGE_TYPE GL_UNSIGNED_BYTE
#else
#error Neither OOLITE_BIG_ENDIAN nor OOLITE_LITTLE_ENDIAN is defined as nonzero!
#endif


// Anisotropic filtering
#if GL_EXT_texture_filter_anisotropic
static BOOL		sAnisotropyAvailable;
static float	sAnisotropyScale;	// Scale of anisotropy values
#else
#define sAnisotropyAvailable		(NO)
#define sAnisotropyScale			(0)
#warning GL_EXT_texture_filter_anisotropic unavailble -- are you using an up-to-date glext.h?
#endif


// CLAMP_TO_EDGE (OK, requiring OpenGL 1.2 wouln't be _that_ big a deal...)
#if !defined(GL_CLAMP_TO_EDGE) && GL_SGIS_texture_edge_clamp
#define GL_CLAMP_TO_EDGE GL_CLAMP_TO_EDGE_SGIS
#endif

#ifdef GL_CLAMP_TO_EDGE
static BOOL		sClampToEdgeAvailable;
#else
#warning GL_CLAMP_TO_EDGE (OpenGL 1.2) and GL_SGIS_texture_edge_clamp are unavailable -- are you using an up-to-date gl.h?
#define sClampToEdgeAvailable	(NO)
#define GL_CLAMP_TO_EDGE		GL_CLAMP
#endif


// Client storage: reduce copying by requiring the app to keep data around
#if GL_APPLE_client_storage

#define OO_GL_CLIENT_STORAGE	(1)
static inline void EnableClientStorage(void)
{
	OO_ENTER_OPENGL();
	OOGL(glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE));
}
// #elif in any equivalents on other platforms here
#else
#define OO_GL_CLIENT_STORAGE	(0)
#define EnableClientStorage()	do {} while (0)
#endif

#if OO_GL_CLIENT_STORAGE
static BOOL		sClientStorageAvialable;
#else
#define sClientStorageAvialable		(NO)
#endif


#if GL_EXT_texture_lod_bias
static BOOL		sTextureLODBiasAvailable;
#else
#define sTextureLODBiasAvailable	(NO)
#endif


#if GL_EXT_texture_rectangle
static BOOL		sRectangleTextureAvailable;
#else
#define sRectangleTextureAvailable	(NO)
#endif


#if GL_ARB_texture_cube_map
static BOOL		sCubeMapAvailable;
#else
#define sCubeMapAvailable			(NO)
#warning GL_ARB_texture_cube_map not defined - cube maps not supported.
#endif


@interface OOTexture (OOPrivate)

- (id) initWithLoader:(OOTextureLoader *)loader
				  key:(NSString *)key
			  options:(uint32_t)options
		   anisotropy:(GLfloat)anisotropy
			  lodBias:(GLfloat)lodBias;

- (id)initWithPath:(NSString *)path
			   key:(NSString *)key
		   options:(uint32_t)options
		anisotropy:(float)anisotropy
		   lodBias:(GLfloat)lodBias;

- (void)setUpTexture;
- (void)uploadTexture;
- (void)uploadTextureDataWithMipMap:(BOOL)mipMap format:(OOTextureDataFormat)format;
#if GL_ARB_texture_cube_map
- (void) uploadTextureCubeMapDataWithMipMap:(BOOL)mipMap format:(OOTextureDataFormat)format;
#endif

- (GLenum) glTextureTarget;

- (void) addToCaches;
+ (OOTexture *) existingTextureForKey:(NSString *)key;

- (void)forceRebind;

+ (void)checkExtensions;

#ifndef NDEBUG
- (id) retainInContext:(NSString *)context;
- (void) releaseInContext:(NSString *)context;
- (id) autoreleaseInContext:(NSString *)context;
#endif

@end


#ifndef NDEBUG
static NSString *sGlobalTraceContext = nil;

#define SET_TRACE_CONTEXT(str) do { sGlobalTraceContext = (str); } while (0)
#else
#define SET_TRACE_CONTEXT(str) do { } while (0)
#endif
#define CLEAR_TRACE_CONTEXT() SET_TRACE_CONTEXT(nil)


@implementation OOTexture

+ (id)textureWithName:(NSString *)name
			 inFolder:(NSString*)directory
			  options:(uint32_t)options
		   anisotropy:(GLfloat)anisotropy
			  lodBias:(GLfloat)lodBias
{
	NSString				*key = nil;
	OOTexture				*result = nil;
	NSString				*path = nil;
	BOOL					noFNF;
	
	if (EXPECT_NOT(name == nil))  return nil;
	if (EXPECT_NOT(!sCheckedExtensions))  [self checkExtensions];
	
	// Set default flags if needed
	if ((options & kOOTextureMinFilterMask) == kOOTextureMinFilterDefault)
	{
		if ([UNIVERSE reducedDetail])
		{
			options |= kOOTextureMinFilterLinear;
		}
		else
		{
			options |= kOOTextureMinFilterMipMap;
		}
	}
	
	if (options & kOOTextureAllowRectTexture)
	{
		// Apply rectangle texture restrictions (regardless of whether rectangle textures are available, for consistency)
		options &= kOOTextureFlagsAllowedForRectangleTexture;
		if ((options & kOOTextureMinFilterMask) == kOOTextureMinFilterMipMap)
		{
			options = (kOOTextureMinFilterMask & ~kOOTextureMinFilterMask) | kOOTextureMinFilterLinear;
		}
		
#if GL_EXT_texture_rectangle
		if (!sRectangleTextureAvailable)
		{
			options &= ~kOOTextureAllowRectTexture;
		}
#else
		options &= ~kOOTextureAllowRectTexture;
#endif
	}
	
	if (options & kOOTextureAllowCubeMap)
	{
		// Apply cube map restrictions (regardless of whether rectangle textures are available, for consistency)
		options &= kOOTextureFlagsAllowedForCubeMap;
	}
	
	options &= kOOTextureDefinedFlags;
	
	if (!sAnisotropyAvailable || (options & kOOTextureMinFilterMask) != kOOTextureMinFilterMipMap)
	{
		anisotropy = 0.0f;
	}
	if (!sTextureLODBiasAvailable || (options & kOOTextureMinFilterMask) != kOOTextureMinFilterMipMap)
	{
		lodBias = 0.0f;
	}
	
	noFNF = (options & kOOTextureNoFNFMessage) != 0;
	options &= ~kOOTextureNoFNFMessage;
	
	// Look for existing texture
	key = [NSString stringWithFormat:@"%@%@%@:0x%.4X/%g/%g", directory ? directory : (NSString *)@"", directory ? @"/" : @"", name, options, anisotropy, lodBias];
	result = [OOTexture existingTextureForKey:key];
	if (result == nil)
	{
		path = [ResourceManager pathForFileNamed:name inFolder:directory];
		if (path == nil)
		{
			if (!noFNF)  OOLog(kOOLogFileNotFound, @"----- WARNING: Could not find texture file \"%@\".", name);
			return nil;
		}
		
		// No existing texture, load texture.
		result = [[[OOTexture alloc] initWithPath:path key:key options:options anisotropy:anisotropy lodBias:lodBias] autorelease];
	}
	
	
	return result;
}


+ (id)textureWithName:(NSString *)name
			 inFolder:(NSString*)directory
{
	return [self textureWithName:name
						inFolder:directory
						 options:kOOTextureDefaultOptions
					  anisotropy:kOOTextureDefaultAnisotropy
						 lodBias:kOOTextureDefaultLODBias];
}


+ (id)textureWithConfiguration:(id)configuration
{
	NSString				*name = nil;
	NSString				*filterString = nil;
	uint32_t				options = 0;
	GLfloat					anisotropy;
	GLfloat					lodBias;
	
	if ([configuration isKindOfClass:[NSString class]])
	{
		name = configuration;
		if ([name isEqual:@""])  return nil;
		options = kOOTextureDefaultOptions;
		anisotropy = kOOTextureDefaultAnisotropy;
		lodBias = kOOTextureDefaultLODBias;
	}
	else if ([configuration isKindOfClass:[NSDictionary class]])
	{
		name = [(NSDictionary *)configuration oo_stringForKey:@"name"];
		if (name == nil)
		{
			OOLog(@"texture.load.noName", @"Invalid texture configuration dictionary (must specify name):\n%@", configuration);
			return nil;
		}
		
		filterString = [configuration oo_stringForKey:@"min_filter" defaultValue:@"default"];
		if ([filterString isEqualToString:@"nearest"])  options |= kOOTextureMinFilterNearest;
		else if ([filterString isEqualToString:@"linear"])  options |= kOOTextureMinFilterLinear;
		else if ([filterString isEqualToString:@"mipmap"])  options |= kOOTextureMinFilterMipMap;
		else  options |= kOOTextureMinFilterDefault;	// Covers "default"
		
		filterString = [configuration oo_stringForKey:@"mag_filter" defaultValue:@"default"];
		if ([filterString isEqualToString:@"nearest"])  options |= kOOTextureMagFilterNearest;
		else  options |= kOOTextureMagFilterLinear;	// Covers "default" and "linear"
		
		if ([configuration oo_boolForKey:@"no_shrink" defaultValue:NO])  options |= kOOTextureNoShrink;
		if ([configuration oo_boolForKey:@"repeat_s" defaultValue:NO])  options |= kOOTextureRepeatS;
		if ([configuration oo_boolForKey:@"repeat_t" defaultValue:NO])  options |= kOOTextureRepeatT;
		if ([configuration oo_boolForKey:@"cube_map" defaultValue:NO])  options |= kOOTextureAllowCubeMap;
		anisotropy = [configuration oo_floatForKey:@"anisotropy" defaultValue:kOOTextureDefaultAnisotropy];
		lodBias = [configuration oo_floatForKey:@"texture_LOD_bias" defaultValue:kOOTextureDefaultLODBias];
		
		NSString *extractChannel = [configuration oo_stringForKey:@"extract_channel"];
		if (extractChannel != nil)
		{
			if ([extractChannel isEqualToString:@"r"])  options |= kOOTextureExtractChannelR;
			else if ([extractChannel isEqualToString:@"g"])  options |= kOOTextureExtractChannelG;
			else if ([extractChannel isEqualToString:@"b"])  options |= kOOTextureExtractChannelB;
			else if ([extractChannel isEqualToString:@"a"])  options |= kOOTextureExtractChannelA;
			else
			{
				OOLogWARN(@"texture.load.extractChannel.invalid", @"Unknown value \"%@\" for extract_channel (should be \"r\", \"g\", \"b\" or \"a\").", extractChannel);
			}
		}
	}
	else
	{
		// Bad type
		if (configuration != nil)  OOLog(kOOLogParameterError, @"%s: expected string or dictionary, got %@.", __PRETTY_FUNCTION__, [configuration class]);
		return nil;
	}
	
	return [self textureWithName:name inFolder:@"Textures" options:options anisotropy:anisotropy lodBias:lodBias];
}


+ (id) nullTexture
{
	return [OONullTexture sharedNullTexture];
}


+ (id) textureWithGenerator:(OOTextureGenerator *)generator
{
	if (generator == nil)  return nil;
	
#ifndef OOTEXTURE_NO_CACHE
	OOTexture *existing = [OOTexture existingTextureForKey:[generator cacheKey]];
	if (existing != nil)  return [[existing retain] autorelease];
#endif
	
	if (![generator enqueue])
	{
		OOLogERR(@"texture.generator.queue.failed", @"Failed to queue generator %@", generator);
		return nil;
	}
	OOLog(@"texture.generator.queue", @"Queued texture generator %@", generator);
	
	OOTexture *result = [[[self alloc] initWithLoader:generator
												  key:[generator cacheKey]
											  options:[generator textureOptions]
										   anisotropy:[generator anisotropy]
											  lodBias:[generator lodBias]] autorelease];
#ifndef NDEBUG
	// [result setTrace:YES];
#endif
	
	return result;
}


- (void)dealloc
{
#ifndef NDEBUG
	OOLog(_trace ? @"texture.allocTrace.dealloc" : @"texture.dealloc", @"Deallocating and uncaching texture %p", self);
#endif
	
	if (_key != nil)
	{
		[sInUseTextures removeObjectForKey:_key];
		NSAssert([sRecentTextures objectForKey:_key] != self, @"Texture retain count error."); //miscount in autorelease
		// The following line is needed in order to avoid crashes when there's a 'texture retain count error'. Please do not delete. -- Kaks 20091221
		[sRecentTextures removeObjectForKey:_key]; // make sure there's no reference left inside sRecentTexture ( was a show stopper for 1.73)
		DESTROY(_key);
	}
	
	if (_loaded)
	{
		if (_textureName != 0)  GLRecycleTextureName(_textureName, _mipLevels);
		free(_bytes);
	}
	
	[_loader release];
	
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
	
	return [NSString stringWithFormat:@"<{%@, %@}", _key, stateDesc];
}


- (NSString *) shortDescriptionComponents
{
	return _key;
}


- (void)apply
{
	OO_ENTER_OPENGL();
	
	if (EXPECT_NOT(!_loaded))  [self setUpTexture];
	else if (EXPECT_NOT(!_uploaded))  [self uploadTexture];
	else  OOGL(glBindTexture([self glTextureTarget], _textureName));
	
#if GL_EXT_texture_lod_bias
	if (sTextureLODBiasAvailable)  OOGL(glTexEnvf(GL_TEXTURE_FILTER_CONTROL_EXT, GL_TEXTURE_LOD_BIAS_EXT, _lodBias));
#endif
}


+ (void)applyNone
{
	OO_ENTER_OPENGL();
	OOGL(glBindTexture(GL_TEXTURE_2D, 0));
#if GL_ARB_texture_cube_map
	OOGL(glBindTexture(GL_TEXTURE_CUBE_MAP_ARB, 0));
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
	return [[_key retain] autorelease];
}


- (NSSize)dimensions
{
	[self ensureFinishedLoading];
	
	return NSMakeSize(_width, _height);
}


- (struct OOPixMap) copyPixMapRepresentation
{
	OOPixMap px = OOMakePixMap(_bytes, _width, _height, OOTextureComponentsForFormat(_format), 0, 0);
	return OODuplicatePixMap(px, 0);
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
#if GL_ARB_texture_cube_map
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


+ (void)clearCache
{
	SET_TRACE_CONTEXT(@"clearing in-use textures cache");
	[sInUseTextures autorelease];
	sInUseTextures = nil;
	
	SET_TRACE_CONTEXT(@"clearing recent textures cache");
	[sRecentTextures autorelease];
	sRecentTextures = nil;
	CLEAR_TRACE_CONTEXT();
}


+ (void)rebindAllTextures
{
	NSEnumerator			*textureEnum = nil;
	id						texture = nil;
	
	for (textureEnum = [sInUseTextures objectEnumerator]; (texture = [[textureEnum nextObject] pointerValue]); )
	{
		[texture forceRebind];
	}
}


#ifndef NDEBUG
- (void) setTrace:(BOOL)trace
{
	if (trace && !_trace)
	{
		OOLog(@"texture.allocTrace.begin", @"Started tracing texture %p with retain count %u.", self, [self retainCount]);
	}
	_trace = trace;
}
#endif

@end


@implementation OOTexture (OOPrivate)

- (id) initWithLoader:(OOTextureLoader *)loader
				  key:(NSString *)key
			  options:(uint32_t)options
		   anisotropy:(GLfloat)anisotropy
			  lodBias:(GLfloat)lodBias
{
#ifndef OOTEXTURE_NO_CACHE
	if (key != nil)
	{
		OOTexture *existing = [OOTexture existingTextureForKey:key];
		if (existing != nil)  return [[existing retain] autorelease];
	}
#endif
	
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
	_anisotropy = OOClamp_0_1_f(anisotropy) * sAnisotropyScale;
#endif
#if GL_EXT_texture_lod_bias
	_lodBias = lodBias;
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
	
	return [self initWithLoader:loader key:key options:options anisotropy:anisotropy lodBias:lodBias];
}


- (void)setUpTexture
{
	// This will block until loading is completed, if necessary.
	if ([_loader getResult:&_bytes format:&_format width:&_width height:&_height])
	{
#if GL_ARB_texture_cube_map
		if (_options & kOOTextureAllowCubeMap && _height == _width * 6)
		{
			_isCubeMap = YES;
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
	
	[_loader release];
	_loader = nil;
}


- (void) uploadTexture
{
	GLint					clampMode;
	GLint					filter;
	BOOL					mipMap = NO;
	
	OO_ENTER_OPENGL();
	
	if (!_uploaded)
	{
		GLenum texTarget = [self glTextureTarget];
		
		_textureName = GLAllocateTextureName();
		OOGL(glBindTexture(texTarget, _textureName));
		
		// Select wrap mode
		clampMode = sClampToEdgeAvailable ? GL_CLAMP_TO_EDGE : GL_CLAMP;
		
		OOGL(glTexParameteri(texTarget, GL_TEXTURE_WRAP_S, (_options & kOOTextureRepeatS) ? GL_REPEAT : clampMode));
		OOGL(glTexParameteri(texTarget, GL_TEXTURE_WRAP_T, (_options & kOOTextureRepeatT) ? GL_REPEAT : clampMode));
#if GL_ARB_texture_cube_map
		if (texTarget == GL_TEXTURE_CUBE_MAP_ARB)
		{
			// Repeat flags should have been filtered out earlier.
			NSAssert(!(_options & (kOOTextureRepeatS | kOOTextureRepeatT)), @"Wrapping does not make sense for cube map textures.");
			
			OOGL(glTexParameteri(texTarget, GL_TEXTURE_WRAP_R, clampMode));
		}
#endif
		
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
		if (sAnisotropyAvailable && mipMap && 1.0 < _anisotropy)
		{
			OOGL(glTexParameterf(texTarget, GL_TEXTURE_MAX_ANISOTROPY_EXT, _anisotropy));
		}
#endif
		
		// Select mag filter
		filter = _options & kOOTextureMagFilterMask;
		if (filter == kOOTextureMagFilterNearest)  filter = GL_NEAREST;
		else  filter = GL_LINEAR;
		OOGL(glTexParameteri(texTarget, GL_TEXTURE_MAG_FILTER, filter));
		
	//	if (sClientStorageAvialable)  EnableClientStorage();
		
		if (texTarget == GL_TEXTURE_2D)
		{
			[self uploadTextureDataWithMipMap:mipMap format:_format];
			OOLog(@"texture.upload", @"Uploaded texture %u (%ux%u pixels, %@)", _textureName, _width, _height, _key);
		}
#if GL_ARB_texture_cube_map
		else if (texTarget == GL_TEXTURE_CUBE_MAP_ARB)
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
	}
}


static inline BOOL DecodeFormat(OOTextureDataFormat format, uint32_t options, GLint *outFormat, GLint *outInternalFormat, GLint *outType)
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


- (void)uploadTextureDataWithMipMap:(BOOL)mipMap format:(OOTextureDataFormat)format
{
	GLint					glFormat = 0, internalFormat = 0, type = 0;
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
	
	_mipLevels = level - 1;
	
	// FIXME: GL_TEXTURE_MAX_LEVEL requires OpenGL 1.2. This should be fixed by generating all mip-maps for non-square textures so we don't need to use it.
	OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, _mipLevels));
}


#if GL_ARB_texture_cube_map
- (void) uploadTextureCubeMapDataWithMipMap:(BOOL)mipMap format:(OOTextureDataFormat)format
{
	OO_ENTER_OPENGL();
	
	GLint glFormat = 0, internalFormat = 0, type = 0;
	if (!DecodeFormat(format, _options, &glFormat, &internalFormat, &type))  return;
	uint8_t components = OOTextureComponentsForFormat(format);
	
	// Calculate stride between cube map sides.
	size_t sideSize = _width * _width * components;
	if (mipMap)
	{
		sideSize = sideSize * 4 / 3;
		sideSize = (sideSize + 15) & ~15;
	}
	
	const GLenum cubeSides[6] =
	{
		GL_TEXTURE_CUBE_MAP_POSITIVE_X_ARB,
		GL_TEXTURE_CUBE_MAP_NEGATIVE_X_ARB,
		GL_TEXTURE_CUBE_MAP_POSITIVE_Y_ARB,
		GL_TEXTURE_CUBE_MAP_NEGATIVE_Y_ARB,
		GL_TEXTURE_CUBE_MAP_POSITIVE_Z_ARB,
		GL_TEXTURE_CUBE_MAP_NEGATIVE_Z_ARB
	};
	
	unsigned side;
	for (side = 0; side < 6; side++)
	{
		char *bytes = _bytes;
		bytes += side * sideSize;
		
		unsigned w = _width, level = 0;
		
		while (0 < w)
		{
			OOGL(glTexImage2D(cubeSides[side], level++, internalFormat, w, w, 0, glFormat, type, bytes));
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
#if GL_ARB_texture_cube_map
	if (_isCubeMap)
	{
		texTarget = GL_TEXTURE_CUBE_MAP_ARB;
	}
#endif
	return texTarget;
}


- (void)forceRebind
{
	if (_loaded && _uploaded && _valid)
	{
		_uploaded = NO;
		GLRecycleTextureName(_textureName, _mipLevels);
		_textureName = 0;
	}
}


- (void) addToCaches
{
#ifndef OOTEXTURE_NO_CACHE
	// Add self to in-use textures cache, wrapped in an NSValue so the texture isn't retained by the cache.
	if (EXPECT_NOT(sInUseTextures == nil))  sInUseTextures = [[NSMutableDictionary alloc] init];
	
	SET_TRACE_CONTEXT(@"in-use textures cache - SHOULD NOT RETAIN");
	[sInUseTextures setObject:[NSValue valueWithPointer:self] forKey:_key];
	CLEAR_TRACE_CONTEXT();
	
	// Add self to recent textures cache.
	if (EXPECT_NOT(sRecentTextures == nil))
	{
		sRecentTextures = [[OOCache alloc] init];
		[sRecentTextures setName:@"recent textures"];
		[sRecentTextures setAutoPrune:YES];
		[sRecentTextures setPruneThreshold:kRecentTexturesCount];
	}
	
	SET_TRACE_CONTEXT(@"adding to recent textures cache");
	[sRecentTextures setObject:self forKey:_key];
	CLEAR_TRACE_CONTEXT();
#endif
}


+ (OOTexture *) existingTextureForKey:(NSString *)key
{
#ifndef OOTEXTURE_NO_CACHE
	if (key != nil)
	{
		return (OOTexture *)[[sInUseTextures objectForKey:key] pointerValue];
	}
	return nil;
#else
	return nil;
#endif
}


+ (void)checkExtensions
{
	OO_ENTER_OPENGL();
	
	sCheckedExtensions = YES;
	
	OOOpenGLExtensionManager	*extMgr = [OOOpenGLExtensionManager sharedManager];
	
#if GL_EXT_texture_filter_anisotropic
	sAnisotropyAvailable = [extMgr haveExtension:@"GL_EXT_texture_filter_anisotropic"];
	OOGL(glGetFloatv(GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT, &sAnisotropyScale));
	sAnisotropyScale *= OOClamp_0_1_f([[NSUserDefaults standardUserDefaults] oo_floatForKey:@"texture-anisotropy-scale" defaultValue:0.5]);
#endif
	
#ifdef GL_CLAMP_TO_EDGE
	// GL_CLAMP_TO_EDGE requires OpenGL 1.2 or later. Oolite probably does too...
	sClampToEdgeAvailable = (2 < [extMgr minorVersionNumber]) || [extMgr haveExtension:@"GL_SGIS_texture_edge_clamp"];
#endif
	
#if GL_APPLE_client_storage
	sClientStorageAvialable = [extMgr haveExtension:@"GL_APPLE_client_storage"];
#endif
	
#if GL_EXT_texture_lod_bias
	if ([[NSUserDefaults standardUserDefaults] oo_boolForKey:@"use-texture-lod-bias" defaultValue:YES])
	{
		sTextureLODBiasAvailable = [extMgr haveExtension:@"GL_EXT_texture_lod_bias"];
	}
	else
	{
		sTextureLODBiasAvailable = NO;
	}
#endif
	
#if GL_EXT_texture_rectangle
	sRectangleTextureAvailable = [extMgr haveExtension:@"GL_EXT_texture_rectangle"];
#endif
	
#if GL_ARB_texture_cube_map
	sCubeMapAvailable = [extMgr haveExtension:@"GL_ARB_texture_cube_map"];
#endif
}


#ifndef NDEBUG
- (id) retainInContext:(NSString *)context
{
	if (_trace)
	{
		if (context)  OOLog(@"texture.allocTrace.retain", @"Texture %p retained (retain count -> %u) - %@.", self, [self retainCount] + 1, context);
		else  OOLog(@"texture.allocTrace.retain", @"Texture %p retained.", self, [self retainCount] + 1);
	}
	
	return [super retain];
}


- (void) releaseInContext:(NSString *)context
{
	if (_trace)
	{
		if (context)  OOLog(@"texture.allocTrace.release", @"Texture %p released (retain count -> %u) - %@.", self, [self retainCount] - 1, context);
		else  OOLog(@"texture.allocTrace.release", @"Texture %p released (retain count -> %u).", self, [self retainCount] - 1);
	}
	
	[super release];
}


- (id) autoreleaseInContext:(NSString *)context
{
	if (_trace)
	{
		if (context)  OOLog(@"texture.allocTrace.autoreleased", @"Texture %p autoreleased - %@.", self, context);
		else  OOLog(@"texture.allocTrace.autoreleased", @"Texture %p autoreleased.", self);
	}
	
	return [super autorelease];
}


- (id) retain
{
	return [self retainInContext:sGlobalTraceContext];
}


- (void) release
{
	[self releaseInContext:sGlobalTraceContext];
}


- (id) autorelease
{
	return [self autoreleaseInContext:sGlobalTraceContext];
}
#endif

@end


@implementation NSDictionary (OOTextureConveniences)

- (NSDictionary *) oo_textureSpecifierForKey:(id)key defaultName:(NSString *)name
{
	return OOTextureSpecFromObject([self objectForKey:key], name);
}

@end

@implementation NSArray (OOTextureConveniences)

- (NSDictionary *) oo_textureSpecifierAtIndex:(unsigned)index defaultName:(NSString *)name
{
	return OOTextureSpecFromObject([self objectAtIndex:index], name);
}

@end

NSDictionary *OOTextureSpecFromObject(id object, NSString *defaultName)
{
	if (object == nil)  object = defaultName;
	if ([object isKindOfClass:[NSString class]])
	{
		if ([object isEqualToString:@""])  return nil;
		return [NSDictionary dictionaryWithObject:object forKey:@"name"];
	}
	if (![object isKindOfClass:[NSDictionary class]])  return nil;
	
	// If we're here, it's a dictionary.
	if (defaultName == nil || [object oo_stringForKey:@"name"] != nil)  return object;
	
	// If we get here, there's no "name" key and there is a default, so we fill it in:
	NSMutableDictionary *mutableResult = [NSMutableDictionary dictionaryWithDictionary:object];
	[mutableResult setObject:[[defaultName copy] autorelease] forKey:@"name"];
	return mutableResult;
}


uint8_t OOTextureComponentsForFormat(OOTextureDataFormat format)
{
	switch (format)
	{
		case kOOTextureDataRGBA:
			return 4;
			
		case kOOTextureDataGrayscale:
			return 1;
			
		case kOOTextureDataGrayscaleAlpha:
			return 2;
			
		case kOOTextureDataInvalid:
			break;
	}
	
	return 0;
}
