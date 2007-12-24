/*

OOTexture.m

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

#import "OOTexture.h"
#import "OOTextureLoader.h"
#import "OOCollectionExtractors.h"
#import "Universe.h"
#import "ResourceManager.h"
#import "OOOpenGLExtensionManager.h"
#import "OOMacroOpenGL.h"
#import "OOCPUInfo.h"
#import "OOCache.h"


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
	#define RGBA_IMAGE_TYPE GL_UNSIGNED_INT_8_8_8_8
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
#warning GL_CLAMP_TO_EDGE (OpenGL 1.2) and GL_SGIS_texture_edge_clamp are unavialble -- are you using an up-to-date gl.h?
#define sClampToEdgeAvailable	(NO)
#define GL_CLAMP_TO_EDGE		GL_CLAMP
#endif


// Client storage: reduce copying by requiring the app to keep data around
#if GL_APPLE_client_storage

#define OO_GL_CLIENT_STORAGE	(1)
static inline void EnableClientStorage(void)
{
	OO_ENTER_OPENGL();
	glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE);
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


@interface OOTexture (OOPrivate)

- (id)initWithPath:(NSString *)path key:(NSString *)key options:(uint32_t)options anisotropy:(float)anisotropy lodBias:(GLfloat)lodBias;
- (void)setUpTexture;
- (void)uploadTexture;
- (void)uploadTextureDataWithMipMap:(BOOL)mipMap format:(OOTextureDataFormat)format;

- (void)forceRebind;

+ (void)checkExtensions;

@end


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
#endif	// Else, options &= kOOTextureDefinedFlags below will clear the flag
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
	key = [NSString stringWithFormat:@"%@%@%@:0x%.4X/%g/%g", directory ? directory : @"", directory ? @"/" : @"", name, options, anisotropy, lodBias];
	result = [[sInUseTextures objectForKey:key] pointerValue];
	if (result == nil)
	{
		path = [ResourceManager pathForFileNamed:name inFolder:directory];
		if (path == nil)
		{
			if (!noFNF)  OOLog(kOOLogFileNotFound, @"***** ERROR: Could not find texture file \"%@\".", name);
			return nil;
		}
				
		// No existing texture, load texture...
		result = [[[OOTexture alloc] initWithPath:path key:key options:options anisotropy:anisotropy lodBias:lodBias] autorelease];
		
		if (result != nil)
		{
			// ...and remember it. Use an NSValue so sInUseTextures doesn't retain the texture.
			if (sInUseTextures == nil)  sInUseTextures = [[NSMutableDictionary alloc] init];
			[sInUseTextures setObject:[NSValue valueWithPointer:result] forKey:key];
		}
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
		name = [configuration stringForKey:@"name"];
		if (name == nil)
		{
			OOLog(@"texture.load.noName", @"Invalid texture configuration dictionary (must specify name):\n%@", configuration);
			return nil;
		}
		
		filterString = [configuration stringForKey:@"min_filter" defaultValue:@"default"];
		if ([filterString isEqualToString:@"nearest"])  options |= kOOTextureMinFilterNearest;
		else if ([filterString isEqualToString:@"linear"])  options |= kOOTextureMinFilterLinear;
		else if ([filterString isEqualToString:@"mipmap"])  options |= kOOTextureMinFilterMipMap;
		else  options |= kOOTextureMinFilterDefault;	// Covers "default"
		
		filterString = [configuration stringForKey:@"mag_filter" defaultValue:@"default"];
		if ([filterString isEqualToString:@"nearest"])  options |= kOOTextureMagFilterNearest;
		else  options |= kOOTextureMagFilterLinear;	// Covers "default" and "linear"
		
		if ([configuration boolForKey:@"no_shrink" defaultValue:NO])  options |= kOOTextureNoShrink;
		if ([configuration boolForKey:@"repeat_s" defaultValue:NO])  options |= kOOTextureRepeatS;
		if ([configuration boolForKey:@"repeat_t" defaultValue:NO])  options |= kOOTextureRepeatT;
		anisotropy = [configuration floatForKey:@"anisotropy" defaultValue:kOOTextureDefaultAnisotropy];
		lodBias = [configuration floatForKey:@"texture_LOD_bias" defaultValue:kOOTextureDefaultLODBias];
	}
	else
	{
		// Bad type
		if (configuration != nil)  OOLog(kOOLogParameterError, @"%s: expected string or dictionary, got %@.", __PRETTY_FUNCTION__, [configuration class]);
		return nil;
	}
	
	return [self textureWithName:name inFolder:@"Textures" options:options anisotropy:anisotropy lodBias:lodBias];
}


- (void)dealloc
{
	OOLog(@"texture.dealloc", @"Deallocating and uncaching texture %@", self);
	
	if (_key != nil)
	{
		[sInUseTextures removeObjectForKey:_key];
		[sRecentTextures removeObjectForKey:_key];
		[_key release];
	}
	
	if (_loaded)
	{
		if (_textureName != 0)  GLRecycleTextureName(_textureName, _mipLevels);
		if (_bytes != NULL) free(_bytes);
	}
	
	[_loader release];
	
	[super dealloc];
}


- (NSString *)description
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
	
	return [NSString stringWithFormat:@"<%@ %p [%u]>{%@, %@}", [self className], self, [self retainCount], _key, stateDesc];
}


- (void)apply
{
	OO_ENTER_OPENGL();
	
	if (EXPECT_NOT(!_loaded))  [self setUpTexture];
	else if (EXPECT_NOT(!_uploaded))  [self uploadTexture];
	else  glBindTexture(GL_TEXTURE_2D, _textureName);
	
#if GL_EXT_texture_lod_bias
	if (sTextureLODBiasAvailable)  glTexEnvf(GL_TEXTURE_FILTER_CONTROL_EXT, GL_TEXTURE_LOD_BIAS_EXT, _lodBias);
#endif
}


+ (void)applyNone
{
	OO_ENTER_OPENGL();
	
	glBindTexture(GL_TEXTURE_2D, 0);
}


- (void)ensureFinishedLoading
{
	if (EXPECT_NOT(!_loaded))  [self setUpTexture];
}


- (NSSize)dimensions
{
	[self ensureFinishedLoading];
	
	return NSMakeSize(_width, _height);
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
	[sInUseTextures autorelease];
	sInUseTextures = nil;
	[sRecentTextures autorelease];
	sRecentTextures = nil;
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

@end


@implementation OOTexture (OOPrivate)

- (id)initWithPath:(NSString *)path key:(NSString *)inKey options:(uint32_t)options anisotropy:(float)anisotropy lodBias:(GLfloat)inLodBias
{
	self = [super init];
	if (EXPECT_NOT(self == nil))  return nil;
	
	_loader = [[OOTextureLoader loaderWithPath:path options:options] retain];
	if (EXPECT_NOT(_loader == nil))
	{
		[self release];
		return nil;
	}
	
	_options = options;
	
#if GL_EXT_texture_filter_anisotropic
	_anisotropy = OOClamp_0_1_f(_anisotropy) * sAnisotropyScale;
#endif
#if GL_EXT_texture_lod_bias
	_lodBias = inLodBias;
#endif
	
	_key = [inKey copy];
	
	// Add self to recent textures cache
	if (EXPECT_NOT(sRecentTextures == nil))
	{
		sRecentTextures = [[OOCache alloc] init];
		[sRecentTextures setName:@"recent textures"];
		[sRecentTextures setAutoPrune:YES];
		[sRecentTextures setPruneThreshold:kRecentTexturesCount];
	}
	[sRecentTextures setObject:self forKey:_key];
	
	return self;
}


- (void)setUpTexture
{
	// This will block until loading is completed, if necessary.
	if ([_loader getResult:&_bytes format:&_format width:&_width height:&_height])
	{
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


- (void)uploadTexture
{
	GLint					clampMode;
	GLint					filter;
	BOOL					mipMap = NO;
	
	OO_ENTER_OPENGL();
	
	if (!_uploaded)
	{
		_textureName = GLAllocateTextureName();
		glBindTexture(GL_TEXTURE_2D, _textureName);
		
		// Select wrap mode
		clampMode = sClampToEdgeAvailable ? GL_CLAMP_TO_EDGE : GL_CLAMP;
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, (_options & kOOTextureRepeatS) ? GL_REPEAT : clampMode);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, (_options & kOOTextureRepeatT) ? GL_REPEAT : clampMode);
		
		// Select min filter
		filter = _options & kOOTextureMinFilterMask;
		if (filter == kOOTextureMinFilterNearest)  filter = GL_NEAREST;
		else if (filter == kOOTextureMinFilterMipMap)
		{
			mipMap = YES;
			filter = GL_LINEAR_MIPMAP_LINEAR;
		}
		else  filter = GL_LINEAR;
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filter);
		
#if GL_EXT_texture_filter_anisotropic
		if (sAnisotropyAvailable && mipMap && 1.0 < _anisotropy)
		{
			glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY_EXT, _anisotropy);
		}
#endif
		
		// Select mag filter
		filter = _options & kOOTextureMagFilterMask;
		if (filter == kOOTextureMagFilterNearest)  filter = GL_NEAREST;
		else  filter = GL_LINEAR;
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filter);
		
		if (sClientStorageAvialable)  EnableClientStorage();
		
		[self uploadTextureDataWithMipMap:mipMap format:_format];
		
		OOLog(@"texture.upload", @"Uploaded texture %u (%ux%u pixels, %@)", _textureName, _width, _height, _key);
		
		_valid = YES;
		_uploaded = YES;
	}
}


- (void)uploadTextureDataWithMipMap:(BOOL)mipMap format:(OOTextureDataFormat)format
{
	GLint					glFormat, internalFormat, type;
	unsigned				w = _width,
							h = _height,
							level = 0;
	char					*bytes = _bytes;
	uint8_t					planes = OOTexturePlanesForFormat(format);
	
	OO_ENTER_OPENGL();
	
	switch (format)
	{
		case kOOTextureDataRGBA:
			glFormat = GL_RGBA;
			internalFormat = GL_RGBA;
			type = RGBA_IMAGE_TYPE;
			break;
		
		case kOOTextureDataGrayscale:
			glFormat = GL_LUMINANCE8;
			internalFormat = GL_LUMINANCE;
			type = GL_UNSIGNED_BYTE;
			break;
		
		default:
			OOLog(kOOLogParameterError, @"Unexpected texture format %u.", format);
			return;
	}
	
	while (1 < w && 1 < h)
	{
		glTexImage2D(GL_TEXTURE_2D, level++, glFormat, w, h, 0, internalFormat, type, bytes);
		if (!mipMap)  return;
		bytes += w * planes * h;
		w >>= 1;
		h >>= 1;
	}
	
	_mipLevels = level - 1;
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, _mipLevels);
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


+ (void)checkExtensions
{
	OO_ENTER_OPENGL();
	
	sCheckedExtensions = YES;
	
	OOOpenGLExtensionManager	*extMgr = [OOOpenGLExtensionManager sharedManager];
	
#if GL_EXT_texture_filter_anisotropic
	sAnisotropyAvailable = [extMgr haveExtension:@"GL_EXT_texture_filter_anisotropic"];
	glGetFloatv(GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT, &sAnisotropyScale);
	sAnisotropyScale *= OOClamp_0_1_f([[NSUserDefaults standardUserDefaults] floatForKey:@"texture-anisotropy-bias" defaultValue:1.0]);
#endif
	
#ifdef GL_CLAMP_TO_EDGE
	// GL_CLAMP_TO_EDGE requires OpenGL 1.2 or later. Oolite probably does too...
	sClampToEdgeAvailable = (2 < [extMgr minorVersionNumber]) || [extMgr haveExtension:@"GL_SGIS_texture_edge_clamp"];
#endif
	
#if GL_APPLE_client_storage
	sClientStorageAvialable = [extMgr haveExtension:@"GL_APPLE_client_storage"];
#endif
	
#if GL_EXT_texture_lod_bias
	sTextureLODBiasAvailable = [extMgr haveExtension:@"GL_EXT_texture_lod_bias"];
#endif
	
#if GL_EXT_texture_rectangle
	sRectangleTextureAvailable = [extMgr haveExtension:@"GL_EXT_texture_rectangle"];
#endif
}

@end


@implementation NSDictionary (OOTextureConveniences)

- (id)textureSpecifierForKey:(id)key defaultName:(NSString *)name
{
	return OOTextureSpecFromObject([self objectForKey:key], name);
}

@end

@implementation NSArray (OOTextureConveniences)

- (id)textureSpecifierAtIndex:(unsigned)index defaultName:(NSString *)name
{
	return OOTextureSpecFromObject([self objectAtIndex:index], name);
}

@end

id OOTextureSpecFromObject(id object, NSString *defaultName)
{
	NSMutableDictionary		*mutableResult = nil;
	
	if (object == nil)  return [[defaultName copy] autorelease];
	if ([object isKindOfClass:[NSString class]])  return [[object copy] autorelease];
	if (![object isKindOfClass:[NSDictionary class]])  return nil;
	
	// If we're here, it's a dictionary.
	if (defaultName == nil || [mutableResult objectForKey:@"name"] != nil)  return object;
	
	// If we get here, there's no "name" key and there is a default, so we fill it in:
	mutableResult = [object mutableCopy];
	[mutableResult setObject:defaultName forKey:@"name"];
	return [mutableResult autorelease];
}
