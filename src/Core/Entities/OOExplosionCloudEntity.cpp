/*

OOExplosionCloudEntity.m

C++20 since bead oo-cenx, with its superclass (see OOParticleSystem.h and OOParticleSystem.mm:
the bodies are the Objective-C ones, translated the same way).


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

#include "OOExplosionCloudEntity.h"
#include "Universe.h"
#include "PlayerEntity.h"
#include "OOColor.h"
#include "OOTexture.h"
#include "OOGraphicsResetManager.h"

#include "oofnd/PListGet.hpp"

#define kExplosionCloudDuration		0.9
#define kGrowthRateFactor			1.5f
#define kExplosionCloudAlpha		0.85f
#define	kExplosionBrightnessMult	1.0f
#define kExplosionDefaultSize		2.5f

// keys for plist file
namespace {
constexpr std::string_view kExplosionAlpha			= "alpha";
constexpr std::string_view kExplosionBrightness	= "brightness";
constexpr std::string_view kExplosionColors		= "color_order";
constexpr std::string_view kExplosionCount			= "count";
constexpr std::string_view kExplosionDuration		= "duration";
constexpr std::string_view kExplosionGrowth		= "growth_rate";
constexpr std::string_view kExplosionSize			= "size";
constexpr std::string_view kExplosionSpread		= "spread";
constexpr std::string_view kExplosionTexture		= "texture";
}	// namespace


bool OOExplosionCloudEntity::initExplosionCloudWithEntity(Entity *entity, float size, const oo::PList &settings)
{
	unsigned i;
	unsigned maxCount = (UNIVERSE != nullptr ? UNIVERSE->getDetailLevel() : OOGraphicsDetail{}) <= DETAIL_LEVEL_SHADERS ? 10 : 25;
	HPVector pos = entity != nullptr ? entity->getPosition() : kZeroHPVector;	// the C++ entity (bead oo-9ht.39.26); nil answered zero
	Vector vel = entity != nullptr ? entity->getVelocity() : kZeroVector;

	if (settings.isNull()) {
		_settings = oo::PList(oo::PList::Dict{});
	} else {
		_settings = settings;
	}

	unsigned count = _settings.get<unsigned int>(kExplosionCount, 25);
	if (count > maxCount) {
		count = maxCount;
	}

	if (size == 0.0) {
		size = (entity != nullptr ? entity->collisionRadius() : 0.0f)*_settings.get<float>(kExplosionSize, kExplosionDefaultSize);
	}

	_growthRate = _settings.get<float>(kExplosionGrowth, kGrowthRateFactor) * size;
	_alpha = _settings.get<float>(kExplosionAlpha, kExplosionCloudAlpha);
	_brightnessMult = _settings.get<float>(kExplosionBrightness, kExplosionBrightnessMult);
	if (_brightnessMult < 1.0f)  _brightnessMult = 1.0f;
	_cloudDuration = _settings.get<double>(kExplosionDuration, kExplosionCloudDuration);

	GLfloat spread = _settings.get<float>(kExplosionSpread, 1.0);

	std::string textureFile = _settings.get<std::string>(kExplosionTexture, "oolite-particle-cloud2.png");
	
	_texture = oo::Ref<OOTexture>(OOTexture::textureWithName(textureFile, std::string("Textures"), kOOTextureMinFilterMipMap | kOOTextureMagFilterLinear | kOOTextureAlphaMask, kOOTextureDefaultAnisotropy, 0.0));
	if (_texture == nullptr)
	{
		return false;
	}

	GLfloat baseColor[4] = {1.0,1.0,1.0,1.0};

	if (magnitude2(vel) > 1000000)
	{
		// slow down rapidly translating explosions
		vel = vector_multiply_scalar(vector_normal(vel),1000);
	}

	initWithPosition(pos, vel, count, size*0.8f*spread, size*1.2f*spread, _cloudDuration, baseColor);
	{
		const std::string color_order = _settings.get<std::string>(kExplosionColors, "rgb");
		
		for (i=0;i<count;i++) 
		{
			if (color_order == "white") {
				// grey
				_particleColor[i][0] = _particleColor[i][1] = _particleColor[i][2] = randf();
			} else {
				float c1 = randf();
				float c2 = randf();
				float c3 = randf();
				if (c2 > c1) {
					c2 = c1;
				}
				if (c3 > c2) {
					c3 = c2;
				}
				if (color_order == "rgb") 
				{
					_particleColor[i][0] = c1;
					_particleColor[i][1] = c2;
					_particleColor[i][2] = c3;
				}
				else if (color_order == "rbg") 
				{
					_particleColor[i][0] = c1;
					_particleColor[i][1] = c3;
					_particleColor[i][2] = c2;
				}
				else if (color_order == "grb") 
				{
					_particleColor[i][0] = c2;
					_particleColor[i][1] = c1;
					_particleColor[i][2] = c3;
				}
				else if (color_order == "gbr") 
				{
					_particleColor[i][0] = c3;
					_particleColor[i][1] = c1;
					_particleColor[i][2] = c2;
				}
				else if (color_order == "brg") 
				{
					_particleColor[i][0] = c2;
					_particleColor[i][1] = c3;
					_particleColor[i][2] = c1;
				}
				else if (color_order == "bgr") 
				{
					_particleColor[i][0] = c3;
					_particleColor[i][1] = c2;
					_particleColor[i][2] = c1;
				}

			}
			
			_particleColor[i][0] *= _brightnessMult;
			_particleColor[i][1] *= _brightnessMult;
			_particleColor[i][2] *= _brightnessMult;
			_particleColor[i][3] = _alpha;
		}
	}
	return true;
}


// -dealloc released the texture: _texture does.


oo::Ref<OOExplosionCloudEntity> OOExplosionCloudEntity::explosionCloudFromEntity(Entity *entity, const oo::PList &settings)
{
	oo::Ref<OOExplosionCloudEntity> result = oo::makeRef<OOExplosionCloudEntity>();
	if (!result->initExplosionCloudWithEntity(entity, 0, settings))  return nullptr;
	return result;
}


oo::Ref<OOExplosionCloudEntity> OOExplosionCloudEntity::explosionCloudFromEntity(Entity *entity, float size, const oo::PList &settings)
{
	oo::Ref<OOExplosionCloudEntity> result = oo::makeRef<OOExplosionCloudEntity>();
	if (!result->initExplosionCloudWithEntity(entity, size, settings))  return nullptr;
	return result;
}


void OOExplosionCloudEntity::update(OOTimeDelta delta_t)
{
	OOParticleSystem::update(delta_t);
	
	// Fade out.
	GLfloat		fadeRate = _count * _brightnessMult / 25.0;
	unsigned	i, count = _count;
	GLfloat		(*particleColor)[4] = _particleColor;
	
	float newAlpha = _alpha * (1-(_timePassed / _cloudDuration));
	const std::string color_order = _settings.get<std::string>(kExplosionColors, "rgb");
	NSUInteger primary = 0, secondary = 1, tertiary = 2;
			
	if (color_order == "rgb") 
	{
		primary = 0;
		secondary = 1;
		tertiary = 2;
	}
	else if (color_order == "rbg") 
	{
		primary = 0;
		secondary = 2;
		tertiary = 1;
	}
	else if (color_order == "grb") 
	{
		primary = 1;
		secondary = 0;
		tertiary = 2;
	}
	else if (color_order == "gbr") 
	{
		primary = 1;
		secondary = 2;
		tertiary = 0;
	}
	else if (color_order == "brg") 
	{
		primary = 2;
		secondary = 0;
		tertiary = 1;
	}
	else if (color_order == "bgr") 
	{
		primary = 2;
		secondary = 1;
		tertiary = 0;
	}


	float fdelta_t = delta_t;
	for (i=0;i<count;i++) {
		
		_particleSize[i] += delta_t * _growthRate;

		particleColor[i][3] = newAlpha;
		if (color_order != "white")
		{

			if (particleColor[i][tertiary] > 0.0f) // fade blue (white to yellow)
			{
				particleColor[i][tertiary] -= fdelta_t * 0.5f * fadeRate;
				if (particleColor[i][tertiary] < 0.0f)
				{
					particleColor[i][tertiary] = 0.0f;
				}
			}
			else if (particleColor[i][secondary] > 0.0f) // fade green (yellow to red)
			{
				particleColor[i][secondary] -= fdelta_t * fadeRate;
				if (particleColor[i][secondary] < 0.0f)
				{
					particleColor[i][secondary] = 0.0f;
				}
			}
			else if (particleColor[i][primary] > 0.0f) // fade red (red to black)
			{
				particleColor[i][primary] -= fdelta_t * 2.0f * fadeRate;
				if (particleColor[i][primary] < 0.0f)
				{
					particleColor[i][primary] = 0.0f;
				}
			}

		}
	}
	
}


OOTexture *OOExplosionCloudEntity::texture()
{
	return _texture.get();
}
