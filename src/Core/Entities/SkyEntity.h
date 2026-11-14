/*

SkyEntity.h

Entity subclass implementing the game backdrop of stars and nebulae.

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

#import "OOEntityWithDrawable.h"

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

namespace cxx {

class SkyEntity : public OOEntityWithDrawable {
public:
    /*	-initWithColors::andSystemInfo:'s body after [super init] (the constructor ran Entity's). The
            facade runs it once it holds this object (amendment oo-0mxi item 2), because the universe
            allocates the sky.
    */
    void initWithColors(OOColor* col1, OOColor* col2, const oo::PList& systemInfo);
    bool changeProperty(const std::string& key, const oo::PList& dict);

    OOColor* getSkyColor(); // -skyColor (amendment oo-862e item 1: the ivar keeps the name)

    void update(OOTimeDelta delta_t) override;
    bool isSky() override;
    bool isVisible() override;
    bool canCollide() override;
    GLfloat cameraRangeFront() override;
    GLfloat cameraRangeBack() override;
    void drawImmediate(bool immediate, bool translucent) override;

#ifdef OO_DEBUG_MONITOR_ENABLED
    std::optional<std::string> descriptionForObjDump() override;
#endif

private:
    bool readColor1(oo::Ref<OOColor>* ioColor1, oo::Ref<OOColor>* ioColor2, oo::Ref<OOColor>* ioColor3, oo::Ref<OOColor>* ioColor4, const oo::PList& dictionary);

    oo::Ref<OOColor> skyColor;
};

} // namespace cxx

// Transitional: the Objective-C SkyEntity, for the universe, which makes it, finds it by its class
// and messages it. Deleted, with namespace cxx above, by the bridge's deletion bead.
#import "SkyEntity+ObjCBridge.h"
