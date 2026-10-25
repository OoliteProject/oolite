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

#pragma once

#include "OOLightParticleEntity.h"


/*	C++ only since bead oo-9ht.106 deleted its Objective-C facade (ADR-0056 amendments oo-9ht.107,
	oo-9ht.23 and oo-9ht.106): the ship and the universe call the factories and hand the flash to
	Objective-C with oo::NewEntityFacade, whose object is the root Entity's facade.
*/
class OOFlashEffectEntity : public OOLightParticleEntity
{
public:
	// +explosionFlashFromEntity: and +laserFlashWithPosition:velocity:color:: a new flash,
	// initialised. Callers hand it to Objective-C with oo::NewEntityFacade.
	static oo::Ref<OOFlashEffectEntity> explosionFlashFromEntity(Entity *entity);	// the C++ entity (bead oo-al52f)
	static oo::Ref<OOFlashEffectEntity> laserFlashWithPosition(HPVector position, Vector vel, OOColor *color);

	static void setUpTexture();
	// Called by the texture's file-local graphics reset client.
	static void resetGraphicsState();

	void update(OOTimeDelta delta_t) override;
	OOTexture *texture() override;

private:
	// The initialisers' bodies, run once right after construction (amendment oo-vl43 item 2).
	void initExplosionFlashWithPosition(HPVector pos, Vector vel, float size);
	void initLaserFlashWithPosition(HPVector pos, Vector vel, OOColor *color);
	// Designated initializer.
	void initWithPosition(HPVector pos, float size, OOColor *color, float duration);

	float				_duration = {};
	float				_growthRate = {};
	float				_alpha = {};
};
