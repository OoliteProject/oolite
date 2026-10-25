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
	asked through it ask the same object as Objective-C now gets it: OOTexture::nullTexture(), the
	root's facade of the C++ null texture, which OOTexture keeps for the process as
	+sharedNullTexture kept its facade; -isKindOfClass: of the deleted class is a dynamic_cast of
	the C++ texture. The facade's own case (facade) was retired with it (ADR-0049, standing
	approval oo-9n5p9). Bead oo-9ht.99 deleted the root's facade too: the cases call the C++
	texture OOTexture::nullTexture() answers, and nullTextureCrossesAsTheRootFacade (the crossing)
	went with it (oo-9n5p9).
	Run: bash tools/check-core-tests.sh
*/

#include "OONullTexture.h"
#include "OOTextureInternal.h"
#include "OODescription.h"

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
	{
		OOTexture *shared = OOTexture::nullTexture().get();
		OO_CHECK(shared != nullptr && shared == OOTexture::nullTexture().get());
		OO_CHECK(shared == OOTexture::nullTexture().get());
		OO_CHECK(dynamic_cast<OONullTexture *>(shared) != nullptr);
	}
	// It outlives the pools it was handed out in.
	{
		OO_CHECK(OOTexture::nullTexture().get() == OONullTexture::sharedNullTexture());
	}
}


OO_TEST(answersAsAnEmptyTexture)
{
	{
		OOTexture *none = OOTexture::nullTexture().get();
		OO_CHECK(SameSize(none->dimensions(), 0, 0) && SameSize(none->originalDimensions(), 0, 0));
		OO_CHECK(!none->isMipMapped());
		OO_CHECK(none->isFinishedLoading() && !none->cacheKey().has_value());
		OO_CHECK(!none->isRectangleTexture() && !none->isCubeMap());
		OO_CHECK(SameSize(none->texCoordsScale(), 1, 1));
		OO_CHECK(OOIsNullPixMap(none->copyPixMapRepresentation()));
		none->ensureFinishedLoading();
		none->forceRebind();		// nothing to rebind
#ifndef NDEBUG
		OO_CHECK(none->name() == std::optional<std::string>("<null texture>"));
		OO_CHECK(none->dataSize() == 0);
#endif
		OO_CHECK(none->description().starts_with("<OONullTexture 0x"));
	}
}


OO_TEST(applyingBindsNoTexture)
{
	OO_CHECK(OOTestGLContext());
	{
		GLuint name = 0;
		glGenTextures(1, &name);
		glBindTexture(GL_TEXTURE_2D, name);
		OO_CHECK(BoundTexture() == (GLint)name);
		OOTexture::nullTexture()->apply();
		OO_CHECK(BoundTexture() == 0);
		glDeleteTextures(1, &name);
	}
}


OO_TEST(graphicsResetLeavesItAlone)
{
	OO_CHECK(OOTestGLContext());
	{
		OOTexture *shared = OOTexture::nullTexture().get();
		OOTexture::rebindAllTextures();
		OO_CHECK(OOTexture::nullTexture().get() == shared);
		OO_CHECK(SameSize(shared->dimensions(), 0, 0));
	}
}


// --- The C++ API (after the conversion) ---------------------------------------------------------

OO_TEST(cxxApi)
{
	OO_CHECK(OOTestGLContext());
	OONullTexture *none = OONullTexture::sharedNullTexture();
	OO_CHECK(none != nullptr && none == OONullTexture::sharedNullTexture());

	// Through the root's virtual members, as the materials call a texture.
	OOTexture *texture = none;
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


OO_TEST_MAIN()
