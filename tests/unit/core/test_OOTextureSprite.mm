/*	test_OOTextureSprite.mm
	Unit tests for cxx::OOTextureSprite (src/Core/OOTextureSprite.h) and its Objective-C facade: bead oo-ljhc (Phase 3, house
	style of proposed ADR-0056).

	A texture sprite is a texture and a size; its only output is the textured quad it hands to
	OpenGL. The test captures that quad in feedback mode (GL_FEEDBACK, GL_3D_COLOR_TEXTURE) on the
	hidden context of oo_gl_test_context.hpp, so nothing is rasterised and no pixel is read: each
	corner's window position, colour and texture coordinate, for the plain, centred and background
	blits, with the alpha clamped to [0, 1]; that the texture is applied once per blit, that 2D
	texturing is off again afterwards, and that the background blit leaves the size as it found it.
	The sprite's texture is a stand-in OOTexture defined here (amendment oo-z1s4 item 4), which
	answers its original dimensions and counts -apply; the extension manager runs with its
	collaborators stubbed as in test_OOOpenGLStateManager. The expectations were written against
	the Objective-C API and run on the unconverted class first; that API is now the facade
	(OOTextureSprite+ObjCBridge.h), so they run through it, and the last tests pin the C++ API
	(cxx::OOTextureSprite) and the facade's contract.
	Run: bash tools/check-core-tests.sh
*/

#import "OOTextureSprite.h"
#import "OOOpenGLExtensionManager.h"

#include "oo_test.hpp"
#include "oo_gl_test_context.hpp"
#include "oofnd/PList.hpp"

#include <cmath>
#include <cstdio>
#include <string>
#include <vector>


// --- Stubs --------------------------------------------------------------------------------------

@interface ResourceManager: OOObject
+ (std::vector<std::string>) cxx_paths;
+ (oo::PList) cxx_dictionaryFromFilesNamed:(const std::string &)fileName inFolder:(const std::string &)folderName andMerge:(BOOL)mergeFiles;
@end

@implementation ResourceManager
+ (std::vector<std::string>) cxx_paths  { return {}; }
+ (oo::PList) cxx_dictionaryFromFilesNamed:(const std::string &)fileName inFolder:(const std::string &)folderName andMerge:(BOOL)mergeFiles  { return oo::PList(oo::PList::Dict{}); }
@end


@interface OORegExpMatcher: OOObject
+ (instancetype) regExpMatcher;
- (BOOL) string:(const std::string &)string matchesExpression:(const std::string &)regExp;
@end

@implementation OORegExpMatcher
+ (instancetype) regExpMatcher  { return [[[self alloc] init] autorelease]; }
- (BOOL) string:(const std::string &)string matchesExpression:(const std::string &)regExp  { return NO; }
@end


OOShaderSetting cxx_OOShaderSettingFromString(const std::string &string)
{
	return string == "SHADERS_FULL" ? SHADERS_FULL : SHADERS_NOT_SUPPORTED;
}


// OOLogging.mm's (it would bring the resource manager into the link); only the state dump uses them.
void OOLogIndent(void)  {}
void OOLogOutdent(void)  {}


// The sprite's texture: its original dimensions, and how often it was applied.
@interface OOTexture: OOObject
{
@public
	NSSize		_dimensions;
	unsigned	_applied;
}
- (NSSize) originalDimensions;
- (void) apply;
@end

@implementation OOTexture
- (NSSize) originalDimensions  { return _dimensions; }
- (void) apply  { _applied++; }
@end


// --- Helpers ------------------------------------------------------------------------------------

namespace {

OOTexture *Texture(float width, float height)
{
	OOTexture *texture = [[[OOTexture alloc] init] autorelease];
	texture->_dimensions = NSMakeSize(width, height);
	return texture;
}


// The window box of the feedback projection: object x, y in [-kHalf, kHalf], z in [-kDepth, kDepth].
constexpr double kHalf = 1024.0;
constexpr double kDepth = 1.0e6;


struct Vertex
{
	double x, y, z;		// window coordinates
	double alpha;
	double s, t;		// texture coordinates
};


// Where an object-space point lands in the 16x16 window under the feedback projection.
Vertex Expect(double x, double y, double z, double alpha, double s, double t)
{
	return Vertex{ (x / kHalf + 1.0) * 8.0, (y / kHalf + 1.0) * 8.0, (-z / kDepth + 1.0) / 2.0, alpha, s, t };
}


bool Near(double a, double b)
{
	return std::fabs(a - b) <= 1.0e-3 * (1.0 + std::fabs(b));
}


bool Same(const Vertex &a, const Vertex &b)
{
	return Near(a.x, b.x) && Near(a.y, b.y) && Near(a.z, b.z) && Near(a.alpha, b.alpha) && Near(a.s, b.s) && Near(a.t, b.t);
}


// Runs draw in feedback mode and answers the vertices of every polygon it handed to OpenGL. A quad
// may come back as one polygon or as two triangles, so the caller compares the distinct vertices.
template <typename Draw>
std::vector<Vertex> Feedback(Draw draw)
{
	static GLfloat buffer[4096];

	glViewport(0, 0, 16, 16);
	glMatrixMode(GL_PROJECTION);
	glLoadIdentity();
	glOrtho(-kHalf, kHalf, -kHalf, kHalf, -kDepth, kDepth);
	glMatrixMode(GL_MODELVIEW);
	glLoadIdentity();

	glFeedbackBuffer(sizeof buffer / sizeof *buffer, GL_3D_COLOR_TEXTURE, buffer);
	glRenderMode(GL_FEEDBACK);
	draw();
	GLint count = glRenderMode(GL_RENDER);

	std::vector<Vertex> vertices;
	for (GLint i = 0; i < count; )
	{
		GLint token = (GLint)buffer[i++];
		if (token == GL_POLYGON_TOKEN)
		{
			GLint n = (GLint)buffer[i++];
			for (GLint v = 0; v < n; v++, i += 11)
			{
				// x y z, r g b a, s t r q
				Vertex vertex{ buffer[i], buffer[i + 1], buffer[i + 2], buffer[i + 6], buffer[i + 7], buffer[i + 8] };
				bool seen = false;
				for (const Vertex &old : vertices)  seen = seen || Same(old, vertex);
				if (!seen)  vertices.push_back(vertex);
			}
		}
		else if (token == GL_PASS_THROUGH_TOKEN)  i += 1;
		else if (token == GL_POINT_TOKEN || token == GL_BITMAP_TOKEN || token == GL_DRAW_PIXEL_TOKEN || token == GL_COPY_PIXEL_TOKEN)  i += 11;
		else if (token == GL_LINE_TOKEN || token == GL_LINE_RESET_TOKEN)  i += 22;
		else
		{
			std::fprintf(stderr, "unexpected feedback token %d\n", token);
			break;
		}
	}
	return vertices;
}


// The quad of a blit to (x, y, z) of size (w, h): ACW from the top left, the texture upside down.
bool IsQuad(const std::vector<Vertex> &vertices, double x, double y, double z, double w, double h, double alpha)
{
	const Vertex corners[4] =
	{
		Expect(x, y + h, z, alpha, 0.0, 0.0),
		Expect(x, y, z, alpha, 0.0, 1.0),
		Expect(x + w, y, z, alpha, 1.0, 1.0),
		Expect(x + w, y + h, z, alpha, 1.0, 0.0),
	};
	bool ok = vertices.size() == 4;
	for (const Vertex &corner : corners)
	{
		bool found = false;
		for (const Vertex &v : vertices)  found = found || Same(v, corner);
		ok = ok && found;
	}
	if (!ok)
	{
		std::fprintf(stderr, "quad at (%g, %g, %g) size (%g, %g) alpha %g; got %zu vertices:\n", x, y, z, w, h, alpha, vertices.size());
		for (const Vertex &v : vertices)  std::fprintf(stderr, "  (%g, %g, %g) a=%g st=(%g, %g)\n", v.x, v.y, v.z, v.alpha, v.s, v.t);
	}
	return ok;
}


bool GLReady()
{
	if (!OOTestGLContext())  return false;
	(void)[OOOpenGLExtensionManager sharedManager];	// loads glActiveTextureARB & co. for the state manager
	return true;
}

}	// namespace


// --- Tests --------------------------------------------------------------------------------------

OO_TEST(noTextureNoSprite)
{
	@autoreleasepool
	{
		OO_CHECK([[OOTextureSprite alloc] initWithTexture:nil] == nil);
		OO_CHECK([[OOTextureSprite alloc] initWithTexture:nil size:NSMakeSize(4, 4)] == nil);
	}
}


OO_TEST(sizeIsTheTexturesOrGiven)
{
	@autoreleasepool
	{
		OOTextureSprite *sprite = [[[OOTextureSprite alloc] initWithTexture:Texture(64, 32)] autorelease];
		OO_CHECK(sprite != nil);
		OO_CHECK([sprite size].width == 64 && [sprite size].height == 32);

		sprite = [[[OOTextureSprite alloc] initWithTexture:Texture(64, 32) size:NSMakeSize(10, 20)] autorelease];
		OO_CHECK([sprite size].width == 10 && [sprite size].height == 20);
	}
}


OO_TEST(spriteKeepsItsTexture)
{
	OOTextureSprite *sprite = nil;
	OOTexture *texture = nil;
	@autoreleasepool
	{
		texture = Texture(8, 8);
		sprite = [[OOTextureSprite alloc] initWithTexture:texture];
		[texture retain];
	}
	OO_CHECK([texture retainCount] == 2);	// the test's and the sprite's
	[sprite release];
	OO_CHECK([texture retainCount] == 1);
	[texture release];
}


OO_TEST(blitDrawsTheTexturedQuad)
{
	OO_CHECK(GLReady());
	@autoreleasepool
	{
		OOTexture *texture = Texture(64, 32);
		OOTextureSprite *sprite = [[[OOTextureSprite alloc] initWithTexture:texture size:NSMakeSize(100, 50)] autorelease];

		std::vector<Vertex> quad = Feedback([&] { [sprite blitToX:10 Y:-20 Z:30 alpha:0.25f]; });
		OO_CHECK(IsQuad(quad, 10, -20, 30, 100, 50, 0.25));
		OO_CHECK(texture->_applied == 1);
		OO_CHECK(!glIsEnabled(GL_TEXTURE_2D));
		OO_CHECK(glIsEnabled(GL_BLEND));	// the overlay state
		OO_CHECK(glGetError() == GL_NO_ERROR);

		// The alpha is clamped to [0, 1].
		OO_CHECK(IsQuad(Feedback([&] { [sprite blitToX:0 Y:0 Z:0 alpha:1.5f]; }), 0, 0, 0, 100, 50, 1.0));
		OO_CHECK(IsQuad(Feedback([&] { [sprite blitToX:0 Y:0 Z:0 alpha:-1.0f]; }), 0, 0, 0, 100, 50, 0.0));
		OO_CHECK(texture->_applied == 3);
	}
}


OO_TEST(centredBlits)
{
	OO_CHECK(GLReady());
	@autoreleasepool
	{
		OOTexture *texture = Texture(64, 32);
		OOTextureSprite *sprite = [[[OOTextureSprite alloc] initWithTexture:texture size:NSMakeSize(1.5, 0.75)] autorelease];

		OO_CHECK(IsQuad(Feedback([&] { [sprite blitCentredToX:100 Y:200 Z:-5 alpha:0.5f]; }), 100 - 0.75, 200 - 0.375, -5, 1.5, 0.75, 0.5));

		// The background blit scales the size and z by 512 (so that it is behind the ships), and
		// puts the size back afterwards.
		OO_CHECK(IsQuad(Feedback([&] { [sprite blitBackgroundCentredToX:1 Y:-2 Z:3 alpha:1.0f]; }), 1 - 384, -2 - 192, 3 * 512, 768, 384, 1.0));
		OO_CHECK([sprite size].width == 1.5 && [sprite size].height == 0.75);
		OO_CHECK(texture->_applied == 2);
		OO_CHECK(glGetError() == GL_NO_ERROR);
	}
}


// --- The C++ class and the facade's contract (after the conversion) ------------------------------

OO_TEST(cxxSprite)
{
	OO_CHECK(GLReady());
	@autoreleasepool
	{
		OO_CHECK(cxx::OOTextureSprite::initWithTexture(nil).get() == nullptr);
		OO_CHECK(cxx::OOTextureSprite::initWithTexture(nil, NSMakeSize(4, 4)).get() == nullptr);

		OOTexture *texture = Texture(64, 32);
		oo::Ref<cxx::OOTextureSprite> sprite = cxx::OOTextureSprite::initWithTexture(texture);
		OO_CHECK(sprite.get() != nullptr && sprite->getSize().width == 64 && sprite->getSize().height == 32);

		sprite = cxx::OOTextureSprite::initWithTexture(texture, NSMakeSize(100, 50));
		OO_CHECK(IsQuad(Feedback([&] { sprite->blitToX(10, -20, 30, 0.25f); }), 10, -20, 30, 100, 50, 0.25));
		OO_CHECK(IsQuad(Feedback([&] { sprite->blitCentredToX(0, 0, 0, 1.0f); }), -50, -25, 0, 100, 50, 1.0));
		OO_CHECK(sprite->getSize().width == 100 && sprite->getSize().height == 50);

		sprite = cxx::OOTextureSprite::initWithTexture(texture, NSMakeSize(1.5, 0.75));
		OO_CHECK(IsQuad(Feedback([&] { sprite->blitBackgroundCentredToX(1, -2, 3, 1.0f); }), 1 - 384, -2 - 192, 3 * 512, 768, 384, 1.0));
		OO_CHECK(sprite->getSize().width == 1.5 && sprite->getSize().height == 0.75);
		OO_CHECK(texture->_applied == 3);
	}
}


OO_TEST(facadeNilStaysNil)
{
	OOTextureSprite *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOTextureSprite *>(nullptr)) == nil);
	[none blitToX:0 Y:0 Z:0 alpha:1.0f];	// nothing, as a message to nil did
}


OO_TEST(facadeIdentity)
{
	@autoreleasepool
	{
		OOTextureSprite *made = [[[OOTextureSprite alloc] initWithTexture:Texture(8, 8)] autorelease];
		OO_CHECK(oo::ToCxx(made) != nullptr && oo::ToObjC(oo::ToCxx(made)) == made);

		oo::Ref<cxx::OOTextureSprite> sprite = cxx::OOTextureSprite::initWithTexture(Texture(8, 4));
		OOTextureSprite *facade = oo::ToObjC(sprite);
		OO_CHECK(facade != nil && facade == oo::ToObjC(sprite.get()));
		OO_CHECK(oo::ToCxx(facade) == sprite.get());
		OO_CHECK([facade size].width == 8 && [facade size].height == 4);
	}
}


OO_TEST_MAIN()
