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

#import "OOLightParticleEntity.h"
#import "ShipEntity.h"

#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

/*	Foundation sweep (proposed ADR-0043, bead oo-5lu6): +flasherWithDictionary: is unique and takes
        the subentity configuration as an oo::PList, as does the initializer -cxx_initWithDictionary:
        (bead oo-3rb.292.1; its id twin retired with oo-qps.44).
*/

namespace cxx {

class OOFlasherEntity : public OOLightParticleEntity {
public:
    // +flasherWithDictionary:: a new flasher, initialised. The facade's class method hands it to
    // Objective-C (oo::NewEntityFacade).
    static oo::Ref<OOFlasherEntity> flasherWithDictionary(const oo::PList& dictionary);

    // -cxx_initWithDictionary:'s body, run once right after construction (amendment oo-vl43 item 2).
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

    // OOSubEntity, answered by the facade.
    void rescaleBy(GLfloat factor);
    void rescaleBy(GLfloat factor, bool writeToCache);

    // Entity (OOFlasherEntityExtensions), which the facade's category answers from here.
    bool isFlasher();

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

} // namespace cxx

// Transitional: the Objective-C OOFlasherEntity, for the ships, the visual effects and the
// scripting binding, which make it and message it. Deleted, with namespace cxx above, by the
// bridge's deletion bead.
#import "OOFlasherEntity+ObjCBridge.h"
