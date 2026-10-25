/*

SkyEntity.m

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


#include "SkyEntity.h"
#include "OOSkyDrawable.h"
#include "PlayerEntity.h"

#include "OOMaths.h"
#include "Universe.h"
#include "MyOpenGLView.h"
#include "OOColor.h"
#include "OOMaterial.h"
#include "OOObjCPList.h"

#include "oofnd/Log.hpp"
#include "oofnd/PListGet.hpp"
#include "oofnd/String.hpp"


#define SKY_BASIS_STARS			4800
#define SKY_BASIS_BLOBS			1280
#define SKY_clusterChance		0.80
#define SKY_alpha				0.10
#define SKY_scale				10.0


namespace {

// -objectForKey: as plist data (a null PList when absent), for +cxx_colorWithDescription:.
oo::PList ValueForKey(const oo::PList &dict, std::string_view key)
{
	const oo::PList *value = dict.find(key);
	return value != nullptr ? *value : oo::PList();
}


// get<std::string> where the Foundation code read nil: std::nullopt when the key is absent or its
// value is neither a string nor a number.
std::optional<std::string> OptionalStringForKey(const oo::PList &dict, std::string_view key)
{
	const oo::PList *value = dict.find(key);
	if (value == nullptr || !(value->isString() || value->isNumber()))  return std::nullopt;
	return dict.get<std::string>(key);
}


// [[OOColor cxx_colorWithDescription:description] premultipliedColor]: null where the colour was nil.
oo::Ref<OOColor> PremultipliedColorWithDescription(const oo::PList &description)
{
	const oo::Ref<OOColor> color = OOColor::colorWithDescription(description);
	return color != nullptr ? color->premultipliedColor() : nullptr;
}

}	// namespace


void SkyEntity::initWithColors(OOColor *col1In, OOColor *col2In, const oo::PList &systemInfo)
{
	oo::Ref<OOSkyDrawable>	skyDrawable;
	float					clusterChance,
							alpha,
							scale,
							starCountMultiplier,
							nebulaCountMultiplier;
	signed					starCount,	// Need to be able to hold -1...
							nebulaCount;

	// self = [super init]: the constructor ran Entity's -init body.

	// The colours the body replaces are owned here (they were autoreleased).
	oo::Ref<OOColor> col1(col1In), col2(col2In);
	oo::Ref<OOColor> col3 = OOColor::colorWithDescription(OOColorObjectNode(col1.get()));	// a copy, as the id form made of a colour
	oo::Ref<OOColor> col4 = OOColor::colorWithDescription(OOColorObjectNode(col2.get()));

	// Load colours
	bool nebulaColorSet = readColor1(&col1, &col2, &col3, &col4, systemInfo);

	skyColor = OOColor::colorWithDescription(ValueForKey(systemInfo, "sun_color"));
	if (skyColor == nullptr)
	{
		// A message to a nil colour answered nil.
		skyColor = (col2 != nullptr) ? col2->blendedColorWithFraction(0.5, col1.get()) : nullptr;
	}

	// Load distribution values
	clusterChance = systemInfo.get<float>("sky_blur_cluster_chance", SKY_clusterChance);
	alpha = systemInfo.get<float>("sky_blur_alpha", SKY_alpha);
	scale = systemInfo.get<float>("sky_blur_scale", SKY_scale);

	// Load star count
	starCount = systemInfo.get<float>("sky_n_stars", -1);
	starCountMultiplier = systemInfo.get<float>("star_count_multiplier", 1.0f);
	if (starCountMultiplier < 0.0f)  starCountMultiplier *= -1.0f;
	if (0 <= starCount)
	{
		// changed for 1.82, default set to 1
		// lets OXPers modify the broad number without stopping variation
		starCount *= starCountMultiplier;
	}
	else
	{
		starCount = starCountMultiplier * SKY_BASIS_STARS * (0.5 + randf());
	}

	// ...and nebula count. (Note: simplifying this would change the appearance of stars/blobs.)
	nebulaCount = systemInfo.get<float>("sky_n_blurs", -1);
	nebulaCountMultiplier = systemInfo.get<float>("nebula_count_multiplier", 1.0f);
	if (nebulaCountMultiplier < 0.0f)  nebulaCountMultiplier *= -1.0f;
	if (0 <= nebulaCount)
	{
		// changed for 1.82, default set to 1
		// lets OXPers modify the broad number without stopping variation
		nebulaCount *= nebulaCountMultiplier;
	}
	else
	{
		nebulaCount = nebulaCountMultiplier * SKY_BASIS_BLOBS * (0.5 + randf());
	}

	if ((UNIVERSE != nullptr ? UNIVERSE->reducedDetail() : false))
	{
		// limit stars and blobs to basis levels, and halve stars again
		if (starCount > SKY_BASIS_STARS)
		{
			starCount = SKY_BASIS_STARS;
		}
		starCount /= 2;
		if (nebulaCount > SKY_BASIS_BLOBS)
		{
			nebulaCount = SKY_BASIS_BLOBS;
		}
	}

	skyDrawable = oo::makeRef<OOSkyDrawable>(col1.get(),
											 col2.get(),
											 col3.get(),
											 col4.get(),
											 starCount,
											 nebulaCount,
											 nebulaColorSet,
											 clusterChance,
											 alpha,
											 scale);
	setDrawable(skyDrawable.get());	// (the root facade until bead oo-hahfg)

	setStatus(STATUS_EFFECT);
}


OOColor *SkyEntity::getSkyColor()
{
	return skyColor.get();
}


bool SkyEntity::changeProperty(const std::string &key, const oo::PList &dict)
{

	// TODO: properties requiring reInit?
	if (key == "sun_color")
	{
		oo::Ref<OOColor> 	col=OOColor::colorWithDescription(ValueForKey(dict, key));
		if (col != nullptr)
		{
			skyColor = col;		// [col copy]: a copy of an immutable colour is the colour itself
			if (UNIVERSE != nullptr)  UNIVERSE->setLighting();
		}
	}
	else
	{
		OO_LOG_WARN("script.warning", "Change to property '{}' not applied, will apply only on leaving and re-entering this system.", key);
		return NO;
	}
	return YES;
}


void SkyEntity::update(OOTimeDelta /*delta_t*/)
{
	::PlayerEntity *player = PLAYER;
	zero_distance = MAX_CLEAR_DEPTH * MAX_CLEAR_DEPTH;
	cam_zero_distance = zero_distance;
	if (player != nil)
	{
		position = (player != nullptr ? player->viewpointPosition() : HPVector{});
	}
	else
	{
		OO_LOG("sky.warning", "{}", "PLAYER is nil");
	}
}


bool SkyEntity::isSky()
{
	return YES;
}


bool SkyEntity::isVisible()
{
	return YES;
}


bool SkyEntity::canCollide()
{
	return NO;
}


GLfloat SkyEntity::cameraRangeFront()
{
	return MAX_CLEAR_DEPTH;
}


GLfloat SkyEntity::cameraRangeBack()
{
	return MAX_CLEAR_DEPTH;
}


void SkyEntity::drawImmediate(bool immediate, bool translucent)
{
	if ((UNIVERSE != nullptr ? UNIVERSE->breakPatternHide() : false))  return;

	OOEntityWithDrawable::drawImmediate(immediate, translucent);

	cxx_OOCheckOpenGLErrors([&]() -> std::string { return "SkyEntity after drawing " + oo::EntityDescription(this); });
}


#ifndef NDEBUG
std::optional<std::string> SkyEntity::descriptionForObjDump()
{
	// Don't include range and visibility flag as they're irrelevant.
	return descriptionForObjDumpBasic();
}
#endif


bool SkyEntity::readColor1(oo::Ref<OOColor> *ioColor1, oo::Ref<OOColor> *ioColor2, oo::Ref<OOColor> *ioColor3, oo::Ref<OOColor> *ioColor4, const oo::PList &dictionary)
{
	oo::PList			colorDesc;
	oo::Ref<OOColor>	color;
	bool				nebulaSet = NO;

	assert(ioColor1 != NULL && ioColor2 != NULL);

	const std::optional<std::string> string = OptionalStringForKey(dictionary, "sky_rgb_colors");
	if (string.has_value())
	{
		oo::PList::Array tokenList;
		for (std::string &token : oo::str::tokens(*string))  tokenList.emplace_back(std::move(token));
		const oo::PList tokens(std::move(tokenList));

		if (tokens.count() == 6)
		{
			float r1 = OOClamp_0_1_f(tokens.at<float>(0));
			float g1 = OOClamp_0_1_f(tokens.at<float>(1));
			float b1 = OOClamp_0_1_f(tokens.at<float>(2));
			float r2 = OOClamp_0_1_f(tokens.at<float>(3));
			float g2 = OOClamp_0_1_f(tokens.at<float>(4));
			float b2 = OOClamp_0_1_f(tokens.at<float>(5));
			*ioColor1 = OOColor::colorWithRed(r1, g1, b1, 1.0);
			*ioColor2 = OOColor::colorWithRed(r2, g2, b2, 1.0);
		}
		else
		{
			OO_LOG_WARN("sky.fromDict", "could not interpret \"{}\" as two RGB colours (must be six numbers).", *string);
		}
	}
	colorDesc = ValueForKey(dictionary, "sky_color_1");
	if (!colorDesc.isNull())
	{
		color = PremultipliedColorWithDescription(colorDesc);
		if (color != nullptr)  *ioColor1 = color;
		else  OO_LOG_WARN("sky.fromDict", "could not interpret \"{}\" as a colour.", oo::DescriptionOf(colorDesc));
	}
	colorDesc = ValueForKey(dictionary, "sky_color_2");
	if (!colorDesc.isNull())
	{
		color = PremultipliedColorWithDescription(colorDesc);
		if (color != nullptr)  *ioColor2 = color;
		else  OO_LOG_WARN("sky.fromDict", "could not interpret \"{}\" as a colour.", oo::DescriptionOf(colorDesc));
	}

	colorDesc = ValueForKey(dictionary, "nebula_color_1");
	if (!colorDesc.isNull())
	{
		color = PremultipliedColorWithDescription(colorDesc);
		if (color != nullptr)
		{
			*ioColor3 = color;
			nebulaSet = YES;
		}
		else  OO_LOG_WARN("sky.fromDict", "could not interpret \"{}\" as a colour.", oo::DescriptionOf(colorDesc));
	}
	else
	{
		colorDesc = ValueForKey(dictionary, "sky_color_1");
		if (!colorDesc.isNull())
		{
			color = PremultipliedColorWithDescription(colorDesc);
			if (color != nullptr)  *ioColor3 = color;
			else  OO_LOG_WARN("sky.fromDict", "could not interpret \"{}\" as a colour.", oo::DescriptionOf(colorDesc));
		}
	}

	colorDesc = ValueForKey(dictionary, "nebula_color_2");
	if (!colorDesc.isNull())
	{
		color = PremultipliedColorWithDescription(colorDesc);
		if (color != nullptr)
		{
			*ioColor4 = color;
			nebulaSet = YES;
		}
		else  OO_LOG_WARN("sky.fromDict", "could not interpret \"{}\" as a colour.", oo::DescriptionOf(colorDesc));
	}
	else
	{
		colorDesc = ValueForKey(dictionary, "sky_color_2");
		if (!colorDesc.isNull())
		{
			color = PremultipliedColorWithDescription(colorDesc);
			if (color != nullptr)  *ioColor4 = color;
			else  OO_LOG_WARN("sky.fromDict", "could not interpret \"{}\" as a colour.", oo::DescriptionOf(colorDesc));
		}
	}
	return nebulaSet;
}

