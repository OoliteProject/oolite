/*

OOMouseInteractionMode.h


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

#ifndef OO_PLAIN_CPP_UNIT
#include "OOFoundation.h"
#else
/*	Plain C++ translation unit (OOMouseInteractionMode.cpp): only
   BOOL is needed, and OOFoundation.h imports Foundation, which does not compile
   in a plain C++ unit.
*/
#include "oofnd/objc/OOFoundationTypes.h"  // bool
#endif
#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "OOEnumFlags.h"

/*
        OOMouseInteractionMode
        Mouse interaction states, defined in game-centric terms. The precise
        semantics may vary across platforms.

        The primary distinction is between UI screens and flight screens. Flight
        screens are screens 1-4 when neither docked nor paused, or the break
        pattern screen. Every other screen is a UI screen, including screens 1-4
        when paused in flight.

        UI screens are divided between ones with clickable controls (like the
        star chart, outfitting screen and config screen), and ones without (like
        the manifest screen, system data screen and pause screen).

        Flight screens have two modes, one for mouse control enabled and one for
        mouse control disabled.
*/
enum class OOMouseInteractionMode : std::int32_t {
  kUiScreenNoInteraction,
  kUiScreenWithInteraction,
  kFlightNoMouseControl,
  kFlightWithMouseControl,
};
static_assert(static_cast<std::int32_t>(
                  OOMouseInteractionMode::kUiScreenNoInteraction) == 0);
static_assert(static_cast<std::int32_t>(
                  OOMouseInteractionMode::kUiScreenWithInteraction) == 1);
static_assert(static_cast<std::int32_t>(
                  OOMouseInteractionMode::kFlightNoMouseControl) == 2);
static_assert(static_cast<std::int32_t>(
                  OOMouseInteractionMode::kFlightWithMouseControl) == 3);

std::string OOStringFromMouseInteractionMode(OOMouseInteractionMode mode);
bool OOMouseInteractionModeIsUIScreen(OOMouseInteractionMode mode);
bool OOMouseInteractionModeIsFlightMode(OOMouseInteractionMode mode);
