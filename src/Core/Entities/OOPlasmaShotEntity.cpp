/*

OOPlasmaShotEntity.m

C++20 since bead oo-z9md (see OOPlasmaShotEntity.h). The bodies are the Objective-C ones: a
message to self is a member call, [super ...] the base's member, and the universe and the entity
hit are handed the shot (its C++ entity since bead oo-xn1j1).


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

#include "OOPlasmaShotEntity.h"
#include "Universe.h"
#include "PlayerEntity.h"
#include "OOColor.h"
#include "OOPlasmaBurstEntity.h"


#define kPlasmaShotSize				12.0f
#define kPlasmaShotActivationDelay	0.05f


/*	If nonzero, plasma shots fade with distance. Bits of this were in the old
	ParticleEntity code, but I think it was disabled on purpose.
	-- Ahruman 2009-09-25
*/
#define PLASMA_ATTENUATION 0


oo::Ref<OOPlasmaShotEntity> OOPlasmaShotEntity::shotWithPosition(HPVector inPosition,
																  Vector inVelocity,
																  float inEnergy,
																  OOTimeDelta duration,
																  OOColor *color)
{
	const oo::Ref<OOPlasmaShotEntity> shot = oo::makeRef<OOPlasmaShotEntity>();
	shot->initWithPosition(inPosition, inVelocity, inEnergy, duration, color);
	return shot;
}


void OOPlasmaShotEntity::initWithPosition(HPVector inPosition,
										  Vector inVelocity,
										  float inEnergy,
										  OOTimeDelta duration,
										  OOColor *color)
{
	OOLightParticleEntity::initWithDiameter(kPlasmaShotSize);
	// [super initWithDiameter:] could not fail.
	{
		setPosition(inPosition);
		setVelocity(inVelocity);
		setCollisionRadius(2.0);
		
		setColor(color, 1.0);
		_colorComponents[3] = 1.0f;
		
		setEnergy(inEnergy);
		_duration = duration;
	}
}


bool OOPlasmaShotEntity::canCollide()
{
	return (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) > getSpawnTime() + kPlasmaShotActivationDelay;
}


// The other entity's members (its object's until bead oo-zwnvp); null answers as a message to nil did.
bool OOPlasmaShotEntity::checkCloseCollisionWith(Entity *otherEntity)
{
	return ((otherEntity != nullptr ? otherEntity->rootShipEntity() : nullptr) != ownerEntity()) && !(otherEntity != nullptr && otherEntity->isEffect());
}


void OOPlasmaShotEntity::update(double delta_t)
{
	OOLightParticleEntity::update(delta_t);
	
	OOTimeDelta lifeTime = timeElapsedSinceSpawn();
	
#if PLASMA_ATTENUATION
	float attenuation = OOClamp_0_1_f(1.0f - lifeTime / _duration);
#else
	const float attenuation = 1.0f;
#endif
	
	const std::vector<oo::EntityHold> colliding = collidingEntities;	// a snapshot (enumerating the live array while it changed raised)
	NSUInteger i, count = colliding.size();
	for (i = 0; i < count; i++)
	{
		Entity *e = colliding[i].get();
		if ((e != nullptr ? e->rootShipEntity() : nullptr) != ownerEntity())	// what [e rootShipEntity] != -owner compared
		{
			// we're going to force the weapon id to be a phantom equipment key so there is something for 
			// the PlayerEntitySound to reference. it allow allows for the sound effects to be overridden by OXP.
			if (e != nullptr)  e->takeEnergyDamage(getEnergy() * attenuation, this, ownerEntity(), "EQ_WEAPON_PLASMA_SHOT");
			if (UNIVERSE != nullptr)  UNIVERSE->removeEntity(this);
			
			// Spawn a plasma burst.
			Entity *burst = oo::MadeEntity(OOPlasmaBurstEntity::burstWithPosition(getPosition()));
			if (UNIVERSE != nullptr)  UNIVERSE->addEntity(burst);
		}
	}
	
#if PLASMA_ATTENUATION
	_colorComponents[3] = attenuation;
#endif
	
	if (lifeTime > _duration)  { if (UNIVERSE != nullptr)  UNIVERSE->removeEntity(this); }
}
