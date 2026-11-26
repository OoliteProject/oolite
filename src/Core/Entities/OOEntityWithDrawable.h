/*

OOEntityWithDrawable.h

Abstract intermediate class for entities which use an OODrawable to render.

C++20 since bead oo-bj8, with Entity the Entities pattern seam (proposed ADR-0056, amendment
oo-bj8). The class is cxx::OOEntityWithDrawable while OOEntityWithDrawable+ObjCBridge.h, imported
at the end of this header, keeps the Objective-C OOEntityWithDrawable that its unconverted
subclasses (ShipEntity, SkyEntity, OOVisualEffectEntity) derive from; the bridge's deletion bead
moves it out of namespace cxx.

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

#import "Entity.h"

@class OODrawable;

namespace cxx {

class OOEntityWithDrawable : public Entity {
public:
    ::OODrawable* getDrawable();
    void setDrawable(::OODrawable* drawable);

    double findCollisionRadius() override;
    void drawImmediate(bool immediate, bool translucent) override;

#ifdef OO_DEBUG_MONITOR_ENABLED
    std::vector<oo::ObjCRef<::OOTexture*>> allTextures() override;
#endif

private:
    // The Objective-C drawable: OOMesh, a drawable still Objective-C, is kept alive by its own
    // object, not by its C++ part (amendment oo-smy item 4).
    oo::ObjCRef<::OODrawable*> drawable;
};

} // namespace cxx

// Transitional: the Objective-C OOEntityWithDrawable, for subclasses not yet converted. Deleted,
// with namespace cxx above, by the bridge's deletion bead.
#import "OOEntityWithDrawable+ObjCBridge.h"
