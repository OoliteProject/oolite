/*	test_OOCrosshairs.mm
	Unit tests for OOCrosshairs (src/Core/OOCrosshairs.h), a C++ class with no Objective-C
	facade (its one caller was adapted): bead oo-zffj (Phase 3, proposed ADR-0056).

	OOCrosshairs turns a crosshair definition (a property-list array of 6-number arrays: alpha,
	x, y of each end of a line segment) into one vertex buffer of 2 coordinates and 4 colour
	components per endpoint, and render() hands that buffer to OpenGL. The test pins the buffer:
	the scale, the colour (green when there is none), the per-point alpha clamped and scaled by
	the overall alpha, the red marker a bad entry becomes, and that nothing is built when the
	overall alpha or the colour's alpha is zero. The expectations were written against the
	Objective-C class and run on it first (reading the ivars through the runtime); the port reads
	the same members through the class's test friend, OOCrosshairsTestAccess.

	render() needs a GL context and the game (UNIVERSE, the GL state and matrix managers), which a
	unit test does not have; the test never calls it. The functions it references are defined
	below as link stubs that abort if called (ADR-0056 amendment oo-zffj), so OOCrosshairs links
	with OOColor alone. Run: bash tools/check-core-tests.sh
*/

#import "OOCrosshairs.h"
#import "OOColor.h"
#import "OOOpenGL.h"
#import "OOOpenGLMatrixManager.h"

#include "oo_test.hpp"

#include <cmath>
#include <cstdlib>
#include <vector>


// --- Link stubs: what render() references. The test never renders; a call is a test bug. -------

@class Universe;
Universe *gSharedUniverse = nil;

void OOSetOpenGLState_(OOOpenGLStateID, const char *, unsigned)	{ std::abort(); }
void OOVerifyOpenGLState_(const char *, unsigned)				{ std::abort(); }
void OOGLPushModelView(void)									{ std::abort(); }
OOMatrix OOGLPopModelView(void)									{ std::abort(); }
void OOGLTranslateModelView(Vector)								{ std::abort(); }
bool cxx_OOCheckOpenGLErrors(const char *, ...)					{ std::abort(); }


// The vertex buffer: 12 floats (x, y, r, g, b, a of each endpoint) per line segment.
struct OOCrosshairsTestAccess
{
	static std::vector<float> Buffer(OOCrosshairs *crosshairs)
	{
		if (crosshairs->_data == nullptr)  return {};
		return std::vector<float>(crosshairs->_data, crosshairs->_data + 12 * crosshairs->_count);
	}
};


namespace {

std::vector<float> Build(const oo::PList &points, float scale, OOColor *color, float alpha)
{
	return OOCrosshairsTestAccess::Buffer(oo::makeRef<OOCrosshairs>(points, scale, color, alpha).get());
}


oo::PList Segment(double a1, double x1, double y1, double a2, double x2, double y2)
{
	return oo::PList(oo::PList::Array{ a1, x1, y1, a2, x2, y2 });
}


bool Same(const std::vector<float> &actual, const std::vector<float> &expected)
{
	if (actual.size() != expected.size())  return false;
	for (size_t i = 0; i < actual.size(); i++)
	{
		if (std::fabs(actual[i] - expected[i]) > 1e-6f)  return false;
	}
	return true;
}


const std::vector<float> kRedMarker = { -0.01f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f,  0.01f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f };

}	// namespace


OO_TEST(greenWithoutAColour)
{
	oo::PList points(oo::PList::Array{ Segment(1.0, 1.0, 2.0, 0.5, 3.0, 4.0) });
	OO_CHECK(Same(Build(points, 2.0f, nullptr, 1.0f), { 2, 4, 0, 1, 0, 1,  6, 8, 0, 1, 0, 0.5f }));
}


OO_TEST(colourAndAlpha)
{
	oo::Ref<OOColor> color = OOColor::colorWithRed(0.25f, 0.5f, 0.75f, 0.5f);
	oo::PList points(oo::PList::Array{ Segment(1.0, -1.0, 0.0, 0.5, 1.0, 0.0), Segment(0.0, 0.0, -2.0, 1.0, 0.0, 2.0) });

	// Point alpha * colour alpha, clamped, then * overall alpha.
	OO_CHECK(Same(Build(points, 0.5f, color.get(), 0.5f), {
		-0.5f, 0, 0.25f, 0.5f, 0.75f, 0.25f,   0.5f, 0, 0.25f, 0.5f, 0.75f, 0.125f,
		0, -1, 0.25f, 0.5f, 0.75f, 0.0f,       0, 1, 0.25f, 0.5f, 0.75f, 0.25f }));
}


OO_TEST(alphaIsClamped)
{
	oo::PList points(oo::PList::Array{ Segment(4.0, 0.0, 0.0, -1.0, 1.0, 1.0) });
	// 4 * 1 clamps to 1 before the overall alpha, and a negative alpha to 0.
	OO_CHECK(Same(Build(points, 1.0f, nullptr, 0.75f), { 0, 0, 0, 1, 0, 0.75f,  1, 1, 0, 1, 0, 0 }));
}


OO_TEST(badEntriesAreRedMarkers)
{
	oo::PList shortEntry(oo::PList::Array{ 1.0, 2.0, 3.0, 4.0, 5.0 });
	oo::PList points(oo::PList::Array{ oo::PList("not an array"), shortEntry, Segment(1.0, 1.0, 1.0, 1.0, 2.0, 2.0) });

	std::vector<float> expected = kRedMarker;
	expected.insert(expected.end(), kRedMarker.begin(), kRedMarker.end());
	std::vector<float> good = { 1, 1, 0, 1, 0, 1,  2, 2, 0, 1, 0, 1 };
	expected.insert(expected.end(), good.begin(), good.end());
	OO_CHECK(Same(Build(points, 1.0f, nullptr, 1.0f), expected));
}


OO_TEST(nothingIsBuilt)
{
	oo::PList points(oo::PList::Array{ Segment(1.0, 1.0, 2.0, 0.5, 3.0, 4.0) });
	OO_CHECK(Build(points, 1.0f, nullptr, 0.0f).empty());		// no overall alpha
	OO_CHECK(Build(points, 1.0f, nullptr, -1.0f).empty());
	OO_CHECK(Build(points, 1.0f, OOColor::clearColor().get(), 1.0f).empty());	// a transparent colour
	OO_CHECK(Build(oo::PList(oo::PList::Array{}), 1.0f, nullptr, 1.0f).empty());	// no points
	OO_CHECK(Build(oo::PList(), 1.0f, nullptr, 1.0f).empty());				// not an array
}


OO_TEST_MAIN()
