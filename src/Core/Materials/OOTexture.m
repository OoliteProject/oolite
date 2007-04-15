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

*/

#import "OOTexture.h"
#import "OOTextureLoader.h"
#import "OOCollectionExtractors.h"
#import "Universe.h"
#import "ResourceManager.h"
#import "OOOpenGLExtensionManager.h"


#if __BIG_ENDIAN__
	#define RGBA_IMAGE_TYPE GL_UNSIGNED_INT_8_8_8_8_REV
#else
	#define RGBA_IMAGE_TYPE GL_UNSIGNED_INT_8_8_8_8
#endif


static NSMutableDictionary	*sInUseTextures = nil;

/*	TODO: add limited-sized OOCache of recently-used textures -- requires
	(re-)adding auto-prune option to OOCache.
	
	Design outline: keep a cache of N recently-accessed textures, which
	retains them, in parallel to the in-use cache. If less than N textures are
	currently in use, the cache will keep additional ones around. Old textures
	which fall out of the cache are released, and if they're not used they
	immediately die; if they are, they stay about (and in sInUseTextures)
	until they're not in use any longer. If something calls for a texture
	which is in sInUseTextures but not the cache, they should get the existing
	one, which should be re-added to the cache.
	-- Ahruman
*/


static BOOL		sCheckedExtensions = NO;

// Anisotropic filtering
#if GL_EXT_texture_filter_anisotropic
static BOOL		sAnisotropyAvailable;
static float	sAnisotropyScale;	// Scale of anisotropy values
#else
#warning GL_EXT_texture_filter_anisotropic unavialble -- are you using an up-to-date glext.h?
#endif


// CLAMP_TO_EDGE (OK, requiring OpenGL 1.2 wouln't be _that_ big a deal...)
#if !defined(GL_CLAMP_TO_EDGE) && GL_SGIS_texture_edge_clamp
#define GL_CLAMP_TO_EDGE GL_CLAMP_TO_EDGE_SGIS
#endif

#ifdef GL_CLAMP_TO_EDGE
static BOOL		sClampToEdgeAvailable;
#else
#warning GL_CLAMP_TO_EDGE (OpenGL 1.2) and GL_SGIS_texture_edge_clamp are unavialble -- are you using an up-to-date gl.h?
#define sClampToEdgeAvailable	NO
#define GL_CLAMP_TO_EDGE		GL_CLAMP
#endif


// Client storage: reduce copying by requiring the app to keep data around
#if GL_APPLE_client_storage
#define OO_GL_CLIENT_STORAGE	1
static inline void EnableClientStorage(void) { glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE); }
// #elif in any equivalents on other platforms here
#else
#define OO_GL_CLIENT_STORAGE	0
#define sClientStorageAvialable	NO
#define EnableClientStorage()	do {} while (0)
#endif

#if OO_GL_CLIENT_STORAGE
static BOOL		sClientStorageAvialable;
#endif


@interface OOTexture (OOPrivate)

- (id)initWithPath:(NSString *)path key:(NSString *)key options:(uint32_t)options anisotropy:(float)anisotropy;
- (void)setUpTexture;
- (void)uploadTextureDataWithMipMap:(BOOL)mipMap format:(OOTextureDataFormat)format;

+ (void)checkExtensions;

@end


@implementation OOTexture

+ (id)textureWithName:(NSString *)name options:(uint32_t)options anisotropy:(float)anisotropy
{
	NSString				*key = nil;
	OOTexture				*result = nil;
	NSString				*path = nil;
	
	options &= kOOTextureDefinedFlags;
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
	if ((options & kOOTextureMagFilterMask) != kOOTextureMagFilterNearest)
	{
		options = (options & ~kOOTextureMagFilterMask) | kOOTextureMagFilterLinear;
	}
	
	// Look for existing texture
	key = [NSString stringWithFormat:@"%@:0x%.4X", name, options];
	result = [[sInUseTextures objectForKey:key] pointerValue];
	if (result == nil)
	{
		path = [ResourceManager pathForFileNamed:name inFolder:@"Textures"];
		if (path == nil)
		{
			OOLog(kOOLogFileNotFound, @"Could not find texture file \"%@\".", name);
			return nil;
		}
		
		if (!sCheckedExtensions)  [self checkExtensions];
		
		// No existing texture, load texture...
		result = [[[OOTexture alloc] initWithPath:path key:key options:options anisotropy:anisotropy] autorelease];
		
		if (result != nil)
		{
			// ...and remember it. Use an NSValue so sInUseTextures doesn't retain the texture.
			if (sInUseTextures == nil)  sInUseTextures = [[NSMutableDictionary alloc] init];
			[sInUseTextures setObject:[NSValue valueWithPointer:result] forKey:key];
		}
	}
	
	return result;
}


+ (id)textureWithConfiguration:(id)configuration
{
	NSString				*name = nil;
	NSString				*filterString = nil;
	uint32_t				options = 0;
	float					anisotropy;
	
	if ([configuration isKindOfClass:[NSString class]])
	{
		name = configuration;
		options = kOOTextureDefaultOptions;
		anisotropy = kOOTextureDefaultAnisotropy;
	}
	else if ([configuration isKindOfClass:[NSDictionary class]])
	{
		name = [configuration stringForKey:@"name" defaultValue:nil];
		if (name == nil)
		{
			OOLog(@"texture.load", @"Invalid texture configuration dictionary (must specify name):\n%@", configuration);
			return nil;
		}
		
		filterString = [configuration stringForKey:@"minFilter" defaultValue:@"default"];
		if ([filterString isEqualToString:@"nearest"])  options |= kOOTextureMinFilterNearest;
		else if ([filterString isEqualToString:@"linear"])  options |= kOOTextureMinFilterLinear;
		else if ([filterString isEqualToString:@"mipMap"])  options |= kOOTextureMinFilterMipMap;
		else  options |= kOOTextureMinFilterDefault;	// Covers "default"
		
		filterString = [configuration stringForKey:@"magFilter" defaultValue:@"default"];
		if ([filterString isEqualToString:@"nearest"])  options |= kOOTextureMagFilterNearest;
		else  options |= kOOTextureMagFilterLinear;	// Covers "default" and "linear"
		
		if ([configuration boolForKey:@"noShrink" defaultValue:NO])  options |= kOOTextureNoShrink;
		if ([configuration boolForKey:@"repeatS" defaultValue:NO])  options |= kOOTextureRepeatS;
		if ([configuration boolForKey:@"repeatT" defaultValue:NO])  options |= kOOTextureRepeatT;
		anisotropy = [configuration floatForKey:@"anisotropy" defaultValue:kOOTextureDefaultAnisotropy];
	}
	else
	{
		// Bad type
		OOLog(kOOLogParameterError, @"%s: expected string or dictionary, got %@.", __PRETTY_FUNCTION__, [configuration class]);
		return nil;
	}
	
	return [self textureWithName:name options:options anisotropy:anisotropy];
}


- (void)dealloc
{
	[sInUseTextures removeObjectForKey:key];
	
	if (loaded)
	{
		if (data.loaded.textureName != 0)  glDeleteTextures(1, &data.loaded.textureName);
		if (data.loaded.bytes != NULL) free(data.loaded.bytes);
	}
	else
	{
		[data.loading.loader release];
	}
	
	[super dealloc];
}


- (NSString *)description
{
	NSString				*stateDesc = nil;
	
	if (loaded)
	{
		if (data.loaded.bytes != NULL)
		{
			stateDesc = [NSString stringWithFormat:@"%u x %u", data.loaded.width, data.loaded.height];
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
	
	return [NSString stringWithFormat:@"<%@ %p{%@, %@}", [self className], self, key, stateDesc];
}


- (void)apply
{
	if (EXPECT_NOT(!loaded))  [self setUpTexture];
	else  glBindTexture(GL_TEXTURE_2D, data.loaded.textureName);
}


- (void)ensureFinishedLoading
{
	if (EXPECT_NOT(!loaded))  [self setUpTexture];
}

@end


@implementation OOTexture (OOPrivate)

- (id)initWithPath:(NSString *)path key:(NSString *)inKey options:(uint32_t)options anisotropy:(float)anisotropy
{
	self = [super init];
	if (EXPECT_NOT(self == nil))  return nil;
	
	data.loading.loader = [[OOTextureLoader loaderWithPath:path options:options] retain];
	if (EXPECT_NOT(data.loading.loader == nil))
	{
		[self release];
		return nil;
	}
	
	data.loading.options = options;
#if GL_EXT_texture_filter_anisotropic
	data.loading.anisotropy = OOClamp_0_1_f(anisotropy) * sAnisotropyScale;
#endif
	
	key = [inKey copy];
	
	return self;
}


- (void)setUpTexture
{
	OOTextureLoader			*loader = nil;
	uint32_t				options;
	GLint					clampMode;
	GLint					filter;
	float					anisotropy;
	BOOL					mipMap = NO;
	OOTextureDataFormat		format;
	
	loader = data.loading.loader;
	options = data.loading.options;
	anisotropy = data.loading.anisotropy;
	
	loaded = YES;
	// data.loaded considered invalid beyond this point.
	
	if ([loader getResult:&data.loaded.bytes format:&format width:&data.loaded.width height:&data.loaded.height])
	{
	//	glPixelStorei(GL_UNPACK_ALIGNMENT, 1);		// FIXME: this is probably not needed. Remove it once stuff works and see if anything changes. (Should probably be 4 if we need to keep it.)
		glGenTextures(1, &data.loaded.textureName);
		glBindTexture(GL_TEXTURE_2D, data.loaded.textureName);
		
		// Select wrap mode
		clampMode = sClampToEdgeAvailable ? GL_CLAMP_TO_EDGE : GL_CLAMP;
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, (options & kOOTextureRepeatS) ? GL_REPEAT : clampMode);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, (options & kOOTextureRepeatT) ? GL_REPEAT : clampMode);
		
		// Select min filter
		filter = options & kOOTextureMinFilterMask;
		if (filter == kOOTextureMinFilterNearest)  filter = GL_NEAREST;
		else if (filter == kOOTextureMinFilterMipMap)
		{
			mipMap = YES;
			filter = GL_LINEAR_MIPMAP_LINEAR;
		}
		else  filter = GL_LINEAR;
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filter);
		
#if GL_EXT_texture_filter_anisotropic
		if (sAnisotropyAvailable && mipMap && 1.0 < anisotropy)
		{
			glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY_EXT, 4.0);
		}
#endif
		
		// Select mag filter
		filter = options & kOOTextureMagFilterMask;
		if (filter == kOOTextureMagFilterNearest)  filter = GL_NEAREST;
		else  filter = GL_LINEAR;
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filter);
		
		if (sClientStorageAvialable)  EnableClientStorage();
		
		[self uploadTextureDataWithMipMap:mipMap format:format];
		
		if (!sClientStorageAvialable)
		{
			free(data.loaded.bytes);
			data.loaded.bytes = NULL;
		}
		
		OOLog(@"texture.setUp", @"Set up texture %u (%ux%u pixels, %@)", data.loaded.textureName, data.loaded.width, data.loaded.height, key);
	}
	else
	{
		data.loaded.textureName = 0;
	}
	
	[loader release];
}


- (void)uploadTextureDataWithMipMap:(BOOL)mipMap format:(OOTextureDataFormat)format
{
	GLint					glFormat, internalFormat, type;
	
	switch (format)
	{
		case kOOTextureDataRGBA:
			glFormat = GL_RGBA;
			internalFormat = GL_RGBA;
			type = RGBA_IMAGE_TYPE;
			break;
		
		case kOOTextureDataGrayscale:
			glFormat = GL_LUMINANCE;
			internalFormat = GL_LUMINANCE;
			type = GL_UNSIGNED_BYTE;
			break;
		
		default:
			OOLog(kOOLogParameterError, @"Unexpected texture format %u.", format);
			return;
	}
	
	unsigned				w = data.loaded.width,
							h = data.loaded.height,
							level = 0;
	uint32_t				*bytes = data.loaded.bytes;
	
	while (1 < w && 1 < h)
	{
		glTexImage2D(GL_TEXTURE_2D, level++, glFormat, w, h, 0, internalFormat, type, bytes);
		if (!mipMap)  return;
		bytes += w * h;
		w >>= 1;
		h >>= 1;
	}
	
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, level - 1);
}


+ (void)checkExtensions
{
	sCheckedExtensions = YES;
	
	OOOpenGLExtensionManager	*extMgr = [OOOpenGLExtensionManager sharedManager];
	
#if GL_EXT_texture_filter_anisotropic
	sAnisotropyAvailable = [extMgr haveExtension:@"GL_EXT_texture_filter_anisotropic"];
	glGetFloatv(GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT, &sAnisotropyScale);
	sAnisotropyScale *= OOClamp_0_1_f([[NSUserDefaults standardUserDefaults] floatForKey:@"texture-anisotropy-bias" defaultValue:1.0]);
#endif
	
#ifdef GL_CLAMP_TO_EDGE
	// GL_CLAMP_TO_EDGE requires OpenGL 1.2 or later
	sClampToEdgeAvailable = (2 < [extMgr minorVersionNumber]) || [extMgr haveExtension:@"GL_SGIS_texture_edge_clamp"];
#endif
	
#if GL_APPLE_client_storage
	sClientStorageAvialable = [extMgr haveExtension:@"GL_APPLE_client_storage"];
#endif
}

@end
