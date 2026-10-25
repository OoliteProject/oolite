/*

OOPlanetEntity.m

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

C++20 since bead oo-mp0d (proposed ADR-0056, amendments oo-bj8 item 12, oo-0mxi and oo-ubjo), a
leaf of Entity. Its Objective-C facade was deleted by bead oo-9ht.129 (amendments oo-9ht.12,
oo-9ht.107, oo-9ht.23 and oo-9ht.129): the class is global and its object is the root's facade.

*/

#include "OOPlanetEntity.h"
#include "OOJSPlanet.h"
#include "OOObjCPList.h"


#define NEW_ATMOSPHERE 1

#include "OOPlanetDrawable.h"
#include "OOTexture.h"

#include "AI.h"
#include "Universe.h"
#include "ShipEntity.h"
#include "PlayerEntity.h"
#include "ShipEntityAI.h"
#include "OOCharacter.h"

#include "OOMaths.h"
#include "ResourceManager.h"
#include "OOStringParsing.h"
#include "OOSystemDescriptionManager.h"

#include "OOPlanetTextureGenerator.h"
#include "OOStandaloneAtmosphereGenerator.h"
#include "OOSingleTextureMaterial.h"
#include "OOShaderMaterial.h"
#include "OOEntityFilterPredicate.h"
#include "OOGraphicsResetManager.h"
#include "OOStringExpander.h"
#include "OOOpenGLMatrixManager.h"
#include "OOJavaScriptEngine.h"	// OONull
#include "OOPListGameTypes.h"

#include "oofnd/Log.hpp"
#include "oofnd/PListGet.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"


#define OO_TERMINATOR_THRESHOLD_VECTOR_DEFAULT	(make_vector(0.105, 0.18, 0.28))	// used to be (0.1, 0.105, 0.12);


namespace {

// -setObject:forKey: on the planet info; nothing when there is no info (messaging nil).
void SetInfo(oo::PList &info, const std::string &key, oo::PList value)
{
	if (oo::PList::Dict *dict = info.getIf<oo::PList::Dict>())  (*dict)[key] = std::move(value);
}


// The live object an Object node for <key> holds (nil when absent, or for any other value, which
// the callers never store there: the colours this class puts in the planet info).
// The colour an Object node of the planet info holds (the colour is the node's foreign object since
// bead oo-9ht.1); null for none.
OOColor *ColorForKey(const oo::PList &dict, std::string_view key)
{
	const oo::PList *value = dict.find(key);
	return value != nullptr ? OOColorInObjectNode(*value) : nullptr;
}


// -objectForKey: as plist data (a null PList when absent), for OOColor::colorWithDescription().
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


// get<Vector>: OOVectorFromPList of the value; the zero vector for no dictionary (messaging nil).
Vector VectorForKey(const oo::PList &dict, std::string_view key, Vector fallback)
{
	if (dict.isNull())  return kZeroVector;
	return OOVectorFromPList(dict.find(key), fallback);
}


// get<PList::Dict>: the dictionary, or null (nil).
oo::PList DictionaryForKey(const oo::PList &dict, std::string_view key)
{
	const oo::PList *value = dict.get<oo::PList::Dict>(key);
	return value != nullptr ? *value : oo::PList();
}


// -dictionaryWithValuesForKeys: of the planet info: OONull for a missing key; nil for no info.
oo::PList ValuesForKeys(const oo::PList &info, std::initializer_list<const char *> keys)
{
	if (!info.isDict())  return oo::PList();
	oo::PList::Dict result;
	for (const char *key : keys)
	{
		const oo::PList *value = info.find(key);
		result[key] = value != nullptr ? *value : OONullObjectNode();
	}
	return oo::PList(std::move(result));
}


// The cube-map texture specifier the Foundation code built with +dictionaryWithObjectsAndKeys:.
oo::PList CubeMapTextureSpec(const std::string &name)
{
	oo::PList::Dict spec;
	spec["name"] = name;
	spec["repeat_s"] = "yes";
	spec["min_filter"] = "linear";
	spec["cube_map"] = "yes";
	return oo::PList(std::move(spec));
}


// A copy of a material configuration with _oo_texture_objects set to the textures up to the first
// nil (+arrayWithObjects: stopped there); null where there was no configuration.
oo::PList MaterialConfigWithTextures(const oo::PList &configuration, std::initializer_list<OOTexture *> textures)
{
	if (configuration.isNull())  return oo::PList();
	oo::PList result = configuration;
	oo::PList::Array textureObjects;
	for (OOTexture *texture : textures)
	{
		if (texture == nil)  break;
		textureObjects.push_back(OOTextureObjectNode(texture));
	}
	(*result.getIf<oo::PList::Dict>())["_oo_texture_objects"] = oo::PList(std::move(textureObjects));
	return result;
}

}	// namespace


// this is exclusively called to initialise the main planet.
void OOPlanetEntity::initAsMainPlanetForSystem(OOSystemID s)
{
	oo::PList planetInfo = (UNIVERSE != nullptr ? UNIVERSE->generateSystemData(s) : oo::PList());

	SetInfo(planetInfo, "mainForLocalSystem", oo::PList(static_cast<bool>(YES)));
	if (s != (PLAYER != nullptr ? PLAYER->systemID() : 0))
	{
		SetInfo(planetInfo, "isMiniature", oo::PList(static_cast<bool>(YES)));
	}
	initFromDictionary(planetInfo, planetInfo.get<bool>("has_atmosphere", YES), ((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getRandomSeedForSystem(s, (PLAYER != nullptr ? PLAYER->galaxyNumber() : OOGalaxyID{})) : Random_Seed()), s);
}


static const double kMesosphere = 10.0 * ATMOSPHERE_DEPTH;	// atmosphere effect starts at 10x the height of the clouds


void OOPlanetEntity::initFromDictionary(const oo::PList &dictionary, bool atmosphere, Random_Seed seed, OOSystemID systemID)
{
	const oo::PList dict = dictionary.isNull() ? oo::PList(oo::PList::Dict{}) : dictionary;
	RANROTSeed savedRanrotSeed = RANROTGetFullSeed();

	// [self init]: the facade made this object, and the constructor ran Entity's -init.

	scanClass = CLASS_NO_DRAW;
	
	oo::PList planetInfo = (UNIVERSE != nullptr ? UNIVERSE->generateSystemData(systemID) : oo::PList());	// null where it was nil

	setUpTypeParametersWithSourceInfo(dict, planetInfo);

	setUpTerrainParametersWithSourceInfo(dict, planetInfo);


	// Load random seed override.
	const std::optional<std::string> seedStr = OptionalStringForKey(dict, "seed");
	if (seedStr.has_value())
	{
		Random_Seed overrideSeed = cxx_RandomSeedFromString(seedStr);
		if (!is_nil_seed(overrideSeed))  seed = overrideSeed;
		else  OO_LOG_ERR("planet.fromDict", "could not interpret \"{}\" as planet seed, using default.", *seedStr);
	}
	
	// Generate various planet info.
	seed_for_planet_description(seed);

	_name.reset();
	// A nil planet info read nil for the name, which then falls back to nothing.
	const std::optional<std::string> infoName = planetInfo ? std::optional<std::string>(planetInfo.get<std::string>(std::string(KEY_PLANETNAME), "%H")) : std::nullopt;
	const std::optional<std::string> planetName = infoName.has_value() ? std::optional<std::string>(dict.get<std::string>(std::string(KEY_PLANETNAME), *infoName)) : OptionalStringForKey(dict, std::string(KEY_PLANETNAME));
	setName(planetName.has_value() ? cxx_OOExpand(*planetName) : std::nullopt);

	int radius_km = dict.get<int>(std::string(KEY_RADIUS), planetInfo.get<int>(std::string(KEY_RADIUS)));
	collision_radius = radius_km * 10.0;	// Scale down by a factor of 100
	OOTechLevelID techLevel = dict.get<int>(std::string(KEY_TECHLEVEL), planetInfo.get<int>(std::string(KEY_TECHLEVEL)));
	
	if (techLevel > 14)  techLevel = 14;
	_shuttlesOnGround = 1 + techLevel / 2;
	_shuttleLaunchInterval = 3600.0 / (double)_shuttlesOnGround;	// All are launched in one hour.
	_lastLaunchTime = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) + 30.0 - _shuttleLaunchInterval;	// launch 30s after player enters universe.
																			// make delay > 0 to allow scripts adding a station nearby.
	
	int percent_land = planetInfo.get<int>("percent_land", 24 + (gen_rnd_number() % 48));
	SetInfo(planetInfo, "land_fraction", oo::PList::singleReal(0.01 * percent_land));	// +numberWithFloat:

	int percent_ice = planetInfo.get<int>("percent_ice", 5);
	SetInfo(planetInfo, "polar_fraction", oo::PList::singleReal(0.01 * percent_ice));

	
	RNG_Seed savedRndSeed = currentRandomSeed();
	
	_planetDrawable = oo::makeRef<OOPlanetDrawable>();
	
	_terminatorThresholdVector = VectorForKey(planetInfo, "terminator_threshold_vector", OO_TERMINATOR_THRESHOLD_VECTOR_DEFAULT);
	
	// Load material parameters, including atmosphere.
	_noiseMapSeed = RANROTGetFullSeed();
	setUpLandParametersWithSourceInfo(dict, planetInfo);
	
	_airColor = nullptr;	// default to no air
	_airColorMixRatio = 0.5f;
	_airDensity = 0.75f;
	
	_illuminationColor = oo::Ref<OOColor>(ColorForKey(planetInfo, "illumination_color"));
	
#if NEW_ATMOSPHERE
	if (atmosphere)
	{
		// shader atmosphere always has a radius of collision_radius + ATMOSPHERE_DEPTH. For texture atmosphere, we need to check
		// if a shader atmosphere is also used. If yes, set its radius to just cover the planet so that it doesn't conflict with 
		// the shader atmosphere at the planet edges. If no shader atmosphere is used, then set it to the standard radius
		double atmosphereRadius = (UNIVERSE != nullptr ? UNIVERSE->getDetailLevel() : OOGraphicsDetail{}) >= DETAIL_LEVEL_SHADERS ? collision_radius : collision_radius + ATMOSPHERE_DEPTH;
		_atmosphereDrawable = OOPlanetDrawable::atmosphereWithRadius(atmosphereRadius);
		_cloudsShaderDrawable = OOPlanetDrawable::atmosphereWithRadius(atmosphereRadius);
		_atmosphereShaderDrawable = OOPlanetDrawable::atmosphereWithRadius(collision_radius + ATMOSPHERE_DEPTH);
		
		// convert the atmosphere settings to generic 'material parameters'
		percent_land = 100 - dict.get<int>("percent_cloud", 100 - (3 + (gen_rnd_number() & 31)+(gen_rnd_number() & 31)));
		SetInfo(planetInfo, "cloud_fraction", oo::PList::singleReal(0.01 * percent_land));
		setUpAtmosphereParametersWithSourceInfo(dict, planetInfo);
		// planetInfo now contains a valid air_color
		_airColor = oo::Ref<OOColor>(ColorForKey(planetInfo, "air_color"));
		_airColorMixRatio = planetInfo.get<float>("air_color_mix_ratio");

		_airDensity = OOClamp_0_1_f(planetInfo.get<float>("air_density"));
		// (debug) translated air colour / cloud colour / polar cloud color via descriptionComponents

		_materialParameters = ValuesForKeys(planetInfo, { "cloud_fraction", "air_color", "air_color_mix_ratio", "air_density", "cloud_color", "polar_cloud_color", "cloud_alpha", "land_fraction", "land_color", "sea_color", "polar_land_color", "polar_sea_color", "economy", "polar_fraction", "isMiniature", "perlin_3d", "terminator_threshold_vector" });
	}
	else
#else
	// NEW_ATMOSPHERE is 0? still differentiate between normal planets and moons.
	if (atmosphere)
	{
		_atmosphereDrawable = OOPlanetDrawable::atmosphereWithRadius(collision_radius + ATMOSPHERE_DEPTH);
		_airColor = OOColor::colorWithRed(0.8f, 0.8f, 0.9f, 1.0f);
	}
	if (YES) // create _materialParameters when NEW_ATMOSPHERE is set to 0
#endif
	{
		_materialParameters = ValuesForKeys(planetInfo, { "land_fraction", "land_color", "sea_color", "polar_land_color", "polar_sea_color", "economy", "polar_fraction",  "isMiniature", "perlin_3d", "terminator_threshold_vector", "illumination_color" });
	}
	
	_mesopause2 = (atmosphere) ? (kMesosphere + collision_radius) * (kMesosphere + collision_radius) : 0.0;
	
	_normSpecMapName = OptionalStringForKey(dict, "texture_normspec"); // must be set up before _textureName

	_textureName = OptionalStringForKey(dict, "texture");
	setUpPlanetFromTexture(_textureName);
	_planetDrawable->setRadius(collision_radius);
		
	// Orientation should be handled by the code that calls this planetEntity. Starting with a default value anyway.
	orientation = (Quaternion){ M_SQRT1_2, M_SQRT1_2, 0, 0 };
	_atmosphereOrientation = kIdentityQuaternion;
	_rotationAxis = vector_up_from_quaternion(orientation);
	
	// set speed of rotation.
	if (dict.find("rotational_velocity") != nullptr)
	{
		_rotationalVelocity = dict.get<float>("rotational_velocity", 0.01f * randf());	// 0.0 .. 0.01 avr 0.005
	}
	else
	{
		_rotationalVelocity = planetInfo.get<float>("rotation_speed", 0.005f * randf()); // 0.0 .. 0.005 avr 0.0025
		_rotationalVelocity *= planetInfo.get<float>("rotation_speed_factor", 1.0f);
	}

	_atmosphereRotationalVelocity = dict.get<float>("atmosphere_rotational_velocity", 0.01f * randf());

	// set energy
	energy = collision_radius * 1000.0f;
	
	setRandomSeed(savedRndSeed);
	RANROTSetFullSeed(savedRanrotSeed);
	
	// rotate planet based on current time, needs to be done here - backported from PlanetEntity.
	int		deltaT = floor(fmod((PLAYER != nullptr ? PLAYER->clockTimeAdjusted() : 0.0), 86400));
	quaternion_rotate_about_axis(&orientation, _rotationAxis, _rotationalVelocity * deltaT);
	quaternion_rotate_about_axis(&_atmosphereOrientation, kBasisYVector, _atmosphereRotationalVelocity * deltaT);
	
	
#ifdef OO_DUMP_PLANETINFO
#define CPROP(PROP)	OO_LOG("planetinfo.record", #PROP " = {};", (ColorForKey(planetInfo, #PROP) != nullptr ? ColorForKey(planetInfo, #PROP)->descriptionComponents() : std::nullopt).value_or("(null)"));
#define FPROP(PROP)	OO_LOG("planetinfo.record", #PROP " = {:f};", planetInfo.get<float>(#PROP));
	CPROP(air_color);
	CPROP(illumination_color);
	FPROP(air_color_mix_ratio);
	FPROP(cloud_alpha);
	CPROP(cloud_color);
	FPROP(cloud_fraction);
	CPROP(land_color);
	FPROP(land_fraction);
	CPROP(polar_cloud_color);
	CPROP(polar_land_color);
	CPROP(polar_sea_color);
	CPROP(sea_color);
	OO_LOG("planetinfo.record", "rotation_speed = {:f}", _rotationalVelocity);
#endif

	setStatus(STATUS_ACTIVE);

	OOGraphicsResetManager::sharedManager()->registerCxxClient(this);
}


static Vector RandomHSBColor(void)
{
	return (Vector)
	{
		(OOScalar)(gen_rnd_number() / 256.0),
		(OOScalar)(gen_rnd_number() / 256.0),
		(OOScalar)(0.5 + gen_rnd_number() / 512.0)
	};
}


static Vector LighterHSBColor(Vector c)
{
	return (Vector)
	{
		c.x,
		c.y * 0.25f,
		1.0f - (c.z * 0.1f)
	};
}


namespace {

Vector HSBColorWithColor(OOColor *color)
{
	OOHSBAComponents c = color->hsbaComponents();	// never nil here
	return (Vector){ c.h/360, c.s, c.b };
}


// The planet info's colours are Object nodes of the colour (bead oo-9ht.1).
oo::PList ColorWithHSBColor(Vector c)
{
	return OOColorObjectNode(OOColor::colorWithHue(c.x, c.y, c.z, 1.0).get());
}

}	// namespace


void OOPlanetEntity::setUpTypeParametersWithSourceInfo(const oo::PList &sourceInfo, oo::PList &targetInfo)
{
	SetInfo(targetInfo, "mainForLocalSystem", oo::PList(sourceInfo.get<bool>("mainForLocalSystem")));
	SetInfo(targetInfo, "isMiniature", oo::PList(sourceInfo.get<bool>("isMiniature")));

}


void OOPlanetEntity::setUpTerrainParametersWithSourceInfo(const oo::PList &sourceInfo, oo::PList &targetInfo)
{
	static const char * const keys[] = { "atmosphere_rotational_velocity","rotational_velocity","cloud_alpha","has_atmosphere","percent_cloud","percent_ice","percent_land","radius","seed" };
	for (const char *key : keys) {
		const oo::PList *sval = sourceInfo.find(key);
		if (sval != nullptr) {
			SetInfo(targetInfo, key, *sval);
		}
	}

}


void OOPlanetEntity::setUpLandParametersWithSourceInfo(const oo::PList &sourceInfo, oo::PList &targetInfo)
{
	setUpColorParametersWithSourceInfo(sourceInfo, targetInfo, false);
}


void OOPlanetEntity::setUpAtmosphereParametersWithSourceInfo(const oo::PList &sourceInfo, oo::PList &targetInfo)
{
	setUpColorParametersWithSourceInfo(sourceInfo, targetInfo, true);
}


void OOPlanetEntity::setUpColorParametersWithSourceInfo(const oo::PList &sourceInfo, oo::PList &targetInfo, bool isAtmosphere)
{
	// Stir the PRNG fourteen times for backwards compatibility.
	unsigned i;
	for (i = 0; i < 14; i++)
	{
		gen_rnd_number();
	}
	
	Vector	landHSB, seaHSB, landPolarHSB, seaPolarHSB, illumHSB;
	Vector	terminatorThreshold;
	oo::Ref<OOColor>	color;
	
	landHSB = RandomHSBColor();
	
	if (!isAtmosphere)
	{
		do
		{
			seaHSB = RandomHSBColor();
		}
		while (dot_product(landHSB, seaHSB) > .80f); // make sure land and sea colors differ significantly
		
		// saturation bias - avoids really grey oceans
		if (seaHSB.y < 0.22f) seaHSB.y = seaHSB.y * 0.3f + 0.2f;
		// brightness bias - avoids really bright landmasses
		if (landHSB.z > 0.66f) landHSB.z = 0.66f;
		
		// planetinfo.plist overrides
		color = OOColor::colorWithDescription(ValueForKey(sourceInfo, "land_color"));
		if (color != nullptr) landHSB = HSBColorWithColor(color.get());
		else cxx_ScanVectorFromString(OptionalStringForKey(sourceInfo, "land_hsb_color"), &landHSB);
		
		color = OOColor::colorWithDescription(ValueForKey(sourceInfo, "sea_color"));
		if (color != nullptr) seaHSB = HSBColorWithColor(color.get());
		else cxx_ScanVectorFromString(OptionalStringForKey(sourceInfo, "sea_hsb_color"), &seaHSB);
		
		color = OOColor::colorWithDescription(ValueForKey(sourceInfo, "illumination_color"));
		if (color != nullptr) illumHSB = HSBColorWithColor(color.get());
		else
		{
			const std::optional<std::string> illumHSBColorString = OptionalStringForKey(sourceInfo, "illumination_hsb_color");
			if (illumHSBColorString.has_value())  cxx_ScanVectorFromString(illumHSBColorString, &illumHSB);
			else illumHSB = HSBColorWithColor(OOColor::colorWithRed(0.8f, 0.8f, 0.4f, 1.0f).get());	
		}
		
		// polar areas are brighter but have less colour (closer to white)
		color = OOColor::colorWithDescription(ValueForKey(sourceInfo, "polar_land_color"));
		if (color != nullptr)
		{
			landPolarHSB = HSBColorWithColor(color.get());
		}
		else 
		{
			landPolarHSB = LighterHSBColor(landHSB);
		}

		color = OOColor::colorWithDescription(ValueForKey(sourceInfo, "polar_sea_color"));
		if (color != nullptr)
		{
			seaPolarHSB = HSBColorWithColor(color.get());
		}
		else
		{
			seaPolarHSB = LighterHSBColor(seaHSB);
		}
		
		SetInfo(targetInfo, "land_color", ColorWithHSBColor(landHSB));
		SetInfo(targetInfo, "sea_color", ColorWithHSBColor(seaHSB));
		SetInfo(targetInfo, "polar_land_color", ColorWithHSBColor(landPolarHSB));
		SetInfo(targetInfo, "polar_sea_color", ColorWithHSBColor(seaPolarHSB));
		SetInfo(targetInfo, "illumination_color", ColorWithHSBColor(illumHSB));
	}
	else
	{
		landHSB = RandomHSBColor();	// NB: randomcolor is called twice to make the cloud colour similar to the old one.

		// add a cloud_color tinge to sky blue({0.66, 0.3, 1}).
		seaHSB = vector_add(landHSB,((Vector){1.333, 0.6, 2}));	// 1 part cloud, 2 parts sky blue
		scale_vector(&seaHSB, 0.333);
				
		float cloudAlpha = OOClamp_0_1_f(sourceInfo.get<float>("cloud_alpha", 1.0f));
		SetInfo(targetInfo, "cloud_alpha", oo::PList::singleReal(cloudAlpha));	// +numberWithFloat:
		
		// planetinfo overrides
		color = OOColor::colorWithDescription(ValueForKey(sourceInfo, "air_color"));
		if (color != nullptr) seaHSB = HSBColorWithColor(color.get());
		
		color = OOColor::colorWithDescription(ValueForKey(sourceInfo, "cloud_color"));
		if (color != nullptr) landHSB = HSBColorWithColor(color.get());
		
		// polar areas: brighter, less saturation
		landPolarHSB = vector_add(landHSB,LighterHSBColor(landHSB));
		scale_vector(&landPolarHSB, 0.5);
		
		color = OOColor::colorWithDescription(ValueForKey(sourceInfo, "polar_cloud_color"));
		if (color != nullptr) landPolarHSB = HSBColorWithColor(color.get());
		
		SetInfo(targetInfo, "air_color", ColorWithHSBColor(seaHSB));
		SetInfo(targetInfo, "cloud_color", ColorWithHSBColor(landHSB));
		SetInfo(targetInfo, "polar_cloud_color", ColorWithHSBColor(landPolarHSB));
		SetInfo(targetInfo, "air_color_mix_ratio", oo::PList::singleReal(sourceInfo.get<float>("air_color_mix_ratio")));
	}
	terminatorThreshold = VectorForKey(sourceInfo, "terminator_threshold_vector", OO_TERMINATOR_THRESHOLD_VECTOR_DEFAULT);
	SetInfo(targetInfo, "terminator_threshold_vector", oo::str::format("%f %f %f", terminatorThreshold.x, terminatorThreshold.y, terminatorThreshold.z));
}


// -initAsMiniatureVersionOfPlanet:, run by miniatureVersion() on the object it made (amendment
// oo-novu): false where the initialiser answered nil.
bool OOPlanetEntity::initAsMiniatureVersionOfPlanet(OOPlanetEntity *planet)
{
	// Nasty, nasty. I'd really prefer to have a separate entity class for this.
	if (planet == nullptr)
	{
		return false;
	}

	// [self init]: the constructor ran Entity's -init.

	scanClass = CLASS_NO_DRAW;
	setStatus(STATUS_COCKPIT_DISPLAY);

	collision_radius = planet->collision_radius * PLANET_MINIATURE_FACTOR;
	orientation = planet->orientation;
	_rotationAxis = planet->_rotationAxis;
	_atmosphereOrientation = planet->_atmosphereOrientation;
	_rotationalVelocity = 0.04;
	
	_terminatorThresholdVector = planet->_terminatorThresholdVector;
	
	_miniature = YES;
	
	_planetDrawable = planet->_planetDrawable->copy();
	_planetDrawable->setRadius(collision_radius);
	
	// FIXME: in old planet code, atmosphere (if textured) is set to 0.6 alpha.
	// A copy of nil was nil.
	_atmosphereDrawable = planet->_atmosphereDrawable ? planet->_atmosphereDrawable->copy() : oo::Ref<OOPlanetDrawable>();
	_cloudsShaderDrawable = planet->_cloudsShaderDrawable ? planet->_cloudsShaderDrawable->copy() : oo::Ref<OOPlanetDrawable>();
	_atmosphereShaderDrawable = planet->_atmosphereShaderDrawable ? planet->_atmosphereShaderDrawable->copy() : oo::Ref<OOPlanetDrawable>();
	if (_atmosphereDrawable)  _atmosphereDrawable->setRadius(collision_radius + ATMOSPHERE_DEPTH * PLANET_MINIATURE_FACTOR * 2.0); //not to scale: invisible otherwise
	if (_cloudsShaderDrawable)  _cloudsShaderDrawable->setRadius(collision_radius + ATMOSPHERE_DEPTH * PLANET_MINIATURE_FACTOR * 2.0); //not to scale: invisible otherwise
	if (_atmosphereShaderDrawable)  _atmosphereShaderDrawable->setRadius(collision_radius + ATMOSPHERE_DEPTH * PLANET_MINIATURE_FACTOR * 2.0);
	
	_planetDrawable->setLevelOfDetail(0.8f);
	if (_atmosphereDrawable)  _atmosphereDrawable->setLevelOfDetail(0.8f);
	if (_cloudsShaderDrawable)  _cloudsShaderDrawable->setLevelOfDetail(0.8f);
	if (_atmosphereShaderDrawable)  _atmosphereShaderDrawable->setLevelOfDetail(0.8f);

	return true;
}


// -dealloc: the members release themselves.
OOPlanetEntity::~OOPlanetEntity()
{
	OOGraphicsResetManager::sharedManager()->unregisterCxxClient(this);
}


// -position and -radius read these members.
std::optional<std::string> OOPlanetEntity::descriptionComponents() const
{
	return oo::str::format("position: %s radius: %g m", cxx_HPVectorDescription(position).c_str(), (double)collision_radius);
}


void OOPlanetEntity::setOrientation(Quaternion quat)
{
	Entity::setOrientation(quat);
	_rotationAxis = vector_up_from_quaternion(quat);
}


double OOPlanetEntity::radius()
{
	return collision_radius;
}


OOStellarBodyType OOPlanetEntity::planetType()
{
	if (_miniature)  return STELLAR_TYPE_MINIATURE;
	if (_atmosphereDrawable != nullptr)  return STELLAR_TYPE_NORMAL_PLANET;
	return STELLAR_TYPE_MOON;
}


oo::Ref<OOPlanetEntity> OOPlanetEntity::miniatureVersion()
{
	// [[[self class] alloc] initAsMiniatureVersionOfPlanet:self]: the class has no subclass.
	oo::Ref<OOPlanetEntity> result = oo::makeRef<OOPlanetEntity>();
	if (!result->initAsMiniatureVersionOfPlanet(this))  return nullptr;
	return result;
}


void OOPlanetEntity::update(OOTimeDelta delta_t)
{
	Entity::update(delta_t);
	
	if (EXPECT(!_miniature))
	{
		BOOL canDrawShaderAtmosphere = _atmosphereShaderDrawable != nullptr && (UNIVERSE != nullptr ? UNIVERSE->getDetailLevel() : OOGraphicsDetail{}) >= DETAIL_LEVEL_SHADERS;
		if (EXPECT_NOT(_atmosphereDrawable != nullptr && cam_zero_distance < _mesopause2))
		{
			OOCAssert(_airColor != nullptr, "Expected a non-nil air colour for normal planet. Exiting.");
			double		alt = (sqrt(cam_zero_distance) - collision_radius) / kMesosphere; // the viewpoint altitude
			double		trueAlt = (sqrt(zero_distance) - collision_radius) / kMesosphere; // the actual ship altitude
			// if at long distance external view, rotating the camera could potentially end up with it being
			// at negative altitude. Since we know we are already inside the atmosphere at this point, just make sure
			// that altitude is kept to a minimum positive value to avoid sudden black skies
			if (alt <= 0.0)  alt = 1e-4;
			if (EXPECT_NOT(alt > 0 && alt <= 1.0))	// ensure aleph is clamped between 0 and 1
			{
				double	aleph = 1.0 - alt;
				double	aleph2 = aleph * aleph;
				
				// night sky, reddish flash on entering the atmosphere, low light pollution otherwhise
				oo::Ref<OOColor>	mixColor = OOColor::colorWithRed((EXPECT_NOT(alt > 0.98) ? 30.0f : 0.1f),
													0.1f,
													0.1f,
													aleph);
															  
				// occlusion rate: .9 is 18 degrees after the terminus, where twilight ends.
				// 1 is the terminus, 1.033 is 6 degrees before the terminus, where the sky begins to redden
				double rate = ((PLAYER != nullptr ? PLAYER->occlusionLevel() : 0.0f) - 0.97)/0.06; // from 0.97 to 1.03

				if (EXPECT(rate <= 1.0 && rate > 0.0))
				{
					mixColor = mixColor->blendedColorWithFraction(rate, _airColor.get());
					// TODO: properly calculated pink sky - needs to depend on sun's angular size,
					// and its angular height on the horizon.
					/*
					rate -= 0.7;
					if (rate >= 0.0) // pink sky!
					{
						rate = 0.5 - (fabs(rate - 0.15) / 0.3);	// at most a 50% blend!
						mixColor = [mixColor blendedColorWithFraction:rate ofColor:[OOColor colorWithRed:0.6
																								   green:0.1
																									blue:0.0
																								   alpha:aleph]];
					}
					*/
				}
				else
				{
					if (PLAYER->isSunlit && _airColor != nullptr) mixColor = _airColor;
				}
				if (UNIVERSE != nullptr)  UNIVERSE->setSkyColorRed(mixColor->redComponent() * aleph2, mixColor->greenComponent() * aleph2, mixColor->blueComponent() * aleph, aleph);
				double atmosphereRadius = canDrawShaderAtmosphere ? collision_radius : collision_radius + (ATMOSPHERE_DEPTH * alt);
				_atmosphereDrawable->setRadius(atmosphereRadius);
				if (_cloudsShaderDrawable) _cloudsShaderDrawable->setRadius(atmosphereRadius);
				if (_atmosphereShaderDrawable)  _atmosphereShaderDrawable->setRadius(collision_radius + (ATMOSPHERE_DEPTH * alt));
				// apply air resistance for the ship, not the camera. Although setSkyColorRed
				// has already set the air resistance to aleph, override it immediately
				if (UNIVERSE != nullptr)  UNIVERSE->setAirResistanceFactor(OOClamp_0_1_f(1.0 - trueAlt));
			}
		}
		else
		{
			// No atmosphere: [nil radius] was 0, and the messages to nil did nothing.
			if (EXPECT_NOT((_atmosphereDrawable ? _atmosphereDrawable->radius() : 0.0f) < collision_radius + ATMOSPHERE_DEPTH))
			{
				if (_atmosphereDrawable)  _atmosphereDrawable->setRadius(collision_radius + ATMOSPHERE_DEPTH);
				if (_cloudsShaderDrawable) _cloudsShaderDrawable->setRadius(collision_radius * ATMOSPHERE_DEPTH);
				if (_atmosphereShaderDrawable)  _atmosphereShaderDrawable->setRadius(collision_radius + ATMOSPHERE_DEPTH);
			}
			if (canDrawShaderAtmosphere && (_atmosphereDrawable ? _atmosphereDrawable->radius() : 0.0f) != collision_radius)
			{
				// if shader atmo is in use, force texture atmo radius to just collision_radius for cosmetic purposes
				if (_atmosphereDrawable)  _atmosphereDrawable->setRadius(collision_radius);
				if (_cloudsShaderDrawable) _cloudsShaderDrawable->setRadius(collision_radius);
			}
			if ((PLAYER != nullptr ? PLAYER->findNearestPlanet() : (OOPlanetEntity *)nullptr) == this) // ensure no problems in case of more than one planets
			{
				if (UNIVERSE != nullptr)  UNIVERSE->setAirResistanceFactor(0.0f);	// out of atmosphere - no air friction
			}
		}
		
		double time = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0);
		
		if (_shuttlesOnGround > 0 && time > _lastLaunchTime + _shuttleLaunchInterval)  launchShuttle();
	}
	
	quaternion_rotate_about_axis(&orientation, _rotationAxis, _rotationalVelocity * delta_t);
	// atmosphere orientation is relative to the orientation of the planet
	quaternion_rotate_about_axis(&_atmosphereOrientation, kBasisYVector, _atmosphereRotationalVelocity * delta_t);

	orientationChanged();
	
	// FIXME: update atmosphere rotation
}


bool OOPlanetEntity::isFinishedLoading()
{
	OOMaterial *material = this->material();
	if (material != nullptr && !material->isFinishedLoading())  return false;
	material = atmosphereMaterial();
	if (material != nullptr && !material->isFinishedLoading())  return false;
	material = atmosphereShaderMaterial();
	if (material != nullptr && !material->isFinishedLoading())  return false;
	return true;
}


// translucent is read only in the branch that OOLITE_HAVE_FIXED_THE_ABOVE_DESCRIBED_BUG_WHICH_WE_HAVENT compiles out.
void OOPlanetEntity::drawImmediate(bool /*immediate*/, bool /*translucent*/)
{
	BOOL canDrawShaderAtmosphere = _atmosphereShaderDrawable != nullptr && (UNIVERSE != nullptr ? UNIVERSE->getDetailLevel() : OOGraphicsDetail{}) >= DETAIL_LEVEL_SHADERS;
	
	if ((UNIVERSE != nullptr ? UNIVERSE->breakPatternHide() : false))   return; // DON'T DRAW
	if (_miniature && !isFinishedLoading())  return; // For responsiveness, don't block to draw as miniature.

	// too far away to be drawn
	if (magnitude(cameraRelativePosition) > radius()*3000) {
		return;
	}
	if (!(UNIVERSE != nullptr ? UNIVERSE->viewFrustumIntersectsSphereAt(cameraRelativePosition, (radius() + ATMOSPHERE_DEPTH)) : false))
	{
		// Don't draw
		return;
	}
	
	if ((UNIVERSE != nullptr ? UNIVERSE->getWireframeGraphics() : false))  OOGLWireframeModeOn();
	
	if (!_miniature)
	{
		_planetDrawable->calculateLevelOfDetailForViewDistance(cam_zero_distance);
		if (_atmosphereDrawable)  _atmosphereDrawable->setLevelOfDetail(_planetDrawable->levelOfDetail());
		if (canDrawShaderAtmosphere)
		{
			if (_cloudsShaderDrawable)  _cloudsShaderDrawable->setLevelOfDetail(_planetDrawable->levelOfDetail());
			_atmosphereShaderDrawable->setLevelOfDetail(_planetDrawable->levelOfDetail());
		}
	}

	// 500km squared
    //	if (magnitude2(cameraRelativePosition) > 250000000000.0) 
	/* Temporarily for 1.82 make this branch unconditional. There's an
	 * odd change in appearance when crossing this boundary, which can
	 * be quite noticeable. There don't appear to be close-range
	 * problems with doing it this way all the time, though it's not
	 * ideal. - CIM */
	{
		/* at this distance the atmosphere is too close to the planet
		 * for a 24-bit depth buffer to reliably distinguish the two,
		 * so cheat and draw the atmosphere on the opaque pass: it's
		 * far enough away that painter's algorithm should do fine */
		_planetDrawable->renderOpaqueParts();
		if (_atmosphereDrawable != nullptr)
		{
			OOGLPushModelView();
			OOGLMultModelView(OOMatrixForQuaternionRotation(_atmosphereOrientation));
			if (canDrawShaderAtmosphere)
			{
				if(_cloudsShaderDrawable) _cloudsShaderDrawable->renderTranslucentPartsOnOpaquePass();
				_atmosphereShaderDrawable->renderTranslucentPartsOnOpaquePass();
			}
			else
			{
				_atmosphereDrawable->renderTranslucentPartsOnOpaquePass();
			}
			OOGLPopModelView();
		}
	}
#if OOLITE_HAVE_FIXED_THE_ABOVE_DESCRIBED_BUG_WHICH_WE_HAVENT
	else 
	{
		/* At close range we can do this properly and draw the
		 * atmosphere on the transparent pass */
		if (translucent)
		{
			if (_atmosphereDrawable != nullptr)
			{
				OOGLPushModelView();
				OOGLMultModelView(OOMatrixForQuaternionRotation(_atmosphereOrientation));
				_atmosphereDrawable->renderTranslucentParts();
				if (canDrawShaderAtmosphere)  _atmosphereShaderDrawable->renderTranslucentParts();
				OOGLPopModelView();
			}
		}
		else
		{
			_planetDrawable->renderOpaqueParts();
		}
	}
#endif
	
	if ((UNIVERSE != nullptr ? UNIVERSE->getWireframeGraphics() : false))  OOGLWireframeModeOff();
}


bool OOPlanetEntity::checkCloseCollisionWith(Entity *other)
{
	if (!other)
		return NO;
	if (other->isShip)
	{
		::ShipEntity *ship = oo::ToShip(other);
		if ((ship != nullptr ? ship->getBehaviour() : OOBehaviour{}) == BEHAVIOUR_LAND_ON_PLANET)
		{
			return NO;
		}
	}
	
	return YES;
}


bool OOPlanetEntity::planetHasStation()
{
	// find the nearest station...
	::ShipEntity	*station =  nil;
	station = oo::ToShip((UNIVERSE != nullptr ? UNIVERSE->nearestShipMatchingPredicate(IsStationPredicate, nullptr, this) : nullptr));
	
	if (station && HPdistance((station != nullptr ? station->getPosition() : HPVector{}), position) < 4 * collision_radius) // there is a station in range.
	{
		return YES;
	}
	return NO;
}


void OOPlanetEntity::launchShuttle()
{
	if (_shuttlesOnGround == 0)  
	{
		return;
	}
	if ((PLAYER != nullptr ? PLAYER->status() : OOEntityStatus{}) == STATUS_START_GAME)
	{
		// don't launch if game not started
		return;
	}
	if (this != (UNIVERSE != nullptr ? UNIVERSE->planet() : nullptr) && !planetHasStation())
	{
		// don't launch shuttles when no station is nearby.
		_shuttlesOnGround = 0;
		return;
	}
	
	Quaternion  q1;
	quaternion_set_random(&q1);
	float start_distance = collision_radius + 125.0f;
	HPVector launch_pos = HPvector_add(position, vectorToHPVector(vector_multiply_scalar(vector_forward_from_quaternion(q1), start_distance)));
	
	::ShipEntity *shuttle_ship = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole("shuttle") : (::ShipEntity *)nil);   // retain count = 1
	if (shuttle_ship)
	{
		if ((shuttle_ship != nullptr ? shuttle_ship->getCrew() : std::optional<std::vector<oo::Ref<OOCharacter>>>()).value_or(std::vector<oo::Ref<OOCharacter>>()).empty())
		{
			if (shuttle_ship != nullptr)  shuttle_ship->setSingleCrewWithRole("trader");
		}
		
		if (shuttle_ship != nullptr)  shuttle_ship->setPosition(launch_pos);
		if (shuttle_ship != nullptr)  shuttle_ship->setOrientation(q1);
		
		if (shuttle_ship != nullptr)  shuttle_ship->setScanClass(CLASS_NEUTRAL);
		if (shuttle_ship != nullptr)  shuttle_ship->setCargoFlag(CARGO_FLAG_FULL_PLENTIFUL);
		if (shuttle_ship != nullptr)  shuttle_ship->switchAITo("oolite-shuttleAI.js");
		if (UNIVERSE != nullptr)  UNIVERSE->addEntity(shuttle_ship);	// STATUS_IN_FLIGHT, AI state GLOBAL
		_shuttlesOnGround--;
		_lastLaunchTime = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0);
		
		if (shuttle_ship != nullptr)  oo::ReleaseEntity(shuttle_ship);
	}
}


void OOPlanetEntity::welcomeShuttle(::ShipEntity * /*shuttle*/)
{
	_shuttlesOnGround++;
}


bool OOPlanetEntity::isPlanet()
{
	return YES;
}


bool OOPlanetEntity::isVisible()
{
	return YES;
}


double OOPlanetEntity::rotationalVelocity()
{
	return _rotationalVelocity;
}


void OOPlanetEntity::setRotationalVelocity(double v)
{
	if (hasAtmosphere())
	{
		// FIXME: change atmosphere rotation speed proportionally
	}
	_rotationalVelocity = v;
}


// this method is visible to shader bindings, hence it returns vector
Vector OOPlanetEntity::airColorAsVector()
{
	float r = 0, g = 0, b = 0, a = 0;	// a message to nil left them unwritten
	if (_airColor != nullptr)  _airColor->getRed(&r, &g, &b, &a);
	return make_vector(r, g, b); // don't care about a
}


OOColor *OOPlanetEntity::airColor()
{
	return _airColor.get();
}


void OOPlanetEntity::setAirColor(OOColor *newColor)
{
	if (newColor)
	{
		_airColor = oo::Ref<OOColor>(newColor);
	}
}


// this method is visible to shader bindings, hence it returns vector
Vector OOPlanetEntity::illuminationColorAsVector()
{
	float r = 0, g = 0, b = 0, a = 0;	// a message to nil left them unwritten
	if (_illuminationColor != nullptr)  _illuminationColor->getRed(&r, &g, &b, &a);
	return make_vector(r, g, b); // don't care about a
}


OOColor *OOPlanetEntity::illuminationColor()
{
	return _illuminationColor.get();
}


void OOPlanetEntity::setIlluminationColor(OOColor *newColor)
{
	if (newColor)
	{
		_illuminationColor = oo::Ref<OOColor>(newColor);
	}
}


// visible to shader bindings
float OOPlanetEntity::airColorMixRatio()
{
	return _airColorMixRatio;
}


void OOPlanetEntity::setAirColorMixRatio(float newRatio)
{
	_airColorMixRatio = OOClamp_0_1_f(newRatio);
}


// visible to shader bindings
float OOPlanetEntity::airDensity()
{
	return _airDensity;
}


void OOPlanetEntity::setAirDensity(float newDensity)
{
	_airDensity = OOClamp_0_1_f(newDensity);
}


void OOPlanetEntity::setTerminatorThresholdVector(Vector newTerminatorThresholdVector)
{
	_terminatorThresholdVector.x = newTerminatorThresholdVector.x;
	_terminatorThresholdVector.y = newTerminatorThresholdVector.y;
	_terminatorThresholdVector.z = newTerminatorThresholdVector.z;
}


Vector OOPlanetEntity::terminatorThresholdVector()
{
	return _terminatorThresholdVector;
}


bool OOPlanetEntity::hasAtmosphere()
{
	return _atmosphereDrawable != nullptr;
}


// FIXME: need material model.
std::optional<std::string> OOPlanetEntity::textureFileName()
{
	return _planetDrawable->textureName();
}


void OOPlanetEntity::resetGraphicsState()
{
	// reset the texture if graphics mode changes
	setUpPlanetFromTexture(_textureName);
}


void OOPlanetEntity::setTextureFileName(const std::optional<std::string> &textureFileName)
{
	BOOL isMoon = _atmosphereDrawable == nullptr;

	std::optional<std::string> textureName = textureFileName;
	oo::Ref<OOTexture> diffuseMap;	// held: the factories answer the texture retained (bead oo-9ht.99)
	oo::Ref<OOTexture> normalMap;
	oo::Ref<OOTexture> generatedDiffuseMap, generatedNormalMap;	// the C++ generator answers them retained (bead oo-kyje)
	oo::PList macros;	// null: nil
	const oo::PList materialDefaults = ResourceManager::materialDefaults();
	
#if OO_SHADERS
	OOGraphicsDetail detailLevel = (UNIVERSE != nullptr ? UNIVERSE->getDetailLevel() : OOGraphicsDetail{});
	BOOL shadersOn = detailLevel >= DETAIL_LEVEL_SHADERS;
#else
	const BOOL shadersOn = NO;
#endif
	
	if (textureName.has_value())
	{
		diffuseMap = OOTexture::textureWithConfiguration(CubeMapTextureSpec(*textureName));
		if (diffuseMap == nullptr)  return;		// OOTexture will have logged a file-not-found warning.
		if (shadersOn)  
		{
			diffuseMap->ensureFinishedLoading(); // only know if it is a cube map if it's loaded
			if (diffuseMap->isCubeMap())
			{
				macros = DictionaryForKey(materialDefaults, isMoon ? "moon-customized-cubemap-macros" : "planet-customized-cubemap-macros");
			}
			else
			{
				macros = DictionaryForKey(materialDefaults, isMoon ? "moon-customized-macros" : "planet-customized-macros");
			}
		}
		else textureName = "dynamic";
		
		 // let's try giving some love to normalMap too
		if (_normSpecMapName.has_value())
		{
			normalMap = OOTexture::textureWithConfiguration(CubeMapTextureSpec(*_normSpecMapName));
			if (normalMap != nullptr) // OOTexture will have logged a file-not-found warning.
			{
				if (shadersOn)  
				{
					normalMap->ensureFinishedLoading(); // only know if it is a cube map if it's loaded
					if (normalMap->isCubeMap())
					{
						macros = DictionaryForKey(materialDefaults, isMoon ? "moon-customized-cubemap-normspec-macros" : "planet-customized-cubemap-normspec-macros");
					}
					else
					{
						macros = DictionaryForKey(materialDefaults, isMoon ? "moon-customized-normspec-macros" : "planet-customized-normspec-macros");
					}
				}
			}
		}
	}
	else
	{
		OOPlanetTextureGenerator::generatePlanetTexture(&generatedDiffuseMap,
														(detailLevel >= DETAIL_LEVEL_SHADERS) ? &generatedNormalMap : NULL,
														_materialParameters,
														_noiseMapSeed);
		diffuseMap = generatedDiffuseMap;
		normalMap = generatedNormalMap;

		if (shadersOn)
		{
			macros = DictionaryForKey(materialDefaults, isMoon ? "moon-dynamic-macros" : "planet-dynamic-macros");
		}
		textureName = "dynamic";
	}

	/* Generate atmosphere texture */
	if (!isMoon)
	{
		OO_LOG("texture.planet.generate", "Preparing atmosphere for planet {}", oo::EntityDescription(this));
		/* Generate a standalone atmosphere texture */
		// (the C++ generator answers it retained: bead oo-y3dd)
		oo::Ref<OOTexture> generatedAtmosphere;
		OOStandaloneAtmosphereGenerator::generateAtmosphereTexture(&generatedAtmosphere,
																   _materialParameters,
																   _noiseMapSeed);
		OOTexture *atmosphere = generatedAtmosphere.get();
		
		OO_LOG("texture.planet.generate", "Planet {} has atmosphere {}", oo::EntityDescription(this), (atmosphere != nullptr) ? atmosphere->description() : std::string("(null)"));
		
		oo::Ref<OOSingleTextureMaterial> dynamicMaterial = OOSingleTextureMaterial::materialWithName("dynamic", atmosphere, oo::PList());
		_atmosphereDrawable->setMaterial(dynamicMaterial.get());

		if (shadersOn)
		{
			const oo::PList aConfig = MaterialConfigWithTextures(DictionaryForKey(materialDefaults, "atmosphere-material"), { diffuseMap.get(), normalMap.get() });

			const oo::PList amacros = DictionaryForKey(materialDefaults, "atmosphere-dynamic-macros");

			oo::Ref<OOShaderMaterial> dynamicShaderMaterial = OOShaderMaterial::shaderMaterialWithName("dynamic",
																	aConfig,
																	amacros,
																	this);	// the C++ planet (bead oo-9ht.39.6)
																	
			if (dynamicShaderMaterial == nullptr)
			{
				_atmosphereShaderDrawable = nullptr;
			}
			else
			{
				if (_atmosphereShaderDrawable)  _atmosphereShaderDrawable->setMaterial(dynamicShaderMaterial.get());
			}

			const oo::PList cloudConfig = MaterialConfigWithTextures(DictionaryForKey(materialDefaults, "clouds-dynamic-material"), { atmosphere });
			const oo::PList cloudMacros = DictionaryForKey(materialDefaults, "clouds-dynamic-macros");

			oo::Ref<OOShaderMaterial> cloudsMaterial = OOShaderMaterial::shaderMaterialWithName("dynamic",
										cloudConfig,
										cloudMacros,
										this);	// the C++ planet (bead oo-9ht.39.6)
			if (cloudsMaterial == nullptr)
			{
				_cloudsShaderDrawable = nullptr;
			}
			else
			{
				if (_cloudsShaderDrawable)  _cloudsShaderDrawable->setMaterial(cloudsMaterial.get());
			}
		}
		
		// [dynamicMaterial release]: the reference's.
	}

	oo::Ref<OOMaterial> material;
	
#if OO_SHADERS
	if (shadersOn)
	{
		const oo::PList config = MaterialConfigWithTextures(DictionaryForKey(materialDefaults, "planet-material"), { diffuseMap.get(), normalMap.get() });

		material = OOShaderMaterial::shaderMaterialWithName(textureName,
											  config,
													 macros,
											  this);	// the C++ planet (bead oo-9ht.39.6)
	}
#endif
	if (material == nullptr)
	{
		material = OOSingleTextureMaterial::materialWithName(textureName, diffuseMap.get(), oo::PList());
	}
	_planetDrawable->setMaterial(material.get());
}


bool OOPlanetEntity::setUpPlanetFromTexture(const std::optional<std::string> &textureName)
{
	setTextureFileName(textureName);
	return YES;
}


OOMaterial *OOPlanetEntity::material()
{
	return _planetDrawable->material();
}


OOMaterial *OOPlanetEntity::atmosphereMaterial()
{
	return _atmosphereDrawable ? _atmosphereDrawable->material() : nil;
}


OOMaterial *OOPlanetEntity::atmosphereShaderMaterial()
{
	if(!_atmosphereShaderDrawable)  return nil;
	return _atmosphereShaderDrawable->material();
}


std::optional<std::string> OOPlanetEntity::name()
{
	return _name;
}


void OOPlanetEntity::setName(const std::optional<std::string> &name)
{
	_name = name;
}


// The binding's bodies (OOJSPlanet.mm), which the facade forwarded to until bead oo-9ht.129.
void OOPlanetEntity::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)
{
	::OOJSPlanetGetJSClass(outClass, outPrototype);
}


std::optional<std::string> OOPlanetEntity::jsClassName()
{
	return ::OOJSPlanetJSClassName(this);
}


bool OOPlanetEntity::isVisibleToScripts()
{
	return ::OOJSPlanetIsVisibleToScripts(this);
}
