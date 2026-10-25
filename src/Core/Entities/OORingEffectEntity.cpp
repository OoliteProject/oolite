/*

OORingEffectEntity.m

C++20 since bead oo-peql (see OORingEffectEntity.h). The bodies are the Objective-C ones: a
message to self is a member call, [super ...] the base's member, and the universe is handed the
entity's Objective-C object, oo::ToObjC(this).

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

#include "OORingEffectEntity.h"
#include "Universe.h"
#include "OOMacroOpenGL.h"

#include "oofnd/String.hpp"


#define kRingDuration					(2.0f)	// seconds
#define kRingAttack						(0.4f)	// fade-up time

// Dimensions and growth rates per second in terms of base size.
#define kInnerRingInitialSizeFactor		(0.5f)
#define kOuterRingInitialSizeFactor		(1.25f * kInnerRingInitialSizeFactor)
#define kInnerRingGrowthRateFactor		(1.1f * kInnerRingInitialSizeFactor)
#define kOuterRingGrowthRateFactor		(1.25f * kInnerRingInitialSizeFactor)

// These factors produce a ring that shrinks to nothing, then expands to the size of a "normal" ring.
#define kShrinkingRingInnerGrowthFactor	(-2.5)
#define kShrinkingRingOuterGrowthFactor	(-2.0)


enum
{
	kCircleSegments					= 65
};
static struct { float x, y; } sCircleVerts[kCircleSegments];	// holds vector coordinates for a unit circle


// +initialize: run once, before the first ring is made.
void OORingEffectEntity::initialize()
{
	static bool initialized = false;
	if (initialized)  return;
	initialized = true;

	unsigned			i;
	for (i = 0; i < kCircleSegments; i++)
	{
		sCircleVerts[i].x = sinf(i * 2 * M_PI / (kCircleSegments - 1));
		sCircleVerts[i].y = cosf(i * 2 * M_PI / (kCircleSegments - 1));
	}
}


// The source is the C++ entity (bead oo-9ht.39.26; it was its Objective-C object, amendment oo-bj8 item 4).
bool OORingEffectEntity::initRingFromEntity(Entity *sourceEntity)
{
	if (sourceEntity == nullptr)
	{
		return false;
	}
	
	// [super init] could not fail: the object is constructed.
	{
		GLfloat baseSize = sourceEntity->collisionRadius();
		_innerRadius = baseSize * kInnerRingInitialSizeFactor;
		_outerRadius = baseSize * kOuterRingInitialSizeFactor;
		_innerGrowthRate = baseSize * kInnerRingGrowthRateFactor;
		_outerGrowthRate = baseSize * kOuterRingGrowthRateFactor;
		
		setPosition(sourceEntity->getPosition());
		setOrientation(sourceEntity->getOrientation());
		setVelocity(sourceEntity->getVelocity());
		
		setStatus(STATUS_EFFECT);
		setScanClass(CLASS_NO_DRAW);
		
		setOwner(sourceEntity);
	}
	
	return true;
}


oo::Ref<OORingEffectEntity> OORingEffectEntity::ringFromEntity(Entity *sourceEntity)
{
	initialize();
	oo::Ref<OORingEffectEntity> result = oo::makeRef<OORingEffectEntity>();
	if (!result->initRingFromEntity(sourceEntity))  return nullptr;
	return result;
}


oo::Ref<OORingEffectEntity> OORingEffectEntity::shrinkingRingFromEntity(Entity *sourceEntity)
{
	oo::Ref<OORingEffectEntity> result = ringFromEntity(sourceEntity);
	if (result != nullptr)
	{
		result->_innerGrowthRate *= kShrinkingRingInnerGrowthFactor;
		result->_outerGrowthRate *= kShrinkingRingOuterGrowthFactor;
	}
	return result;
}


std::optional<std::string> OORingEffectEntity::descriptionComponents() const
{
	return oo::str::format("%f seconds passed of %f", _timePassed, kRingDuration);
}


void OORingEffectEntity::update(OOTimeDelta delta_t)
{
	Entity::update(delta_t);
	_timePassed += delta_t;
	
	_innerRadius += delta_t * _innerGrowthRate;
	_outerRadius += delta_t * _outerGrowthRate;
	
	if (_timePassed > kRingDuration)
	{
		if (UNIVERSE != nullptr)  UNIVERSE->removeEntity(this);
	}
}


void OORingEffectEntity::drawImmediate(bool /*immediate*/, bool translucent)
{
	if (!translucent || (UNIVERSE != nullptr ? UNIVERSE->breakPatternHide() : false))  return;
	
	OO_ENTER_OPENGL();
	OOSetOpenGLState(OPENGL_STATE_ADDITIVE_BLENDING);
	
	GLfloat alpha = OOClamp_0_1_f((kRingDuration - _timePassed) / kRingAttack);
	
	GLfloat ex_em_hi[4]		= {0.6, 0.8, 1.0, alpha};   // pale blue
	GLfloat ex_em_lo[4]		= {0.2, 0.0, 1.0, 0.0};		// purplish-blue-black
	
	OOGLBEGIN(GL_TRIANGLE_STRIP);
		for (unsigned i = 0; i < kCircleSegments; i++)
		{
			glColor4fv(ex_em_lo);
			glVertex3f(_innerRadius * sCircleVerts[i].x, _innerRadius * sCircleVerts[i].y, 0.0f);
			glColor4fv(ex_em_hi);
			glVertex3f(_outerRadius * sCircleVerts[i].x, _outerRadius * sCircleVerts[i].y, 0.0f);
		}
	OOGLEND();
	
	OOVerifyOpenGLState();
	cxx_OOCheckOpenGLErrors([&]() -> std::string { return "OOQuiriumCascadeEntity after drawing " + oo::EntityDescription(this); });
}


bool OORingEffectEntity::isEffect()
{
	return true;
}


bool OORingEffectEntity::canCollide()
{
	return false;
}
