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
	Run: bash tools/check-core-tests.sh
*/

#import "GuiDisplayGen.h"

#include "oo_test.hpp"


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


OO_TEST_MAIN()
