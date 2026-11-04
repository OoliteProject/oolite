/*

OOStringWidth.h

cxx_OOStringWidthInEm(), declared here, not in HeadUpDisplay.h, so a plain C++
translation unit (OOJSFont) can call it without parsing an @interface.
HeadUpDisplay.h includes it back; the definition stays in HeadUpDisplay.mm.
CGFloat is the floor's C type.


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

#include <string>

#include "oofnd/objc/OOFoundationTypes.h"

CGFloat cxx_OOStringWidthInEm(const std::string& text);
