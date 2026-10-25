/*

OOParticleSystem.m

C++20 since bead oo-cenx (see OOParticleSystem.h). The bodies are the Objective-C ones: a
message to self is a member call, [super ...] the base's member, a superclass initialiser that
could not fail keeps its guarded statements in a plain block, and the universe is handed the
entity's Objective-C object, oo::ToObjC(this). Other entities stay their Objective-C objects
(amendment oo-bj8 item 4).

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

#include "OOParticleSystem.h"
#include "OOVector.h"	// make_vector (ADR-0063 item 5 draws on lines of their own)

#include "Universe.h"
#include "OOTexture.h"
#include "PlayerEntity.h"
#include "OOLightParticleEntity.h"
#include "OOMacroOpenGL.h"
#include "MyOpenGLView.h"

#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"


//	Testing toy: cause particle systems to stop after half a second.
#define FREEZE_PARTICLES	0


/*	Initialize shared aspects of the fragburst entities.
	Also stashes generated particle speeds in _particleSize[] array.
*/
void OOParticleSystem::initWithPosition(HPVector pos,
										Vector vel,
										unsigned count,
										float minSpeed,
										float maxSpeed,
										OOTimeDelta duration,
										GLfloat baseColor[4])
{
	OOCParameterAssert(count <= kFragmentBurstMaxParticles);

	// [super init] could not fail: the object is constructed.
	{
		_count = count;
		setPosition(pos);

		velocity = vel;
		_duration = duration;
		_maxSpeed = maxSpeed;
		
		for (unsigned i = 0; i < count; i++)
		{
			GLfloat speed = minSpeed + 0.5f * (randf()+randf()) * (maxSpeed - minSpeed);	// speed tends toward middle of range
			_particleVelocity[i] = vector_multiply_scalar(OORandomUnitVector(), speed);
			
			GLfloat red = baseColor[0] * 0.1f * (9.5f + randf());	// one draw per local, in the order Clang evaluates the arguments (ADR-0063 item 5)
			GLfloat green = baseColor[1] * 0.1f * (9.5f + randf());
			GLfloat blue = baseColor[2] * 0.1f * (9.5f + randf());
			Vector color = make_vector(red, green, blue);
			color = vector_normal(color);
			_particleColor[i][0] = color.x;
			_particleColor[i][1] = color.y;
			_particleColor[i][2] = color.z;
			_particleColor[i][3] = baseColor[3];
			
			_particleSize[i] = speed;
		}
		
		setStatus(STATUS_EFFECT);
		scanClass = CLASS_NO_DRAW;
	}
}


std::optional<std::string> OOParticleSystem::descriptionComponents() const
{
	return oo::str::format("ttl: %.3fs", _duration - _timePassed);
}


bool OOParticleSystem::canCollide()
{
	return false;
}


bool OOParticleSystem::checkCloseCollisionWith(Entity *other)
{
	if (other == oo::LiveOwner(this))  return false;	// the owner's C++ entity, null for none (bead oo-9ht.39.20)
	return other == nullptr || !other->isEffect();	// [nil isEffect] answered NO
}


void OOParticleSystem::update(OOTimeDelta delta_t)
{
	Entity::update(delta_t);

	_timePassed += delta_t;
	collision_radius += delta_t * _maxSpeed;
	
	unsigned	i, count = _count;
	Vector		*particlePosition = _particlePosition;
	Vector		*particleVelocity = _particleVelocity;
	
	for (i = 0; i < count; i++)
	{
		particlePosition[i] = vector_add(particlePosition[i], vector_multiply_scalar(particleVelocity[i], delta_t));
	}
	
	// disappear eventually.
	if (_timePassed > _duration)  { if (UNIVERSE != nullptr)  UNIVERSE->removeEntity(this); }
}


#define DrawQuadForView(x, y, z, sz) \
do { \
	glTexCoord2f(0.0, 1.0);	glVertex3f(x-sz, y-sz, z); \
	glTexCoord2f(1.0, 1.0);	glVertex3f(x+sz, y-sz, z); \
	glTexCoord2f(1.0, 0.0);	glVertex3f(x+sz, y+sz, z); \
	glTexCoord2f(0.0, 0.0);	glVertex3f(x-sz, y+sz, z); \
} while (0)


void OOParticleSystem::drawImmediate(bool /*immediate*/, bool translucent)
{
	if (!translucent || (UNIVERSE != nullptr ? UNIVERSE->breakPatternHide() : false))  return;

	OO_ENTER_OPENGL();
	OOSetOpenGLState(OPENGL_STATE_ADDITIVE_BLENDING);
	
	OOGL(glPushAttrib(GL_ENABLE_BIT | GL_COLOR_BUFFER_BIT));
	
	OOGL(glEnable(GL_TEXTURE_2D));
	OOGL(glEnable(GL_BLEND));
	OOGL(glBlendFunc(GL_SRC_ALPHA, GL_ONE));
	if (OOTexture *particle = texture())  particle->apply();	// a message to nil did nothing
	
	HPVector		viewPosition = (PLAYER != nullptr ? PLAYER->viewpointPosition() : HPVector{});
	HPVector		selfPosition = getPosition();
	
	unsigned	i, count = _count;
	Vector		*particlePosition = _particlePosition;
	GLfloat		(*particleColor)[4] = _particleColor;
	GLfloat		*particleSize = _particleSize;
	
	if ((UNIVERSE != nullptr ? UNIVERSE->reducedDetail() : false))
	{
		// Quick rendering - particle cloud is effectively a 2D billboard.
		OOGLPushModelView();
		OOGLMultModelView(OOMatrixForBillboard(selfPosition, viewPosition));
		
		OOGLBEGIN(GL_QUADS);
		for (i = 0; i < count; i++)
		{
			glColor4fv(particleColor[i]);
			DrawQuadForView(particlePosition[i].x, particlePosition[i].y, particlePosition[i].z, particleSize[i]);
		}
		OOGLEND();
		
		OOGLPopModelView();
	}
	else
	{
		float distanceThreshold = collision_radius * 2.0f;	// Distance between player and middle of effect where we start to transition to "non-fast rendering."
		float thresholdSq = distanceThreshold * distanceThreshold;
		float distanceSq = cam_zero_distance;
		
		if (distanceSq > thresholdSq)
		{
			/*	Semi-quick rendering - particle positions are volumetric, but
				orientation is shared. This can cause noticeable distortion
				if the player is close to the centre of the cloud.
			*/
			OOMatrix bbMatrix = OOMatrixForBillboard(selfPosition, viewPosition);
			
			for (i = 0; i < count; i++)
			{
				OOGLPushModelView();
				OOGLTranslateModelView(particlePosition[i]);
				OOGLMultModelView(bbMatrix);
				
				glColor4fv(particleColor[i]);
				OOGLBEGIN(GL_QUADS);
					DrawQuadForView(0, 0, 0, particleSize[i]);
				OOGLEND();
				
				OOGLPopModelView();
			}
		}
		else
		{
			/*	Non-fast rendering - each particle is billboarded individually.
				The "individuality" factor interpolates between this behavior
				and "semi-quick" to avoid jumping at the boundary.
			*/
			float individuality = 3.0f * (1.0f - distanceSq / thresholdSq);
			individuality = OOClamp_0_1_f(individuality);
			
			for (i = 0; i < count; i++)
			{
				OOGLPushModelView();
				OOGLTranslateModelView(particlePosition[i]);
				OOGLMultModelView(OOMatrixForBillboard(HPvector_add(selfPosition, vectorToHPVector(vector_multiply_scalar(particlePosition[i], individuality))), viewPosition));
				
				glColor4fv(particleColor[i]);
				OOGLBEGIN(GL_QUADS);
				DrawQuadForView(0, 0, 0, particleSize[i]);
				OOGLEND();
				
				OOGLPopModelView();
			}
		}

	}
	
	OOGL(glPopAttrib());
	
	OOVerifyOpenGLState();
	cxx_OOCheckOpenGLErrors([&]() -> std::string { return "OOParticleSystem after drawing " + oo::EntityDescription(this); });
}


bool OOParticleSystem::isEffect()
{
	return true;
}

OOTexture *OOParticleSystem::texture()
{
	return ::OOLightParticleEntity::defaultParticleTexture();
}

#ifndef NDEBUG
std::vector<oo::Ref<OOTexture>> OOParticleSystem::allTextures()
{
	std::vector<oo::Ref<OOTexture>> result;
	result.emplace_back(::OOLightParticleEntity::defaultParticleTexture());
	return result;
}
#endif


void OOSmallFragmentBurstEntity::initFragmentBurstFrom(HPVector fragPosition, Vector fragVelocity, GLfloat size)
{
	enum
	{
		kMinSpeed = 100, kMaxSpeed = 400
	};
	
	unsigned count = 0.4f * size;
	count = MIN(count | 12, (unsigned)kFragmentBurstMaxParticles);
	
	// Select base colour
	// yellow/orange (0.12) through yellow (0.1667) to yellow/slightly green (0.20)
	oo::Ref<OOColor> hsvColor = OOColor::colorWithHue(0.12f + 0.08f * randf(), 1.0f, 1.0f, 1.0f);
	GLfloat baseColor[4];
	hsvColor->getRed(&baseColor[0], &baseColor[1], &baseColor[2], &baseColor[3]);

	initWithPosition(fragPosition, fragVelocity, count, kMinSpeed, kMaxSpeed, 1.5, baseColor);
	{
		for (unsigned i = 0; i < count; i++)
		{
			// Note: initWithPosition:... stashes speeds in _particleSize[].
			_particleSize[i] = 32.0f * static_cast<float>(kMinSpeed) / _particleSize[i];
		}
	}
}


oo::Ref<OOSmallFragmentBurstEntity> OOSmallFragmentBurstEntity::fragmentBurstFromEntity(Entity *entity)
{
	oo::Ref<OOSmallFragmentBurstEntity> result = oo::makeRef<OOSmallFragmentBurstEntity>();
	result->initFragmentBurstFrom(entity != nullptr ? entity->getPosition() : kZeroHPVector, entity != nullptr ? entity->getVelocity() : kZeroVector, entity != nullptr ? entity->collisionRadius() : 0.0f);	// the C++ entity's members (bead oo-al52f); none answers zero, as nil did
	return result;
}


void OOSmallFragmentBurstEntity::update(OOTimeDelta delta_t)
{
#if FREEZE_PARTICLES
	if (_timePassed + delta_t > 0.5) delta_t = 0.5 - _timePassed;
#endif
	
	OOParticleSystem::update(delta_t);

	unsigned	i, count = _count;
	GLfloat		(*particleColor)[4] = _particleColor;
	GLfloat		timePassed = _timePassed;

	for (i = 0; i < count; i++)
	{
		GLfloat du = 0.5f + (1.0f/32.0f) * (32 - i);
		particleColor[i][3] = OOClamp_0_1_f(1.0f - timePassed / du);
	}
}


void OOBigFragmentBurstEntity::initFragmentBurstFrom(HPVector fragPosition, Vector fragVelocity, GLfloat size)
{
	float minSpeed = 1.0f + size * 0.5f;
	float maxSpeed = minSpeed * 4.0f;
	
	unsigned count = 0.2f * size;
	count = MIN(count | 3, (unsigned)kBigFragmentBurstMaxParticles);
	
	GLfloat baseColor[4] = { 1.0f, 1.0f, 0.5f, 1.0f };	
	
	size *= 2.0f;	 // Account for margins in particle texture.
	initWithPosition(fragPosition, fragVelocity, count, minSpeed, maxSpeed, 1.0, baseColor);
	{
		_baseSize = size;

		for (unsigned i = 0; i < count; i++)
		{
			_particleSize[i] = size;
		}
	}
}


oo::Ref<OOBigFragmentBurstEntity> OOBigFragmentBurstEntity::fragmentBurstFromEntity(Entity *entity)
{
	oo::Ref<OOBigFragmentBurstEntity> result = oo::makeRef<OOBigFragmentBurstEntity>();
	result->initFragmentBurstFrom(entity != nullptr ? entity->getPosition() : kZeroHPVector, vector_multiply_scalar(entity != nullptr ? entity->getVelocity() : kZeroVector, 0.85), entity != nullptr ? entity->collisionRadius() : 0.0f);	// the C++ entity's members (bead oo-al52f)
	return result;
}


void OOBigFragmentBurstEntity::update(double delta_t)
{
#if FREEZE_PARTICLES
	if (_timePassed + delta_t > 0.5) delta_t = 0.5 - _timePassed;
#endif
	
	OOParticleSystem::update(delta_t);

	unsigned	i, count = _count;
	GLfloat		(*particleColor)[4] = _particleColor;
	GLfloat		*particleSize = _particleSize;
	GLfloat		timePassed = _timePassed;
	GLfloat		duration = _duration;
	
	GLfloat size = (1.0f + timePassed) * _baseSize;
	GLfloat di = 1.0f / (count - 1);
	
	for (i = 0; i < count; i++)
	{
		GLfloat du = duration * (0.5f + di * i);
		particleColor[i][3] = OOClamp_0_1_f(1.0f - timePassed / du);
		
		particleSize[i] = size;
	}
}
