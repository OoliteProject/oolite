/*

OOFlashEffectEntity.m


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

#include "OOFlashEffectEntity.h"
#include "Universe.h"
#include "PlayerEntity.h"
#include "OOColor.h"
#include "OOTexture.h"
#include "OOGraphicsResetManager.h"


#define kLaserFlashDuration			0.3f
#define kExplosionFlashDuration		0.4f
#define kGrowthRateFactor			150.0f	// if average flashSize is 80 then this is 12000
#define kMinExplosionGrowth			600.0f
#define kLaserFlashInitialSize		1.0f
#define kExplosionFlashAlpha		0.5f

static OOTexture *sFlashTexture = nil;


namespace {

// The texture's graphics reset client, which the facade class was until bead oo-9ht.23 (ADR-0056
// amendment oo-jpd8 item 3, as OOLaserShotEntity's): registered once, with the texture, and never
// destroyed.
class FlashTextureResetClient : public OOGraphicsResetClient
{
public:
	void resetGraphicsState() override  { OOFlashEffectEntity::resetGraphicsState(); }
};

}	// namespace


void OOFlashEffectEntity::initExplosionFlashWithPosition(HPVector pos, Vector vel, float size)
{
	initWithPosition(pos, size, OOColor::whiteColor().get(), kExplosionFlashDuration);
	// [self initWithPosition:...] could not fail.
	{
		_growthRate = fmax(_growthRate, kMinExplosionGrowth);
		_alpha = kExplosionFlashAlpha;
		setVelocity(vel);
	}
}


void OOFlashEffectEntity::initLaserFlashWithPosition(HPVector pos, Vector vel, OOColor *color)
{
	initWithPosition(pos, kLaserFlashInitialSize, color, kLaserFlashDuration);
	// [self initWithPosition:...] could not fail.
	{
		setVelocity(vel);
		_alpha = 1.0f;
	}
}


// The C++ entity (bead oo-al52f; it was its Objective-C object, amendment oo-bj8 item 4): the
// members -position, -velocity and -collisionRadius forwarded to; none answers zero, as nil did.
oo::Ref<OOFlashEffectEntity> OOFlashEffectEntity::explosionFlashFromEntity(Entity *entity)
{
	const oo::Ref<OOFlashEffectEntity> flash = oo::makeRef<OOFlashEffectEntity>();
	flash->initExplosionFlashWithPosition(entity != nullptr ? entity->getPosition() : kZeroHPVector, entity != nullptr ? entity->getVelocity() : kZeroVector, entity != nullptr ? entity->collisionRadius() : 0.0f);
	return flash;
}


oo::Ref<OOFlashEffectEntity> OOFlashEffectEntity::laserFlashWithPosition(HPVector pos, Vector vel, OOColor *color)
{
	const oo::Ref<OOFlashEffectEntity> flash = oo::makeRef<OOFlashEffectEntity>();
	flash->initLaserFlashWithPosition(pos, vel, color);
	return flash;
}


void OOFlashEffectEntity::initWithPosition(HPVector pos, float size, OOColor *color, float duration)
{
	OOLightParticleEntity::initWithDiameter(size);
	// [super initWithDiameter:] could not fail.
	{
		setPosition(pos);
		_duration = duration;
		_growthRate = kGrowthRateFactor * size;
		setColor(color, 1.0f);
		assert(collisionRadius() == 0 && getEnergy() == 0 && magnitude(getVelocity()) == 0);
	}
}


void OOFlashEffectEntity::update(OOTimeDelta delta_t)
{
	OOLightParticleEntity::update(delta_t);
	
	float tf = _duration * 0.667f;
	float tf1 = _duration - tf;
	
	// Scale up.
	_diameter += delta_t * _growthRate;
	
	// Fade in and out.
	OOTimeDelta lifeTime = timeElapsedSinceSpawn();
	_colorComponents[3] = _alpha * ((lifeTime < tf) ? (lifeTime / tf) : (_duration - lifeTime) / tf1);
	
	// Disappear as necessary.
	if (lifeTime > _duration)  { if (UNIVERSE != nullptr)  UNIVERSE->removeEntity(this); }
}


OOTexture *OOFlashEffectEntity::texture()
{
	if (sFlashTexture == nil)  OOFlashEffectEntity::setUpTexture();
	return sFlashTexture;
}


void OOFlashEffectEntity::setUpTexture()
{
	if (sFlashTexture == nil)
	{
		sFlashTexture = OOTexture::textureWithName("oolite-particle-flash.png", "Textures", kOOTextureMinFilterMipMap | kOOTextureMagFilterLinear | kOOTextureAlphaMask, kOOTextureDefaultAnisotropy, 0.0).leakRef();
		OOGraphicsResetManager::sharedManager()->registerCxxClient(new FlashTextureResetClient);
	}
}


void OOFlashEffectEntity::resetGraphicsState()
{
	oo::release(sFlashTexture);
	sFlashTexture = nullptr;
}

