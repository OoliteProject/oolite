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

#include "OOLightParticleEntity.h"
#include "ShipEntity.h"

#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

/*	+flasherWithDictionary: takes the subentity configuration as an
   oo::PList, as does the initializer -cxx_initWithDictionary:.

        The ships and the visual effects make it with flasherWithDictionary(). The engine's JS
   questions reach it through the root's virtual members, and an owner's rescaleBy()
   through cxx::OOSubEntityInterface.
*/

class OOFlasherEntity : public OOLightParticleEntity, public cxx::OOSubEntityInterface {
public:
    // A new flasher, initialised.
    static oo::Ref<OOFlasherEntity> flasherWithDictionary(const oo::PList& dictionary);

    // -cxx_initWithDictionary:'s body, run once right after construction.
    void initWithDictionary(const oo::PList& dictionary);

    bool isActive();
    void setActive(bool active);

    oo::Ref<OOColor> color();
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

    // Entity (OOFlasherEntityExtensions)'s answer; callers ask dynamic_cast<OOFlasherEntity *>.
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
    void setUpColors(const oo::PList* colorSpecifiers); // an array node, or nullptr
    void getCurrentColorComponents();
    OOColor* flasherColorAtIndex(NSUInteger index);

    float _frequency = { };
    float _phase = { };
    float _wave = { };
    float _brightfraction = { };
    std::vector<oo::Ref<OOColor>> _colors;
    NSUInteger _activeColor = { };

    OOTimeDelta _time = { };

    bool _active = { };
    bool _justSwitched = { };
};
