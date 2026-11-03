/*	test_OOConcreteTexture.mm
	Unit tests for OOConcreteTexture (src/Core/Materials/OOConcreteTexture.h), the texture that a
	loader fills and OpenGL holds: bead oo-qa7c (Phase 3, house style of proposed ADR-0056; a leaf
	of the textures root, amendment oo-whzh).

	A concrete texture is made with a loader (here a generator, so no file is read and the resource
	manager is never reached), caches itself under its key, and on first use waits for the loader,
	uploads the pixels to OpenGL (with mip-maps when asked) and answers their size. It links the
	whole game but main (tests/unit/core/meson.build entry ['*']), on the hidden GL context of
	oo_gl_test_context.hpp; the generator runs on the game's own work manager. The expectations
	were written against the Objective-C API and run on the unconverted class first (commit
	4477d13b5); that API is now the facade (OOConcreteTexture+ObjCBridge.h), so they run through
	it, and the last tests pin the C++ API (cxx::OOConcreteTexture) and the facade's contract.
	Run: bash tools/check-core-tests.sh
*/

#import "OOConcreteTexture.h"
#import "OOTextureInternal.h"
#import "OOTextureGenerator.h"
#import "OODescription.h"

#include "oo_test.hpp"
#include "oo_gl_test_context.hpp"

#include <cstdlib>
#include <cstring>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


// A generator of a 4 x 2 RGBA image whose bytes count up from 1, or of nothing.
@interface TestGenerator: OOTextureGenerator
{
@public
	BOOL	_empty;
}
@end

@implementation TestGenerator

- (void) loadTexture
{
	if (_empty)  return;
	_cxxLoader->_width = 4;
	_cxxLoader->_height = 2;
	_cxxLoader->_format = kOOPixMapRGBA;
	uint8_t *bytes = (uint8_t *)malloc(4 * 2 * 4);
	for (unsigned i = 0; i < 4 * 2 * 4; i++)  bytes[i] = (uint8_t)(i + 1);
	_cxxLoader->_data = bytes;
}

@end


namespace {

bool SameSize(NSSize size, double width, double height)
{
	return size.width == width && size.height == height;
}


GLint BoundTexture()
{
	GLint bound = -1;
	glGetIntegerv(GL_TEXTURE_BINDING_2D, &bound);
	return bound;
}


// The loaders' sizes come from their one-time set-up, which a path with no known extension runs
// (and then answers nil, reading nothing).
void SetUpLoaders()
{
	@autoreleasepool
	{
		(void)[OOTextureLoader cxx_loaderWithPath:std::string("unknown.type") options:0];
	}
}


TestGenerator *QueuedGenerator(uint32_t options, BOOL empty)
{
	TestGenerator *generator = [[[TestGenerator alloc] cxx_initWithPath:std::string("test generator") options:options] autorelease];
	generator->_empty = empty;
	OO_CHECK([generator enqueue]);
	return generator;
}


OOConcreteTexture *Texture(OOTextureLoader *loader, const std::optional<std::string> &key, uint32_t options)
{
	return [[[OOConcreteTexture alloc] initWithLoader:loader key:key options:options anisotropy:0.5f lodBias:0.0f] autorelease];
}


void ClearCache()
{
	@autoreleasepool
	{
		oo::AutoreleaseScope scope;
		[OOTexture clearCache];
	}
}

}	// namespace


OO_TEST(noLoaderNoTexture)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	@autoreleasepool
	{
		OO_CHECK(Texture(nil, std::string("test:none"), kOOTextureDefaultOptions) == nil);
		OO_CHECK([[[OOConcreteTexture alloc] initWithPath:"no-such-loader.type" key:std::string("test:none") options:kOOTextureDefaultOptions anisotropy:0.5f lodBias:0.0f] autorelease] == nil);
		OO_CHECK([OOTexture cxx_existingTextureForKey:std::string("test:none")] == nil);
	}
}


OO_TEST(beforeLoading)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	@autoreleasepool
	{
		const uint32_t options = kOOTextureMinFilterLinear | kOOTextureMagFilterLinear;
		OOConcreteTexture *texture = Texture(QueuedGenerator(options, NO), std::string("test:before"), options);
		OO_CHECK([texture isKindOfClass:[OOTexture class]]);
		OO_CHECK([texture cxx_cacheKey] == std::optional<std::string>("test:before"));
		OO_CHECK([OOTexture cxx_existingTextureForKey:std::string("test:before")] == texture);
		OO_CHECK(SameSize([texture texCoordsScale], 1, 1));	// no rectangle texture: no wait
		OO_CHECK(![texture isRectangleTexture] && ![texture isCubeMap]);
#ifndef NDEBUG
		OO_CHECK([texture cxx_name] == std::optional<std::string>("<TestGenerator>"));
#endif
		const std::string text = oo::DescriptionOf(texture);
		OO_CHECK(text.starts_with("<OOConcreteTexture 0x") && text.ends_with(">{test:before, loading}"));
		OO_CHECK(oo::ShortDescriptionOf(texture).ends_with(">{test:before}"));
	}
	ClearCache();
}


OO_TEST(loadsAndUploads)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	@autoreleasepool
	{
		const uint32_t options = kOOTextureMinFilterLinear | kOOTextureMagFilterLinear;
		OOConcreteTexture *texture = Texture(QueuedGenerator(options, NO), std::string("test:linear"), options);
		[texture ensureFinishedLoading];
		OO_CHECK([texture isFinishedLoading]);
		// The loader scales the 4 x 2 image to 2 x 2; the original size is kept.
		OO_CHECK(SameSize([texture dimensions], 2, 2) && SameSize([texture originalDimensions], 4, 2));
		OO_CHECK(![texture isMipMapped]);
		const GLint name = [texture glTextureName];
		OO_CHECK(name != 0);
		OO_CHECK(oo::DescriptionOf(texture).ends_with(">{test:linear, 2 x 2}"));
#ifndef NDEBUG
		OO_CHECK([texture dataSize] == 4);
#endif

		// Applying binds it.
		glBindTexture(GL_TEXTURE_2D, 0);
		[texture apply];
		OO_CHECK(BoundTexture() == name);

		// A generated texture keeps its bytes (it cannot be reloaded): the copy is of them.
		OOPixMap pixMap = [texture copyPixMapRepresentation];
		OO_CHECK(OOIsValidPixMap(pixMap) && pixMap.width == 2 && pixMap.height == 2 && pixMap.format == kOOPixMapRGBA && pixMap.rowBytes == 8);
		const uint8_t *bytes = (const uint8_t *)pixMap.pixels;
		OO_CHECK(bytes != NULL && bytes[0] == 3);	// the scaled first pixel
		OOFreePixMap(&pixMap);

		// A graphics reset deletes the GL texture; the next use uploads it again.
		[texture forceRebind];
		[texture apply];
		OO_CHECK([texture glTextureName] != 0 && BoundTexture() == [texture glTextureName]);
		OO_CHECK(SameSize([texture dimensions], 2, 2));
	}
	ClearCache();
}


OO_TEST(mipMapped)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	@autoreleasepool
	{
		const uint32_t options = kOOTextureMinFilterMipMap | kOOTextureMagFilterLinear;
		OOConcreteTexture *texture = Texture(QueuedGenerator(options, NO), std::string("test:mip"), options);
		OO_CHECK([texture isMipMapped]);	// waits for loading
		OO_CHECK(SameSize([texture dimensions], 2, 2));
		OO_CHECK([texture glTextureName] != 0);
		GLint maxLevel = -1;
		glBindTexture(GL_TEXTURE_2D, [texture glTextureName]);
		glGetTexParameteriv(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, &maxLevel);
		OO_CHECK(maxLevel == 1);
#ifndef NDEBUG
		OO_CHECK([texture dataSize] == 5);	// 2 * 2, mip-mapped: * 4 / 3
#endif
	}
	ClearCache();
}


OO_TEST(failedLoad)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	@autoreleasepool
	{
		OOConcreteTexture *texture = Texture(QueuedGenerator(kOOTextureDefaultOptions, YES), std::string("test:empty"), kOOTextureDefaultOptions);
		OO_CHECK(SameSize([texture dimensions], 0, 0));
		OO_CHECK([texture glTextureName] == 0 && [texture isFinishedLoading]);
		OO_CHECK(oo::DescriptionOf(texture).ends_with(">{test:empty, LOAD ERROR}"));
		OO_CHECK(OOIsNullPixMap([texture copyPixMapRepresentation]));
		[texture forceRebind];	// not valid: nothing to delete
		[texture apply];
	}
	ClearCache();
}


OO_TEST(deallocUncaches)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	@autoreleasepool
	{
		const uint32_t options = kOOTextureMinFilterLinear | kOOTextureMagFilterLinear;
		OOConcreteTexture *texture = Texture(QueuedGenerator(options, NO), std::string("test:gone"), options);
		[texture ensureFinishedLoading];
		OO_CHECK([OOTexture cxx_existingTextureForKey:std::string("test:gone")] == texture);
	}
	// Kept by the recent textures until they are cleared; then released, and uncached.
	OO_CHECK([OOTexture cxx_existingTextureForKey:std::string("test:gone")] != nil);
	ClearCache();
	OO_CHECK([OOTexture cxx_existingTextureForKey:std::string("test:gone")] == nil);
#ifndef NDEBUG
	@autoreleasepool
	{
		for (const oo::ObjCRef<OOTexture *> &texture : [OOTexture cxx_allTextures])
		{
			OO_CHECK([texture.get() cxx_cacheKey] != std::optional<std::string>("test:gone"));
		}
	}
#endif
}


// --- The C++ API and the facade (after the conversion) ---------------------------------------

OO_TEST(cxxApi)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	@autoreleasepool
	{
		OO_CHECK(cxx::OOConcreteTexture::initWithLoader(nil, std::string("test:cxx"), kOOTextureDefaultOptions, 0.5f, 0.0f) == nullptr);
		OO_CHECK(cxx::OOConcreteTexture::initWithPath("no-such-loader.type", std::string("test:cxx"), kOOTextureDefaultOptions, 0.5f, 0.0f) == nullptr);

		const uint32_t options = kOOTextureMinFilterLinear | kOOTextureMagFilterLinear;
		const oo::Ref<cxx::OOConcreteTexture> texture = cxx::OOConcreteTexture::initWithLoader(QueuedGenerator(options, NO), std::string("test:cxx"), options, 0.5f, 0.0f);
		OO_CHECK(texture != nullptr && texture->cacheKey() == std::optional<std::string>("test:cxx"));
		OO_CHECK(cxx::OOTexture::existingTextureForKey(std::string("test:cxx")) == texture.get());
		OO_CHECK(texture->descriptionComponents() == std::optional<std::string>("test:cxx, loading"));
		OO_CHECK(texture->shortDescriptionComponents() == std::optional<std::string>("test:cxx"));

		texture->ensureFinishedLoading();
		OO_CHECK(texture->isFinishedLoading());
		OO_CHECK(SameSize(texture->dimensions(), 2, 2) && SameSize(texture->originalDimensions(), 4, 2));
		OO_CHECK(texture->glTextureName() != 0 && !texture->isMipMapped());
		OO_CHECK(texture->descriptionComponents() == std::optional<std::string>("test:cxx, 2 x 2"));
		glBindTexture(GL_TEXTURE_2D, 0);
		texture->apply();
		OO_CHECK(BoundTexture() == texture->glTextureName());
#ifndef NDEBUG
		OO_CHECK(texture->name() == std::optional<std::string>("<TestGenerator>") && texture->dataSize() == 4);
		texture->setTrace(true);
		texture->setTrace(false);
#endif
	}
	ClearCache();
}


OO_TEST(facade)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	@autoreleasepool
	{
		const uint32_t options = kOOTextureMinFilterLinear | kOOTextureMagFilterLinear;

		// What the Objective-C initialiser answers is the C++ texture's one facade, cached.
		OOConcreteTexture *made = Texture(QueuedGenerator(options, NO), std::string("test:facade"), options);
		cxx::OOConcreteTexture *texture = oo::ToCxx(made);
		OO_CHECK(texture != nullptr && oo::ToObjC(texture) == made);
		OO_CHECK(oo::ToObjC(static_cast<cxx::OOTexture *>(texture)) == made);
		OO_CHECK([OOTexture cxx_existingTextureForKey:std::string("test:facade")] == made);
		OO_CHECK([made class] == [OOConcreteTexture class]);

		// The factory's textures are concrete C++ textures behind that facade.
		TestGenerator *generator = [[[TestGenerator alloc] cxx_initWithPath:std::string("test generator") options:options] autorelease];	// the factory queues it
		OOTexture *generated = [OOTexture textureWithGenerator:generator];
		OO_CHECK([generated isKindOfClass:[OOConcreteTexture class]]);
		OO_CHECK(dynamic_cast<cxx::OOConcreteTexture *>(oo::ToCxx(generated)) != nullptr);
	}
	ClearCache();
	OOConcreteTexture *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOConcreteTexture *>(nullptr)) == nil);
}


OO_TEST_MAIN()
