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
	written against the Objective-C class and run on it first; the last tests pin the C++ API and
	the facade's contract. Run: bash tools/check-core-tests.sh test_HeadUpDisplay
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


// [[HeadUpDisplay alloc] cxx_initWithDictionary:inFile:], autoreleased.
HeadUpDisplay *NewHUD(const oo::PList &info, const std::optional<std::string> &name = std::string("test-hud.plist"))
{
	return [[[HeadUpDisplay alloc] cxx_initWithDictionary:info inFile:name] autorelease];
}


oo::PList Dial(const char *selector)
{
	return oo::PList(oo::PList::Dict{ { "selector", oo::PList(selector) } });
}


bool SameRGBA(OOColor *color, float r, float g, float b, float a)
{
	if (color == nil)  return false;
	float cr = 0, cg = 0, cb = 0, ca = 0;
	[color getRed:&cr green:&cg blue:&cb alpha:&ca];
	return cr == r && cg == g && cb == b && ca == a;
}

}	// namespace


OO_TEST(madeFromAnEmptyDictionary)
{
	SetUp();
	@autoreleasepool
	{
		HeadUpDisplay *hud = NewHUD(oo::PList(oo::PList::Dict{}));
		OO_CHECK(hud != nil);
		OO_CHECK([hud cxx_hudName] == std::optional<std::string>("test-hud.plist"));
		OO_CHECK(![hud cxx_deferredHudName].has_value());
		OO_CHECK_EQ([hud mfdCount], 0u);
		OO_CHECK([hud overallAlpha] == 0.75f);
		OO_CHECK(![hud reticleTargetSensitive]);
		OO_CHECK(![hud allowBigGui]);
		OO_CHECK(![hud isHidden]);
		OO_CHECK(![hud isUpdating]);
		OO_CHECK(![hud isCompassActive]);
		OO_CHECK(![hud minimalisticScanner]);
		OO_CHECK(![hud nonlinearScanner]);
		OO_CHECK(![hud scannerUltraZoom]);
		OO_CHECK([hud lineWidth] == 1.0f);
		OO_CHECK([hud scannerZoom] == 0.0f);
		OO_CHECK(![hud cxx_crosshairDefinition].has_value());

		// The reticle sensitivity's properties: accurate, last computed at the universe's time (nil: 0).
		oo::PList *properties = [hud propertiesReticleTargetSensitive];
		OO_CHECK(properties != nullptr);
		OO_CHECK(properties->get<bool>("isAccurate", false));
		OO_CHECK(properties->get<double>("timeLastAccuracyProbabilityCalculation", -1.0) == 0.0);

		// No drawTargetReticle: dial: green, red, cyan.
		OO_CHECK(SameRGBA([hud reticleColorForIndex:OO_RETICLE_COLOR_TARGET], 0, 1, 0, 1));
		OO_CHECK(SameRGBA([hud reticleColorForIndex:OO_RETICLE_COLOR_TARGET_SENSITIVE], 1, 0, 0, 1));
		OO_CHECK(SameRGBA([hud reticleColorForIndex:OO_RETICLE_COLOR_WORMHOLE], 0, 1, 1, 1));
		OO_CHECK([hud reticleColorForIndex:3] == nil);

		// A nil name is kept as nil.
		OO_CHECK(![NewHUD(oo::PList(oo::PList::Dict{}), std::nullopt) cxx_hudName].has_value());
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
		HeadUpDisplay *hud = NewHUD(info);
		OO_CHECK_EQ([hud mfdCount], 3u);
		OO_CHECK([hud overallAlpha] == 0.5f);
		OO_CHECK([hud reticleTargetSensitive]);
		OO_CHECK([hud allowBigGui]);
		OO_CHECK([hud isCompassActive]);
		OO_CHECK([hud minimalisticScanner]);
		OO_CHECK([hud nonlinearScanner]);
		OO_CHECK([hud scannerUltraZoom]);
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
		HeadUpDisplay *hud = NewHUD(oo::PList(oo::PList::Dict{ { "dials", oo::PList(oo::PList::Array{ reticle }) } }));
		OO_CHECK(SameRGBA([hud reticleColorForIndex:OO_RETICLE_COLOR_TARGET], 0, 0, 1, 1));
		OO_CHECK(SameRGBA([hud reticleColorForIndex:OO_RETICLE_COLOR_TARGET_SENSITIVE], 1, 0, 0, 1));	// the default
		OO_CHECK(SameRGBA([hud reticleColorForIndex:OO_RETICLE_COLOR_WORMHOLE], 1, 1, 0, 1));

		// The list stops at the first colour that does not parse.
		oo::PList shortList(oo::PList::Dict{ { "selector", oo::PList("drawTargetReticle:") },
											 { "target_sensitive_rgba", oo::PList(oo::PList::Array{}) } });
		HeadUpDisplay *shortHUD = NewHUD(oo::PList(oo::PList::Dict{ { "dials", oo::PList(oo::PList::Array{ shortList }) } }));
		OO_CHECK(SameRGBA([shortHUD reticleColorForIndex:OO_RETICLE_COLOR_TARGET], 0, 1, 0, 1));
		OO_CHECK([shortHUD reticleColorForIndex:OO_RETICLE_COLOR_TARGET_SENSITIVE] == nil);
		OO_CHECK([shortHUD reticleColorForIndex:OO_RETICLE_COLOR_WORMHOLE] == nil);
		OO_CHECK(![shortHUD setReticleColorForIndex:OO_RETICLE_COLOR_WORMHOLE toColor:[OOColor whiteColor]]);
	}
}


OO_TEST(setReticleColour)
{
	SetUp();
	@autoreleasepool
	{
		HeadUpDisplay *hud = NewHUD(oo::PList(oo::PList::Dict{}));
		OOColor *magenta = [OOColor magentaColor];
		OO_CHECK([hud setReticleColorForIndex:OO_RETICLE_COLOR_WORMHOLE toColor:magenta]);
		OO_CHECK([hud reticleColorForIndex:OO_RETICLE_COLOR_WORMHOLE] == magenta);	// the same object
		OO_CHECK(![hud setReticleColorForIndex:OO_RETICLE_COLOR_TARGET toColor:nil]);
		OO_CHECK(SameRGBA([hud reticleColorForIndex:OO_RETICLE_COLOR_TARGET], 0, 1, 0, 1));
		OO_CHECK(![hud setReticleColorForIndex:3 toColor:magenta]);
	}
}


OO_TEST(crosshairFile)
{
	SetUp();
	@autoreleasepool
	{
		HeadUpDisplay *hud = NewHUD(oo::PList(oo::PList::Dict{ { "crosshair_file", oo::PList("testcross.plist") } }));
		OO_CHECK([hud cxx_crosshairDefinition] == std::optional<std::string>("testcross.plist"));

		// A file that is not found falls back to crosshairs.plist.
		HeadUpDisplay *missing = NewHUD(oo::PList(oo::PList::Dict{ { "crosshair_file", oo::PList("nosuch.plist") } }));
		OO_CHECK([missing cxx_crosshairDefinition] == std::optional<std::string>("crosshairs.plist"));
	}
}


OO_TEST(accessorsAndSetters)
{
	SetUp();
	@autoreleasepool
	{
		HeadUpDisplay *hud = NewHUD(oo::PList(oo::PList::Dict{}));

		[hud setHudName:std::string("other.plist")];
		OO_CHECK([hud cxx_hudName] == std::optional<std::string>("other.plist"));
		[hud setHudName:std::nullopt];	// ignored
		OO_CHECK([hud cxx_hudName] == std::optional<std::string>("other.plist"));

		[hud cxx_setDeferredHudName:std::string("deferred.plist")];
		OO_CHECK([hud cxx_deferredHudName] == std::optional<std::string>("deferred.plist"));
		[hud cxx_setDeferredHudName:std::nullopt];
		OO_CHECK(![hud cxx_deferredHudName].has_value());

		[hud setScannerZoom:2.5f];
		OO_CHECK([hud scannerZoom] == 2.5f);

		[hud setOverallAlpha:1.5f];
		OO_CHECK([hud overallAlpha] == 1.0f);
		[hud setOverallAlpha:-1.0f];
		OO_CHECK([hud overallAlpha] == 0.0f);
		[hud setOverallAlpha:0.25f];
		OO_CHECK([hud overallAlpha] == 0.25f);

		[hud setReticleTargetSensitive:YES];
		OO_CHECK([hud reticleTargetSensitive]);

		// Hidden: big GUIs are allowed while the HUD is hidden.
		[hud setHidden:YES];
		OO_CHECK([hud isHidden]);
		OO_CHECK([hud allowBigGui]);
		[hud setHidden:NO];
		OO_CHECK(![hud allowBigGui]);

		[hud setCompassActive:YES];
		OO_CHECK([hud isCompassActive]);
		[hud setCompassActive:NO];
		OO_CHECK(![hud isCompassActive]);

		[hud setMinimalisticScanner:YES];
		OO_CHECK([hud minimalisticScanner]);
		[hud setNonlinearScanner:YES];
		OO_CHECK([hud nonlinearScanner]);
		[hud setScannerUltraZoom:YES];
		OO_CHECK([hud scannerUltraZoom]);

		[hud setLineWidth:3.0f];
		OO_CHECK([hud lineWidth] == 3.0f);

		// Nothing to refresh, nothing to reset, and the player is not flying: no universe.
		[hud refreshLastTransmitter];
		[hud cxx_resetGuis:oo::PList(oo::PList::Dict{ { "message_gui", oo::PList(oo::PList::Dict{}) } })];
	}
}


OO_TEST(hiddenSelectors)
{
	SetUp();
	@autoreleasepool
	{
		HeadUpDisplay *hud = NewHUD(oo::PList(oo::PList::Dict{}));
		OO_CHECK(![hud hasHidden:std::string("drawCompass:")]);
		OO_CHECK(![hud hasHidden:std::nullopt]);
		[hud cxx_setHiddenSelector:"drawCompass:" hidden:YES];
		[hud cxx_setHiddenSelector:"drawScanner:" hidden:YES];
		OO_CHECK([hud hasHidden:std::string("drawCompass:")]);
		OO_CHECK([hud hasHidden:std::string("drawScanner:")]);
		[hud cxx_setHiddenSelector:"drawCompass:" hidden:NO];
		OO_CHECK(![hud hasHidden:std::string("drawCompass:")]);
		OO_CHECK([hud hasHidden:std::string("drawScanner:")]);
		[hud clearHiddenSelectors];
		OO_CHECK(![hud hasHidden:std::string("drawScanner:")]);
	}
}


OO_TEST(nonlinearScannerScale)
{
	// The direction is kept; the length is the scanner's nonlinear map of the distance.
	const Vector v = [HeadUpDisplay nonlinearScannerScale:make_vector(3000.0f, 0.0f, 4000.0f) Zoom:1.0f Scale:256.0];
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
		// Slice 2 (bead oo-8fiz9): the scripts' crosshair setter, and the frame's dials by name.
		HeadUpDisplay *hud = NewHUD(oo::PList(oo::PList::Dict{}));
		OO_CHECK([hud cxx_setCrosshairDefinition:"testcross.plist"]);
		OO_CHECK([hud cxx_crosshairDefinition] == std::optional<std::string>("testcross.plist"));
		OO_CHECK(![hud cxx_setCrosshairDefinition:"nosuch.plist"]);
		OO_CHECK([hud cxx_crosshairDefinition] == std::optional<std::string>("crosshairs.plist"));

		OO_CHECK([hud respondsToSelector:OOSelectorFromName("drawSurround:")]);
		OO_CHECK([hud respondsToSelector:OOSelectorFromName("drawGreenSurround:")]);
		OO_CHECK([hud respondsToSelector:OOSelectorFromName("drawYellowSurround:")]);
		OO_CHECK([hud respondsToSelector:OOSelectorFromName("renderHUD")]);
	}
}


OO_TEST(beaconCodeIcon)
{
	SetUp();
	@autoreleasepool
	{
		// Slice 4 (bead oo-2p1ug): the entities hold the code icon by the protocol; the facade keeps
		// the C++ icon's identity.
		OOHUDBeaconCodeIcon *icon = [[[OOHUDBeaconCodeIcon alloc] initWithText:"A"] autorelease];
		OO_CHECK(icon != nil);
		OO_CHECK([icon conformsToProtocol:objc_getProtocol("OOHUDBeaconIcon")]);
		OO_CHECK([icon respondsToSelector:OOSelectorFromName("oo_drawHUDBeaconIconAt:size:alpha:z:")]);
		cxx::OOHUDBeaconCodeIcon *cxxIcon = oo::ToCxx(icon);
		OO_CHECK(cxxIcon != nullptr && oo::ToObjC(cxxIcon) == icon);
	}
}


// --- The C++ API and the facade's contract (bead oo-engam) ----------------------------------

OO_TEST(cxxAPI)
{
	SetUp();
	@autoreleasepool
	{
		oo::Ref<cxx::HeadUpDisplay> hud = oo::makeRef<cxx::HeadUpDisplay>();
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

		oo::Ref<cxx::OOColor> target = hud->reticleColorForIndex(OO_RETICLE_COLOR_TARGET);
		OO_CHECK(target != nullptr && target->redComponent() == 0.0f && target->greenComponent() == 1.0f);
		OO_CHECK(hud->reticleColorForIndex(3) == nullptr);
		oo::Ref<cxx::OOColor> blue = cxx::OOColor::blueColor();
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

		const Vector v = cxx::HeadUpDisplay::nonlinearScannerScale(make_vector(3000.0f, 0.0f, 4000.0f), 1.0f, 256.0);
		OO_CHECK(std::fabs(magnitude(v) - 50.0f) < 1e-4f);
	}
}


OO_TEST(facadeContract)
{
	SetUp();
	@autoreleasepool
	{
		// The facade the caller made is the C++ HUD's peer, and the crossing keeps identity.
		HeadUpDisplay *hud = NewHUD(oo::PList(oo::PList::Dict{}));
		cxx::HeadUpDisplay *cxxHUD = oo::ToCxx(hud);
		OO_CHECK(cxxHUD != nullptr);
		OO_CHECK(oo::ToObjC(cxxHUD) == hud);
		OO_CHECK(oo::ToCxx(static_cast<HeadUpDisplay *>(nil)) == nullptr);
		OO_CHECK(oo::ToObjC(static_cast<cxx::HeadUpDisplay *>(nullptr)) == nil);

		// The same answers through either side.
		cxxHUD->setScannerZoom(3.0f);
		OO_CHECK([hud scannerZoom] == 3.0f);
		[hud setLineWidth:2.0f];
		OO_CHECK(cxxHUD->getLineWidth() == 2.0f);

		// A colour set through the facade is held as its C++ colour and reads back as the same object.
		OOColor *orange = [OOColor orangeColor];
		OO_CHECK([hud setReticleColorForIndex:OO_RETICLE_COLOR_TARGET toColor:orange]);
		OO_CHECK(cxxHUD->reticleColorForIndex(OO_RETICLE_COLOR_TARGET).get() == oo::ToCxx(orange));
		OO_CHECK([hud reticleColorForIndex:OO_RETICLE_COLOR_TARGET] == orange);

		// The dials are the facade's methods, called by name.
		OO_CHECK([hud respondsToSelector:OOSelectorFromName("drawCompass:")]);
		OO_CHECK([hud respondsToSelector:OOSelectorFromName("drawPrimedEquipment:")]);

		// A C++ HUD with no facade gets one when it crosses.
		oo::Ref<cxx::HeadUpDisplay> bare = oo::makeRef<cxx::HeadUpDisplay>();
		HeadUpDisplay *made = oo::ToObjC(bare);
		OO_CHECK(made != nil && oo::ToCxx(made) == bare.get() && oo::ToObjC(bare) == made);
	}
}


OO_TEST_MAIN()
