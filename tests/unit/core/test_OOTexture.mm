/*	test_OOTexture.mm
	Unit tests for OOTexture (src/Core/Materials/OOTexture.h), the root of the textures: bead
	oo-whzh (Phase 3, house style of proposed ADR-0056; the Materials module's pattern, amendments
	oo-smy and oo-2en).

	OOTexture is abstract. OOConcreteTexture and OONullTexture derive from it in their own files
	and convert in their own beads. The root keeps the texture caches (the live textures by cache
	key, unretained; the recent textures, retained; every live texture, for graphics resets) and is
	the factory that answers a cached texture or a new OOConcreteTexture. It links the whole game
	but main (tests/unit/core/meson.build entry ['*']), on the hidden GL context of
	oo_gl_test_context.hpp, because the factory checks the GL extensions on first use. Nothing here
	reaches the resource manager: the named texture is found in the cache by its key, and the
	generator's -enqueue is the test's, so no file is read and no worker thread runs.

	The expectations were written against the Objective-C API and run on the unconverted class
	first (commit 84b1acfc6); that API is now the facade (OOTexture+ObjCBridge.h), so they run
	through it, which is its forwarding test. Two Objective-C subclasses stand for the concrete
	textures: TestTexture overrides what OOConcreteTexture does and caches itself under a key,
	BareTexture overrides nothing, so it answers the root's defaults. After them come the C++ API
	and the hierarchy's crossing both ways, as test_OOSound.mm does.
	Run: bash tools/check-core-tests.sh
*/

#import "OOTexture.h"
#import "OOTextureInternal.h"
#import "OOTextureGenerator.h"
#import "OOConcreteTexture.h"
#import "OONullTexture.h"
#import "OODescription.h"

#include "oo_test.hpp"
#include "oo_gl_test_context.hpp"

#include <algorithm>
#include <string>
#include <vector>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


static int gTestDeallocs = 0;


// A texture as OOConcreteTexture is one: it caches itself under its key, and uncaches itself.
@interface TestTexture: OOTexture
{
@public
	std::optional<std::string>	_key;
	int							_rebinds;
	int							_applies;
}

- (id) initWithKey:(const std::optional<std::string> &)key;

@end


@implementation TestTexture

- (id) initWithKey:(const std::optional<std::string> &)key
{
	if ((self = [super init]))
	{
		_key = key;
		[self addToCaches];
	}
	return self;
}


- (void) dealloc
{
	gTestDeallocs++;
	[self removeFromCaches];
	[super dealloc];
}


- (void) apply									{ _applies++; }
- (NSSize) dimensions							{ return NSMakeSize(8, 4); }
- (BOOL) isMipMapped							{ return YES; }
- (void) forceRebind							{ _rebinds++; }
- (std::optional<std::string>) cxx_cacheKey		{ return _key; }
- (GLint) glTextureName							{ return 7; }
- (std::optional<std::string>) cxx_descriptionComponents	{ return std::string("test"); }
#ifndef NDEBUG
- (std::optional<std::string>) cxx_name			{ return std::string("test texture"); }
#endif

@end


// A texture that overrides nothing: the root's own answers.
@interface BareTexture: OOTexture
@end

@implementation BareTexture
@end


// A generator that is never queued: -enqueue answers what the test says, and counts.
@interface TestGenerator: OOTextureGenerator
{
@public
	std::optional<std::string>	_key;
	BOOL						_accept;
	int							_enqueues;
}
@end

@implementation TestGenerator

- (std::optional<std::string>) cxx_cacheKey		{ return _key; }
- (BOOL) enqueue								{ _enqueues++; return _accept; }

@end


namespace {

TestTexture *MakeTexture(const std::optional<std::string> &key)
{
	return [[[TestTexture alloc] initWithKey:key] autorelease];
}


TestGenerator *MakeGenerator(const std::optional<std::string> &key, BOOL accept)
{
	TestGenerator *generator = [[[TestGenerator alloc] cxx_initWithPath:std::string("test generator") options:0] autorelease];
	generator->_key = key;
	generator->_accept = accept;
	return generator;
}


// -clearCache autoreleases the recent textures (a C++ cache), which needs a scope to be released.
void ClearCache()
{
	@autoreleasepool
	{
		oo::AutoreleaseScope scope;
		[OOTexture clearCache];
	}
}


bool SameSize(NSSize size, double width, double height)
{
	return size.width == width && size.height == height;
}


#ifndef NDEBUG
bool Contains(const std::vector<oo::ObjCRef<OOTexture *>> &textures, OOTexture *texture)
{
	return std::find(textures.begin(), textures.end(), texture) != textures.end();
}
#endif

}	// namespace


OO_TEST(rootDefaults)
{
	@autoreleasepool
	{
		OOTexture *bare = [[[BareTexture alloc] init] autorelease];
		OO_CHECK([bare isKindOfClass:[OOWeakRefObject class]]);
		OO_CHECK([bare isFinishedLoading]);
		OO_CHECK(![bare cxx_cacheKey].has_value());
		OO_CHECK(![bare isRectangleTexture] && ![bare isCubeMap]);
		OO_CHECK(SameSize([bare texCoordsScale], 1, 1));
		OO_CHECK(OOIsNullPixMap([bare copyPixMapRepresentation]));
		[bare ensureFinishedLoading];

		// The subclass responsibilities log and answer zero.
		OO_CHECK(SameSize([bare dimensions], 0, 0));
		OO_CHECK(SameSize([bare originalDimensions], 0, 0));
		OO_CHECK(![bare isMipMapped]);
		OO_CHECK([bare glTextureName] == 0);
		[bare apply];
#ifndef NDEBUG
		OO_CHECK(![bare cxx_name].has_value());
		OO_CHECK([bare dataSize] == 0);
#endif
		OO_CHECK(oo::DescriptionOf(bare).starts_with("<BareTexture 0x"));
	}
}


OO_TEST(subclassOverrides)
{
	@autoreleasepool
	{
		TestTexture *texture = MakeTexture(std::nullopt);
		OO_CHECK(SameSize([texture originalDimensions], 8, 4));	// the root's, from -dimensions
		OO_CHECK(SameSize([texture texCoordsScale], 1, 1));
		OO_CHECK([texture glTextureName] == 7 && [texture isMipMapped]);
		[texture apply];
		OO_CHECK(texture->_applies == 1);
#ifndef NDEBUG
		OO_CHECK([texture dataSize] == 42);	// 8 * 4, mip-mapped: * 4 / 3
		OO_CHECK([texture cxx_name] == std::optional<std::string>("test texture"));
		[texture setTrace:YES];
		[texture setTrace:NO];
#endif
		const std::string text = oo::DescriptionOf(texture);
		OO_CHECK(text.starts_with("<TestTexture 0x") && text.ends_with(">{test}"));
	}
}


OO_TEST(cachesKeepAndForget)
{
	ClearCache();
	const int deallocs = gTestDeallocs;
	TestTexture *texture = nil;
	OOTexture *bare = nil;
	@autoreleasepool
	{
		texture = MakeTexture(std::string("test:cache"));
		bare = [[BareTexture alloc] init];
		OO_CHECK([OOTexture cxx_existingTextureForKey:std::string("test:cache")] == texture);
		OO_CHECK([OOTexture cxx_existingTextureForKey:std::nullopt] == nil);
		OO_CHECK([OOTexture cxx_existingTextureForKey:std::string("test:none")] == nil);
	}

	// The recent textures keep it alive; the live textures find it.
	OO_CHECK(gTestDeallocs == deallocs);
	OO_CHECK([OOTexture cxx_existingTextureForKey:std::string("test:cache")] == texture);
#ifndef NDEBUG
	@autoreleasepool
	{
		OO_CHECK(Contains([OOTexture cxx_cachedTexturesByAge], texture));
		OO_CHECK(!Contains([OOTexture cxx_cachedTexturesByAge], bare));	// no key: not cached
		const std::vector<oo::ObjCRef<OOTexture *>> all = [OOTexture cxx_allTextures];
		OO_CHECK(Contains(all, texture) && Contains(all, bare));
	}
#endif

	// Clearing forgets both caches, and releases what only they kept.
	@autoreleasepool
	{
		oo::AutoreleaseScope scope;
		[OOTexture clearCache];
		OO_CHECK([OOTexture cxx_existingTextureForKey:std::string("test:cache")] == nil);
	}
	OO_CHECK(gTestDeallocs == deallocs + 1);
#ifndef NDEBUG
	@autoreleasepool
	{
		OO_CHECK([OOTexture cxx_cachedTexturesByAge].empty());
		const std::vector<oo::ObjCRef<OOTexture *>> all = [OOTexture cxx_allTextures];
		OO_CHECK(Contains(all, bare));
		OO_CHECK(std::none_of(all.begin(), all.end(), [](const oo::ObjCRef<OOTexture *> &t) { return [t.get() isKindOfClass:[TestTexture class]]; }));
	}
#endif
	[bare release];
}


OO_TEST(rebindAllTextures)
{
	const int deallocs = gTestDeallocs;
	@autoreleasepool
	{
		TestTexture *cached = MakeTexture(std::string("test:rebind"));
		TestTexture *plain = MakeTexture(std::nullopt);
		[OOTexture rebindAllTextures];
		OO_CHECK(cached->_rebinds == 1 && plain->_rebinds == 1);

		// The recent textures are dropped; the live textures still find it while it lives.
		OO_CHECK([OOTexture cxx_existingTextureForKey:std::string("test:rebind")] == cached);
#ifndef NDEBUG
		OO_CHECK([OOTexture cxx_cachedTexturesByAge].empty());
#endif
	}
	OO_CHECK(gTestDeallocs == deallocs + 2);
	OO_CHECK([OOTexture cxx_existingTextureForKey:std::string("test:rebind")] == nil);
}


OO_TEST(namedTextureFromTheCache)
{
	OO_CHECK(OOTestGLContext());
	@autoreleasepool
	{
		OO_CHECK([OOTexture cxx_textureWithName:std::nullopt inFolder:std::string("Textures")] == nil);

		// Linear filtering: no anisotropy and no LOD bias in the key, whatever the extensions.
		const std::string key = OOGenerateTextureCacheKey(std::string("Textures"), "test.png", kOOTextureMinFilterLinear | kOOTextureMagFilterLinear, 0.5f, -0.25f);
		OO_CHECK(key == "Textures/test.png:0x0006/0/0");
		TestTexture *texture = MakeTexture(key);

		OO_CHECK([OOTexture cxx_textureWithName:std::string("test.png")
									   inFolder:std::string("Textures")
										options:kOOTextureMinFilterLinear | kOOTextureMagFilterLinear | kOOTextureNoFNFMessage
									 anisotropy:kOOTextureDefaultAnisotropy
										lodBias:kOOTextureDefaultLODBias] == texture);
		OO_CHECK([OOTexture cxx_textureWithConfiguration:oo::PList(oo::PList::Dict{ { "name", oo::PList("test.png") }, { "min_filter", oo::PList("linear") } })] == texture);
		OO_CHECK([OOTexture cxx_textureWithConfiguration:oo::PList(oo::PList::Dict{ { "name", oo::PList("test.png") } }) extraOptions:kOOTextureMinFilterLinear] == texture);

		// A specifier that names no texture.
		OO_CHECK([OOTexture cxx_textureWithConfiguration:oo::PList(oo::PList::Dict{ { "min_filter", oo::PList("linear") } })] == nil);
		OO_CHECK([OOTexture cxx_textureWithConfiguration:oo::PList(3.0)] == nil);
		OO_CHECK([OOTexture cxx_textureWithConfiguration:oo::PList()] == nil);
		ClearCache();
	}
}


OO_TEST(texturesFromGenerators)
{
	@autoreleasepool
	{
		ClearCache();
		OO_CHECK([OOTexture textureWithGenerator:nil] == nil);
		TestGenerator *refusing = MakeGenerator(std::string("test:refused"), NO);
		OO_CHECK([OOTexture textureWithGenerator:refusing] == nil && refusing->_enqueues == 1);

		TestGenerator *generator = MakeGenerator(std::string("test:gen"), YES);
		OOTexture *first = [OOTexture textureWithGenerator:generator];
		OO_CHECK((dynamic_cast<OOConcreteTexture *>(oo::ToCxx(first)) != nullptr) && generator->_enqueues == 1);
		OO_CHECK([first cxx_cacheKey] == std::optional<std::string>("test:gen"));
		OO_CHECK([OOTexture cxx_existingTextureForKey:std::string("test:gen")] == first);

		// Cached: the same texture, not queued again; unless the caller forces a new one.
		OO_CHECK([OOTexture textureWithGenerator:generator] == first && generator->_enqueues == 1);
		OOTexture *second = [OOTexture textureWithGenerator:generator enqueue:YES];
		OO_CHECK(second != nil && second != first && generator->_enqueues == 2);
		OO_CHECK([OOTexture cxx_existingTextureForKey:std::string("test:gen")] == second);

		// No key: never cached.
		TestGenerator *uncached = MakeGenerator(std::nullopt, YES);
		OOTexture *a = [OOTexture textureWithGenerator:uncached];
		OOTexture *b = [OOTexture textureWithGenerator:uncached];
		OO_CHECK(a != nil && b != nil && a != b && uncached->_enqueues == 2);
	}

	/*	The first texture's -dealloc (when the recent textures replaced it and the pool drained)
		uncached its key from the live textures, although the second texture had it by then.
	*/
	OO_CHECK([OOTexture cxx_existingTextureForKey:std::string("test:gen")] == nil);
	ClearCache();
}


OO_TEST(nullTexture)
{
	OO_CHECK(OOTestGLContext());
	@autoreleasepool
	{
		OOTexture *none = [OOTexture nullTexture];
		OO_CHECK(dynamic_cast<OONullTexture *>(oo::ToCxx(none)) != nullptr && none == [OOTexture nullTexture]);	// was -isKindOfClass: of the facade bead oo-9ht.100 deleted
		OO_CHECK(SameSize([none dimensions], 0, 0) && ![none isMipMapped]);
#ifndef NDEBUG
		OO_CHECK([none cxx_name] == std::optional<std::string>("<null texture>"));
#endif
		[none forceRebind];

		// Applying it is applying none.
		GLuint name = 0;
		glGenTextures(1, &name);
		glBindTexture(GL_TEXTURE_2D, name);
		[none apply];
		GLint bound = -1;
		glGetIntegerv(GL_TEXTURE_BINDING_2D, &bound);
		OO_CHECK(bound == 0);
		glDeleteTextures(1, &name);
	}
}


OO_TEST(applyNone)
{
	OO_CHECK(OOTestGLContext());
	GLuint name = 0;
	glGenTextures(1, &name);
	glBindTexture(GL_TEXTURE_2D, name);
	GLint bound = -1;
	glGetIntegerv(GL_TEXTURE_BINDING_2D, &bound);
	OO_CHECK(bound == (GLint)name);
	[OOTexture applyNone];
	glGetIntegerv(GL_TEXTURE_BINDING_2D, &bound);
	OO_CHECK(bound == 0);
	glDeleteTextures(1, &name);
}


// --- The C++ API and the crossing (after the conversion) -------------------------------------

// A converted texture, as OOConcreteTexture will be one: a C++ subclass, cached under its key.
// Global, so its facade prints its name as a global class's.
class TestCxxTexture final : public cxx::OOTexture
{
public:
	explicit TestCxxTexture(std::optional<std::string> key) : _key(std::move(key))  { addToCaches(); }
	~TestCxxTexture() override  { removeFromCaches(); }

	void apply() override												{ applies++; }
	NSSize dimensions() override										{ return NSMakeSize(16, 2); }
	bool isMipMapped() override											{ return false; }
	void forceRebind() override											{ rebinds++; }
	std::optional<std::string> cacheKey() override						{ return _key; }
	GLint glTextureName() override										{ return 9; }
	std::optional<std::string> descriptionComponents() const override	{ return std::string("cxx"); }

	int applies = 0;
	int rebinds = 0;

private:
	std::optional<std::string> _key;
};


OO_TEST(cxxApi)
{
	ClearCache();
	@autoreleasepool
	{
		// The factories answer the Objective-C texture, retained.
		OO_CHECK(!cxx::OOTexture::textureWithName(std::nullopt, std::string("Textures")));
		const oo::ObjCRef<OOTexture *> none = cxx::OOTexture::nullTexture();
		OO_CHECK(dynamic_cast<OONullTexture *>(oo::ToCxx(none.get())) != nullptr && none.get() == [OOTexture nullTexture]);
		TestGenerator *generator = MakeGenerator(std::string("test:cxxgen"), YES);
		const oo::ObjCRef<OOTexture *> generated = cxx::OOTexture::textureWithGenerator(generator);
		OO_CHECK((dynamic_cast<OOConcreteTexture *>(oo::ToCxx(generated.get())) != nullptr));
		OO_CHECK(cxx::OOTexture::existingTextureForKey(std::string("test:cxxgen")) == oo::ToCxx(generated.get()));
		OO_CHECK(cxx::OOTexture::textureWithGenerator(generator, false) == generated && generator->_enqueues == 1);
		OO_CHECK(!cxx::OOTexture::textureWithConfiguration(oo::PList(3.0)));
		OO_CHECK(cxx::OOTexture::existingTextureForKey(std::nullopt) == nullptr);
		ClearCache();
	}

	// The root's own answers.
	const oo::Ref<cxx::OOTexture> root = oo::makeRef<cxx::OOTexture>();
	OO_CHECK(root->isFinishedLoading() && !root->cacheKey().has_value());
	OO_CHECK(SameSize(root->dimensions(), 0, 0) && SameSize(root->originalDimensions(), 0, 0));
	OO_CHECK(SameSize(root->texCoordsScale(), 1, 1) && !root->isMipMapped() && root->glTextureName() == 0);
	OO_CHECK(!root->isRectangleTexture() && !root->isCubeMap() && OOIsNullPixMap(root->copyPixMapRepresentation()));
	OO_CHECK(!root->descriptionComponents().has_value());
	root->apply();
	root->ensureFinishedLoading();
	root->forceRebind();
#ifndef NDEBUG
	OO_CHECK(!root->name().has_value() && root->dataSize() == 0);
#endif
}


OO_TEST(cxxTextureBehindTheFacade)
{
	const int deallocs = gTestDeallocs;
	@autoreleasepool
	{
		const oo::Ref<TestCxxTexture> texture = oo::makeRef<TestCxxTexture>(std::string("test:cxx"));
		OOTexture *facade = oo::ToObjC(texture.get());
		OO_CHECK(facade != nil && facade == oo::ToObjC(texture.get()));	// one live facade
		OO_CHECK(oo::ToCxx(facade) == texture.get());

		// The callers' messages reach the C++ overrides, and the root's defaults.
		OO_CHECK(SameSize([facade dimensions], 16, 2) && SameSize([facade originalDimensions], 16, 2));
		OO_CHECK([facade glTextureName] == 9 && ![facade isMipMapped] && [facade isFinishedLoading]);
		OO_CHECK([facade cxx_cacheKey] == std::optional<std::string>("test:cxx"));
		[facade apply];
		OO_CHECK(texture->applies == 1);
#ifndef NDEBUG
		OO_CHECK([facade dataSize] == 32);
#endif
		const std::string text = oo::DescriptionOf(facade);
		OO_CHECK(text.starts_with("<TestCxxTexture 0x") && text.ends_with(">{cxx}"));

		// The caches hold it: by key, its facade; a graphics reset reaches it.
		OO_CHECK([OOTexture cxx_existingTextureForKey:std::string("test:cxx")] == facade);
		[OOTexture rebindAllTextures];
		OO_CHECK(texture->rebinds == 1);
#ifndef NDEBUG
		@autoreleasepool
		{
			OO_CHECK(Contains([OOTexture cxx_allTextures], facade));
		}
#endif
	}
	ClearCache();
	OO_CHECK([OOTexture cxx_existingTextureForKey:std::string("test:cxx")] == nil);	// destroyed: uncached
	OO_CHECK(gTestDeallocs == deallocs);
}


OO_TEST(objCTextureBehindACxxPointer)
{
	@autoreleasepool
	{
		TestTexture *objCTexture = MakeTexture(std::string("test:objc"));
		cxx::OOTexture *part = oo::ToCxx(objCTexture);
		OO_CHECK(part != nullptr && oo::ToObjC(part) == objCTexture);	// the object itself
		OO_CHECK(cxx::OOTexture::existingTextureForKey(std::string("test:objc")) == part);

		// Virtual calls from C++ reach the Objective-C overrides; the root answers the rest.
		OO_CHECK(SameSize(part->dimensions(), 8, 4) && SameSize(part->originalDimensions(), 8, 4));
		OO_CHECK(part->isMipMapped() && part->glTextureName() == 7);
		OO_CHECK(part->cacheKey() == std::optional<std::string>("test:objc"));
		OO_CHECK(part->descriptionComponents() == std::optional<std::string>("test"));
		part->apply();
		part->forceRebind();
		OO_CHECK(objCTexture->_applies == 1 && objCTexture->_rebinds == 1);
		OO_CHECK(part->isFinishedLoading() && !part->isCubeMap() && SameSize(part->texCoordsScale(), 1, 1));
#ifndef NDEBUG
		OO_CHECK(part->name() == std::optional<std::string>("test texture") && part->dataSize() == 42);
#endif

		cxx::OOTexture *bare = oo::ToCxx([[[BareTexture alloc] init] autorelease]);
		OO_CHECK(SameSize(bare->dimensions(), 0, 0) && bare->glTextureName() == 0 && !bare->cacheKey().has_value());
		ClearCache();
	}
}


OO_TEST(nilAndLifetime)
{
	OOTexture *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOTexture *>(nullptr)) == nil);
	OO_CHECK([OOTexture cxx_existingTextureForKey:std::string("test:nothing")] == nil);
	OO_CHECK(SameSize([none dimensions], 0, 0) && [none glTextureName] == 0);

	// An Objective-C texture's C++ part outlives it, and then answers as nil did.
	oo::Ref<cxx::OOTexture> part;
	@autoreleasepool
	{
		part = oo::Ref<cxx::OOTexture>(oo::ToCxx([[[TestTexture alloc] initWithKey:std::nullopt] autorelease]));
	}
	OO_CHECK(SameSize(part->dimensions(), 0, 0) && part->glTextureName() == 0 && !part->isMipMapped());
	OO_CHECK(!part->cacheKey().has_value() && !part->isFinishedLoading());
	OO_CHECK(oo::ToObjC(part) == nil);
#ifndef NDEBUG
	@autoreleasepool
	{
		const std::vector<oo::ObjCRef<OOTexture *>> all = [OOTexture cxx_allTextures];
		OO_CHECK(std::none_of(all.begin(), all.end(), [](const oo::ObjCRef<OOTexture *> &t) { return t.get() == nil; }));
	}
#endif
	part->forceRebind();	// nothing: its object has gone
}


OO_TEST_MAIN()
