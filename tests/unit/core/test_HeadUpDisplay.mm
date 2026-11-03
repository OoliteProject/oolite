/*	test_HeadUpDisplay.mm
	Unit tests for HeadUpDisplay (src/Core/HeadUpDisplay.h): bead oo-engam (Phase 3, slice 1 of
	docs/phases/3-slices/HeadUpDisplay.md, the class shell; proposed ADR-0056 and its amendments
	oo-pni4 and oo-9ht.139).

	The HUD is made from a hud.plist dictionary: its MFDs, its reticle colours (from the
	drawTargetReticle: dial, green/red/cyan without one), whether it has a compass, its overall
	alpha, the reticle sensitivity and its properties, big-GUI permission, the crosshair file (a
	missing file falls back to crosshairs.plist) and the scanner flags. The tests pin those, the
	accessors and setters (clamping, the hidden selectors, the deferred HUD name, nil colours
	refused), the reticle colours' identity, and +nonlinearScannerScale:Zoom:Scale:. Drawing is GL
	and is pinned by the goldens, not here (amendment oo-z1s4).

	The HUD's object references the universe, the player and the GUIs, so the test links the whole
	game but main (tests/unit/core/meson.build entry ['*'], amendment oo-44gg) on the hidden GL
	context of oo_gl_test_context.hpp. UNIVERSE and PLAYER are nil. The resource manager runs in
	strict mode on a scratch Resources folder the test writes (the current directory and HOMEPATH
	point at it), holding its own whitelist and one crosshair file, so no game resource and no
	add-on is read; the font is missing, so the text engine has no texture. The expectations were
	written against the Objective-C class and run on it first; the last test pins the C++ API (the
	facade's contract went with the facade, bead oo-mwd58). Run: bash tools/check-core-tests.sh test_HeadUpDisplay
*/

#import "HeadUpDisplay.h"
#import "OOColor.h"
#import "ResourceManager.h"

#include "oo_test.hpp"
#include "oo_gl_test_context.hpp"

#include "oofnd/objc/OORuntime.h"

#include <process.h>
#include <stdlib.h>

#include <cmath>
#include <filesystem>
#include <fstream>
#include <string>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


namespace {

namespace stdfs = std::filesystem;

stdfs::path sRoot;


void WriteFile(const stdfs::path &path, const char *text)
{
	std::ofstream out(path, std::ios::binary);
	out << text;
}


/*	The scratch folder, before the resource manager's first use: a whitelist naming the dials the
	tests use, and a crosshair file.
*/
void SetUp()
{
	OO_CHECK(OOTestGLContext());
	if (!sRoot.empty())  return;
	sRoot = stdfs::temp_directory_path() / ("oo-test-hud-" + std::to_string(static_cast<unsigned long>(::_getpid())));
	stdfs::remove_all(sRoot);
	stdfs::create_directories(sRoot / "Resources" / "Config");
	OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
	stdfs::current_path(sRoot);
	WriteFile(sRoot / "Resources" / "Config" / "whitelist.plist",
			  "{\n\thud_dial_methods = (\"drawTrumbles:\", \"drawTargetReticle:\", \"drawCompass:\", \"drawScanner:\");\n}\n");
	WriteFile(sRoot / "Resources" / "Config" / "testcross.plist",
			  "{\n\tWEAPON_OFFLINE = (1, 2, 3, 4, 5, 6);\n}\n");
	[ResourceManager cxx_setUseAddOns:std::string(SCENARIO_OXP_DEFINITION_NONE)];	// strict: the built-in Resources alone
}


// [[HeadUpDisplay alloc] cxx_initWithDictionary:inFile:] (the C++ HUD since bead oo-mwd58).
oo::Ref<HeadUpDisplay> NewHUD(const oo::PList &info, const std::optional<std::string> &name = std::string("test-hud.plist"))
{
	oo::Ref<HeadUpDisplay> hud = oo::makeRef<HeadUpDisplay>();
	hud->initWithDictionary(info, name);
	return hud;
}


oo::PList Dial(const char *selector)
{
	return oo::PList(oo::PList::Dict{ { "selector", oo::PList(selector) } });
}


bool SameRGBA(OOColor *color, float r, float g, float b, float a)
{
	if (color == nil)  return false;
	float cr = 0, cg = 0, cb = 0, ca = 0;
	color->getRed(&cr, &cg, &cb, &ca);
	return cr == r && cg == g && cb == b && ca == a;
}

}	// namespace


OO_TEST(madeFromAnEmptyDictionary)
{
	SetUp();
	@autoreleasepool
	{
		oo::Ref<HeadUpDisplay> hud = NewHUD(oo::PList(oo::PList::Dict{}));
		OO_CHECK(hud != nil);
		OO_CHECK(hud->getHudName() == std::optional<std::string>("test-hud.plist"));
		OO_CHECK(!hud->getDeferredHudName().has_value());
		OO_CHECK_EQ(hud->mfdCount(), 0u);
		OO_CHECK(hud->getOverallAlpha() == 0.75f);
		OO_CHECK(!hud->getReticleTargetSensitive());
		OO_CHECK(!hud->getAllowBigGui());
		OO_CHECK(!hud->isHidden());
		OO_CHECK(!hud->isUpdating());
		OO_CHECK(!hud->isCompassActive());
		OO_CHECK(!hud->minimalisticScanner());
		OO_CHECK(!hud->nonlinearScanner());
		OO_CHECK(!hud->scannerUltraZoom());
		OO_CHECK(hud->getLineWidth() == 1.0f);
		OO_CHECK(hud->scannerZoom() == 0.0f);
		OO_CHECK(!hud->getCrosshairDefinition().has_value());

		// The reticle sensitivity's properties: accurate, last computed at the universe's time (nil: 0).
		oo::PList *properties = hud->getPropertiesReticleTargetSensitive();
		OO_CHECK(properties != nullptr);
		OO_CHECK(properties->get<bool>("isAccurate", false));
		OO_CHECK(properties->get<double>("timeLastAccuracyProbabilityCalculation", -1.0) == 0.0);

		// No drawTargetReticle: dial: green, red, cyan.
		OO_CHECK(SameRGBA(hud->reticleColorForIndex(OO_RETICLE_COLOR_TARGET).get(), 0, 1, 0, 1));
		OO_CHECK(SameRGBA(hud->reticleColorForIndex(OO_RETICLE_COLOR_TARGET_SENSITIVE).get(), 1, 0, 0, 1));
		OO_CHECK(SameRGBA(hud->reticleColorForIndex(OO_RETICLE_COLOR_WORMHOLE).get(), 0, 1, 1, 1));
		OO_CHECK(hud->reticleColorForIndex(3) == nil);

		// A nil name is kept as nil.
		OO_CHECK(!NewHUD(oo::PList(oo::PList::Dict{}), std::nullopt)->getHudName().has_value());
	}
}


OO_TEST(readsItsConfiguration)
{
	SetUp();
	@autoreleasepool
	{
		const oo::PList mfd(oo::PList::Dict{ { "x", oo::PList(10) }, { "y", oo::PList(20) } });
		const oo::PList info(oo::PList::Dict{
			{ "dials", oo::PList(oo::PList::Array{ Dial("drawCompass:"), Dial("drawScanner:"), oo::PList("not a dictionary") }) },
			{ "multi_function_displays", oo::PList(oo::PList::Array{ mfd, mfd, oo::PList(7) }) },	// a non-dictionary entry counts too
			{ "overall_alpha", oo::PList(0.5) },
			{ "reticle_target_sensitive", oo::PList(true) },
			{ "allow_big_gui", oo::PList(true) },
			{ "scanner_minimalistic", oo::PList(true) },
			{ "scanner_non_linear", oo::PList(true) },
			{ "scanner_ultra_zoom", oo::PList(true) },
		});
		oo::Ref<HeadUpDisplay> hud = NewHUD(info);
		OO_CHECK_EQ(hud->mfdCount(), 3u);
		OO_CHECK(hud->getOverallAlpha() == 0.5f);
		OO_CHECK(hud->getReticleTargetSensitive());
		OO_CHECK(hud->getAllowBigGui());
		OO_CHECK(hud->isCompassActive());
		OO_CHECK(hud->minimalisticScanner());
		OO_CHECK(hud->nonlinearScanner());
		OO_CHECK(hud->scannerUltraZoom());
	}
}


OO_TEST(reticleColoursFromTheTargetReticleDial)
{
	SetUp();
	@autoreleasepool
	{
		oo::PList reticle(oo::PList::Dict{ { "selector", oo::PList("drawTargetReticle:") },
										   { "target_rgba", oo::PList("blueColor") },
										   { "wormhole_rgba", oo::PList("yellowColor") } });
		oo::Ref<HeadUpDisplay> hud = NewHUD(oo::PList(oo::PList::Dict{ { "dials", oo::PList(oo::PList::Array{ reticle }) } }));
		OO_CHECK(SameRGBA(hud->reticleColorForIndex(OO_RETICLE_COLOR_TARGET).get(), 0, 0, 1, 1));
		OO_CHECK(SameRGBA(hud->reticleColorForIndex(OO_RETICLE_COLOR_TARGET_SENSITIVE).get(), 1, 0, 0, 1));	// the default
		OO_CHECK(SameRGBA(hud->reticleColorForIndex(OO_RETICLE_COLOR_WORMHOLE).get(), 1, 1, 0, 1));

		// The list stops at the first colour that does not parse.
		oo::PList shortList(oo::PList::Dict{ { "selector", oo::PList("drawTargetReticle:") },
											 { "target_sensitive_rgba", oo::PList(oo::PList::Array{}) } });
		oo::Ref<HeadUpDisplay> shortHUD = NewHUD(oo::PList(oo::PList::Dict{ { "dials", oo::PList(oo::PList::Array{ shortList }) } }));
		OO_CHECK(SameRGBA(shortHUD->reticleColorForIndex(OO_RETICLE_COLOR_TARGET).get(), 0, 1, 0, 1));
		OO_CHECK(shortHUD->reticleColorForIndex(OO_RETICLE_COLOR_TARGET_SENSITIVE) == nil);
		OO_CHECK(shortHUD->reticleColorForIndex(OO_RETICLE_COLOR_WORMHOLE) == nil);
		OO_CHECK(!shortHUD->setReticleColorForIndex(OO_RETICLE_COLOR_WORMHOLE, OOColor::whiteColor().get()));
	}
}


OO_TEST(setReticleColour)
{
	SetUp();
	@autoreleasepool
	{
		oo::Ref<HeadUpDisplay> hud = NewHUD(oo::PList(oo::PList::Dict{}));
		oo::Ref<OOColor>	magenta = OOColor::magentaColor();
		OO_CHECK(hud->setReticleColorForIndex(OO_RETICLE_COLOR_WORMHOLE, magenta.get()));
		OO_CHECK(hud->reticleColorForIndex(OO_RETICLE_COLOR_WORMHOLE) == magenta);	// the same object
		OO_CHECK(!hud->setReticleColorForIndex(OO_RETICLE_COLOR_TARGET, nil));
		OO_CHECK(SameRGBA(hud->reticleColorForIndex(OO_RETICLE_COLOR_TARGET).get(), 0, 1, 0, 1));
		OO_CHECK(!hud->setReticleColorForIndex(3, magenta.get()));
	}
}


OO_TEST(crosshairFile)
{
	SetUp();
	@autoreleasepool
	{
		oo::Ref<HeadUpDisplay> hud = NewHUD(oo::PList(oo::PList::Dict{ { "crosshair_file", oo::PList("testcross.plist") } }));
		OO_CHECK(hud->getCrosshairDefinition() == std::optional<std::string>("testcross.plist"));

		// A file that is not found falls back to crosshairs.plist.
		oo::Ref<HeadUpDisplay> missing = NewHUD(oo::PList(oo::PList::Dict{ { "crosshair_file", oo::PList("nosuch.plist") } }));
		OO_CHECK(missing->getCrosshairDefinition() == std::optional<std::string>("crosshairs.plist"));
	}
}


OO_TEST(accessorsAndSetters)
{
	SetUp();
	@autoreleasepool
	{
		oo::Ref<HeadUpDisplay> hud = NewHUD(oo::PList(oo::PList::Dict{}));

		hud->setHudName(std::string("other.plist"));
		OO_CHECK(hud->getHudName() == std::optional<std::string>("other.plist"));
		hud->setHudName(std::nullopt);	// ignored
		OO_CHECK(hud->getHudName() == std::optional<std::string>("other.plist"));

		hud->setDeferredHudName(std::string("deferred.plist"));
		OO_CHECK(hud->getDeferredHudName() == std::optional<std::string>("deferred.plist"));
		hud->setDeferredHudName(std::nullopt);
		OO_CHECK(!hud->getDeferredHudName().has_value());

		hud->setScannerZoom(2.5f);
		OO_CHECK(hud->scannerZoom() == 2.5f);

		hud->setOverallAlpha(1.5f);
		OO_CHECK(hud->getOverallAlpha() == 1.0f);
		hud->setOverallAlpha(-1.0f);
		OO_CHECK(hud->getOverallAlpha() == 0.0f);
		hud->setOverallAlpha(0.25f);
		OO_CHECK(hud->getOverallAlpha() == 0.25f);

		hud->setReticleTargetSensitive(YES);
		OO_CHECK(hud->getReticleTargetSensitive());

		// Hidden: big GUIs are allowed while the HUD is hidden.
		hud->setHidden(YES);
		OO_CHECK(hud->isHidden());
		OO_CHECK(hud->getAllowBigGui());
		hud->setHidden(NO);
		OO_CHECK(!hud->getAllowBigGui());

		hud->setCompassActive(YES);
		OO_CHECK(hud->isCompassActive());
		hud->setCompassActive(NO);
		OO_CHECK(!hud->isCompassActive());

		hud->setMinimalisticScanner(YES);
		OO_CHECK(hud->minimalisticScanner());
		hud->setNonlinearScanner(YES);
		OO_CHECK(hud->nonlinearScanner());
		hud->setScannerUltraZoom(YES);
		OO_CHECK(hud->scannerUltraZoom());

		hud->setLineWidth(3.0f);
		OO_CHECK(hud->getLineWidth() == 3.0f);

		// Nothing to refresh, nothing to reset, and the player is not flying: no universe.
		hud->refreshLastTransmitter();
		hud->resetGuis(oo::PList(oo::PList::Dict{ { "message_gui", oo::PList(oo::PList::Dict{}) } }));
	}
}


OO_TEST(hiddenSelectors)
{
	SetUp();
	@autoreleasepool
	{
		oo::Ref<HeadUpDisplay> hud = NewHUD(oo::PList(oo::PList::Dict{}));
		OO_CHECK(!hud->hasHidden(std::string("drawCompass:")));
		OO_CHECK(!hud->hasHidden(std::nullopt));
		hud->setHiddenSelector("drawCompass:", YES);
		hud->setHiddenSelector("drawScanner:", YES);
		OO_CHECK(hud->hasHidden(std::string("drawCompass:")));
		OO_CHECK(hud->hasHidden(std::string("drawScanner:")));
		hud->setHiddenSelector("drawCompass:", NO);
		OO_CHECK(!hud->hasHidden(std::string("drawCompass:")));
		OO_CHECK(hud->hasHidden(std::string("drawScanner:")));
		hud->clearHiddenSelectors();
		OO_CHECK(!hud->hasHidden(std::string("drawScanner:")));
	}
}


OO_TEST(nonlinearScannerScale)
{
	// The direction is kept; the length is the scanner's nonlinear map of the distance.
	const Vector v = HeadUpDisplay::nonlinearScannerScale(make_vector(3000.0f, 0.0f, 4000.0f), 1.0f, 256.0);
	const Vector unit = vector_normal(v);
	OO_CHECK(std::fabs(unit.x - 0.6f) < 1e-6f && unit.y == 0.0f && std::fabs(unit.z - 0.8f) < 1e-6f);
	const float length = magnitude(v);
	OO_CHECK(std::fabs(length - 50.0f) < 1e-4f);	// 49.9999962 on the Objective-C class
}


OO_TEST(setCrosshairDefinition)
{
	SetUp();
	@autoreleasepool
	{
		// Slice 2 (bead oo-8fiz9): the scripts' crosshair setter. (The frame's dials by name were the
		// facade's selectors until bead oo-mwd58; they are the dial table's now.)
		oo::Ref<HeadUpDisplay> hud = NewHUD(oo::PList(oo::PList::Dict{}));
		OO_CHECK(hud->setCrosshairDefinition("testcross.plist"));
		OO_CHECK(hud->getCrosshairDefinition() == std::optional<std::string>("testcross.plist"));
		OO_CHECK(!hud->setCrosshairDefinition("nosuch.plist"));
		OO_CHECK(hud->getCrosshairDefinition() == std::optional<std::string>("crosshairs.plist"));
	}
}


OO_TEST(beaconCodeIcon)
{
	SetUp();
	@autoreleasepool
	{
		// Slice 4 (bead oo-2p1ug): the entities hold the code icon by the C++ OOHUDBeaconIcon interface
		// (the protocol and the icon's facade until bead oo-7ae4p; the facade's identity check went
		// with it, standing approval oo-9n5p9).
		oo::Ref<OOHUDBeaconCodeIcon> icon = oo::makeRef<OOHUDBeaconCodeIcon>("A");
		OO_CHECK(icon != nullptr);
		OO_CHECK(dynamic_cast<OOHUDBeaconIcon *>(icon.get()) != nullptr);
	}
}


// --- The C++ API (bead oo-engam) ------------------------------------------------------------

OO_TEST(cxxAPI)
{
	SetUp();
	@autoreleasepool
	{
		oo::Ref<HeadUpDisplay> hud = oo::makeRef<HeadUpDisplay>();
		hud->initWithDictionary(oo::PList(oo::PList::Dict{
			{ "dials", oo::PList(oo::PList::Array{ Dial("drawCompass:") }) },
			{ "multi_function_displays", oo::PList(oo::PList::Array{ oo::PList(oo::PList::Dict{}) }) },
			{ "crosshair_file", oo::PList("testcross.plist") },
		}), std::string("cxx.plist"));
		OO_CHECK(hud->getHudName() == std::optional<std::string>("cxx.plist"));
		OO_CHECK_EQ(hud->mfdCount(), 1u);
		OO_CHECK(hud->isCompassActive());
		OO_CHECK(hud->getOverallAlpha() == 0.75f);
		OO_CHECK(hud->getLineWidth() == 1.0f);
		OO_CHECK(hud->getCrosshairDefinition() == std::optional<std::string>("testcross.plist"));
		OO_CHECK(hud->getPropertiesReticleTargetSensitive()->get<bool>("isAccurate", false));

		oo::Ref<OOColor> target = hud->reticleColorForIndex(OO_RETICLE_COLOR_TARGET);
		OO_CHECK(target != nullptr && target->redComponent() == 0.0f && target->greenComponent() == 1.0f);
		OO_CHECK(hud->reticleColorForIndex(3) == nullptr);
		oo::Ref<OOColor> blue = OOColor::blueColor();
		OO_CHECK(hud->setReticleColorForIndex(OO_RETICLE_COLOR_TARGET, blue.get()));
		OO_CHECK(hud->reticleColorForIndex(OO_RETICLE_COLOR_TARGET) == blue);
		OO_CHECK(!hud->setReticleColorForIndex(OO_RETICLE_COLOR_TARGET, nullptr));

		hud->setOverallAlpha(2.0f);
		OO_CHECK(hud->getOverallAlpha() == 1.0f);
		hud->setHidden(true);
		OO_CHECK(hud->getAllowBigGui());
		hud->setHiddenSelector("drawCompass:", true);
		OO_CHECK(hud->hasHidden(std::string("drawCompass:")));

		// Neither the player nor the universe: not in flight.
		OO_CHECK(!hud->checkPlayerInFlight());
		OO_CHECK(!hud->checkPlayerInSystemFlight());

		const Vector v = HeadUpDisplay::nonlinearScannerScale(make_vector(3000.0f, 0.0f, 4000.0f), 1.0f, 256.0);
		OO_CHECK(std::fabs(magnitude(v) - 50.0f) < 1e-4f);
	}
}


OO_TEST_MAIN()
