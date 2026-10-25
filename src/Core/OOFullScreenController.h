/*

OOFullScreenController.h

Abstract base class for full screen mode controllers. Concrete implementations
exist for different target platforms.


Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#pragma once

#include "OOCocoa.h"
#include "OOMouseInteractionMode.h"

#include "oofnd/Ref.hpp"
#include "oofnd/PList.hpp"
#include <string_view>

#include "MyOpenGLView.h"	// oo::Ref<MyOpenGLView> (C++ since bead oo-9ht.153)


/*	Display-mode dictionary keys. On Mac OS X they were CoreGraphics' kCGDisplay* constants, whose
	values are these same strings (CFSTR("Width") and so on), so a mode dictionary answers to either.
*/
inline constexpr std::string_view kOODisplayWidth			= "Width";
inline constexpr std::string_view kOODisplayHeight		= "Height";
inline constexpr std::string_view kOODisplayRefreshRate	= "RefreshRate";
#if OOLITE_MAC_OS_X
#define kOODisplayBitsPerPixel	(@"BitsPerPixel")
#define kOODisplayIOFlags		(@"IOFlags")
#endif


#define DISPLAY_MIN_COLOURS		32
#define DISPLAY_MIN_WIDTH		640
#define DISPLAY_MIN_HEIGHT		480
#define DISPLAY_MAX_WIDTH		7680		// 8K gaming, yay!!
#define DISPLAY_MAX_HEIGHT		4320


/*	C++20 since bead oo-bgmb (proposed ADR-0056, amendment oo-bgmb). The abstract base of the Mac
	full-screen controllers, which are Mac-only and not in this tree. Its callers (GameController,
	under OO_USE_FULLSCREEN_CONTROLLER, which is OOLITE_MAC_OS_X) are never compiled here, so the
	class has no Objective-C facade and is global. The "subclass responsibility" methods are
	virtual, so a C++ subclass overrides them; the base's bodies still log and answer the default.
*/
class OOFullScreenController : public oo::RefCounted
{
public:
	explicit OOFullScreenController(MyOpenGLView *view);	// -initWithGameView:

	MyOpenGLView *gameView();

	virtual bool inFullScreenMode();
	virtual void setFullScreenMode(bool value);

	virtual oo::PList displayModes();	// array of mode dictionaries (flipped with its family, bead oo-3rb.273)
	oo::PList currentDisplayMode();	// a mode dictionary
	virtual NSUInteger indexOfCurrentDisplayMode();

	virtual bool setDisplayWidth(NSUInteger width, NSUInteger height, NSUInteger refresh);
	virtual oo::PList findDisplayModeForWidth(NSUInteger width, NSUInteger height, NSUInteger d_refresh);	// a mode dictionary; null: none

	virtual void noteMouseInteractionModeChangedFrom(OOMouseInteractionMode oldMode, OOMouseInteractionMode newMode);

private:
	oo::Ref<MyOpenGLView>		_gameView;	// retained, as the Objective-C view was (C++ since bead oo-9ht.153)
};
