/*	test_OOTextureScaling.mm
	Unit tests for the texture scaler (src/Core/OOTextureScaling.h): bead oo-dqxj, slice 1 of the
	Phase 3 slice plan docs/phases/3-slices/OOTextureScaling.md, in the house style of the OOColor
	exemplar (proposed ADR-0056).

	Slice 1 converts the three format-dispatch wrappers (SqueezeVertically, StretchHorizontally,
	SqueezeHorizontally), whose only Objective-C was the +[OOException raise:format:] in their
	unreachable default arm. They are file-static, so this test reaches them through
	OOScalePixMap(): each scaling direction, for each of the three pixel formats, pinned byte for
	byte, plus uniform images (which every scaler must keep uniform) and the invalid pixmap that
	OOScalePixMap() refuses before any wrapper runs. The expectations were written against the
	unconverted file and run on it first. Run: bash tools/check-core-tests.sh test_OOTextureScaling
*/

#include "OOTextureScaling.h"
#include "OOLogging.h"
#include "Universe.h"
#include "MyOpenGLView.h"
#include "oofnd/objc/OOException.h"

#include "oo_test.hpp"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>


// Link stubs: the scaler's object and OOPixMap.mm reach these, and the test does not link the game.
namespace {
int sParameterErrors = 0;
}

void OOLogGenericParameterErrorForFunction(const char *inFunction)
{
	(void)inFunction;
	++sParameterErrors;
}

const char *const cxx_kOOLogParameterError = "general.error.parameterError";	// OOLogging.mm's
Universe *gSharedUniverse = nil;	// OODumpPixMap's UNIVERSE (debug builds); never called here

// OODumpPixMap's view dumps: members since bead oo-9ht.153 deleted the view's facade (they were
// sends); never called here.
#ifndef NDEBUG
void MyOpenGLView::dumpGrayToFileNamed(const std::string &, uint8_t *, NSUInteger, NSUInteger, NSUInteger)  { std::abort(); }
void MyOpenGLView::dumpGrayAlphaToFileNamed(const std::string &, uint8_t *, NSUInteger, NSUInteger, NSUInteger)  { std::abort(); }
void MyOpenGLView::dumpRGBAToRGBFileNamed(const std::optional<std::string> &, const std::optional<std::string> &, uint8_t *, NSUInteger, NSUInteger, NSUInteger)  { std::abort(); }
#endif


namespace {

// A malloc'd pixmap (OOScalePixMap frees its source) filled with a fixed pattern.
OOPixMap MakePatterned(OOPixMapDimension width, OOPixMapDimension height, OOPixMapFormat format)
{
	OOPixMap pixMap = OOAllocatePixMap(width, height, format, 0, 0);
	uint8_t *bytes = static_cast<uint8_t *>(pixMap.pixels);
	for (size_t i = 0; i < pixMap.rowBytes * height; i++)  bytes[i] = static_cast<uint8_t>((i * 37 + 13) & 0xFF);
	return pixMap;
}


OOPixMap MakeUniform(OOPixMapDimension width, OOPixMapDimension height, OOPixMapFormat format, uint8_t value)
{
	OOPixMap pixMap = OOAllocatePixMap(width, height, format, 0, 0);
	std::memset(pixMap.pixels, value, pixMap.rowBytes * height);
	return pixMap;
}


std::vector<int> Bytes(OOPixMap pixMap)
{
	std::vector<int> result;
	const uint8_t *bytes = static_cast<const uint8_t *>(pixMap.pixels);
	for (OOPixMapDimension y = 0; y < pixMap.height; y++)
	{
		for (size_t x = 0; x < pixMap.width * OOPixMapBytesPerPixel(pixMap); x++)  result.push_back(bytes[y * pixMap.rowBytes + x]);
	}
	return result;
}


// Checks the result's shape and bytes; on a mismatch prints the bytes it got, so a pin can be read.
bool Pinned(const char *what, OOPixMap pixMap, OOPixMapDimension width, OOPixMapDimension height, std::vector<int> expected)
{
	bool ok = OO_CHECK(pixMap.pixels != nullptr);
	ok = OO_CHECK_EQ(pixMap.width, width) && ok;
	ok = OO_CHECK_EQ(pixMap.height, height) && ok;
	ok = OO_CHECK_EQ(pixMap.rowBytes, static_cast<size_t>(width) * OOPixMapBytesPerPixel(pixMap)) && ok;
	if (pixMap.pixels == nullptr)  return false;
	std::vector<int> actual = Bytes(pixMap);
	if (!OO_CHECK(actual == expected))
	{
		std::fprintf(stderr, "  %s got {", what);
		for (size_t i = 0; i < actual.size(); i++)  std::fprintf(stderr, "%s%d", i ? ", " : " ", actual[i]);
		std::fprintf(stderr, " }\n");
		ok = false;
	}
	return ok;
}


bool AllEqual(OOPixMap pixMap, uint8_t value)
{
	for (int byte : Bytes(pixMap))  if (byte != value)  return false;
	return true;
}


const OOPixMapFormat kFormats[] = { kOOPixMapRGBA, kOOPixMapGrayscale, kOOPixMapGrayscaleAlpha };

}	// namespace


// SqueezeVertically(): 2x4 -> 2x2, in place, for each format.
OO_TEST(squeezesVertically)
{
	OOPixMap rgba = OOScalePixMap(MakePatterned(2, 4, kOOPixMapRGBA), 2, 2, NO);
	Pinned("rgba", rgba, 2, 2, { 33, 70, 107, 144, 181, 218, 127, 36, 113, 150, 187, 224, 133, 42, 79, 116 });
	free(rgba.pixels);

	OOPixMap gray = OOScalePixMap(MakePatterned(2, 4, kOOPixMapGrayscale), 2, 2, NO);
	Pinned("gray", gray, 2, 2, { 50, 87, 198, 107 });
	free(gray.pixels);

	OOPixMap grayAlpha = OOScalePixMap(MakePatterned(2, 4, kOOPixMapGrayscaleAlpha), 2, 2, NO);
	Pinned("grayAlpha", grayAlpha, 2, 2, { 87, 124, 161, 70, 127, 164, 73, 110 });
	free(grayAlpha.pixels);
}


// StretchHorizontally(): 2x2 -> 4x2, into a new buffer, for each format.
OO_TEST(stretchesHorizontally)
{
	OOPixMap rgba = OOScalePixMap(MakePatterned(2, 2, kOOPixMapRGBA), 4, 2, NO);
	Pinned("rgba", rgba, 4, 2, { 13, 50, 87, 124, 13, 50, 87, 124, 161, 198, 235, 16, 161, 198, 235, 16, 53, 90, 127, 164, 53, 90, 127, 164, 201, 238, 19, 56, 201, 238, 19, 56 });
	free(rgba.pixels);

	OOPixMap gray = OOScalePixMap(MakePatterned(2, 2, kOOPixMapGrayscale), 4, 2, NO);
	Pinned("gray", gray, 4, 2, { 13, 13, 50, 50, 87, 87, 124, 124 });
	free(gray.pixels);

	OOPixMap grayAlpha = OOScalePixMap(MakePatterned(2, 2, kOOPixMapGrayscaleAlpha), 4, 2, NO);
	Pinned("grayAlpha", grayAlpha, 4, 2, { 13, 50, 13, 50, 87, 124, 87, 124, 161, 198, 161, 198, 235, 16, 235, 16 });
	free(grayAlpha.pixels);
}


// SqueezeHorizontally(): 4x2 -> 2x2, in place, for each format.
OO_TEST(squeezesHorizontally)
{
	OOPixMap rgba = OOScalePixMap(MakePatterned(4, 2, kOOPixMapRGBA), 2, 2, NO);
	Pinned("rgba", rgba, 2, 2, { 87, 124, 161, 70, 127, 164, 73, 110, 167, 76, 113, 150, 79, 116, 153, 190 });
	free(rgba.pixels);

	OOPixMap gray = OOScalePixMap(MakePatterned(4, 2, kOOPixMapGrayscale), 2, 2, NO);
	Pinned("gray", gray, 2, 2, { 31, 105, 179, 125 });
	free(gray.pixels);

	OOPixMap grayAlpha = OOScalePixMap(MakePatterned(4, 2, kOOPixMapGrayscaleAlpha), 2, 2, NO);
	Pinned("grayAlpha", grayAlpha, 2, 2, { 50, 87, 198, 107, 90, 127, 110, 147 });
	free(grayAlpha.pixels);
}


// oo-snnh6: StretchVertically() (2x3 -> 2x4 and 2x2 -> 2x4, into a new buffer; RGBA and
// gray+alpha take the 4-byte path StretchVerticallyN_x4, 2-wide grayscale the byte path
// StretchVerticallyN_x1) and the last row of StretchHorizontally() (3x1 -> 4x1, one row, so only
// the last-row loop runs). The last output row of a vertical stretch is the last source row and
// the last output pixel of a horizontal one is the last source pixel. 2x3 -> 2x4 and every
// horizontal case gave these same bytes before the fix; 2x2 -> 2x4 copied its last row from one
// row past the source buffer (an ASan heap-buffer-overflow READ), as 3x1 -> 4x1 read one pixel
// past it at weight 0.
OO_TEST(stretchesVerticallyAndKeepsTheEdges)
{
	OOPixMap rgba = OOScalePixMap(MakePatterned(2, 3, kOOPixMapRGBA), 2, 4, NO);
	Pinned("rgba 2x3 -> 2x4", rgba, 2, 4, { 13, 50, 87, 124, 161, 198, 235, 16, 33, 70, 107, 144, 181, 218, 127, 36, 63, 100, 137, 174, 211, 184, 29, 66, 93, 130, 167, 204, 241, 22, 59, 96 });
	free(rgba.pixels);

	OOPixMap gray = OOScalePixMap(MakePatterned(2, 3, kOOPixMapGrayscale), 2, 4, NO);
	Pinned("gray 2x3 -> 2x4", gray, 2, 4, { 13, 50, 50, 87, 105, 142, 161, 198 });
	free(gray.pixels);

	OOPixMap grayAlpha = OOScalePixMap(MakePatterned(2, 3, kOOPixMapGrayscaleAlpha), 2, 4, NO);
	Pinned("grayAlpha 2x3 -> 2x4", grayAlpha, 2, 4, { 13, 50, 87, 124, 87, 124, 161, 70, 134, 171, 208, 53, 53, 90, 127, 164 });
	free(grayAlpha.pixels);

	OOPixMap rgbaDouble = OOScalePixMap(MakePatterned(2, 2, kOOPixMapRGBA), 2, 4, NO);
	Pinned("rgba 2x2 -> 2x4", rgbaDouble, 2, 4, { 13, 50, 87, 124, 161, 198, 235, 16, 13, 50, 87, 124, 161, 198, 235, 16, 53, 90, 127, 164, 201, 238, 19, 56, 53, 90, 127, 164, 201, 238, 19, 56 });
	free(rgbaDouble.pixels);

	OOPixMap grayDouble = OOScalePixMap(MakePatterned(2, 2, kOOPixMapGrayscale), 2, 4, NO);
	Pinned("gray 2x2 -> 2x4", grayDouble, 2, 4, { 13, 50, 13, 50, 87, 124, 87, 124 });
	free(grayDouble.pixels);

	OOPixMap grayAlphaDouble = OOScalePixMap(MakePatterned(2, 2, kOOPixMapGrayscaleAlpha), 2, 4, NO);
	Pinned("grayAlpha 2x2 -> 2x4", grayAlphaDouble, 2, 4, { 13, 50, 87, 124, 13, 50, 87, 124, 161, 198, 235, 16, 161, 198, 235, 16 });
	free(grayAlphaDouble.pixels);

	OOPixMap rgbaRow = OOScalePixMap(MakePatterned(3, 1, kOOPixMapRGBA), 4, 1, NO);
	Pinned("rgba 3x1 -> 4x1", rgbaRow, 4, 1, { 13, 50, 87, 124, 87, 124, 161, 70, 134, 171, 208, 53, 53, 90, 127, 164 });
	free(rgbaRow.pixels);

	OOPixMap grayRow = OOScalePixMap(MakePatterned(3, 1, kOOPixMapGrayscale), 4, 1, NO);
	Pinned("gray 3x1 -> 4x1", grayRow, 4, 1, { 13, 31, 59, 87 });
	free(grayRow.pixels);

	OOPixMap grayAlphaRow = OOScalePixMap(MakePatterned(3, 1, kOOPixMapGrayscaleAlpha), 4, 1, NO);
	Pinned("grayAlpha 3x1 -> 4x1", grayAlphaRow, 4, 1, { 13, 50, 50, 87, 105, 142, 161, 198 });
	free(grayAlphaRow.pixels);
}


// A uniform image stays uniform through every wrapper, in both directions at once. Grayscale is
// squeezed vertically by a whole factor (8 -> 4): by 8 -> 5 its last row comes out at about 3/8 of
// the value, a defect of the plain-C SqueezeVertically1() that this slice does not touch (oo-9ht.115).
OO_TEST(keepsUniformImagesUniform)
{
	for (OOPixMapFormat format : kFormats)
	{
		const OOPixMapDimension height = (format == kOOPixMapGrayscale) ? 4 : 5;
		OOPixMap squeezed = OOScalePixMap(MakeUniform(8, 8, format, 0x5A), 3, height, NO);
		OO_CHECK(squeezed.pixels != nullptr && squeezed.width == 3 && squeezed.height == height);
		OO_CHECK(AllEqual(squeezed, 0x5A));
		free(squeezed.pixels);

		OOPixMap stretched = OOScalePixMap(MakeUniform(3, 8, format, 0xC3), 7, height, NO);
		OO_CHECK(stretched.pixels != nullptr && stretched.width == 7 && stretched.height == height);
		OO_CHECK(AllEqual(stretched, 0xC3));
		free(stretched.pixels);
	}
}


// oo-9ht.115: a uniform grayscale image squeezed vertically by a non-integer factor (8 -> 5, and
// 8x8 -> 3x5 through both squeezers) stays uniform in every row, the last included. Before the fix
// SqueezeVertically1() counted the final source row's weight without its value, so the last row of
// 0x5A came out at 33 and of 0xC3 at 73; SqueezeVertically2/4 were already right.
OO_TEST(squeezesGrayscaleVerticallyByANonIntegerFactorUniformly)
{
	for (uint8_t value : { static_cast<uint8_t>(0x5A), static_cast<uint8_t>(0xC3) })
	{
		OOPixMap tall = OOScalePixMap(MakeUniform(8, 8, kOOPixMapGrayscale, value), 8, 5, NO);
		Pinned("gray 8x8 -> 8x5", tall, 8, 5, std::vector<int>(8 * 5, value));
		free(tall.pixels);

		OOPixMap both = OOScalePixMap(MakeUniform(8, 8, kOOPixMapGrayscale, value), 3, 5, NO);
		Pinned("gray 8x8 -> 3x5", both, 3, 5, std::vector<int>(3 * 5, value));
		free(both.pixels);
	}
}


// A pixmap with no valid format is refused before any wrapper runs: a null pixmap and one
// parameter-error log line, as before.
OO_TEST(refusesAnInvalidPixMap)
{
	OOPixMap invalid = { malloc(16), 2, 2, kOOPixMapInvalidFormat, 8, 16 };
	int before = sParameterErrors;
	OOPixMap result = OOScalePixMap(invalid, 1, 1, NO);
	OO_CHECK(result.pixels == nullptr);
	OO_CHECK_EQ(sParameterErrors, before + 1);
}


// The wrappers' unreachable default arm now raises with OORaiseException(), the function form of
// +[OOException raise:format:]: the same name and formatted reason (the C++ oo::Exception since
// bead oo-rskgl.1, caught as catch (const oo::Exception &) where @catch (OOException *) was).
OO_TEST(raiseExceptionThrowsTheSameException)
{
	const char *name = nullptr;
	std::string reason;
	std::optional<oo::Exception> kept;	// what the autorelease pool kept alive (bead oo-rskgl.1)
	try
	{
		OORaiseException(OOInternalInconsistencyException, "Unsupported pixmap format in scaler: %s", OOPixMapFormatName(kOOPixMapInvalidFormat).c_str());
	}
	catch (const oo::Exception &e)	// was @catch (OOException *e)
	{
		kept = e;
		name = kept->name();
		reason = kept->reason();
	}
	OO_CHECK(name != nullptr && std::strcmp(name, OOInternalInconsistencyException) == 0);
	OO_CHECK_EQ(reason, std::string("Unsupported pixmap format in scaler: ") + OOPixMapFormatName(kOOPixMapInvalidFormat));

	std::string messageReason;
	try
	{
		OORaiseException(OOInternalInconsistencyException, "Unsupported pixmap format in scaler: %s", OOPixMapFormatName(kOOPixMapInvalidFormat).c_str());	// was +[OOException raise:format:]
	}
	catch (const oo::Exception &e)	// was @catch (OOException *e)
	{
		messageReason = e.reason();
	}
	OO_CHECK_EQ(messageReason, reason);
}


OO_TEST_MAIN()
