/*

OOFlashEffectEntity.h

Flashes during explosions and laser hits - not to be confused with flashers.


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

namespace cxx {

class OOFlashEffectEntity : public OOLightParticleEntity {
public:
    // +explosionFlashFromEntity: and +laserFlashWithPosition:velocity:color:: a new flash,
    // initialised. The facade's class methods hand it to Objective-C (oo::NewEntityFacade).
    static oo::Ref<OOFlashEffectEntity> explosionFlashFromEntity(::Entity* entity);
    static oo::Ref<OOFlashEffectEntity> laserFlashWithPosition(HPVector position, Vector vel, OOColor* color);

    static void setUpTexture();
    // The graphics reset client is the facade class, which forwards here.
    static void resetGraphicsState();

    void update(OOTimeDelta delta_t) override;
    ::OOTexture* texture() override;

private:
    // The initialisers' bodies, run once right after construction (amendment oo-vl43 item 2).
    void initExplosionFlashWithPosition(HPVector pos, Vector vel, float size);
    void initLaserFlashWithPosition(HPVector pos, Vector vel, OOColor* color);
    // Designated initializer.
    void initWithPosition(HPVector pos, float size, OOColor* color, float duration);

    float _duration = { };
    float _growthRate = { };
    float _alpha = { };
};

} // namespace cxx

// Transitional: the Objective-C OOFlashEffectEntity, for the ship and the universe, which message
// the class. Deleted, with namespace cxx above, by the bridge's deletion bead.
#import "OOFlashEffectEntity+ObjCBridge.h"
