/*

OOParticleSystem.h

C++20 since bead oo-cenx, a leaf of the Entities seam (proposed ADR-0056, amendment oo-bj8 item
12), converted with all its subclasses (amendment oo-kdyh item 1): the two fragment bursts here
and OOExplosionCloudEntity. Global classes over Entity, with no facade: nothing messages
them by their own selectors. Their callers (ShipEntity, Universe) make them with a factory and
hand the universe the Entity facade oo::NewEntityFacade makes, which is each one's Objective-C
object from then on.

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

#include "Entity.h"

#include "OOTypes.h"
#include "OOMaths.h"

class OOTexture;
class OOColor;

enum
{
	kFragmentBurstMaxParticles		= 64,
	kBigFragmentBurstMaxParticles	= 16
};


class OOParticleSystem : public Entity
{
public:
	std::optional<std::string> descriptionComponents() const override;
	bool canCollide() override;
	bool checkCloseCollisionWith(Entity *other) override;
	void update(OOTimeDelta delta_t) override;
	void drawImmediate(bool immediate, bool translucent) override;
	bool isEffect() override;

	virtual OOTexture *texture();

#ifndef NDEBUG
	std::vector<oo::Ref<OOTexture>> allTextures() override;
#endif

protected:
	// -init answered nil: only a subclass makes one, then runs initWithPosition().
	OOParticleSystem() = default;

	/*	Initialize particle effect with particles flying out randomly.
		Initiali _particleSize[] is equal to speed.
	 */
	void initWithPosition(HPVector position,
						  Vector velocity,
						  unsigned count,
						  float minSpeed,
						  float maxSpeed,
						  OOTimeDelta duration,
						  GLfloat baseColor[4]);

	Vector			_particlePosition[kFragmentBurstMaxParticles] = {};
	Vector			_particleVelocity[kFragmentBurstMaxParticles] = {};
	GLfloat			_particleColor[kFragmentBurstMaxParticles][4] = {};
	GLfloat			_particleSize[kFragmentBurstMaxParticles] = {};
	unsigned		_count = {};
	
	unsigned		_particleType = {};
	
	OOTimeDelta		_timePassed = {}, _duration = {};
	double			_maxSpeed = {};
};


class OOSmallFragmentBurstEntity : public OOParticleSystem
{
public:
	static oo::Ref<OOSmallFragmentBurstEntity> fragmentBurstFromEntity(Entity *entity);	// the C++ entity (bead oo-al52f)

	void update(OOTimeDelta delta_t) override;

private:
	void initFragmentBurstFrom(HPVector fragPosition, Vector fragVelocity, GLfloat size);
};


class OOBigFragmentBurstEntity : public OOParticleSystem
{
public:
	static oo::Ref<OOBigFragmentBurstEntity> fragmentBurstFromEntity(Entity *entity);	// the C++ entity (bead oo-al52f)

	void update(double delta_t) override;

private:
	void initFragmentBurstFrom(HPVector fragPosition, Vector fragVelocity, GLfloat size);

	GLfloat			_baseSize = {};
};
