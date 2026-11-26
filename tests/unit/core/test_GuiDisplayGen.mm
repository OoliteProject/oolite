/*	test_GuiDisplayGen.mm
	Unit tests for -[GuiDisplayGen rowAtVirtualJoystickPosition:] (src/Core/GuiDisplayGen.h):
	bead oo-3rb.348.

	A mouse click on a GUI screen activates a row. It used to activate UNIVERSE->cursor_row, which
	only -drawGUI:drawCursor:YES recomputes, i.e. the row under the pointer at the LAST RENDER. After
	a stall longer than the GUI tier's 1 s settle, the pointer's motion events and the click arrive in
	one tick, and the click activated a row the pointer had only crossed (G5: aimed at the start
	screen's row 26, activated row 22, NEWGAME). The click now asks the GUI for the row under the
	pointer as it is at click time (PlayerEntityControls ClickedGUIRow), and the render uses the same
	method, so the two cannot disagree. These tests pin that method's maths on the main GUI (480 px
	high, rows 16 px from 40 px down) and that it needs no render.

	GuiDisplayGen's object references Universe and the player, so the test links the whole game but
	main (tests/unit/core/meson.build entry ['*'], ADR-0056 amendment oo-44gg) and defines the one
	global main.mm did, gDebugFlags. UNIVERSE is nil; -init and this method do not use it.

	Bead oo-2g51 (slice 1 of docs/phases/3-slices/GuiDisplayGen.md, Phase 3, house style of proposed
	ADR-0056 and its amendments oo-pni4 and oo-3bgz) added the tests after these four: they pin, through
	the Objective-C API the game uses, what the slice's units computed before the conversion (the two
	initialisers, the sizes, the title rule, the rows' texts and keys, the selection and its skip rows,
	the colours and the colour settings, the fades' alpha, the tab-stop override, clearing and the two
	resizes). They were written against the unconverted class and run on it first (commit 9afc661c6);
	the last two (cxxAPIAnswersTheSame, facadeContract) pin the C++ API and the facade's contract. The units of slices
	2-4 that they reach (-clear's -clearBackground, -cxx_getLastLines, -cxx_setArray:forRow:,
	-cxx_printLineNoScroll:...) run as they are. The settings -init reads (gui-settings.plist, through
	the real ResourceManager) depend on where the test runs, so the tests that need them check that
	they are a dictionary first and pin nothing of their content.
	Run: bash tools/check-core-tests.sh
*/

#import "GuiDisplayGen.h"
#import "OOColor.h"
#import "OOJavaScriptEngine.h"
#import "OOJSEngineCore.h"

#include "oofnd/Data.hpp"
#include "oofnd/FileSystem.hpp"
#include "oofnd/String.hpp"

#include "oo_test.hpp"

#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <process.h>
#include <string>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


namespace {

// The virtual-joystick y that puts the pointer at the vertical middle of main-GUI row `row`
// (the inverse of the row maths: row r spans cursor_y in (200 - 16 r, 216 - 16 r]).
double MiddleOfRow(int row)
{
	double cursor_y = 0.5 * MAIN_GUI_PIXEL_HEIGHT - MAIN_GUI_PIXEL_ROW_START - MAIN_GUI_ROW_HEIGHT * (row - 0.5);
	return -cursor_y / MAIN_GUI_PIXEL_HEIGHT;
}

}	// namespace


OO_TEST(everyRowUnderItsOwnMiddle)
{
	@autoreleasepool
	{
		GuiDisplayGen *gui = [[[GuiDisplayGen alloc] init] autorelease];
		OO_CHECK([gui rowHeight] == MAIN_GUI_ROW_HEIGHT && [gui rowStart] == MAIN_GUI_PIXEL_ROW_START);
		// Rows 0..28 are on screen: row 29's middle (cursor_y -256) is below the GUI's bottom edge
		// (-240), where the pointer is clamped into row 28 (pointerOffTheScreenIsClampedToItsEdge).
		for (int row = 0; row <= 28; row++)
		{
			OO_CHECK_EQ([gui rowAtVirtualJoystickPosition:NSMakePoint(0.0, MiddleOfRow(row))], row);
			// x does not move the row.
			OO_CHECK_EQ([gui rowAtVirtualJoystickPosition:NSMakePoint(0.4, MiddleOfRow(row))], row);
			OO_CHECK_EQ([gui rowAtVirtualJoystickPosition:NSMakePoint(-0.4, MiddleOfRow(row))], row);
		}
	}
}


OO_TEST(rowBorders)
{
	@autoreleasepool
	{
		GuiDisplayGen *gui = [[[GuiDisplayGen alloc] init] autorelease];
		// Row 26 spans cursor_y in (-216, -200]; half a pixel inside and outside each border.
		OO_CHECK_EQ([gui rowAtVirtualJoystickPosition:NSMakePoint(0.0, 200.5 / 480.0)], 26);
		OO_CHECK_EQ([gui rowAtVirtualJoystickPosition:NSMakePoint(0.0, 215.5 / 480.0)], 26);
		OO_CHECK_EQ([gui rowAtVirtualJoystickPosition:NSMakePoint(0.0, 216.5 / 480.0)], 27);
		OO_CHECK_EQ([gui rowAtVirtualJoystickPosition:NSMakePoint(0.0, 199.5 / 480.0)], 25);
	}
}


OO_TEST(pointerOffTheScreenIsClampedToItsEdge)
{
	@autoreleasepool
	{
		GuiDisplayGen *gui = [[[GuiDisplayGen alloc] init] autorelease];
		// cursor_y is clamped to +-240 (half the GUI's height), as the render clamps the pointer.
		OO_CHECK_EQ([gui rowAtVirtualJoystickPosition:NSMakePoint(0.0, 10.0)], 28);	// 1 + floor(440 / 16)
		OO_CHECK_EQ([gui rowAtVirtualJoystickPosition:NSMakePoint(0.0, 0.5)], 28);
		OO_CHECK_EQ([gui rowAtVirtualJoystickPosition:NSMakePoint(0.0, -10.0)], -2);	// 1 + floor(-40 / 16)
		OO_CHECK_EQ([gui rowAtVirtualJoystickPosition:NSMakePoint(0.0, -0.5)], -2);
	}
}


OO_TEST(answersForThePointerNowWithoutARender)
{
	@autoreleasepool
	{
		// The G5 failure: the pointer tweened from row 20 through 22 to 26 and the click came before
		// any render. Nothing is drawn here; the row follows the pointer alone.
		GuiDisplayGen *gui = [[[GuiDisplayGen alloc] init] autorelease];
		OO_CHECK_EQ([gui rowAtVirtualJoystickPosition:NSMakePoint(0.0, MiddleOfRow(20))], 20);
		OO_CHECK_EQ([gui rowAtVirtualJoystickPosition:NSMakePoint(0.0, MiddleOfRow(22))], 22);
		OO_CHECK_EQ([gui rowAtVirtualJoystickPosition:NSMakePoint(0.0, MiddleOfRow(26))], 26);
	}
}


// --- bead oo-2g51: slice 1 (the class shell, sizes, colours, fades, rows and selection) ---

namespace {

bool SameComponents(OOColor *a, OOColor *b)
{
	if (a == nil || b == nil)  return a == b;
	OORGBAComponents ca = [a rgbaComponents], cb = [b rgbaComponents];
	return ca.r == cb.r && ca.g == cb.g && ca.b == cb.b && ca.a == cb.a;
}


std::optional<std::string> RowString(GuiDisplayGen *gui, OOGUIRow row)
{
	const oo::PList text = [gui objectForRow:row];
	if (const std::string *string = text.getIf<std::string>())  return *string;
	return std::nullopt;
}


/*	Selecting a row reports it to the player's scripts (guiSelectedRowChanged), and naming that event
	(OOJSID) needs the JavaScript engine, even though PLAYER is nil and nothing is sent. The engine
	is started once, as test_OOJSScript starts it: in a scratch home and game folder, so that it
	reads none of the machine's own files.
*/
void StartJavaScript()
{
	static bool started = false;
	if (started)  return;
	started = true;
	namespace stdfs = std::filesystem;
	const stdfs::path root = stdfs::temp_directory_path() / ("oo-test-guidisplaygen-" + std::to_string(static_cast<unsigned long>(::_getpid())));
	stdfs::remove_all(root);
	stdfs::create_directories(root / "Resources");
	OO_CHECK(::_putenv_s("HOMEPATH", root.string().c_str()) == 0);
	stdfs::current_path(root);
	const std::string info = "{ CFBundleVersion = \"9.9.9-test\"; }";
	OO_CHECK(oo::fs::writeFile(root / "Resources" / "Info-gnustep.plist", oo::Data(info.data(), info.size()), oo::fs::WriteMode::direct).has_value());
	(void)[OOJavaScriptEngine sharedEngine];
}


// A small GUI made by the second initialiser: 5 rows, no user settings.
GuiDisplayGen *SmallGUI(const std::optional<std::string> &title)
{
	return [[[GuiDisplayGen alloc] cxx_initWithPixelSize:NSMakeSize(200, 100) columns:4 rows:5 rowHeight:12 rowStart:8 title:title] autorelease];
}

}	// namespace


OO_TEST(initDefaults)
{
	@autoreleasepool
	{
		GuiDisplayGen *gui = [[[GuiDisplayGen alloc] init] autorelease];
		OO_CHECK([gui size].width == 480 && [gui size].height == 480);
		OO_CHECK_EQ([gui columns], 6u);
		OO_CHECK_EQ([gui rows], 30u);
		OO_CHECK_EQ([gui rowHeight], 16u);
		OO_CHECK_EQ([gui rowStart], 40);
		OO_CHECK([gui cxx_title] == std::optional<std::string>(""));	// empty, not none
		Vector position = [gui drawPosition];
		OO_CHECK(position.x == 0.0f && position.y == 0.0f && position.z == 640.0f);
		OO_CHECK(SameComponents([gui textColor], [OOColor yellowColor]));
		OO_CHECK([gui textCommsColor] == nil);
		OO_CHECK(RowString(gui, 0) == std::optional<std::string>("."));
		OO_CHECK(RowString(gui, 29) == std::optional<std::string>("."));
		OO_CHECK([gui objectForRow:30].isNull());
		OO_CHECK([gui objectForRow:-1].isNull());
		OO_CHECK([gui cxx_keyForRow:3] == std::optional<std::string>("3"));
		OO_CHECK([gui cxx_keyForRow:30] == std::nullopt);
		OO_CHECK_EQ([gui cxx_rowForKey:"17"], 17);
		OO_CHECK_EQ([gui cxx_rowForKey:"x"], -1);
		OO_CHECK_EQ([gui cxx_rowForKey:std::nullopt], -1);
		OO_CHECK_EQ([gui selectedRow], -1);	// nothing selectable yet
		OO_CHECK([gui selectableRange].location == 0 && [gui selectableRange].length == 0);
		OO_CHECK_EQ([gui alpha], 0.0f);
		OO_CHECK_EQ([gui statusPage], 0u);
	}
}


OO_TEST(initWithPixelSize)
{
	@autoreleasepool
	{
		GuiDisplayGen *gui = SmallGUI("T");
		OO_CHECK([gui size].width == 200 && [gui size].height == 100);
		OO_CHECK_EQ([gui columns], 4u);
		OO_CHECK_EQ([gui rows], 5u);
		OO_CHECK_EQ([gui rowHeight], 12u);
		OO_CHECK_EQ([gui rowStart], 8);
		OO_CHECK([gui cxx_title] == std::optional<std::string>("T"));
		OO_CHECK(RowString(gui, 4) == std::optional<std::string>(""));
		OO_CHECK([gui objectForRow:5].isNull());
		OO_CHECK([gui cxx_keyForRow:0] == std::optional<std::string>(""));
		OO_CHECK_EQ([gui cxx_rowForKey:""], 0);	// the first empty key
		OO_CHECK(SameComponents([gui textColor], [OOColor yellowColor]));
		OO_CHECK([gui cxx_userSettings].isNull());
		Vector position = [gui drawPosition];
		OO_CHECK(position.x == 0.0f && position.y == 0.0f && position.z == 0.0f);
		// The title is kept as given: an empty one stays empty, none stays none.
		OO_CHECK([SmallGUI("") cxx_title] == std::optional<std::string>(""));
		OO_CHECK([SmallGUI(std::nullopt) cxx_title] == std::nullopt);
	}
}


OO_TEST(titleAndDrawPosition)
{
	@autoreleasepool
	{
		GuiDisplayGen *gui = SmallGUI("T");
		[gui cxx_setTitle:"Hello"];
		OO_CHECK([gui cxx_title] == std::optional<std::string>("Hello"));
		[gui cxx_setTitle:""];	// an empty title is no title
		OO_CHECK([gui cxx_title] == std::nullopt);
		[gui cxx_setTitle:"Again"];
		[gui cxx_setTitle:std::nullopt];
		OO_CHECK([gui cxx_title] == std::nullopt);
		[gui setDrawPosition:make_vector(1.0f, -2.0f, 3.5f)];
		Vector position = [gui drawPosition];
		OO_CHECK(position.x == 1.0f && position.y == -2.0f && position.z == 3.5f);
	}
}


OO_TEST(rowTextsAndKeys)
{
	@autoreleasepool
	{
		GuiDisplayGen *gui = SmallGUI("T");
		[gui cxx_setText:"one" forRow:1];
		OO_CHECK(RowString(gui, 1) == std::optional<std::string>("one"));
		[gui cxx_setText:std::optional<std::string>("two") forRow:2 align:GUI_ALIGN_RIGHT];
		OO_CHECK(RowString(gui, 2) == std::optional<std::string>("two"));
		[gui cxx_setText:std::optional<std::string>(std::nullopt) forRow:2 align:GUI_ALIGN_LEFT];	// none: no change
		OO_CHECK(RowString(gui, 2) == std::optional<std::string>("two"));
		[gui cxx_setText:"out" forRow:5];	// out of range: ignored
		[gui cxx_setText:"out" forRow:-1];
		OO_CHECK([gui objectForRow:5].isNull());
		[gui cxx_setKey:"k3" forRow:3];
		[gui cxx_setKey:"k9" forRow:9];	// ignored
		OO_CHECK([gui cxx_keyForRow:3] == std::optional<std::string>("k3"));
		OO_CHECK_EQ([gui cxx_rowForKey:"k3"], 3);
		OO_CHECK_EQ([gui cxx_rowForKey:"k9"], -1);
		[gui cxx_setArray:{ "a", "b" } forRow:4];	// slice 2's unit: a row of columns
		OO_CHECK([gui objectForRow:4].isArray());
		OO_CHECK_EQ([gui objectForRow:4].count(), 2u);

		// The last two rows' text, colour and fade time (slice 2's -cxx_getLastLines) show the colour.
		[gui setColor:[OOColor redColor] forRow:3];
		[gui setColor:[OOColor greenColor] forRow:7];	// ignored
		[gui cxx_setText:"three" forRow:3];
		[gui cxx_setText:"four" forRow:4];
		const oo::PList lines = [gui cxx_getLastLines];
		OO_CHECK_EQ(lines.count(), 6u);
		OO_CHECK(lines.at<std::string>(0) == "three");
		OO_CHECK(lines.at<std::string>(1) == "1 0 0 1");
		OO_CHECK(lines.at<std::string>(3) == "four");
		OO_CHECK(lines.at<std::string>(4) == "0 1 0 1");	// the initialiser's green
	}
}


OO_TEST(selectionSkipsSkipRows)
{
	@autoreleasepool
	{
		StartJavaScript();
		GuiDisplayGen *gui = [[[GuiDisplayGen alloc] init] autorelease];
		[gui clear];	// every key is SKIP-ROW
		OO_CHECK([gui cxx_keyForRow:0] == std::optional<std::string>(GUI_KEY_SKIP));
		for (OOGUIRow row = 2; row <= 6; row++)
		{
			[gui cxx_setKey:oo::str::format("key%d", (int)row) forRow:row];
			[gui cxx_setText:oo::str::format("text%d", (int)row) forRow:row];
		}
		[gui cxx_setKey:std::string(GUI_KEY_SKIP) forRow:4];
		[gui cxx_setArray:{ "first", "second" } forRow:6];
		[gui setSelectableRange:NSMakeRange(2, 5)];
		OO_CHECK([gui selectableRange].location == 2 && [gui selectableRange].length == 5);

		OO_CHECK(![gui setSelectedRow:4]);	// a skip row
		OO_CHECK(![gui setSelectedRow:7]);	// outside the range
		OO_CHECK([gui setSelectedRow:3]);
		OO_CHECK_EQ([gui selectedRow], 3);
		OO_CHECK([gui setSelectedRow:3]);	// already selected
		OO_CHECK([gui cxx_selectedRowKey] == std::optional<std::string>("key3"));
		OO_CHECK([gui cxx_selectedRowText] == std::optional<std::string>("text3"));

		OO_CHECK([gui setNextRow:1]);	// over the skip row
		OO_CHECK_EQ([gui selectedRow], 5);
		OO_CHECK([gui setNextRow:1]);
		OO_CHECK_EQ([gui selectedRow], 6);
		OO_CHECK([gui cxx_selectedRowText] == std::optional<std::string>("first"));	// the first column
		OO_CHECK(![gui setNextRow:1]);	// off the end: unchanged
		OO_CHECK_EQ([gui selectedRow], 6);
		OO_CHECK([gui setNextRow:-2]);
		OO_CHECK_EQ([gui selectedRow], 2);	// 4 is a skip row, 2 is not

		OO_CHECK([gui setLastSelectableRow]);
		OO_CHECK_EQ([gui selectedRow], 6);
		OO_CHECK([gui setFirstSelectableRow]);
		OO_CHECK_EQ([gui selectedRow], 2);

		[gui setNoSelectedRow];
		OO_CHECK_EQ([gui selectedRow], -1);
		OO_CHECK([gui cxx_selectedRowKey] == std::nullopt);

		// A selection outside the selectable range is reported as none, but kept.
		OO_CHECK([gui setSelectedRow:5]);
		[gui setSelectableRange:NSMakeRange(10, 2)];
		OO_CHECK_EQ([gui selectedRow], -1);
		OO_CHECK([gui cxx_selectedRowKey] == std::optional<std::string>("key5"));

		// Nothing selectable (rows 10 and 11 are skip rows, or an empty range): none.
		OO_CHECK(![gui setFirstSelectableRow]);
		OO_CHECK(![gui setLastSelectableRow]);
		OO_CHECK([gui cxx_selectedRowKey] == std::nullopt);
		[gui setSelectableRange:NSMakeRange(0, 0)];
		OO_CHECK(![gui setFirstSelectableRow]);
		OO_CHECK(![gui setLastSelectableRow]);
	}
}


OO_TEST(currentRowIsWhereALineIsPrinted)
{
	@autoreleasepool
	{
		GuiDisplayGen *gui = SmallGUI("T");
		[gui setCurrentRow:3];
		[gui cxx_printLineNoScroll:"printed" align:GUI_ALIGN_LEFT color:nil fadeTime:0.0f key:"pk" addToArray:nullptr];
		OO_CHECK(RowString(gui, 3) == std::optional<std::string>("printed"));
		OO_CHECK([gui cxx_keyForRow:3] == std::optional<std::string>("pk"));
		[gui setCurrentRow:5];	// out of range: no current row (and no text cursor)
		[gui setCurrentRow:1];
		[gui cxx_printLineNoScroll:"again" align:GUI_ALIGN_LEFT color:nil fadeTime:0.0f key:std::nullopt addToArray:nullptr];
		OO_CHECK(RowString(gui, 1) == std::optional<std::string>("again"));
		[gui setShowTextCursor:YES];
	}
}


OO_TEST(alphaAndFades)
{
	@autoreleasepool
	{
		GuiDisplayGen *gui = SmallGUI("T");
		[gui setAlpha:0.5f];
		OO_CHECK_EQ([gui alpha], 0.5f);	// max alpha 1
		[gui setMaxAlpha:0.5f];
		[gui setAlpha:0.5f];
		OO_CHECK_EQ([gui alpha], 0.25f);
		[gui fadeOutFromTime:10.0 overDuration:2.0];
		[gui fadeOutFromTime:10.0 overDuration:0.0];
		[gui stopFadeOuts];
		OO_CHECK_EQ([gui alpha], 0.25f);	// fading happens as the GUI is drawn
		[gui setAlpha:0.0f];
		[gui fadeOutFromTime:10.0 overDuration:2.0];	// nothing to fade
		OO_CHECK_EQ([gui alpha], 0.0f);
	}
}


OO_TEST(coloursAndColourSettings)
{
	@autoreleasepool
	{
		GuiDisplayGen *gui = SmallGUI("T");
		OOColor *red = [OOColor redColor];
		[gui setTextColor:red];
		OO_CHECK([gui textColor] == red);
		[gui setTextColor:nil];
		OO_CHECK(SameComponents([gui textColor], [OOColor yellowColor]));
		[gui setTextCommsColor:red];
		OO_CHECK([gui textCommsColor] == red);
		[gui setTextCommsColor:nil];
		OO_CHECK(SameComponents([gui textCommsColor], [OOColor yellowColor]));
		[gui setBackgroundColor:red];
		[gui setBackgroundColor:nil];

		// No settings: the default, else the text colour, as a copy.
		[gui setTextColor:[OOColor blueColor]];
		OO_CHECK(SameComponents([gui cxx_colorFromSetting:"anything" defaultValue:nil], [OOColor blueColor]));
		OO_CHECK(SameComponents([gui cxx_colorFromSetting:std::nullopt defaultValue:nil], [OOColor blueColor]));
		OO_CHECK(SameComponents([gui cxx_colorFromSetting:"anything" defaultValue:[OOColor greenColor]], [OOColor greenColor]));
		[gui cxx_setGuiColorSettingFromKey:"k" color:red];	// no settings: nothing to change
		OO_CHECK([gui cxx_userSettings].isNull());

		// With settings (gui-settings.plist, when the test finds it), a set colour is read back.
		GuiDisplayGen *main = [[[GuiDisplayGen alloc] init] autorelease];
		if ([main cxx_userSettings].isDict())
		{
			[main cxx_setGuiColorSettingFromKey:"oo_test_colour" color:red];
			OO_CHECK([main cxx_userSettings].find("oo_test_colour") != nullptr);
			OO_CHECK(SameComponents([main cxx_colorFromSetting:"oo_test_colour" defaultValue:[OOColor greenColor]], red));
			[main cxx_setGuiColorSettingFromKey:"oo_test_colour" color:nil];
			OO_CHECK([main cxx_userSettings].find("oo_test_colour") == nullptr);
			OO_CHECK(SameComponents([main cxx_colorFromSetting:"oo_test_colour" defaultValue:[OOColor greenColor]], [OOColor greenColor]));
		}
	}
}


OO_TEST(tabStops)
{
	@autoreleasepool
	{
		GuiDisplayGen *gui = SmallGUI("T");
		OOGUITabSettings stops = { 0, 10, 20 };
		[gui setTabStops:stops];
		[gui setTabStops:NULL];
		// No settings: the stops are left as they are.
		[gui cxx_overrideTabs:stops from:"equipment_tabs" length:3];
		OO_CHECK(stops[0] == 0 && stops[1] == 10 && stops[2] == 20);
		[gui cxx_overrideTabs:NULL from:"equipment_tabs" length:3];
		[gui setCharacterSize:NSMakeSize(8, 8)];
		[gui setShowAdvancedNavArray:YES];
	}
}


OO_TEST(clearAndResize)
{
	@autoreleasepool
	{
		GuiDisplayGen *gui = SmallGUI("T");
		[gui cxx_setText:"x" forRow:2];
		[gui cxx_setKey:"k" forRow:2];
		[gui setSelectableRange:NSMakeRange(0, 3)];
		[gui clearAndKeepBackground:YES];
		OO_CHECK([gui cxx_title] == std::nullopt);
		OO_CHECK(RowString(gui, 2) == std::optional<std::string>(""));
		OO_CHECK([gui cxx_keyForRow:2] == std::optional<std::string>(GUI_KEY_SKIP));
		OO_CHECK([gui selectableRange].length == 0);
		[gui cxx_setTitle:"T"];
		[gui clear];
		OO_CHECK([gui cxx_title] == std::nullopt);

		// Resize with explicit metrics: the title follows -setTitle:'s rule.
		[gui cxx_resizeWithPixelSize:NSMakeSize(300, 200) columns:3 rows:4 rowHeight:10 rowStart:5 title:""];
		OO_CHECK([gui size].width == 300 && [gui size].height == 200);
		OO_CHECK_EQ([gui columns], 3u);
		OO_CHECK_EQ([gui rows], 4u);
		OO_CHECK_EQ([gui rowHeight], 10u);
		OO_CHECK_EQ([gui rowStart], 5);
		OO_CHECK([gui cxx_title] == std::nullopt);
		OO_CHECK([gui objectForRow:4].isNull());	// the row range is 0..3 now
		[gui cxx_resizeWithPixelSize:NSMakeSize(300, 200) columns:3 rows:4 rowHeight:10 rowStart:5 title:"R"];
		OO_CHECK([gui cxx_title] == std::optional<std::string>("R"));

		// Resize to a character height: the metrics follow from it, and a title moves the rows down.
		[gui cxx_resizeTo:NSMakeSize(320, 168) characterHeight:16 title:"R"];
		OO_CHECK_EQ([gui columns], 20u);
		OO_CHECK_EQ([gui rows], 10u);
		OO_CHECK_EQ([gui rowHeight], 16u);
		OO_CHECK_EQ([gui rowStart], 48);	// 2.75 * 16 + 0.5 * (168 - 160)
		OO_CHECK([gui cxx_title] == std::nullopt);	// the closing -clear drops the title the rows made room for
		OO_CHECK(RowString(gui, 9) == std::optional<std::string>(""));
		OO_CHECK([gui cxx_keyForRow:9] == std::optional<std::string>(GUI_KEY_SKIP));
		OO_CHECK([gui objectForRow:10].isNull());
		[gui cxx_resizeTo:NSMakeSize(320, 168) characterHeight:16 title:std::nullopt];
		OO_CHECK_EQ([gui rowStart], 20);	// 16 + 0.5 * 8
		OO_CHECK([gui cxx_title] == std::nullopt);
	}
}


// --- after the conversion: the C++ API and the facade's contract ---

OO_TEST(cxxAPIAnswersTheSame)
{
	@autoreleasepool
	{
		oo::Ref<cxx::GuiDisplayGen> gui = oo::makeRef<cxx::GuiDisplayGen>(NSMakeSize(200, 100), 4, 5, 12, 8, std::optional<std::string>("T"));
		OO_CHECK_EQ(gui->columns(), 4u);
		OO_CHECK_EQ(gui->rows(), 5u);
		OO_CHECK_EQ(gui->rowHeight(), 12u);
		OO_CHECK_EQ(gui->rowStart(), 8);
		OO_CHECK(gui->getTitle() == std::optional<std::string>("T"));
		gui->setTitle("");
		OO_CHECK(gui->getTitle() == std::nullopt);
		gui->setText("one", 1);
		gui->setKey("k1", 1);
		OO_CHECK(gui->objectForRow(1) == oo::PList("one"));
		OO_CHECK(gui->keyForRow(1) == std::optional<std::string>("k1"));
		OO_CHECK_EQ(gui->rowForKey("k1"), 1);
		gui->setSelectableRange(NSMakeRange(0, 3));
		OO_CHECK(gui->getSelectableRange().location == 0 && gui->getSelectableRange().length == 3);
		gui->setMaxAlpha(0.5f);
		gui->setAlpha(1.0f);
		OO_CHECK_EQ(gui->alpha(), 0.5f);
		gui->setDrawPosition(make_vector(1.0f, 2.0f, 3.0f));
		OO_CHECK(gui->getDrawPosition().z == 3.0f);
		OO_CHECK(SameComponents(gui->getTextColor(), [OOColor yellowColor]));
		OO_CHECK_EQ(gui->rowAtVirtualJoystickPosition(NSMakePoint(0.0, 0.0)), 4);	// 1 + floor((50 - 8) / 12)
		gui->clearAndKeepBackground(true);
		OO_CHECK(gui->keyForRow(1) == std::optional<std::string>(GUI_KEY_SKIP));

		oo::Ref<cxx::GuiDisplayGen> main = oo::makeRef<cxx::GuiDisplayGen>();
		OO_CHECK_EQ(main->rows(), 30u);
		OO_CHECK(main->objectForRow(0) == oo::PList("."));
	}
}


OO_TEST(facadeContract)
{
	@autoreleasepool
	{
		// The facade the universe makes with +alloc/-init is the C++ GUI's one facade.
		GuiDisplayGen *facade = [[[GuiDisplayGen alloc] init] autorelease];
		cxx::GuiDisplayGen *gui = oo::ToCxx(facade);
		OO_CHECK(gui != nullptr);
		OO_CHECK(oo::ToObjC(gui) == facade);
		OO_CHECK(oo::ToObjC(gui) == oo::ToObjC(gui));
		GuiDisplayGen *small = SmallGUI("T");
		OO_CHECK(oo::ToObjC(oo::ToCxx(small)) == small);
		OO_CHECK(oo::ToObjC(static_cast<cxx::GuiDisplayGen *>(nullptr)) == nil);
		OO_CHECK(oo::ToCxx(static_cast<GuiDisplayGen *>(nil)) == nullptr);

		// The same answers from either side.
		[facade cxx_setText:"x" forRow:3];
		OO_CHECK(gui->objectForRow(3) == oo::PList("x"));
		gui->setKey("k", 3);
		OO_CHECK([facade cxx_keyForRow:3] == std::optional<std::string>("k"));

		// A C++ GUI made first gets a facade on demand, and keeps it while it is used.
		oo::Ref<cxx::GuiDisplayGen> made = oo::makeRef<cxx::GuiDisplayGen>(NSMakeSize(100, 100), 2, 3, 10, 0, std::optional<std::string>());
		GuiDisplayGen *madeFacade = oo::ToObjC(made);
		OO_CHECK(madeFacade != nil && oo::ToCxx(madeFacade) == made.get());
		OO_CHECK_EQ([madeFacade rows], 3u);
		// The facade's category (slices 2-4) reaches the same state.
		[madeFacade cxx_setArray:{ "a", "b" } forRow:2];
		OO_CHECK(made->objectForRow(2).isArray());
	}
}


// --- bead oo-6dvw: slice 2 (text layout and printing, arrays, scrolling, textures, the status page) ---
// The unit test links no font: until the HUD's text engine has loaded oolite-font.plist every
// glyph is 0 wide, so a line always fits and long text is split only at its newlines.

OO_TEST(longTextAndReflow)
{
	@autoreleasepool
	{
		GuiDisplayGen *gui = SmallGUI("T");
		OO_CHECK_EQ([gui cxx_addLongText:std::nullopt startingAtRow:1 align:GUI_ALIGN_LEFT], 1);
		OO_CHECK_EQ([gui cxx_addLongText:"one line" startingAtRow:1 align:GUI_ALIGN_LEFT], 2);
		OO_CHECK(RowString(gui, 1) == std::optional<std::string>("one line"));
		OO_CHECK_EQ([gui cxx_addLongText:"a\nb\nc" startingAtRow:2 align:GUI_ALIGN_CENTER], 5);
		OO_CHECK(RowString(gui, 2) == std::optional<std::string>("a"));
		OO_CHECK(RowString(gui, 4) == std::optional<std::string>("c"));

		OO_CHECK([gui cxx_reflowTextForMFD:std::nullopt] == std::optional<std::string>(""));
		OO_CHECK([gui cxx_reflowTextForMFD:"one  two\nthree"] == std::optional<std::string>("one two\nthree\n"));
		OO_CHECK([gui cxx_reflowTextForMFD:""] == std::optional<std::string>("\n"));
	}
}


OO_TEST(printingScrollsAndKeepsTheLines)
{
	@autoreleasepool
	{
		GuiDisplayGen *gui = SmallGUI("T");	// 5 rows
		[gui setCurrentRow:3];
		std::vector<std::string> printed;
		[gui cxx_printLongText:"first\nsecond" align:GUI_ALIGN_LEFT color:[OOColor redColor] fadeTime:2.0f key:"pk" addToArray:&printed];
		OO_CHECK(printed == (std::vector<std::string>{ "first", "second" }));
		// "first" goes on row 3; "second" would go on the last row, so everything scrolls up by one
		// before it is printed: "first" on row 2, row 3 empty.
		OO_CHECK(RowString(gui, 2) == std::optional<std::string>("first"));
		OO_CHECK(RowString(gui, 3) == std::optional<std::string>(""));
		OO_CHECK(RowString(gui, 4) == std::optional<std::string>("second"));
		OO_CHECK([gui cxx_keyForRow:4] == std::optional<std::string>("pk"));
		// The current row is still the last: the next line scrolls everything up by one again.
		[gui cxx_printLongText:"third" align:GUI_ALIGN_LEFT color:nil fadeTime:0.0f key:std::nullopt addToArray:nullptr];
		OO_CHECK(RowString(gui, 1) == std::optional<std::string>("first"));
		OO_CHECK(RowString(gui, 2) == std::optional<std::string>(""));
		OO_CHECK(RowString(gui, 3) == std::optional<std::string>("second"));
		OO_CHECK(RowString(gui, 4) == std::optional<std::string>("third"));
		[gui cxx_printLongText:std::nullopt align:GUI_ALIGN_LEFT color:nil fadeTime:0.0f key:std::nullopt addToArray:&printed];
		OO_CHECK_EQ(printed.size(), 2u);

		const oo::PList lines = [gui cxx_getLastLines];
		OO_CHECK(lines.at<std::string>(0) == "second");
		OO_CHECK(lines.at<std::string>(1) == "1 0 0 1");
		OO_CHECK(lines.at<double>(2) == 2.0);
		OO_CHECK(lines.at<std::string>(3) == "third");

		[gui scrollUp:2];
		OO_CHECK(RowString(gui, 0) == std::optional<std::string>(""));
		OO_CHECK(RowString(gui, 1) == std::optional<std::string>("second"));
		OO_CHECK(RowString(gui, 2) == std::optional<std::string>("third"));
		OO_CHECK(RowString(gui, 3) == std::optional<std::string>(""));
		OO_CHECK([gui cxx_keyForRow:4] == std::optional<std::string>(""));

		[gui leaveLastLine];
		OO_CHECK(RowString(gui, 0) == std::optional<std::string>(""));
		OO_CHECK(RowString(gui, 4) == std::optional<std::string>(""));	// the last row is kept (it was empty)
		const oo::PList last = [gui cxx_getLastLines];
		OO_CHECK(last.at<double>(5) > 0.39 && last.at<double>(5) < 0.41);	// it fades
	}
}


OO_TEST(arraysAndInsertedItems)
{
	@autoreleasepool
	{
		GuiDisplayGen *gui = SmallGUI("T");
		[gui cxx_setArray:{ "a", "b", "c" } forRow:0];
		OO_CHECK_EQ([gui objectForRow:0].count(), 3u);
		[gui cxx_setArray:{ "x" } forRow:5];	// out of range
		OO_CHECK([gui objectForRow:5].isNull());

		for (OOGUIRow row = 0; row < 5; row++)
		{
			[gui cxx_setText:oo::str::format("r%d", (int)row) forRow:row];
			[gui cxx_setKey:oo::str::format("k%d", (int)row) forRow:row];
		}
		const oo::PList items(oo::PList::Array{ oo::PList("new1"), oo::PList(oo::PList::Array{ oo::PList("c1"), oo::PList("c2") }) });
		const oo::PList keys(oo::PList::Array{ oo::PList("n1"), oo::PList("n2") });
		[gui cxx_insertItemsFromArray:items withKeys:keys intoRow:1 color:nil];
		OO_CHECK(RowString(gui, 0) == std::optional<std::string>("r0"));
		OO_CHECK(RowString(gui, 1) == std::optional<std::string>("new1"));
		OO_CHECK([gui objectForRow:2].isArray());
		OO_CHECK(RowString(gui, 3) == std::optional<std::string>("r1"));
		OO_CHECK(RowString(gui, 4) == std::optional<std::string>("r2"));
		OO_CHECK([gui cxx_keyForRow:2] == std::optional<std::string>("n2"));
		OO_CHECK([gui cxx_keyForRow:4] == std::optional<std::string>("k2"));

		// Without keys the inserted rows get empty keys; nothing to insert changes nothing.
		[gui cxx_insertItemsFromArray:oo::PList(oo::PList::Array{ oo::PList("only") }) withKeys:oo::PList() intoRow:0 color:[OOColor redColor]];
		OO_CHECK(RowString(gui, 0) == std::optional<std::string>("only"));
		OO_CHECK([gui cxx_keyForRow:0] == std::optional<std::string>(""));
		[gui cxx_insertItemsFromArray:oo::PList() withKeys:oo::PList() intoRow:0 color:nil];
		[gui cxx_insertItemsFromArray:oo::PList(oo::PList::Array{}) withKeys:oo::PList() intoRow:0 color:nil];
		OO_CHECK(RowString(gui, 0) == std::optional<std::string>("only"));

		// Keys of another length raise.
		bool raised = false;
		@try
		{
			[gui cxx_insertItemsFromArray:items withKeys:oo::PList(oo::PList::Array{ oo::PList("one") }) intoRow:0 color:nil];
		}
		@catch (id exception)
		{
			raised = true;
		}
		OO_CHECK(raised);
	}
}


OO_TEST(statusPage)
{
	@autoreleasepool
	{
		GuiDisplayGen *gui = SmallGUI("T");
		[gui setStatusPage:0];
		OO_CHECK_EQ([gui statusPage], 1u);
		[gui setStatusPage:2];
		OO_CHECK_EQ([gui statusPage], 3u);
		[gui setStatusPage:-1];
		OO_CHECK_EQ([gui statusPage], 2u);
		[gui setStatusPage:-2];	// would reach 0: back to the first page
		OO_CHECK_EQ([gui statusPage], 1u);
		[gui cxx_drawEquipmentList:oo::PList() z:0.0f];	// nothing to draw
		[gui cxx_drawEquipmentList:oo::PList(oo::PList::Array{}) z:0.0f];
	}
}


OO_TEST(noTexturesWithoutAUniverse)
{
	@autoreleasepool
	{
		StartJavaScript();
		GuiDisplayGen *gui = SmallGUI("T");
		// No texture is named: no sprite.
		OO_CHECK(![gui cxx_setBackgroundTextureDescriptor:oo::PList()]);
		OO_CHECK(![gui cxx_setForegroundTextureDescriptor:oo::PList()]);
		OO_CHECK(![gui cxx_setBackgroundTextureKey:std::nullopt]);
		OO_CHECK(![gui cxx_setForegroundTextureKey:"anything"]);
		OO_CHECK(![gui cxx_preloadGUITexture:oo::PList()]);
		[gui clearBackground];
		[gui setBackgroundTextureSpecial:GUI_BACKGROUND_SPECIAL_LONG withBackground:YES];
		[gui setBackgroundTextureSpecial:GUI_BACKGROUND_SPECIAL_NONE withBackground:NO];

		// A JS null is "no texture" (an empty descriptor), and an empty string the same.
		JSContext *context = OOJSAcquireContext();
		const oo::PList none = [gui cxx_textureDescriptorFromJSValue:JS_NULL inContext:context callerDescription:"test"];
		OO_CHECK(none.isDict() && none.count() == 0);
		OOJSRelinquishContext(context);
	}
}


OO_TEST(cxxSlice2API)
{
	@autoreleasepool
	{
		StartJavaScript();
		oo::Ref<cxx::GuiDisplayGen> gui = oo::makeRef<cxx::GuiDisplayGen>(NSMakeSize(200, 100), 4, 5, 12, 8, std::optional<std::string>("T"));
		OO_CHECK_EQ(gui->addLongText("a\nb", 0, GUI_ALIGN_LEFT), 2);
		OO_CHECK(gui->objectForRow(1) == oo::PList("b"));
		OO_CHECK(gui->reflowTextForMFD("x y") == std::optional<std::string>("x y\n"));
		gui->setCurrentRow(2);
		std::vector<std::string> printed;
		gui->printLineNoScroll("p", GUI_ALIGN_LEFT, nil, 0.0f, std::optional<std::string>("pk"), &printed);
		OO_CHECK(gui->keyForRow(2) == std::optional<std::string>("pk") && printed.size() == 1);
		gui->setArray({ "c1", "c2" }, 3);
		OO_CHECK(gui->objectForRow(3).isArray());
		gui->scrollUp(1);
		OO_CHECK(gui->objectForRow(2).isArray());
		gui->setStatusPage(0);
		OO_CHECK_EQ(gui->getStatusPage(), 1u);
		OO_CHECK(!gui->setBackgroundTextureDescriptor(oo::PList()));
		OO_CHECK(!gui->preloadGUITexture(oo::PList()));
		gui->clearBackground();
		gui->leaveLastLine();
		OO_CHECK(gui->getLastLines().isArray());
		// The facade forwards slice 2's selectors to the same object.
		GuiDisplayGen *facade = oo::ToObjC(gui);
		[facade cxx_setArray:{ "f" } forRow:0];
		OO_CHECK(gui->objectForRow(0).isArray());
		OO_CHECK_EQ([facade statusPage], 1u);
	}
}


// --- bead oo-bcz4: slice 3 (drawing, the star chart's title, found systems) ---
// No universe and no player (both nil): the drawing has no view to ask, no chart to draw and no
// found systems, so these pin what the units do without them.

OO_TEST(drawingWithoutAUniverse)
{
	@autoreleasepool
	{
		StartJavaScript();
		GuiDisplayGen *gui = SmallGUI("T");
		OO_CHECK_EQ([gui drawGUI:0.0f drawCursor:NO], 0);	// too faint to draw: nothing, row 0
		[gui setAlpha:0.5f];
		[gui fadeOutFromTime:0.0 overDuration:1.0];
		OO_CHECK_EQ([gui drawGUI:0.0f drawCursor:NO], 0);
		OO_CHECK_EQ([gui alpha], 0.5f);	// the fade moves only as the GUI is drawn visibly
		[gui drawGUIBackground];	// no background sprite
		[gui refreshStarChart];
		OO_CHECK_EQ([gui targetNextFoundSystem:1], 0);	// not on a chart screen: the player's target
		OO_CHECK_EQ([gui targetNextFoundSystem:0], 0);
	}
}


OO_TEST(starChartTitleWithoutAUniverse)
{
	@autoreleasepool
	{
		StartJavaScript();
		GuiDisplayGen *gui = SmallGUI("T");
		[gui setStarChartTitle];
		const std::optional<std::string> title = [gui cxx_title];
		std::printf("  star chart title: %s\n", title ? title->c_str() : "(none)");
		OO_CHECK(title != std::optional<std::string>("T"));	// replaced
	}
}


OO_TEST(cxxSlice3API)
{
	@autoreleasepool
	{
		StartJavaScript();
		oo::Ref<cxx::GuiDisplayGen> gui = oo::makeRef<cxx::GuiDisplayGen>(NSMakeSize(200, 100), 4, 5, 12, 8, std::optional<std::string>("T"));
		OO_CHECK_EQ(gui->drawGUI(0.0f, false), 0);
		gui->drawGUIBackground();
		gui->refreshStarChart();
		OO_CHECK_EQ(gui->targetNextFoundSystem(1), 0);
		gui->setStarChartTitle();
		OO_CHECK(gui->getTitle() != std::optional<std::string>("T"));
		// The facade forwards slice 3's selectors, and the ones slice 4 still sends.
		GuiDisplayGen *facade = oo::ToObjC(gui);
		OO_CHECK_EQ([facade drawGUI:0.0f drawCursor:NO], 0);
		OO_CHECK([facade respondsToSelector:@selector(drawSystemMarkers:atX:andY:andZ:withAlpha:andScale:)]);
	}
}


OO_TEST_MAIN()
