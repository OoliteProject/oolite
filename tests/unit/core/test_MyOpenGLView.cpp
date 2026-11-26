/*	test_MyOpenGLView.mm
	Unit tests for MyOpenGLView (src/SDL/MyOpenGLView.h), the game's SDL window and OpenGL view:
	bead oo-6rb6, slice 1 of the Phase 3 slice plan docs/phases/3-slices/MyOpenGLView.md (the class
	shell, the window and OpenGL lifecycle, the splash screen), in the house style of the OOColor
	exemplar (proposed ADR-0056, amendments oo-o89, oo-3bgz and oo-2g51).

	The view is made as the game makes it (new and init(); +alloc/-init until bead oo-9ht.153), in a scratch home (no user defaults,
	so the splash screen is on and -init opens no window) with OpenAL on its null backend. The tests
	pin, through the Objective-C API (the C++ members since its facade went), what the slice's units answer without a window: the state
	-init leaves (no game controller, the window caption, the size the view starts at, the input
	state, a matrix manager), the display it would open on and that display's native size, and the
	projection -updateGLSize: sets up, read back from a hidden OpenGL context
	(oo_gl_test_context.hpp). Opening the game's window (-createWindowWithSize:, -initSplashScreen,
	-endSplashScreen, -initialiseGLWithSize:, -updateScreen) would show a real window on the desktop,
	which a unit test must not do (CLAUDE.md, tools/gui-lock); the goldens launch the game, which runs
	all of them. The expectations were written against the unconverted class and run on it first.
	The view's -dealloc quits SDL, so one view serves every test and the last one releases it.
	Bead oo-72cz (slice 2) adds the accessors, the display-mode list and the saved window,
	full-screen and HDR settings, again without a window.
	Bead oo-299r (slice 3) adds the debug image dumps; the snapshot needs the game window.

	MyOpenGLView.mm reaches the game controller, the universe and the player, so the test links
	every game object but main's (tests/unit/core/meson.build entry ['*'], ADR-0056 amendment
	oo-44gg) and defines gDebugFlags.
	Run: bash tools/check-core-tests.sh test_MyOpenGLView
*/

#include "MyOpenGLView.h"
#include "GameController.h"
#include "OOOpenGLMatrixManager.h"
#include "OOFullScreenController.h"

#include "oofnd/Defaults.hpp"
#include "oofnd/PList.hpp"
#include "oo_gl_test_context.hpp"
#include "oo_test.hpp"

#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <process.h>
#include <string>
#include <vector>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


namespace {

MyOpenGLView *sView = nil;


// A scratch home (no user defaults) and the null OpenAL backend, then the view, made once.
MyOpenGLView *View()
{
	if (sView != nil)  return sView;
	namespace stdfs = std::filesystem;
	OO_CHECK(::_putenv_s("ALSOFT_DRIVERS", "null") == 0);
	const stdfs::path root = stdfs::temp_directory_path() / ("oo-test-myopenglview-" + std::to_string(static_cast<unsigned long>(::_getpid())));
	stdfs::remove_all(root);
	stdfs::create_directories(root);
	OO_CHECK(::_putenv_s("HOMEPATH", root.string().c_str()) == 0);
	stdfs::current_path(root);
	sView = new MyOpenGLView();	// [[MyOpenGLView alloc] init]: nil (released) where init() fails
	if (!sView->init())
	{
		sView->release();
		sView = nullptr;
	}
	return sView;
}


bool Near(double a, double b)
{
	return std::fabs(a - b) < 1e-3;
}

}	// namespace


OO_TEST(initWithoutAWindow)
{
	{
		MyOpenGLView *view = View();
		OO_CHECK(view != nil);
		if (view == nil)  return;
		OO_CHECK(view->getGameController() == nil);
		OO_CHECK(!view->inFullScreenMode());
		// No defaults: the window size the game starts windowed at.
		OO_CHECK(view->getViewSize().width == WINDOW_SIZE_DEFAULT_WIDTH && view->getViewSize().height == WINDOW_SIZE_DEFAULT_HEIGHT);
		OO_CHECK(view->getVirtualJoystickPosition().x == 0.0 && view->getVirtualJoystickPosition().y == 0.0);
		OO_CHECK(view->getAllowingStringInput() == gvStringInputNo);
		OO_CHECK(!view->getIsAlphabetKeyDown());
		OO_CHECK_EQ(view->mouseWheelDelta(), 0.0f);
		// The matrix manager is C++: the C++ view's getter answers it, the same one each time.
		OO_CHECK(view != nullptr && view->getOpenGLMatrixManager() != nullptr);
		OO_CHECK(view != nullptr && view->getOpenGLMatrixManager() == view->getOpenGLMatrixManager());
		OO_CHECK(!view->hdrOutput());	// set when the window is made
		OO_CHECK(!view->msaa());
		OO_CHECK(!view->getScreenSizeArray().empty());	// the display's modes, the native one first
	}
}


OO_TEST(windowCaption)
{
	{
		MyOpenGLView *view = View();
		const std::optional<std::string> caption = view->getWindowCaption();
		OO_CHECK(caption.has_value());
		OO_CHECK(caption.has_value() && caption->rfind("Oolite v", 0) == 0);
		OO_CHECK(caption.has_value() && caption->find(" by ") != std::string::npos);
		OO_CHECK(caption == view->getWindowCaption());
	}
}


OO_TEST(displayAndNativeSize)
{
	{
		MyOpenGLView *view = View();
		// No window yet: the first display.
		OO_CHECK(view->getDisplayId() != 0);
		const oo::PList native = view->getNativeSize();
		OO_CHECK(native.isDict());
		OO_CHECK(native.get<int>(std::string(kOODisplayWidth), -1) > 0);
		OO_CHECK(native.get<int>(std::string(kOODisplayHeight), -1) > 0);
		OO_CHECK(native.get<int>(std::string(kOODisplayRefreshRate), -1) == 0);
		OO_CHECK_EQ(native.count(), 3u);
		// The mode list starts with it.
		const std::vector<oo::PList> modes = view->getScreenSizeArray();
		OO_CHECK(!modes.empty() && modes[0].get<int>(std::string(kOODisplayWidth), -1) == native.get<int>(std::string(kOODisplayWidth), -2));
	}
}


OO_TEST(updateGLSizeSetsTheProjection)
{
	{
		MyOpenGLView *view = View();
		OO_CHECK(OOTestGLContext());

		// 4:3 or narrower: the depth and x offset are fixed, y follows the aspect.
		view->updateGLSize(NSMakeSize(800, 600));
		OO_CHECK(view->getViewSize().width == 800 && view->getViewSize().height == 600);
		OO_CHECK(view->backingViewSize().width == 800);
		OO_CHECK(Near(view->getDisplay_z(), 640.0));
		OO_CHECK(Near(view->getX_offset(), 320.0));
		OO_CHECK(Near(view->getY_offset(), 240.0));
		GLint viewport[4] = { -1, -1, -1, -1 };
		glGetIntegerv(GL_VIEWPORT, viewport);
		OO_CHECK(viewport[0] == 0 && viewport[1] == 0 && viewport[2] == 800 && viewport[3] == 600);

		view->updateGLSize(NSMakeSize(640, 960));
		OO_CHECK(Near(view->getDisplay_z(), 640.0));
		OO_CHECK(Near(view->getX_offset(), 320.0));
		OO_CHECK(Near(view->getY_offset(), 480.0));

		// Wider than 4:3: the depth and x offset follow the aspect, y is fixed.
		view->updateGLSize(NSMakeSize(1600, 900));
		OO_CHECK(Near(view->getDisplay_z(), 480.0 * 1600.0 / 900.0));
		OO_CHECK(Near(view->getX_offset(), 240.0 * 1600.0 / 900.0));
		OO_CHECK(Near(view->getY_offset(), 240.0));
		glGetIntegerv(GL_VIEWPORT, viewport);
		OO_CHECK(viewport[2] == 1600 && viewport[3] == 900);
	}
}


// --- bead oo-72cz: slice 2 (accessors, display modes, settings, display / HDR, FOV and MSAA) ---
// No window: none of these open one (full-screen mode is only switched off again, and the screen
// size is set while windowed). Settings the setters save go to the scratch home's defaults.

OO_TEST(slice2AccessorsAndViewSettings)
{
	{
		MyOpenGLView *view = View();

		// The game controller is not retained: any controller round-trips (storage nothing constructs:
		// the view only keeps the pointer).
		alignas(GameController) static unsigned char controllerStorage[sizeof(GameController)];
		GameController *controller = reinterpret_cast<GameController *>(controllerStorage);
		view->setGameController(controller);
		OO_CHECK(view->getGameController() == controller);
		view->setGameController(nullptr);
		OO_CHECK(view->getGameController() == nil);

		// FOV: stored as tan(half the angle); in degrees or as that fraction.
		view->setFov(60.0f, NO);
		OO_CHECK(Near(view->fov(YES), std::tan(30.0 * M_PI / 180.0)));
		OO_CHECK(Near(view->fov(NO), 60.0));
		view->setFov(0.5f, YES);
		OO_CHECK(Near(view->fov(YES), 0.5));
		OO_CHECK(Near(view->fov(NO), 2.0 * std::atan(0.5) * 180.0 / M_PI));

		view->setMsaa(YES);
		OO_CHECK(view->msaa());
		view->setMsaa(NO);
		OO_CHECK(!view->msaa());

		// SDR tone mapper: clamped to the enum's range.
		view->setSDRToneMapper((OOSDRToneMapper)99);
		OO_CHECK(view->sdrToneMapper() == OOSDR_TONEMAPPER_REINHARD);
		view->setSDRToneMapper((OOSDRToneMapper)-7);
		OO_CHECK(view->sdrToneMapper() == OOSDR_TONEMAPPER_NONE);
		view->setSDRToneMapper(OOSDR_TONEMAPPER_AgX);
		OO_CHECK(view->sdrToneMapper() == OOSDR_TONEMAPPER_AgX);

		// Colour saturation: adjusted, clamped to [0, MAX_COLOR_SATURATION]. No window: it starts at 0.
		OO_CHECK_EQ(view->colorSaturation(), 0.0f);
		view->adjustColorSaturation(0.25f);
		OO_CHECK(Near(view->colorSaturation(), 0.25));
		view->adjustColorSaturation(10.0f);
		OO_CHECK(Near(view->colorSaturation(), MAX_COLOR_SATURATION));
		view->adjustColorSaturation(-10.0f);
		OO_CHECK_EQ(view->colorSaturation(), 0.0f);

		OO_CHECK(!view->hdrOutput());
		(void)view->isOutputDisplayHDREnabled();	// the display's; not pinned
		view->grabMouseInsideGameWindow(NO);

		// +pollShiftKey reads the keyboard: nobody holds shift during a test run.
		OO_CHECK(!::MyOpenGLView::pollShiftKey());
		OO_CHECK(view != nullptr && view->getOpenGLMatrixManager() != nullptr);

#if OOLITE_WINDOWS
		// No window: -isRunningOnPrimaryDisplayDevice answers NO, and -atDesktopResolution is unset.
		OO_CHECK(!view->isRunningOnPrimaryDisplayDevice());
		OO_CHECK(!view->getAtDesktopResolution());
		unsigned width = 7, height = 9;
		view->getDisplayDimensions(&width, &height);	// no window, no display: unchanged
		OO_CHECK(width == 7 && height == 9);

		// HDR settings: clamped and saved to the defaults.
		view->setHDRMaxBrightness(10.0f);
		OO_CHECK(Near(view->hdrMaxBrightness(), MIN_HDR_MAXBRIGHTNESS));
		view->setHDRMaxBrightness(5000.0f);
		OO_CHECK(Near(view->hdrMaxBrightness(), MAX_HDR_MAXBRIGHTNESS));
		view->setHDRMaxBrightness(600.0f);
		OO_CHECK(Near(view->hdrMaxBrightness(), 600.0));
		OO_CHECK(Near(oo::Defaults::standard().floatForKey("hdr-max-brightness"), 600.0));
		view->setHDRPaperWhiteBrightness(1.0f);
		OO_CHECK(Near(view->hdrPaperWhiteBrightness(), MIN_HDR_PAPERWHITE));
		view->setHDRPaperWhiteBrightness(1000.0f);
		OO_CHECK(Near(view->hdrPaperWhiteBrightness(), MAX_HDR_PAPERWHITE));
		view->setHDRPaperWhiteBrightness(150.0f);
		OO_CHECK(Near(view->hdrPaperWhiteBrightness(), 150.0));
		OO_CHECK(Near(oo::Defaults::standard().floatForKey("hdr-paperwhite-brightness"), 150.0));
		view->setHDRToneMapper((OOHDRToneMapper)42);
		OO_CHECK(view->hdrToneMapper() == OOHDR_TONEMAPPER_REINHARD);
		view->setHDRToneMapper((OOHDRToneMapper)-3);
		OO_CHECK(view->hdrToneMapper() == OOHDR_TONEMAPPER_NONE);
		view->setHDRToneMapper(OOHDR_TONEMAPPER_DICE);
		OO_CHECK(view->hdrToneMapper() == OOHDR_TONEMAPPER_DICE);
#endif
	}
}


OO_TEST(slice2DisplayModesAndSavedSettings)
{
	{
		MyOpenGLView *view = View();
		const std::vector<oo::PList> modes = view->getScreenSizeArray();
		OO_CHECK(!modes.empty());
		if (modes.empty())  return;
		const int nativeWidth = modes[0].get<int>(std::string(kOODisplayWidth), -1);
		const int nativeHeight = modes[0].get<int>(std::string(kOODisplayHeight), -1);

		// Mode 0 is the native mode, refresh 0.
		OO_CHECK(view->modeAsSize(0).width == nativeWidth && view->modeAsSize(0).height == nativeHeight);
		OO_CHECK_EQ(view->indexOfDisplayModeForWidth(nativeWidth, nativeHeight, 0), 0);
		OO_CHECK_EQ(view->indexOfDisplayModeForWidth(7, 5, 3), 0);	// none: the native mode
		const int last = static_cast<int>(modes.size()) - 1;
		const oo::PList &lastMode = modes[last];
		const int lastIndex = view->indexOfDisplayModeForWidth(lastMode.get<int>(std::string(kOODisplayWidth)), lastMode.get<int>(std::string(kOODisplayHeight)), lastMode.get<int>(std::string(kOODisplayRefreshRate)));
		OO_CHECK(lastIndex >= 0 && lastIndex <= last);

		// Repopulating the list gives the same list.
		view->populateFullScreenModelist();
		OO_CHECK_EQ(view->getScreenSizeArray().size(), modes.size());

		// Windowed: choosing a mode only records it.
		OO_CHECK(!view->inFullScreenMode());
		view->setScreenSize(last);
		OO_CHECK(view->currentScreenMode() == lastMode);
		OO_CHECK(view->currentScreenSize().width == lastMode.get<int>(std::string(kOODisplayWidth)));
		view->setDisplayMode(0, NO);
		OO_CHECK(!view->inFullScreenMode());
		OO_CHECK(view->currentScreenMode() == modes[0]);
		OO_CHECK(view->currentScreenSize().width == nativeWidth && view->currentScreenSize().height == nativeHeight);

		// Full-screen mode is saved to the defaults; switching it on without a window is not tried.
		view->setFullScreenMode(NO);
		OO_CHECK(!view->inFullScreenMode());
		OO_CHECK(oo::Defaults::standard().object("fullscreen").isBool() && !oo::Defaults::standard().boolForKey("fullscreen"));

		// The windowed size round-trips through the defaults.
		view->saveWindowSize(NSMakeSize(1000, 700));
		OO_CHECK_EQ(oo::Defaults::standard().integerForKey("window_width"), 1000);
		OO_CHECK(view->loadWindowSize().width == 1000 && view->loadWindowSize().height == 700);

		// Full-screen settings: windowed (saved above), the saved mode's index (none saved: 0).
		OO_CHECK_EQ(view->loadFullscreenSettings(), 0);
		OO_CHECK(!view->inFullScreenMode());
		oo::Defaults::standard().setInteger("display_width", nativeWidth);
		oo::Defaults::standard().setInteger("display_height", nativeHeight);
		oo::Defaults::standard().setInteger("display_refresh", 0);
		OO_CHECK_EQ(view->loadFullscreenSettings(), 0);
		OO_CHECK(view->currentScreenMode() == modes[0]);
	}
}


// --- bead oo-299r: slice 3 (snapshots and the debug image dumps) ---
// -cxx_snapShot: reads the game window's surface, which a unit test may not open (the goldens'
// screenshots run it). The dumps write PNGs under <home>/oolite-saves/snapshots.

#ifndef NDEBUG
namespace {

std::filesystem::path DumpPath(const std::string &name)
{
	return std::filesystem::current_path() / "oolite-saves" / "snapshots" / (name + ".png");
}

}	// namespace


OO_TEST(slice3DebugImageDumps)
{
	{
		namespace stdfs = std::filesystem;
		MyOpenGLView *view = View();
		std::filesystem::create_directories(stdfs::current_path() / "oolite-saves" / "snapshots");
		OO_CHECK(stdfs::exists(stdfs::current_path() / "oolite-saves" / "snapshots"));

		// 3 x 2 pixels, rows padded to 16 bytes.
		std::vector<uint8_t> rgba(16 * 2, 0x80);
		view->dumpRGBAToFileNamed("oo-test-rgba", rgba.data(), 3, 2, 16);
		OO_CHECK(stdfs::exists(DumpPath("oo-test-rgba")));
		view->dumpRGBToFileNamed("oo-test-rgb", rgba.data(), 3, 2, 16);
		OO_CHECK(stdfs::exists(DumpPath("oo-test-rgb")));
		view->dumpGrayToFileNamed("oo-test-gray", rgba.data(), 3, 2, 16);
		OO_CHECK(stdfs::exists(DumpPath("oo-test-gray")));
		// -dumpGrayAlpha writes its expansion into the bytes it was given (4 per pixel), so they are
		// a buffer with 4 bytes a pixel; only the file is pinned.
		std::vector<uint8_t> grayAlpha(16 * 2, 0x40);
		view->dumpGrayAlphaToFileNamed("oo-test-grayalpha", grayAlpha.data(), 3, 2, 16);
		OO_CHECK(stdfs::exists(DumpPath("oo-test-grayalpha")));

		// Too short rows, no bytes, or no size: nothing is written.
		view->dumpRGBAToFileNamed("oo-test-short", rgba.data(), 3, 2, 11);
		view->dumpRGBToFileNamed("oo-test-short", nullptr, 3, 2, 16);
		view->dumpGrayToFileNamed("oo-test-short", rgba.data(), 0, 2, 16);
		view->dumpGrayAlphaToFileNamed("oo-test-short", rgba.data(), 3, 2, 5);
		OO_CHECK(!stdfs::exists(DumpPath("oo-test-short")));

		// RGBA split: the RGB file always; the gray (alpha) file only when some alpha is neither 0 nor 255.
		std::vector<uint8_t> opaque(16 * 2, 0xFF);
		view->dumpRGBAToRGBFileNamed(std::string("oo-test-split-rgb"), std::string("oo-test-split-alpha"), opaque.data(), 3, 2, 16);
		OO_CHECK(stdfs::exists(DumpPath("oo-test-split-rgb")));
		OO_CHECK(!stdfs::exists(DumpPath("oo-test-split-alpha")));
		std::vector<uint8_t> translucent(16 * 2, 0x80);
		view->dumpRGBAToRGBFileNamed(std::nullopt, std::string("oo-test-split2-alpha"), translucent.data(), 3, 2, 16);
		OO_CHECK(stdfs::exists(DumpPath("oo-test-split2-alpha")));
		view->dumpRGBAToRGBFileNamed(std::nullopt, std::nullopt, translucent.data(), 3, 2, 16);
	}
}

// Bead oo-5thb0: a gray+alpha dump reads the caller's bytes (2 a pixel, tightly packed rows) and
// writes neither them nor past their end.
OO_TEST(dumpGrayAlphaLeavesTheCallersBytes)
{
	{
		namespace stdfs = std::filesystem;
		MyOpenGLView *view = View();
		stdfs::create_directories(stdfs::current_path() / "oolite-saves" / "snapshots");

		const NSUInteger width = 3, height = 2, rowBytes = 2 * width;
		std::vector<uint8_t> buffer(rowBytes * height + 64, 0xA5);	// the image, then a guard
		for (size_t i = 0; i < rowBytes * height; i++)  buffer[i] = static_cast<uint8_t>(i * 17 + 3);
		const std::vector<uint8_t> before = buffer;
		view->dumpGrayAlphaToFileNamed("oo-test-grayalpha-tight", buffer.data(), width, height, rowBytes);
		OO_CHECK(stdfs::exists(DumpPath("oo-test-grayalpha-tight")));
		OO_CHECK(buffer == before);
	}
}

#endif


// The view's state is private since bead oo-mlpcc; MyOpenGLView.h names this struct its friend so
// the checks below read the same members (expected values unchanged).
struct MyOpenGLViewTestAccess
{
	static auto &viewSize(MyOpenGLView *view)	{ return view->viewSize; }
	static auto &display_z(MyOpenGLView *view)	{ return view->display_z; }
	static auto &matrixManager(MyOpenGLView *view)	{ return view->matrixManager; }
};


// After the conversion: the C++ view the game made (its facade's crossings went with bead oo-9ht.153).
OO_TEST(cxxAPI)
{
	{
		MyOpenGLView *view = View();
		MyOpenGLView *cxxView = view;
		OO_CHECK(cxxView != nullptr);
		OO_CHECK(cxxView->getWindowCaption() == view->getWindowCaption());
		OO_CHECK(cxxView->getDisplayId() == view->getDisplayId());
		cxxView->updateGLSize(NSMakeSize(1024, 768));
		OO_CHECK(view->getViewSize().width == 1024 && MyOpenGLViewTestAccess::viewSize(cxxView).height == 768);
		OO_CHECK(Near(MyOpenGLViewTestAccess::display_z(cxxView), 640.0));
		// The matrix manager is C++; the view's getter answers it.
		OO_CHECK(cxxView->getOpenGLMatrixManager() == MyOpenGLViewTestAccess::matrixManager(cxxView).get());
	}
}


// After slice 2's conversion: its members answer as the facade's methods do.
OO_TEST(cxxSlice2API)
{
	{
		MyOpenGLView *view = View();
		MyOpenGLView *cxxView = view;
		OO_CHECK(cxxView != nullptr);
		if (cxxView == nullptr)  return;
		OO_CHECK(cxxView->getViewSize().width == view->getViewSize().width);
		OO_CHECK(cxxView->backingViewSize().height == view->backingViewSize().height);
		OO_CHECK(cxxView->getDisplay_z() == view->getDisplay_z());
		OO_CHECK(cxxView->getX_offset() == view->getX_offset() && cxxView->getY_offset() == view->getY_offset());
		OO_CHECK(cxxView->getGameController() == view->getGameController());
		cxxView->setFov(45.0f, false);
		OO_CHECK(Near(view->fov(NO), 45.0) && cxxView->fov(true) == view->fov(YES));
		cxxView->setMsaa(true);
		OO_CHECK(view->msaa() && cxxView->msaa());
		cxxView->setMsaa(false);
		cxxView->setSDRToneMapper(OOSDR_TONEMAPPER_UC2);
		OO_CHECK(view->sdrToneMapper() == OOSDR_TONEMAPPER_UC2);
		OO_CHECK(cxxView->colorSaturation() == view->colorSaturation());
		OO_CHECK(cxxView->hdrOutput() == static_cast<bool>(view->hdrOutput()));
		OO_CHECK(cxxView->inFullScreenMode() == static_cast<bool>(view->inFullScreenMode()));
		OO_CHECK(cxxView->getScreenSizeArray() == view->getScreenSizeArray());
		OO_CHECK(cxxView->currentScreenMode() == view->currentScreenMode());
		OO_CHECK(cxxView->modeAsSize(0).width == view->modeAsSize(0).width);
		OO_CHECK_EQ(cxxView->indexOfDisplayModeForWidth(7, 5, 3), 0);
		OO_CHECK(cxxView->loadWindowSize().width == view->loadWindowSize().width);
		OO_CHECK(MyOpenGLView::pollShiftKey() == static_cast<bool>(::MyOpenGLView::pollShiftKey()));
#if OOLITE_WINDOWS
		cxxView->setHDRMaxBrightness(700.0f);
		OO_CHECK(Near(view->hdrMaxBrightness(), 700.0));
		OO_CHECK(cxxView->getAtDesktopResolution() == static_cast<bool>(view->getAtDesktopResolution()));
#endif
	}
}


// After slice 3's conversion: the dumps as members.
OO_TEST(cxxSlice3API)
{
	{
#ifndef NDEBUG
		namespace stdfs = std::filesystem;
		MyOpenGLView *cxxView = View();
		OO_CHECK(cxxView != nullptr);
		if (cxxView == nullptr)  return;
		std::vector<uint8_t> rgba(16 * 2, 0x80);
		cxxView->dumpRGBAToFileNamed("oo-test-cxx-rgba", rgba.data(), 3, 2, 16);
		OO_CHECK(stdfs::exists(DumpPath("oo-test-cxx-rgba")));
		cxxView->dumpRGBAToRGBFileNamed(std::string("oo-test-cxx-rgb"), std::string("oo-test-cxx-alpha"), rgba.data(), 3, 2, 16);
		OO_CHECK(stdfs::exists(DumpPath("oo-test-cxx-rgb")));
		OO_CHECK(stdfs::exists(DumpPath("oo-test-cxx-alpha")));
		cxxView->dumpGrayToFileNamed("oo-test-cxx-short", rgba.data(), 3, 2, 2);
		OO_CHECK(!stdfs::exists(DumpPath("oo-test-cxx-short")));
#endif
	}
}


// Last: -dealloc quits SDL.
OO_TEST(zzDeallocReleasesTheView)
{
	{
		MyOpenGLView *view = View();
		if (view != nullptr)  view->release();
		sView = nil;
	}
}


OO_TEST_MAIN()
