/*

OOFullScreenController.m


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

#include "OOFullScreenController.h"

#include "OOLogging.h"

OOFullScreenController::OOFullScreenController(MyOpenGLView* view)
    : _gameView(view) {}

MyOpenGLView* OOFullScreenController::gameView() { return _gameView.get(); }

bool OOFullScreenController::inFullScreenMode() {
  OOLogGenericSubclassResponsibility();
  return false;
}

void OOFullScreenController::setFullScreenMode(bool /*value*/) {
  OOLogGenericSubclassResponsibility();
}

oo::PList OOFullScreenController::displayModes() {
  OOLogGenericSubclassResponsibility();
  return oo::PList();
}

oo::PList OOFullScreenController::currentDisplayMode() {
  const oo::PList modes = displayModes();
  const oo::PList::Array* arr = modes.getIf<oo::PList::Array>();
  if (arr == nullptr) return oo::PList();
  const std::size_t idx = indexOfCurrentDisplayMode();
  if (idx >= arr->size()) return oo::PList();
  return (*arr)[idx];
}

std::size_t OOFullScreenController::indexOfCurrentDisplayMode() {
  OOLogGenericSubclassResponsibility();
  return oo::kNotFound;
}

bool OOFullScreenController::setDisplayWidth(std::size_t /*width*/,
                                             std::size_t /*height*/,
                                             std::size_t /*refresh*/) {
  OOLogGenericSubclassResponsibility();
  return false;
}

oo::PList OOFullScreenController::findDisplayModeForWidth(
    std::size_t /*width*/, std::size_t /*height*/, std::size_t /*d_refresh*/) {
  OOLogGenericSubclassResponsibility();
  return oo::PList();
}

void OOFullScreenController::noteMouseInteractionModeChangedFrom(
    OOMouseInteractionMode /*oldMode*/, OOMouseInteractionMode /*newMode*/) {}
