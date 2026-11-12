/*

OOMouseInteractionMode.m


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

#define OO_PLAIN_CPP_UNIT \
  1  // a plain C++ unit: the shared headers' game-unit parts stay out of it
#include "OOMouseInteractionMode.h"

#include <format>

#include "oofnd/String.hpp"

std::string OOStringFromMouseInteractionMode(OOMouseInteractionMode mode) {
  switch (mode) {
    case OOMouseInteractionMode::kUiScreenNoInteraction:
      return "UI_SCREEN_NO_INTERACTION";
    case OOMouseInteractionMode::kUiScreenWithInteraction:
      return "UI_SCREEN_WITH_INTERACTION";
    case OOMouseInteractionMode::kFlightNoMouseControl:
      return "FLIGHT_NO_MOUSE_CONTROL";
    case OOMouseInteractionMode::kFlightWithMouseControl:
      return "FLIGHT_WITH_MOUSE_CONTROL";
  }

  return std::format("<unknown mode {}>", static_cast<unsigned int>(mode));
}

bool OOMouseInteractionModeIsUIScreen(OOMouseInteractionMode mode) {
  switch (mode) {
    case OOMouseInteractionMode::kUiScreenNoInteraction:
      return true;
    case OOMouseInteractionMode::kUiScreenWithInteraction:
      return true;
    case OOMouseInteractionMode::kFlightNoMouseControl:
      return false;
    case OOMouseInteractionMode::kFlightWithMouseControl:
      return false;
  }

  return false;
}

bool OOMouseInteractionModeIsFlightMode(OOMouseInteractionMode mode) {
  switch (mode) {
    case OOMouseInteractionMode::kUiScreenNoInteraction:
      return false;
    case OOMouseInteractionMode::kUiScreenWithInteraction:
      return false;
    case OOMouseInteractionMode::kFlightNoMouseControl:
      return true;
    case OOMouseInteractionMode::kFlightWithMouseControl:
      return true;
  }

  return false;
}
