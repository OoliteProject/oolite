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

*/

#import "OOPlanetEntity.h"
#import "OOObjCPList.h"

#if NEW_PLANETS

#define NEW_ATMOSPHERE 1

#import "OOPlanetDrawable.h"

#import "AI.h"
#import "OOCharacter.h"
#import "PlayerEntity.h"
#import "ShipEntity.h"
#import "ShipEntityAI.h"
#import "Universe.h"

#import "OOMaths.h"
#import "OOStringParsing.h"
#import "OOSystemDescriptionManager.h"
#import "ResourceManager.h"

#import "OOEntityFilterPredicate.h"
#import "OOGraphicsResetManager.h"
#import "OOJavaScriptEngine.h" // OONull
#import "OOOpenGLMatrixManager.h"
#import "OOPListGameTypes.h"
#import "OOPlanetTextureGenerator.h"
#import "OOShaderMaterial.h"
#import "OOSingleTextureMaterial.h"
#import "OOStandaloneAtmosphereGenerator.h"
#import "OOStringExpander.h"

#include "oofnd/Log.hpp"
#include "oofnd/PListGet.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"

#define OO_TERMINATOR_THRESHOLD_VECTOR_DEFAULT (make_vector(0.105, 0.18, 0.28)) // used to be (0.1, 0.105, 0.12);

@interface OOPlanetEntity (Private) <OOGraphicsResetClient>

- (void)setUpTerrainParametersWithSourceInfo:(const oo::PList&)sourceInfo targetInfo:(oo::PList&)targetInfo;
- (void)setUpLandParametersWithSourceInfo:(const oo::PList&)sourceInfo targetInfo:(oo::PList&)targetInfo;
- (void)setUpAtmosphereParametersWithSourceInfo:(const oo::PList&)sourceInfo targetInfo:(oo::PList&)targetInfo;
- (void)setUpColorParametersWithSourceInfo:(const oo::PList&)sourceInfo targetInfo:(oo::PList&)targetInfo isAtmosphere:(BOOL)isAtmosphere;
- (void)setUpTypeParametersWithSourceInfo:(const oo::PList&)sourceInfo targetInfo:(oo::PList&)targetInfo;

@end

namespace {

// -setObject:forKey: on the planet info; nothing when there is no info (messaging nil).
void SetInfo(oo::PList& info, const std::string& key, oo::PList value)
{
    if (oo::PList::Dict* dict = info.getIf<oo::PList::Dict>())
        (*dict)[key] = std::move(value);
}

// The live object an Object node for <key> holds (nil when absent, or for any other value, which
// the callers never store there: the colours this class puts in the planet info).
id ObjectForKey(const oo::PList& dict, std::string_view key)
{
    const oo::PList* value = dict.find(key);
    return value != nullptr ? oo::ObjectIn(*value) : nil;
}

// -objectForKey: as plist data (a null PList when absent), for +cxx_colorWithDescription:.
oo::PList ValueForKey(const oo::PList& dict, std::string_view key)
{
    const oo::PList* value = dict.find(key);
    return value != nullptr ? *value : oo::PList();
}

// get<std::string> where the Foundation code read nil: std::nullopt when the key is absent or its
// value is neither a string nor a number.
std::optional<std::string> OptionalStringForKey(const oo::PList& dict, std::string_view key)
{
    const oo::PList* value = dict.find(key);
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return std::nullopt;
    return dict.get<std::string>(key);
}

// get<Vector>: OOVectorFromPList of the value; the zero vector for no dictionary (messaging nil).
Vector VectorForKey(const oo::PList& dict, std::string_view key, Vector fallback)
{
    if (dict.isNull())
        return kZeroVector;
    return OOVectorFromPList(dict.find(key), fallback);
}

// get<PList::Dict>: the dictionary, or null (nil).
oo::PList DictionaryForKey(const oo::PList& dict, std::string_view key)
{
    const oo::PList* value = dict.get<oo::PList::Dict>(key);
    return value != nullptr ? *value : oo::PList();
}

// -dictionaryWithValuesForKeys: of the planet info: OONull for a missing key; nil for no info.
oo::PList ValuesForKeys(const oo::PList& info, std::initializer_list<const char*> keys)
{
    if (!info.isDict())
        return oo::PList();
    oo::PList::Dict result;
    for (const char* key : keys) {
        const oo::PList* value = info.find(key);
        result[key] = value != nullptr ? *value : oo::PListObject([OONull null]);
    }
    return oo::PList(std::move(result));
}

// The cube-map texture specifier the Foundation code built with +dictionaryWithObjectsAndKeys:.
oo::PList CubeMapTextureSpec(const std::string& name)
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
oo::PList MaterialConfigWithTextures(const oo::PList& configuration, std::initializer_list<OOTexture*> textures)
{
    if (configuration.isNull())
        return oo::PList();
    oo::PList result = configuration;
    oo::PList::Array textureObjects;
    for (OOTexture* texture : textures) {
        if (texture == nil)
            break;
        textureObjects.push_back(oo::PListObject(texture));
    }
    (*result.getIf<oo::PList::Dict>())["_oo_texture_objects"] = oo::PList(std::move(textureObjects));
    return result;
}

} // namespace

@implementation OOPlanetEntity {
    // The texture generators' noise seed, handed to them directly; was a value box
    // under "noise_map_seed" in planetInfo / _materialParameters (bead oo-3rb.48).
    RANROTSeed _noiseMapSeed;
}

// this is exclusively called to initialise the main planet.
- (id)initAsMainPlanetForSystem:(OOSystemID)s
{
    oo::PList planetInfo = [UNIVERSE cxx_generateSystemData:s];

    SetInfo(planetInfo, "mainForLocalSystem", oo::PList(static_cast<bool>(YES)));
    if (s != [PLAYER systemID]) {
        SetInfo(planetInfo, "isMiniature", oo::PList(static_cast<bool>(YES)));
    }
    return [self initFromDictionary:planetInfo withAtmosphere:planetInfo.get<bool>("has_atmosphere", YES) andSeed:[[UNIVERSE systemManager] getRandomSeedForSystem:s inGalaxy:[PLAYER galaxyNumber]] forSystem:s];
}

static const double kMesosphere = 10.0 * ATMOSPHERE_DEPTH; // atmosphere effect starts at 10x the height of the clouds

- (id)initFromDictionary:(const oo::PList&)dictionary withAtmosphere:(BOOL)atmosphere andSeed:(Random_Seed)seed forSystem:(OOSystemID)systemID
{
    const oo::PList dict = dictionary.isNull() ? oo::PList(oo::PList::Dict { }) : dictionary;
    RANROTSeed savedRanrotSeed = RANROTGetFullSeed();

    self = [self init];
    if (self == nil)
        return nil;

    scanClass = CLASS_NO_DRAW;

    oo::PList planetInfo = [UNIVERSE cxx_generateSystemData:systemID]; // null where it was nil

    [self setUpTypeParametersWithSourceInfo:dict targetInfo:planetInfo];

    [self setUpTerrainParametersWithSourceInfo:dict targetInfo:planetInfo];

    // Load random seed override.
    const std::optional<std::string> seedStr = OptionalStringForKey(dict, "seed");
    if (seedStr.has_value()) {
        Random_Seed overrideSeed = cxx_RandomSeedFromString(seedStr);
        if (!is_nil_seed(overrideSeed))
            seed = overrideSeed;
        else
            OO_LOG_ERR("planet.fromDict", "could not interpret \"{}\" as planet seed, using default.", *seedStr);
    }

    // Generate various planet info.
    seed_for_planet_description(seed);

    _name.reset();
    // A nil planet info read nil for the name, which then falls back to nothing.
    const std::optional<std::string> infoName = planetInfo ? std::optional<std::string>(planetInfo.get<std::string>(std::string(KEY_PLANETNAME), "%H")) : std::nullopt;
    const std::optional<std::string> planetName = infoName.has_value() ? std::optional<std::string>(dict.get<std::string>(std::string(KEY_PLANETNAME), *infoName)) : OptionalStringForKey(dict, std::string(KEY_PLANETNAME));
    [self cxx_setName:planetName.has_value() ? cxx_OOExpand(*planetName) : std::nullopt];

    int radius_km = dict.get<int>(std::string(KEY_RADIUS), planetInfo.get<int>(std::string(KEY_RADIUS)));
    collision_radius = radius_km * 10.0; // Scale down by a factor of 100
    OOTechLevelID techLevel = dict.get<int>(std::string(KEY_TECHLEVEL), planetInfo.get<int>(std::string(KEY_TECHLEVEL)));

    if (techLevel > 14)
        techLevel = 14;
    _shuttlesOnGround = 1 + techLevel / 2;
    _shuttleLaunchInterval = 3600.0 / (double)_shuttlesOnGround; // All are launched in one hour.
    _lastLaunchTime = [UNIVERSE getTime] + 30.0 - _shuttleLaunchInterval; // launch 30s after player enters universe.
                                                                          // make delay > 0 to allow scripts adding a station nearby.

    int percent_land = planetInfo.get<int>("percent_land", 24 + (gen_rnd_number() % 48));
    SetInfo(planetInfo, "land_fraction", oo::PList::singleReal(0.01 * percent_land)); // +numberWithFloat:

    int percent_ice = planetInfo.get<int>("percent_ice", 5);
    SetInfo(planetInfo, "polar_fraction", oo::PList::singleReal(0.01 * percent_ice));

    RNG_Seed savedRndSeed = currentRandomSeed();

    _planetDrawable = [[OOPlanetDrawable alloc] init];

    _terminatorThresholdVector = VectorForKey(planetInfo, "terminator_threshold_vector", OO_TERMINATOR_THRESHOLD_VECTOR_DEFAULT);

    // Load material parameters, including atmosphere.
    _noiseMapSeed = RANROTGetFullSeed();
    [self setUpLandParametersWithSourceInfo:dict targetInfo:planetInfo];

    _airColor = nil; // default to no air
    _airColorMixRatio = 0.5f;
    _airDensity = 0.75f;

    _illuminationColor = [ObjectForKey(planetInfo, "illumination_color") retain];

#if NEW_ATMOSPHERE
    if (atmosphere) {
        // shader atmosphere always has a radius of collision_radius + ATMOSPHERE_DEPTH. For texture atmosphere, we need to check
        // if a shader atmosphere is also used. If yes, set its radius to just cover the planet so that it doesn't conflict with
        // the shader atmosphere at the planet edges. If no shader atmosphere is used, then set it to the standard radius
        double atmosphereRadius = [UNIVERSE detailLevel] >= DETAIL_LEVEL_SHADERS ? collision_radius : collision_radius + ATMOSPHERE_DEPTH;
        _atmosphereDrawable = [[OOPlanetDrawable atmosphereWithRadius:atmosphereRadius] retain];
        _cloudsShaderDrawable = [[OOPlanetDrawable atmosphereWithRadius:atmosphereRadius] retain];
        _atmosphereShaderDrawable = [[OOPlanetDrawable atmosphereWithRadius:collision_radius + ATMOSPHERE_DEPTH] retain];

        // convert the atmosphere settings to generic 'material parameters'
        percent_land = 100 - dict.get<int>("percent_cloud", 100 - (3 + (gen_rnd_number() & 31) + (gen_rnd_number() & 31)));
        SetInfo(planetInfo, "cloud_fraction", oo::PList::singleReal(0.01 * percent_land));
        [self setUpAtmosphereParametersWithSourceInfo:dict targetInfo:planetInfo];
        // planetInfo now contains a valid air_color
        _airColor = [ObjectForKey(planetInfo, "air_color") retain];
        _airColorMixRatio = planetInfo.get<float>("air_color_mix_ratio");

        _airDensity = OOClamp_0_1_f(planetInfo.get<float>("air_density"));
        // (debug) translated air colour / cloud colour / polar cloud color via descriptionComponents

        _materialParameters = ValuesForKeys(planetInfo, { "cloud_fraction", "air_color", "air_color_mix_ratio", "air_density", "cloud_color", "polar_cloud_color", "cloud_alpha", "land_fraction", "land_color", "sea_color", "polar_land_color", "polar_sea_color", "economy", "polar_fraction", "isMiniature", "perlin_3d", "terminator_threshold_vector" });
    } else
#else
    // NEW_ATMOSPHERE is 0? still differentiate between normal planets and moons.
    if (atmosphere) {
        _atmosphereDrawable = [[OOPlanetDrawable atmosphereWithRadius:collision_radius + ATMOSPHERE_DEPTH] retain];
        _airColor = [[OOColor colorWithRed:0.8f green:0.8f blue:0.9f alpha:1.0f] retain];
    }
    if (YES) // create _materialParameters when NEW_ATMOSPHERE is set to 0
#endif
    {
        _materialParameters = ValuesForKeys(planetInfo, { "land_fraction", "land_color", "sea_color", "polar_land_color", "polar_sea_color", "economy", "polar_fraction", "isMiniature", "perlin_3d", "terminator_threshold_vector", "illumination_color" });
    }

    _mesopause2 = (atmosphere) ? (kMesosphere + collision_radius) * (kMesosphere + collision_radius) : 0.0;

    _normSpecMapName = OptionalStringForKey(dict, "texture_normspec"); // must be set up before _textureName

    _textureName = OptionalStringForKey(dict, "texture");
    [self setUpPlanetFromTexture:_textureName];
    [_planetDrawable setRadius:collision_radius];

    // Orientation should be handled by the code that calls this planetEntity. Starting with a default value anyway.
    orientation = (Quaternion) { M_SQRT1_2, M_SQRT1_2, 0, 0 };
    _atmosphereOrientation = kIdentityQuaternion;
    _rotationAxis = vector_up_from_quaternion(orientation);

    // set speed of rotation.
    if (dict.find("rotational_velocity") != nullptr) {
        _rotationalVelocity = dict.get<float>("rotational_velocity", 0.01f * randf()); // 0.0 .. 0.01 avr 0.005
    } else {
        _rotationalVelocity = planetInfo.get<float>("rotation_speed", 0.005f * randf()); // 0.0 .. 0.005 avr 0.0025
        _rotationalVelocity *= planetInfo.get<float>("rotation_speed_factor", 1.0f);
    }

    _atmosphereRotationalVelocity = dict.get<float>("atmosphere_rotational_velocity", 0.01f * randf());

    // set energy
    energy = collision_radius * 1000.0f;

    setRandomSeed(savedRndSeed);
    RANROTSetFullSeed(savedRanrotSeed);

    // rotate planet based on current time, needs to be done here - backported from PlanetEntity.
    int deltaT = floor(fmod([PLAYER clockTimeAdjusted], 86400));
    quaternion_rotate_about_axis(&orientation, _rotationAxis, _rotationalVelocity * deltaT);
    quaternion_rotate_about_axis(&_atmosphereOrientation, kBasisYVector, _atmosphereRotationalVelocity * deltaT);

#ifdef OO_DUMP_PLANETINFO
#define CPROP(PROP) OO_LOG("planetinfo.record", #PROP " = {};", [(OOColor*)ObjectForKey(planetInfo, #PROP) cxx_descriptionComponents].value_or("(null)"));
#define FPROP(PROP) OO_LOG("planetinfo.record", #PROP " = {:f};", planetInfo.get<float>(#PROP));
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

    [self setStatus:STATUS_ACTIVE];

    [[OOGraphicsResetManager sharedManager] registerClient:self];

    return self;
}

static Vector RandomHSBColor(void)
{
    return (Vector) {
        (OOScalar)(gen_rnd_number() / 256.0),
        (OOScalar)(gen_rnd_number() / 256.0),
        (OOScalar)(0.5 + gen_rnd_number() / 512.0)
    };
}

static Vector LighterHSBColor(Vector c)
{
    return (Vector) {
        c.x,
        c.y * 0.25f,
        1.0f - (c.z * 0.1f)
    };
}

static Vector HSBColorWithColor(OOColor* color)
{
    OOHSBAComponents c = [color hsbaComponents];
    return (Vector) { c.h / 360, c.s, c.b };
}

static OOColor* ColorWithHSBColor(Vector c)
{
    return [OOColor colorWithHue:c.x saturation:c.y brightness:c.z alpha:1.0];
}

- (void)setUpTypeParametersWithSourceInfo:(const oo::PList&)sourceInfo targetInfo:(oo::PList&)targetInfo
{
    SetInfo(targetInfo, "mainForLocalSystem", oo::PList(sourceInfo.get<bool>("mainForLocalSystem")));
    SetInfo(targetInfo, "isMiniature", oo::PList(sourceInfo.get<bool>("isMiniature")));
}

- (void)setUpTerrainParametersWithSourceInfo:(const oo::PList&)sourceInfo targetInfo:(oo::PList&)targetInfo
{
    static const char* const keys[] = { "atmosphere_rotational_velocity", "rotational_velocity", "cloud_alpha", "has_atmosphere", "percent_cloud", "percent_ice", "percent_land", "radius", "seed" };
    for (const char* key : keys) {
        const oo::PList* sval = sourceInfo.find(key);
        if (sval != nullptr) {
            SetInfo(targetInfo, key, *sval);
        }
    }
}

- (void)setUpLandParametersWithSourceInfo:(const oo::PList&)sourceInfo targetInfo:(oo::PList&)targetInfo
{
    [self setUpColorParametersWithSourceInfo:sourceInfo targetInfo:targetInfo isAtmosphere:NO];
}

- (void)setUpAtmosphereParametersWithSourceInfo:(const oo::PList&)sourceInfo targetInfo:(oo::PList&)targetInfo
{
    [self setUpColorParametersWithSourceInfo:sourceInfo targetInfo:targetInfo isAtmosphere:YES];
}

- (void)setUpColorParametersWithSourceInfo:(const oo::PList&)sourceInfo targetInfo:(oo::PList&)targetInfo isAtmosphere:(BOOL)isAtmosphere
{
    // Stir the PRNG fourteen times for backwards compatibility.
    unsigned i;
    for (i = 0; i < 14; i++) {
        gen_rnd_number();
    }

    Vector landHSB, seaHSB, landPolarHSB, seaPolarHSB, illumHSB;
    Vector terminatorThreshold;
    OOColor* color;

    landHSB = RandomHSBColor();

    if (!isAtmosphere) {
        do {
            seaHSB = RandomHSBColor();
        } while (dot_product(landHSB, seaHSB) > .80f); // make sure land and sea colors differ significantly

        // saturation bias - avoids really grey oceans
        if (seaHSB.y < 0.22f)
            seaHSB.y = seaHSB.y * 0.3f + 0.2f;
        // brightness bias - avoids really bright landmasses
        if (landHSB.z > 0.66f)
            landHSB.z = 0.66f;

        // planetinfo.plist overrides
        color = [OOColor cxx_colorWithDescription:ValueForKey(sourceInfo, "land_color")];
        if (color != nil)
            landHSB = HSBColorWithColor(color);
        else
            cxx_ScanVectorFromString(OptionalStringForKey(sourceInfo, "land_hsb_color"), &landHSB);

        color = [OOColor cxx_colorWithDescription:ValueForKey(sourceInfo, "sea_color")];
        if (color != nil)
            seaHSB = HSBColorWithColor(color);
        else
            cxx_ScanVectorFromString(OptionalStringForKey(sourceInfo, "sea_hsb_color"), &seaHSB);

        color = [OOColor cxx_colorWithDescription:ValueForKey(sourceInfo, "illumination_color")];
        if (color != nil)
            illumHSB = HSBColorWithColor(color);
        else {
            const std::optional<std::string> illumHSBColorString = OptionalStringForKey(sourceInfo, "illumination_hsb_color");
            if (illumHSBColorString.has_value())
                cxx_ScanVectorFromString(illumHSBColorString, &illumHSB);
            else
                illumHSB = HSBColorWithColor([OOColor colorWithRed:0.8f green:0.8f blue:0.4f alpha:1.0f]);
        }

        // polar areas are brighter but have less colour (closer to white)
        color = [OOColor cxx_colorWithDescription:ValueForKey(sourceInfo, "polar_land_color")];
        if (color != nil) {
            landPolarHSB = HSBColorWithColor(color);
        } else {
            landPolarHSB = LighterHSBColor(landHSB);
        }

        color = [OOColor cxx_colorWithDescription:ValueForKey(sourceInfo, "polar_sea_color")];
        if (color != nil) {
            seaPolarHSB = HSBColorWithColor(color);
        } else {
            seaPolarHSB = LighterHSBColor(seaHSB);
        }

        SetInfo(targetInfo, "land_color", oo::PListObject(ColorWithHSBColor(landHSB)));
        SetInfo(targetInfo, "sea_color", oo::PListObject(ColorWithHSBColor(seaHSB)));
        SetInfo(targetInfo, "polar_land_color", oo::PListObject(ColorWithHSBColor(landPolarHSB)));
        SetInfo(targetInfo, "polar_sea_color", oo::PListObject(ColorWithHSBColor(seaPolarHSB)));
        SetInfo(targetInfo, "illumination_color", oo::PListObject(ColorWithHSBColor(illumHSB)));
    } else {
        landHSB = RandomHSBColor(); // NB: randomcolor is called twice to make the cloud colour similar to the old one.

        // add a cloud_color tinge to sky blue({0.66, 0.3, 1}).
        seaHSB = vector_add(landHSB, ((Vector) { 1.333, 0.6, 2 })); // 1 part cloud, 2 parts sky blue
        scale_vector(&seaHSB, 0.333);

        float cloudAlpha = OOClamp_0_1_f(sourceInfo.get<float>("cloud_alpha", 1.0f));
        SetInfo(targetInfo, "cloud_alpha", oo::PList::singleReal(cloudAlpha)); // +numberWithFloat:

        // planetinfo overrides
        color = [OOColor cxx_colorWithDescription:ValueForKey(sourceInfo, "air_color")];
        if (color != nil)
            seaHSB = HSBColorWithColor(color);

        color = [OOColor cxx_colorWithDescription:ValueForKey(sourceInfo, "cloud_color")];
        if (color != nil)
            landHSB = HSBColorWithColor(color);

        // polar areas: brighter, less saturation
        landPolarHSB = vector_add(landHSB, LighterHSBColor(landHSB));
        scale_vector(&landPolarHSB, 0.5);

        color = [OOColor cxx_colorWithDescription:ValueForKey(sourceInfo, "polar_cloud_color")];
        if (color != nil)
            landPolarHSB = HSBColorWithColor(color);

        SetInfo(targetInfo, "air_color", oo::PListObject(ColorWithHSBColor(seaHSB)));
        SetInfo(targetInfo, "cloud_color", oo::PListObject(ColorWithHSBColor(landHSB)));
        SetInfo(targetInfo, "polar_cloud_color", oo::PListObject(ColorWithHSBColor(landPolarHSB)));
        SetInfo(targetInfo, "air_color_mix_ratio", oo::PList::singleReal(sourceInfo.get<float>("air_color_mix_ratio")));
    }
    terminatorThreshold = VectorForKey(sourceInfo, "terminator_threshold_vector", OO_TERMINATOR_THRESHOLD_VECTOR_DEFAULT);
    SetInfo(targetInfo, "terminator_threshold_vector", oo::str::format("%f %f %f", terminatorThreshold.x, terminatorThreshold.y, terminatorThreshold.z));
}

- (id)initAsMiniatureVersionOfPlanet:(OOPlanetEntity*)planet
{
    // Nasty, nasty. I'd really prefer to have a separate entity class for this.
    if (planet == nil) {
        [self release];
        return nil;
    }

    self = [self init];
    if (self == nil)
        return nil;

    scanClass = CLASS_NO_DRAW;
    [self setStatus:STATUS_COCKPIT_DISPLAY];

    collision_radius = planet->collision_radius * PLANET_MINIATURE_FACTOR;
    orientation = planet->orientation;
    _rotationAxis = planet->_rotationAxis;
    _atmosphereOrientation = planet->_atmosphereOrientation;
    _rotationalVelocity = 0.04;

    _terminatorThresholdVector = planet->_terminatorThresholdVector;

    _miniature = YES;

    _planetDrawable = [planet->_planetDrawable copy];
    [_planetDrawable setRadius:collision_radius];

    // FIXME: in old planet code, atmosphere (if textured) is set to 0.6 alpha.
    _atmosphereDrawable = [planet->_atmosphereDrawable copy];
    _cloudsShaderDrawable = [planet->_cloudsShaderDrawable copy];
    _atmosphereShaderDrawable = [planet->_atmosphereShaderDrawable copy];
    [_atmosphereDrawable setRadius:collision_radius + ATMOSPHERE_DEPTH * PLANET_MINIATURE_FACTOR * 2.0]; // not to scale: invisible otherwise
    if (_cloudsShaderDrawable)
        [_cloudsShaderDrawable setRadius:collision_radius + ATMOSPHERE_DEPTH * PLANET_MINIATURE_FACTOR * 2.0]; // not to scale: invisible otherwise
    if (_atmosphereShaderDrawable)
        [_atmosphereShaderDrawable setRadius:collision_radius + ATMOSPHERE_DEPTH * PLANET_MINIATURE_FACTOR * 2.0];

    [_planetDrawable setLevelOfDetail:0.8f];
    [_atmosphereDrawable setLevelOfDetail:0.8f];
    if (_cloudsShaderDrawable)
        [_cloudsShaderDrawable setLevelOfDetail:0.8f];
    if (_atmosphereShaderDrawable)
        [_atmosphereShaderDrawable setLevelOfDetail:0.8f];

    return self;
}

- (void)dealloc
{
    _name.reset();
    DESTROY(_planetDrawable);
    DESTROY(_atmosphereDrawable);
    DESTROY(_cloudsShaderDrawable);
    DESTROY(_atmosphereShaderDrawable);
    DESTROY(_airColor);
    DESTROY(_illuminationColor);

    [[OOGraphicsResetManager sharedManager] unregisterClient:self];

    [super dealloc];
}

- (std::optional<std::string>)cxx_descriptionComponents
{
    return oo::str::format("position: %s radius: %g m", cxx_HPVectorDescription([self position]).c_str(), [self radius]);
}

- (void)setOrientation:(Quaternion)quat
{
    [super setOrientation:quat];
    _rotationAxis = vector_up_from_quaternion(quat);
}

- (double)radius
{
    return collision_radius;
}

- (OOStellarBodyType)planetType
{
    if (_miniature)
        return STELLAR_TYPE_MINIATURE;
    if (_atmosphereDrawable != nil)
        return STELLAR_TYPE_NORMAL_PLANET;
    return STELLAR_TYPE_MOON;
}

- (instancetype)miniatureVersion
{
    return [[[[self class] alloc] initAsMiniatureVersionOfPlanet:self] autorelease];
}

- (void)update:(OOTimeDelta)delta_t
{
    [super update:delta_t];

    if (EXPECT(!_miniature)) {
        BOOL canDrawShaderAtmosphere = _atmosphereShaderDrawable && [UNIVERSE detailLevel] >= DETAIL_LEVEL_SHADERS;
        if (EXPECT_NOT(_atmosphereDrawable && cam_zero_distance < _mesopause2)) {
            OOAssert(_airColor != nil, "Expected a non-nil air colour for normal planet. Exiting.");
            double alt = (sqrt(cam_zero_distance) - collision_radius) / kMesosphere; // the viewpoint altitude
            double trueAlt = (sqrt(zero_distance) - collision_radius) / kMesosphere; // the actual ship altitude
            // if at long distance external view, rotating the camera could potentially end up with it being
            // at negative altitude. Since we know we are already inside the atmosphere at this point, just make sure
            // that altitude is kept to a minimum positive value to avoid sudden black skies
            if (alt <= 0.0)
                alt = 1e-4;
            if (EXPECT_NOT(alt > 0 && alt <= 1.0)) // ensure aleph is clamped between 0 and 1
            {
                double aleph = 1.0 - alt;
                double aleph2 = aleph * aleph;

                // night sky, reddish flash on entering the atmosphere, low light pollution otherwhise
                OOColor* mixColor = [OOColor colorWithRed:(EXPECT_NOT(alt > 0.98) ? 30.0f : 0.1f)
                                                    green:0.1f
                                                     blue:0.1f
                                                    alpha:aleph];

                // occlusion rate: .9 is 18 degrees after the terminus, where twilight ends.
                // 1 is the terminus, 1.033 is 6 degrees before the terminus, where the sky begins to redden
                double rate = ([PLAYER occlusionLevel] - 0.97) / 0.06; // from 0.97 to 1.03

                if (EXPECT(rate <= 1.0 && rate > 0.0)) {
                    mixColor = [mixColor blendedColorWithFraction:rate ofColor:_airColor];
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
                } else {
                    if (PLAYER->isSunlit && _airColor != nil)
                        mixColor = _airColor;
                }
                [UNIVERSE setSkyColorRed:[mixColor redComponent] * aleph2
                                   green:[mixColor greenComponent] * aleph2
                                    blue:[mixColor blueComponent] * aleph
                                   alpha:aleph];
                double atmosphereRadius = canDrawShaderAtmosphere ? collision_radius : collision_radius + (ATMOSPHERE_DEPTH * alt);
                [_atmosphereDrawable setRadius:atmosphereRadius];
                if (_cloudsShaderDrawable)
                    [_cloudsShaderDrawable setRadius:atmosphereRadius];
                if (_atmosphereShaderDrawable)
                    [_atmosphereShaderDrawable setRadius:collision_radius + (ATMOSPHERE_DEPTH * alt)];
                // apply air resistance for the ship, not the camera. Although setSkyColorRed
                // has already set the air resistance to aleph, override it immediately
                [UNIVERSE setAirResistanceFactor:OOClamp_0_1_f(1.0 - trueAlt)];
            }
        } else {
            if (EXPECT_NOT([_atmosphereDrawable radius] < collision_radius + ATMOSPHERE_DEPTH)) {
                [_atmosphereDrawable setRadius:collision_radius + ATMOSPHERE_DEPTH];
                if (_cloudsShaderDrawable)
                    [_cloudsShaderDrawable setRadius:collision_radius * ATMOSPHERE_DEPTH];
                if (_atmosphereShaderDrawable)
                    [_atmosphereShaderDrawable setRadius:collision_radius + ATMOSPHERE_DEPTH];
            }
            if (canDrawShaderAtmosphere && [_atmosphereDrawable radius] != collision_radius) {
                // if shader atmo is in use, force texture atmo radius to just collision_radius for cosmetic purposes
                [_atmosphereDrawable setRadius:collision_radius];
                if (_cloudsShaderDrawable)
                    [_cloudsShaderDrawable setRadius:collision_radius];
            }
            if ([PLAYER findNearestPlanet] == self) // ensure no problems in case of more than one planets
            {
                [UNIVERSE setAirResistanceFactor:0.0f]; // out of atmosphere - no air friction
            }
        }

        double time = [UNIVERSE getTime];

        if (_shuttlesOnGround > 0 && time > _lastLaunchTime + _shuttleLaunchInterval)
            [self launchShuttle];
    }

    quaternion_rotate_about_axis(&orientation, _rotationAxis, _rotationalVelocity * delta_t);
    // atmosphere orientation is relative to the orientation of the planet
    quaternion_rotate_about_axis(&_atmosphereOrientation, kBasisYVector, _atmosphereRotationalVelocity * delta_t);

    [self orientationChanged];

    // FIXME: update atmosphere rotation
}

- (BOOL)isFinishedLoading
{
    OOMaterial* material = [self material];
    if (material != nil && ![material isFinishedLoading])
        return NO;
    material = [self atmosphereMaterial];
    if (material != nil && ![material isFinishedLoading])
        return NO;
    material = [self atmosphereShaderMaterial];
    if (material != nil && ![material isFinishedLoading])
        return NO;
    return YES;
}

- (void)drawImmediate:(bool)immediate translucent:(bool)translucent
{
    BOOL canDrawShaderAtmosphere = _atmosphereShaderDrawable && [UNIVERSE detailLevel] >= DETAIL_LEVEL_SHADERS;

    if ([UNIVERSE breakPatternHide])
        return; // DON'T DRAW
    if (_miniature && ![self isFinishedLoading])
        return; // For responsiveness, don't block to draw as miniature.

    // too far away to be drawn
    if (magnitude(cameraRelativePosition) > [self radius] * 3000) {
        return;
    }
    if (![UNIVERSE viewFrustumIntersectsSphereAt:cameraRelativePosition withRadius:([self radius] + ATMOSPHERE_DEPTH)]) {
        // Don't draw
        return;
    }

    if ([UNIVERSE wireframeGraphics])
        OOGLWireframeModeOn();

    if (!_miniature) {
        [_planetDrawable calculateLevelOfDetailForViewDistance:cam_zero_distance];
        [_atmosphereDrawable setLevelOfDetail:[_planetDrawable levelOfDetail]];
        if (canDrawShaderAtmosphere) {
            if (_cloudsShaderDrawable)
                [_cloudsShaderDrawable setLevelOfDetail:[_planetDrawable levelOfDetail]];
            [_atmosphereShaderDrawable setLevelOfDetail:[_planetDrawable levelOfDetail]];
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
        [_planetDrawable renderOpaqueParts];
        if (_atmosphereDrawable != nil) {
            OOGLPushModelView();
            OOGLMultModelView(OOMatrixForQuaternionRotation(_atmosphereOrientation));
            if (canDrawShaderAtmosphere) {
                if (_cloudsShaderDrawable)
                    [_cloudsShaderDrawable renderTranslucentPartsOnOpaquePass];
                [_atmosphereShaderDrawable renderTranslucentPartsOnOpaquePass];
            } else {
                [_atmosphereDrawable renderTranslucentPartsOnOpaquePass];
            }
            OOGLPopModelView();
        }
    }
#if OOLITE_HAVE_FIXED_THE_ABOVE_DESCRIBED_BUG_WHICH_WE_HAVENT
    else
    {
        /* At close range we can do this properly and draw the
         * atmosphere on the transparent pass */
        if (translucent) {
            if (_atmosphereDrawable != nil) {
                OOGLPushModelView();
                OOGLMultModelView(OOMatrixForQuaternionRotation(_atmosphereOrientation));
                [_atmosphereDrawable renderTranslucentParts];
                if (canDrawShaderAtmosphere)
                    [_atmosphereShaderDrawable renderTranslucentParts];
                OOGLPopModelView();
            }
        } else {
            [_planetDrawable renderOpaqueParts];
        }
    }
#endif

    if ([UNIVERSE wireframeGraphics])
        OOGLWireframeModeOff();
}

- (BOOL)checkCloseCollisionWith:(Entity*)other
{
    if (!other)
        return NO;
    if (other->isShip) {
        ShipEntity* ship = (ShipEntity*)other;
        if ([ship behaviour] == BEHAVIOUR_LAND_ON_PLANET) {
            return NO;
        }
    }

    return YES;
}

- (BOOL)planetHasStation
{
    // find the nearest station...
    ShipEntity* station = nil;
    station = [UNIVERSE nearestShipMatchingPredicate:IsStationPredicate
                                           parameter:nil
                                    relativeToEntity:self];

    if (station && HPdistance([station position], position) < 4 * collision_radius) // there is a station in range.
    {
        return YES;
    }
    return NO;
}

- (void)launchShuttle
{
    if (_shuttlesOnGround == 0) {
        return;
    }
    if ([PLAYER status] == STATUS_START_GAME) {
        // don't launch if game not started
        return;
    }
    if (self != [UNIVERSE planet] && ![self planetHasStation]) {
        // don't launch shuttles when no station is nearby.
        _shuttlesOnGround = 0;
        return;
    }

    Quaternion q1;
    quaternion_set_random(&q1);
    float start_distance = collision_radius + 125.0f;
    HPVector launch_pos = HPvector_add(position, vectorToHPVector(vector_multiply_scalar(vector_forward_from_quaternion(q1), start_distance)));

    ShipEntity* shuttle_ship = [UNIVERSE cxx_newShipWithRole:"shuttle"]; // retain count = 1
    if (shuttle_ship) {
        if ([shuttle_ship cxx_crew].value_or(std::vector<oo::ObjCRef<OOCharacter*>>()).empty()) {
            [shuttle_ship cxx_setSingleCrewWithRole:"trader"];
        }

        [shuttle_ship setPosition:launch_pos];
        [shuttle_ship setOrientation:q1];

        [shuttle_ship setScanClass:CLASS_NEUTRAL];
        [shuttle_ship setCargoFlag:CARGO_FLAG_FULL_PLENTIFUL];
        [shuttle_ship switchAITo:"oolite-shuttleAI.js"];
        [UNIVERSE addEntity:shuttle_ship]; // STATUS_IN_FLIGHT, AI state GLOBAL
        _shuttlesOnGround--;
        _lastLaunchTime = [UNIVERSE getTime];

        [shuttle_ship release];
    }
}

- (void)welcomeShuttle:(ShipEntity*)shuttle
{
    _shuttlesOnGround++;
}

- (BOOL)isPlanet
{
    return YES;
}

- (BOOL)isVisible
{
    return YES;
}

- (double)rotationalVelocity
{
    return _rotationalVelocity;
}

- (void)setRotationalVelocity:(double)v
{
    if ([self hasAtmosphere]) {
        // FIXME: change atmosphere rotation speed proportionally
    }
    _rotationalVelocity = v;
}

// this method is visible to shader bindings, hence it returns vector
- (Vector)airColorAsVector
{
    float r, g, b, a;
    [_airColor getRed:&r green:&g blue:&b alpha:&a];
    return make_vector(r, g, b); // don't care about a
}

- (OOColor*)airColor
{
    return _airColor;
}

- (void)setAirColor:(OOColor*)newColor
{
    if (newColor) {
        [_airColor release];
        _airColor = [newColor retain];
    }
}

// this method is visible to shader bindings, hence it returns vector
- (Vector)illuminationColorAsVector
{
    float r, g, b, a;
    [_illuminationColor getRed:&r green:&g blue:&b alpha:&a];
    return make_vector(r, g, b); // don't care about a
}

- (OOColor*)illuminationColor
{
    return _illuminationColor;
}

- (void)setIlluminationColor:(OOColor*)newColor
{
    if (newColor) {
        [_illuminationColor release];
        _illuminationColor = [newColor retain];
    }
}

// visible to shader bindings
- (float)airColorMixRatio
{
    return _airColorMixRatio;
}

- (void)setAirColorMixRatio:(float)newRatio
{
    _airColorMixRatio = OOClamp_0_1_f(newRatio);
}

// visible to shader bindings
- (float)airDensity
{
    return _airDensity;
}

- (void)setAirDensity:(float)newDensity
{
    _airDensity = OOClamp_0_1_f(newDensity);
}

- (void)setTerminatorThresholdVector:(Vector)newTerminatorThresholdVector
{
    _terminatorThresholdVector.x = newTerminatorThresholdVector.x;
    _terminatorThresholdVector.y = newTerminatorThresholdVector.y;
    _terminatorThresholdVector.z = newTerminatorThresholdVector.z;
}

- (Vector)terminatorThresholdVector
{
    return _terminatorThresholdVector;
}

- (BOOL)hasAtmosphere
{
    return _atmosphereDrawable != nil;
}

// FIXME: need material model.
- (std::optional<std::string>)textureFileName
{
    return [_planetDrawable textureName];
}

- (void)resetGraphicsState
{
    // reset the texture if graphics mode changes
    [self setUpPlanetFromTexture:_textureName];
}

- (void)setTextureFileName:(const std::optional<std::string>&)textureFileName
{
    BOOL isMoon = _atmosphereDrawable == nil;

    std::optional<std::string> textureName = textureFileName;
    OOTexture* diffuseMap = nil;
    OOTexture* normalMap = nil;
    oo::PList macros; // null: nil
    const oo::PList materialDefaults = [ResourceManager cxx_materialDefaults];

#if OO_SHADERS
    OOGraphicsDetail detailLevel = [UNIVERSE detailLevel];
    BOOL shadersOn = detailLevel >= DETAIL_LEVEL_SHADERS;
#else
    const BOOL shadersOn = NO;
#endif

    if (textureName.has_value()) {
        diffuseMap = [OOTexture cxx_textureWithConfiguration:CubeMapTextureSpec(*textureName)];
        if (diffuseMap == nil)
            return; // OOTexture will have logged a file-not-found warning.
        if (shadersOn) {
            [diffuseMap ensureFinishedLoading]; // only know if it is a cube map if it's loaded
            if ([diffuseMap isCubeMap]) {
                macros = DictionaryForKey(materialDefaults, isMoon ? "moon-customized-cubemap-macros" : "planet-customized-cubemap-macros");
            } else {
                macros = DictionaryForKey(materialDefaults, isMoon ? "moon-customized-macros" : "planet-customized-macros");
            }
        } else
            textureName = "dynamic";

        // let's try giving some love to normalMap too
        if (_normSpecMapName.has_value()) {
            normalMap = [OOTexture cxx_textureWithConfiguration:CubeMapTextureSpec(*_normSpecMapName)];
            if (normalMap != nil) // OOTexture will have logged a file-not-found warning.
            {
                if (shadersOn) {
                    [normalMap ensureFinishedLoading]; // only know if it is a cube map if it's loaded
                    if ([normalMap isCubeMap]) {
                        macros = DictionaryForKey(materialDefaults, isMoon ? "moon-customized-cubemap-normspec-macros" : "planet-customized-cubemap-normspec-macros");
                    } else {
                        macros = DictionaryForKey(materialDefaults, isMoon ? "moon-customized-normspec-macros" : "planet-customized-normspec-macros");
                    }
                }
            }
        }
    } else {
        [OOPlanetTextureGenerator generatePlanetTexture:&diffuseMap
                                       secondaryTexture:(detailLevel >= DETAIL_LEVEL_SHADERS) ? &normalMap : NULL
                                               withInfo:_materialParameters
                                                   seed:_noiseMapSeed];

        if (shadersOn) {
            macros = DictionaryForKey(materialDefaults, isMoon ? "moon-dynamic-macros" : "planet-dynamic-macros");
        }
        textureName = "dynamic";
    }

    /* Generate atmosphere texture */
    if (!isMoon) {
        OO_LOG("texture.planet.generate", "Preparing atmosphere for planet {}", oo::DescriptionOf(self));
        /* Generate a standalone atmosphere texture */
        OOTexture* atmosphere = nil;
        [OOStandaloneAtmosphereGenerator generateAtmosphereTexture:&atmosphere
                                                          withInfo:_materialParameters
                                                              seed:_noiseMapSeed];

        OO_LOG("texture.planet.generate", "Planet {} has atmosphere {}", oo::DescriptionOf(self), oo::DescriptionOf(atmosphere));

        OOSingleTextureMaterial* dynamicMaterial = [[OOSingleTextureMaterial alloc] initWithName:"dynamic" texture:atmosphere configuration:oo::PList()];
        [_atmosphereDrawable setMaterial:dynamicMaterial];

        if (shadersOn) {
            const oo::PList aConfig = MaterialConfigWithTextures(DictionaryForKey(materialDefaults, "atmosphere-material"), { diffuseMap, normalMap });

            const oo::PList amacros = DictionaryForKey(materialDefaults, "atmosphere-dynamic-macros");

            OOMaterial* dynamicShaderMaterial = [OOShaderMaterial shaderMaterialWithName:"dynamic"
                                                                           configuration:aConfig
                                                                                  macros:amacros
                                                                           bindingTarget:self];

            if (dynamicShaderMaterial == nil) {
                DESTROY(_atmosphereShaderDrawable);
            } else {
                [_atmosphereShaderDrawable setMaterial:dynamicShaderMaterial];
            }

            const oo::PList cloudConfig = MaterialConfigWithTextures(DictionaryForKey(materialDefaults, "clouds-dynamic-material"), { atmosphere });
            const oo::PList cloudMacros = DictionaryForKey(materialDefaults, "clouds-dynamic-macros");

            OOMaterial* cloudsMaterial = [OOShaderMaterial shaderMaterialWithName:"dynamic"
                                                                    configuration:cloudConfig
                                                                           macros:cloudMacros
                                                                    bindingTarget:self];
            if (cloudsMaterial == nil) {
                DESTROY(_cloudsShaderDrawable);
            } else {
                [_cloudsShaderDrawable setMaterial:cloudsMaterial];
            }
        }

        [dynamicMaterial release];
    }

    OOMaterial* material = nil;

#if OO_SHADERS
    if (shadersOn) {
        const oo::PList config = MaterialConfigWithTextures(DictionaryForKey(materialDefaults, "planet-material"), { diffuseMap, normalMap });

        material = [OOShaderMaterial shaderMaterialWithName:textureName
                                              configuration:config
                                                     macros:macros
                                              bindingTarget:self];
    }
#endif
    if (material == nil) {
        material = [[OOSingleTextureMaterial alloc] initWithName:textureName texture:diffuseMap configuration:oo::PList()];
        [material autorelease];
    }
    [_planetDrawable setMaterial:material];
}

- (BOOL)setUpPlanetFromTexture:(const std::optional<std::string>&)textureName
{
    [self setTextureFileName:textureName];
    return YES;
}

- (OOMaterial*)material
{
    return [_planetDrawable material];
}

- (OOMaterial*)atmosphereMaterial
{
    return [_atmosphereDrawable material];
}

- (OOMaterial*)atmosphereShaderMaterial
{
    if (!_atmosphereShaderDrawable)
        return nil;
    return [_atmosphereShaderDrawable material];
}

- (std::optional<std::string>)cxx_name
{
    return _name;
}

- (void)cxx_setName:(const std::optional<std::string>&)name
{
    _name = name;
}

@end

#endif // NEW_PLANETS
