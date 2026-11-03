/*	test_OONullTexture.mm
	Unit tests for OONullTexture (src/Core/Materials/OONullTexture.h), the texture that applies no
	texture: bead oo-jvm6 (Phase 3, house style of proposed ADR-0056; a leaf of the textures root,
	amendment oo-whzh).

	The null texture is a process-wide singleton that OOTexture's +nullTexture answers. It links
	the whole game but main (tests/unit/core/meson.build entry ['*']), on the hidden GL context of
	oo_gl_test_context.hpp, because applying it unbinds the current texture. The expectations were
	written against the Objective-C API and run on the unconverted class first: one shared
	instance, what it answers as a texture (no size, not mip-mapped, the root's defaults), that
	applying it binds no texture, that a graphics reset leaves it alone, and its debug name (commit
	dc5b2aff6). That API then became the facade, and the last tests
	pinned the C++ API and the facade's contract.

	Bead oo-9ht.100 deleted the facade (ADR-0056 amendment "deleting a facade"). The cases that
	asked through it ask the same object as Objective-C now gets it: [OOTexture nullTexture], the
	root's facade of the C++ null texture, which OOTexture keeps for the process as
	+sharedNullTexture kept its facade; -isKindOfClass: of the deleted class is a dynamic_cast of
	the C++ texture. The facade's own case (facade) was retired with it (ADR-0049, standing
	approval oo-9n5p9); nullTextureCrossesAsTheRootFacade pins the crossing now.
	Run: bash tools/check-core-tests.sh
*/

#import "OONullTexture.h"
#import "OOTextureInternal.h"
#import "OODescription.h"

#include "oo_test.hpp"
#include "oo_gl_test_context.hpp"


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


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

}	// namespace


OO_TEST(oneSharedInstance)
{
	@autoreleasepool
	{
		OOTexture *shared = [OOTexture nullTexture];
		OO_CHECK(shared != nil && shared == [OOTexture nullTexture]);
		OO_CHECK(shared == cxx::OOTexture::nullTexture().get());
		OO_CHECK([shared isKindOfClass:[OOTexture class]] && dynamic_cast<OONullTexture *>(oo::ToCxx(shared)) != nullptr);
	}
	// It outlives the pools it was handed out in.
	@autoreleasepool
	{
		OO_CHECK(oo::ToCxx(static_cast<OOTexture *>([OOTexture nullTexture])) == OONullTexture::sharedNullTexture());
	}
}


OO_TEST(answersAsAnEmptyTexture)
{
	@autoreleasepool
	{
		OOTexture *none = [OOTexture nullTexture];
		OO_CHECK(SameSize([none dimensions], 0, 0) && SameSize([none originalDimensions], 0, 0));
		OO_CHECK(![none isMipMapped]);
		OO_CHECK([none isFinishedLoading] && ![none cxx_cacheKey].has_value());
		OO_CHECK(![none isRectangleTexture] && ![none isCubeMap]);
		OO_CHECK(SameSize([none texCoordsScale], 1, 1));
		OO_CHECK(OOIsNullPixMap([none copyPixMapRepresentation]));
		[none ensureFinishedLoading];
		[none forceRebind];		// nothing to rebind
#ifndef NDEBUG
		OO_CHECK([none cxx_name] == std::optional<std::string>("<null texture>"));
		OO_CHECK([none dataSize] == 0);
#endif
		OO_CHECK(oo::DescriptionOf(none).starts_with("<OONullTexture 0x"));
	}
}


OO_TEST(applyingBindsNoTexture)
{
	OO_CHECK(OOTestGLContext());
	@autoreleasepool
	{
		GLuint name = 0;
		glGenTextures(1, &name);
		glBindTexture(GL_TEXTURE_2D, name);
		OO_CHECK(BoundTexture() == (GLint)name);
		[[OOTexture nullTexture] apply];
		OO_CHECK(BoundTexture() == 0);
		glDeleteTextures(1, &name);
	}
}


OO_TEST(graphicsResetLeavesItAlone)
{
	OO_CHECK(OOTestGLContext());
	@autoreleasepool
	{
		OOTexture *shared = [OOTexture nullTexture];
		[OOTexture rebindAllTextures];
		OO_CHECK([OOTexture nullTexture] == shared);
		OO_CHECK(SameSize([shared dimensions], 0, 0));
	}
}


// --- The C++ API and the facade (after the conversion) ---------------------------------------

OO_TEST(cxxApi)
{
	OO_CHECK(OOTestGLContext());
	OONullTexture *none = OONullTexture::sharedNullTexture();
	OO_CHECK(none != nullptr && none == OONullTexture::sharedNullTexture());

	// Through the root's virtual members, as the materials call a texture.
	cxx::OOTexture *texture = none;
	OO_CHECK(SameSize(texture->dimensions(), 0, 0) && SameSize(texture->originalDimensions(), 0, 0));
	OO_CHECK(!texture->isMipMapped() && texture->isFinishedLoading() && !texture->cacheKey().has_value());
	texture->forceRebind();
#ifndef NDEBUG
	OO_CHECK(texture->name() == std::optional<std::string>("<null texture>"));
#endif
	GLuint name = 0;
	glGenTextures(1, &name);
	glBindTexture(GL_TEXTURE_2D, name);
	texture->apply();
	OO_CHECK(BoundTexture() == 0);
	glDeleteTextures(1, &name);
}


// Objective-C sees the null texture as the root's facade of the C++ object (bead oo-9ht.100).
OO_TEST(nullTextureCrossesAsTheRootFacade)
{
	@autoreleasepool
	{
		OOTexture *facade = [OOTexture nullTexture];
		OO_CHECK([facade class] == [OOTexture class]);
		OO_CHECK(oo::ToCxx(facade) == OONullTexture::sharedNullTexture());
		OO_CHECK(oo::ToObjC(static_cast<cxx::OOTexture *>(OONullTexture::sharedNullTexture())) == facade);
		OO_CHECK(cxx::OOTexture::nullTexture().get() == facade);
	}
}


OO_TEST_MAIN()
