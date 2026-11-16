/*

OOFlasherEntity.h

Flashing light attached to ships.


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

#include "OOLightParticleEntity.h"
#include "ShipEntity.h"
#include "oofnd/Object.hpp"
#include "oofnd/PList.hpp"

/*	+flasherWithDictionary: takes the subentity configuration as an
   oo::PList, as does the initializer -initWithDictionary:.

        The ships and the visual effects make it with flasherWithDictionary().
   The engine's JS questions reach it through the root's virtual members, and an
   owner's rescaleBy() through cxx::OOSubEntityInterface.
*/

class OOFlasherEntity : public OOLightParticleEntity,
                        public cxx::OOSubEntityInterface {
 public:
  // A new flasher, initialised.
  static std::shared_ptr<OOFlasherEntity> flasherWithDictionary(
      const oo::PList& dictionary);

  // -initWithDictionary:'s body, run once right after construction.
  void initWithDictionary(const oo::PList& dictionary);

  bool isActive();
  void setActive(bool active);

  std::shared_ptr<OOColor> color();
  // setColor is defined by superclass

  float frequency();
  void setFrequency(float frequency);

  float phase();
  void setPhase(float phase);

  float fraction();
  void setFraction(float fraction);

  // OOSubEntity.
  void rescaleBy(GLfloat factor) override;
  void rescaleBy(GLfloat factor, bool writeToCache) override;

  // Entity (OOFlasherEntityExtensions)'s answer; callers ask
  // dynamic_cast<OOFlasherEntity *>.
  bool isFlasher();

  // Entity (OOJavaScriptExtensions): the binding's bodies (OOJSFlasher.h).
  JSClassID jsClassID() override;
  std::optional<std::string> jsClassName() override;
  bool isVisibleToScripts() override;

  void update(OOTimeDelta delta_t) override;
  void drawImmediate(bool immediate, bool translucent) override;
  void drawSubEntityImmediate(bool immediate, bool translucent) override;
  double findCollisionRadius() override;

 private:
  void setUpColors(
      const oo::PList* colorSpecifiers);  // an array node, or nullptr
  void getCurrentColorComponents();
  OOColor* flasherColorAtIndex(std::size_t index);

  float _frequency = {};
  float _phase = {};
  float _wave = {};
  float _brightfraction = {};
  std::vector<std::shared_ptr<OOColor>> _colors;
  std::size_t _activeColor = {};

  OOTimeDelta _time = {};

  bool _active = {};
  bool _justSwitched = {};
};
