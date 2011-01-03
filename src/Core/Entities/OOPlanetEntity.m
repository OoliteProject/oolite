/*

OOPlanetEntity.m

Oolite
Copyright (C) 2004-2011 Giles C Williams and contributors

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

#if NEW_PLANETS

#define NEW_ATMOSPHERE 0

#import "OOPlanetDrawable.h"

#import "AI.h"
#import "Universe.h"
#import "ShipEntity.h"
#import "ShipEntityAI.h"
#import "OOCharacter.h"

#import "OOMaths.h"
#import "ResourceManager.h"
#import "OOStringParsing.h"
#import "OOCollectionExtractors.h"

#import "OOPlanetTextureGenerator.h"
#import "OOSingleTextureMaterial.h"
#import "OOShaderMaterial.h"


@interface OOPlanetEntity (Private)

- (void) setUpLandParametersWithSourceInfo:(NSDictionary *)sourceInfo targetInfo:(NSMutableDictionary *)targetInfo;
- (void) setUpAtmosphereParametersWithSourceInfo:(NSDictionary *)sourceInfo targetInfo:(NSMutableDictionary *)targetInfo;
- (void) setUpColorParametersWithSourceInfo:(NSDictionary *)sourceInfo targetInfo:(NSMutableDictionary *)targetInfo isAtmosphere:(BOOL)isAtmosphere;

@end


@implementation OOPlanetEntity

// this is exclusively called to initialise the main planet.
- (id) initAsMainPlanetForSystemSeed:(Random_Seed)seed
{
	NSMutableDictionary *planetInfo = [[UNIVERSE generateSystemData:seed] mutableCopy];
	[planetInfo autorelease];
	
	[planetInfo oo_setBool:YES forKey:@"mainForLocalSystem"];
	return [self initFromDictionary:planetInfo withAtmosphere:YES andSeed:seed];
}


- (id) initFromDictionary:(NSDictionary *)dict withAtmosphere:(BOOL)atmosphere andSeed:(Random_Seed)seed
{
	if (dict == nil)  dict = [NSDictionary dictionary];
	RANROTSeed savedRanrotSeed = RANROTGetFullSeed();
	
	self = [self init];
	if (self == nil)  return nil;
	
	scanClass = CLASS_NO_DRAW;
	
	// Load random seed override.
	NSString *seedStr = [dict oo_stringForKey:@"seed"];
	if (seedStr != nil)
	{
		Random_Seed overrideSeed = RandomSeedFromString(seedStr);
		if (!is_nil_seed(overrideSeed))  seed = overrideSeed;
		else  OOLogERR(@"planet.fromDict", @"could not interpret \"%@\" as planet seed, using default.", seedStr);
	}
	
	// Generate various planet info.
	seed_for_planet_description(seed);
	NSMutableDictionary *planetInfo = [[UNIVERSE generateSystemData:seed] mutableCopy];
	[planetInfo autorelease];
	
	int radius_km = [dict oo_intForKey:KEY_RADIUS defaultValue:[planetInfo oo_intForKey:KEY_RADIUS]];
	OOTechLevelID techLevel = [dict oo_intForKey:KEY_TECHLEVEL defaultValue:[planetInfo oo_intForKey:KEY_TECHLEVEL]];
	
	if (techLevel > 14)  techLevel = 14;
	_shuttlesOnGround = 1 + techLevel / 2;
	_shuttleLaunchInterval = 3600.0 / (double)_shuttlesOnGround;	// All are launched in one hour.
	_lastLaunchTime = 30.0 - _shuttleLaunchInterval;				// debug - launch 30s after player enters universe	 FIXME: is 0 the correct non-debug value?
	
	int percent_land = [planetInfo oo_intForKey:@"percent_land" defaultValue:24 + (gen_rnd_number() % 48)];
	[planetInfo setObject:[NSNumber numberWithFloat:0.01 * percent_land] forKey:@"land_fraction"];
	
	RNG_Seed savedRndSeed = currentRandomSeed();
	
	_planetDrawable = [[OOPlanetDrawable alloc] init];
	
	// Load material parameters, including atmosphere.
	RANROTSeed planetNoiseSeed = RANROTGetFullSeed();
	[planetInfo setObject:[NSValue valueWithBytes:&planetNoiseSeed objCType:@encode(RANROTSeed)] forKey:@"noise_map_seed"];
	[self setUpLandParametersWithSourceInfo:dict targetInfo:planetInfo];
	
#if NEW_ATMOSPHERE
	if (atmosphere)
	{
		_atmosphereDrawable = [[OOPlanetDrawable atmosphereWithRadius:collision_radius + ATMOSPHERE_DEPTH] retain];
		
		// convert the atmosphere settings to generic 'material parameters'
		percent_land = 100 - [dict oo_intForKey:@"percent_cloud" defaultValue:100 - (3 + (gen_rnd_number() & 31)+(gen_rnd_number() & 31))];
		[planetInfo setObject:[NSNumber numberWithFloat:0.01 * percent_land] forKey:@"cloud_fraction"];
		[self setUpAtmosphereParametersWithSourceInfo:dict targetInfo:planetInfo];
		
		_materialParameters = [planetInfo dictionaryWithValuesForKeys:[NSArray arrayWithObjects:@"cloud_fraction", @"air_color", @"polar_air_color", @"cloud_color", @"polar_cloud_color", @"cloud_alpha",
																								@"land_fraction", @"land_color", @"sea_color", @"polar_land_color", @"polar_sea_color", @"noise_map_seed", @"economy", nil]];
	}
	else
#else
	// differentiate between normal planets and moons.
	if (atmosphere)
	{
		_atmosphereDrawable = [[OOPlanetDrawable atmosphereWithRadius:collision_radius + ATMOSPHERE_DEPTH] retain];
	}
#endif
	
	_materialParameters = [planetInfo dictionaryWithValuesForKeys:[NSArray arrayWithObjects:@"land_fraction", @"land_color", @"sea_color", @"polar_land_color", @"polar_sea_color", @"noise_map_seed", @"economy", nil]];
	[_materialParameters retain];
	
	NSString *textureName = [dict oo_stringForKey:@"texture"];
	[self setUpPlanetFromTexture:textureName];
	
	collision_radius = radius_km * 10.0;	// Scale down by a factor of 100
	_rotationAxis = kBasisYVector;
	orientation = (Quaternion){ M_SQRT1_2, M_SQRT1_2, 0, 0 };	// do we want to do something more interesting here?
										// EW: NO, setting orientation should be handled by the code that adds the planet, not by planetEntity itself.
										// just start with a default value.
	[_planetDrawable setRadius:collision_radius];
	
	// set speed of rotation.
	if ([dict objectForKey:@"rotational_velocity"])
	{
		_rotationalVelocity = [dict oo_floatForKey:@"rotational_velocity" defaultValue:0.01f * randf()];	// 0.0 .. 0.01 avr 0.005
	}
	else
	{
		_rotationalVelocity = [planetInfo oo_floatForKey:@"rotation_speed" defaultValue:0.005 * randf()]; // 0.0 .. 0.005 avr 0.0025
		_rotationalVelocity *= [planetInfo oo_floatForKey:@"rotation_speed_factor" defaultValue:1.0f];
	}
	
	// set energy
	energy = collision_radius * 1000.0;
	
	setRandomSeed(savedRndSeed);
	RANROTSetFullSeed(savedRanrotSeed);
	
	[self setStatus:STATUS_ACTIVE];
	
	return self;
}


static Vector RandomHSBColor(void)
{
	return (Vector)
	{
		gen_rnd_number() / 256.0,
		gen_rnd_number() / 256.0,
		0.5 + gen_rnd_number() / 512.0
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


static Vector HSBColorWithColor(OOColor *color)
{
	OOHSBAComponents c = [color hsbaComponents];
	return (Vector){ c.h, c.s, c.b };
}


static OOColor *ColorWithHSBColor(Vector c)
{
	return [OOColor colorWithCalibratedHue:c.x saturation:c.y brightness:c.z alpha:1.0];
}


- (void) setUpLandParametersWithSourceInfo:(NSDictionary *)sourceInfo targetInfo:(NSMutableDictionary *)targetInfo
{
	[self setUpColorParametersWithSourceInfo:sourceInfo targetInfo:targetInfo isAtmosphere:NO];
}


- (void) setUpAtmosphereParametersWithSourceInfo:(NSDictionary *)sourceInfo targetInfo:(NSMutableDictionary *)targetInfo
{
	[self setUpColorParametersWithSourceInfo:sourceInfo targetInfo:targetInfo isAtmosphere:YES];
}


- (void) setUpColorParametersWithSourceInfo:(NSDictionary *)sourceInfo targetInfo:(NSMutableDictionary *)targetInfo isAtmosphere:(BOOL)isAtmosphere
{
	// Stir the PRNG fourteen times for backwards compatibility.
	unsigned i;
	for (i = 0; i < 14; i++)
	{
		gen_rnd_number();
	}
	
//	float polarColorFactor = [sourceInfo oo_floatForKey:@"polar_color_factor" defaultValue:0.5];
	
	Vector	landHSB, seaHSB, landPolarHSB, seaPolarHSB;
	OOColor	*color;
	
	landHSB = RandomHSBColor();
	do
	{
		seaHSB = RandomHSBColor();
	}
	while (dot_product(landHSB, seaHSB) > .80); // make sure land and sea colors differ significantly
	
	if (!isAtmosphere)
	{
		// possibly get landHSB and seaHSB from planetinfo.plist entry
		ScanVectorFromString([sourceInfo oo_stringForKey:@"land_hsb_color"], &landHSB);
		ScanVectorFromString([sourceInfo oo_stringForKey:@"sea_hsb_color"], &seaHSB);
		
		// polar areas are brighter but have less colour (closer to white)
		landPolarHSB = LighterHSBColor(landHSB);
		seaPolarHSB = LighterHSBColor(seaHSB);
		
		// TODO: use all dictionary overrides
		[targetInfo setObject:ColorWithHSBColor(landHSB) forKey:@"land_color"];
		[targetInfo setObject:ColorWithHSBColor(seaHSB) forKey:@"sea_color"];
		[targetInfo setObject:ColorWithHSBColor(landPolarHSB) forKey:@"polar_land_color"];
		[targetInfo setObject:ColorWithHSBColor(seaPolarHSB) forKey:@"polar_sea_color"];
	}
	else
	{
		float cloudAlpha = OOClamp_0_1_f([sourceInfo oo_floatForKey:@"cloud_alpha" defaultValue:1.0f]);
		[targetInfo setObject:[NSNumber numberWithFloat:cloudAlpha] forKey:@"cloud_alpha"];
		
		color = [OOColor colorWithDescription:[sourceInfo objectForKey:@"cloud_color"]];
		if (color != nil) landHSB = HSBColorWithColor(color);
		color = [OOColor colorWithDescription:[sourceInfo objectForKey:@"clear_sky_color"]];
		if (color != nil) seaHSB = HSBColorWithColor(color);

		// polar areas are brighter but have less colour (closer to white)
		landPolarHSB = LighterHSBColor(landHSB);
		seaPolarHSB = LighterHSBColor(seaHSB);
		
		color = [OOColor colorWithDescription:[sourceInfo objectForKey:@"polar_cloud_color"]];
		if (color != nil) landPolarHSB = HSBColorWithColor(color);
		color = [OOColor colorWithDescription:[sourceInfo objectForKey:@"polar_clear_sky_color"]];
		if (color != nil) seaPolarHSB = HSBColorWithColor(color);
		
		[targetInfo setObject:ColorWithHSBColor(landHSB) forKey:@"air_color"];
		[targetInfo setObject:ColorWithHSBColor(seaHSB) forKey:@"cloud_color"];
		[targetInfo setObject:ColorWithHSBColor(landPolarHSB) forKey:@"polar_air_color"];
		[targetInfo setObject:ColorWithHSBColor(seaPolarHSB) forKey:@"polar_cloud_color"];
	}
}


- (id) initAsMiniatureVersionOfPlanet:(OOPlanetEntity *)planet
{
	// Nasty, nasty. I'd really prefer to have a separate entity class for this.
	if (planet == nil)
	{
		[self release];
		return nil;
	}
	
	self = [self init];
	if (self == nil)  return nil;
	
	scanClass = CLASS_NO_DRAW;
	[self setStatus:STATUS_COCKPIT_DISPLAY];
	
	collision_radius = planet->collision_radius * PLANET_MINIATURE_FACTOR;
	orientation = planet->orientation;
	_rotationAxis = planet->_rotationAxis;
	_rotationalVelocity = 0.04;
	
	_miniature = YES;
	
	_planetDrawable = [planet->_planetDrawable copy];
	[_planetDrawable setRadius:collision_radius];
	
	// FIXME: in old planet code, atmosphere (if textured) is set to 0.6 alpha.
	_atmosphereDrawable = [planet->_atmosphereDrawable copy];
	[_atmosphereDrawable setRadius:collision_radius + ATMOSPHERE_DEPTH * PLANET_MINIATURE_FACTOR * 2.0]; //not to scale: invisible otherwise
	
	[_planetDrawable setLevelOfDetail:0.8f];
	[_atmosphereDrawable setLevelOfDetail:0.8f];
	
	return self;
}


- (void) dealloc
{
	DESTROY(_planetDrawable);
	DESTROY(_atmosphereDrawable);
	DESTROY(_materialParameters);
	
	[super dealloc];
}


- (NSString*) descriptionComponents
{
	return [NSString stringWithFormat:@"position: %@ radius: %g m", VectorDescription([self position]), [self radius]];
}


- (void) setOrientation:(Quaternion) quat
{
	[super setOrientation: quat];
	_rotationAxis = vector_up_from_quaternion(quat);
}


- (double) radius
{
	return collision_radius;
}


- (OOStellarBodyType) planetType
{
	if (_miniature)  return STELLAR_TYPE_MINIATURE;
	if (_atmosphereDrawable != nil)  return STELLAR_TYPE_NORMAL_PLANET;
	return STELLAR_TYPE_MOON;
}


- (id) miniatureVersion
{
	return [[[[self class] alloc] initAsMiniatureVersionOfPlanet:self] autorelease];
}


- (void) update:(OOTimeDelta) delta_t
{
	[super update:delta_t];
	
	if (!_miniature)
	{
		double time = [UNIVERSE getTime];
		
		if (_shuttlesOnGround > 0 && time > _lastLaunchTime + _shuttleLaunchInterval)  [self launchShuttle];
		
		// FIXME: update atmosphere
	}
	
	quaternion_rotate_about_axis(&orientation, _rotationAxis, _rotationalVelocity * delta_t);

	[self orientationChanged];
	
	// FIXME: update atmosphere
}


- (void) drawEntity:(BOOL)immediate :(BOOL)translucent
{
	if (translucent || [UNIVERSE breakPatternHide])   return; // DON'T DRAW
	
	if ([UNIVERSE wireframeGraphics])  GLDebugWireframeModeOn();
	
	if (!_miniature)
	{
		[_planetDrawable calculateLevelOfDetailForViewDistance:zero_distance];
		[_atmosphereDrawable setLevelOfDetail:[_planetDrawable levelOfDetail]];
	}
	
	[_planetDrawable renderOpaqueParts];
#if NEW_ATMOSPHERE
	if (_atmosphereDrawable != nil)
	{
		[_atmosphereDrawable renderOpaqueParts];
	}
#endif
	
	if ([UNIVERSE wireframeGraphics])  GLDebugWireframeModeOff();
}


- (void) launchShuttle
{
	if (_shuttlesOnGround == 0)  return;
	
	Quaternion  q1;
	quaternion_set_random(&q1);
	float start_distance = collision_radius + 125.0f;
	Vector launch_pos = vector_add(position, vector_multiply_scalar(vector_forward_from_quaternion(q1), start_distance));
	
	ShipEntity *shuttle_ship = [UNIVERSE newShipWithRole:@"shuttle"];   // retain count = 1
	if (shuttle_ship)
	{
		if ([[shuttle_ship crew] count] == 0)
		{
			[shuttle_ship setCrew:[NSArray arrayWithObject:
								   [OOCharacter randomCharacterWithRole: @"trader"
													  andOriginalSystem: [UNIVERSE systemSeed]]]];
		}
		
		[shuttle_ship setPosition:launch_pos];
		[shuttle_ship setOrientation:q1];
		
		[shuttle_ship setScanClass: CLASS_NEUTRAL];
		[shuttle_ship setCargoFlag:CARGO_FLAG_FULL_PLENTIFUL];
		[shuttle_ship switchAITo:@"risingShuttleAI.plist"];
		[UNIVERSE addEntity:shuttle_ship];	// STATUS_IN_FLIGHT, AI state GLOBAL
		_shuttlesOnGround--;
		_lastLaunchTime = [UNIVERSE getTime];
		
		[shuttle_ship release];
	}
}


- (void) welcomeShuttle:(ShipEntity *)shuttle
{
	_shuttlesOnGround++;
}


- (BOOL) isPlanet
{
	return YES;
}

- (BOOL) hasAtmosphere
{
	return _atmosphereDrawable != nil;
}


// FIXME: need material model.
- (NSString *) textureFileName
{
	return [_planetDrawable textureName];
}


- (void) setTextureFileName:(NSString *)textureName
{
	BOOL isMoon = _atmosphereDrawable == nil;
	
	OOTexture *diffuseMap = nil;
	OOTexture *normalMap = nil;
	NSDictionary *macros = nil;
	NSDictionary *materialDefaults = [ResourceManager materialDefaults];
	
#if OO_SHADERS
	OOShaderSetting shaderLevel = [UNIVERSE shaderEffectsLevel];
	BOOL shadersOn = shaderLevel > SHADERS_OFF;
#else
	const BOOL shadersOn = NO;
#endif
	
	if (textureName != nil)
	{
		NSDictionary *spec = [NSDictionary dictionaryWithObjectsAndKeys:textureName, @"name", @"yes", @"repeat_s", @"linear", @"min_filter", nil];
		diffuseMap = [OOTexture textureWithConfiguration:spec];
		if (diffuseMap == nil)  return;		// OOTexture will have logged a file-not-found warning.
		if (shadersOn)  macros = [materialDefaults oo_dictionaryForKey:isMoon ? @"moon-customized-macros" : @"planet-customized-macros"];
	}
	else
	{
		if (isMoon)
		{
			[OOPlanetTextureGenerator generatePlanetTexture:&diffuseMap
										   secondaryTexture:(shaderLevel == SHADERS_FULL) ? &normalMap : NULL
												   withInfo:_materialParameters];
		}
		else
		{
			OOTexture *atmosphere = nil;
			[OOPlanetTextureGenerator generatePlanetTexture:&diffuseMap
										   secondaryTexture:(shaderLevel == SHADERS_FULL) ? &normalMap : NULL
											  andAtmosphere:&atmosphere
												   withInfo:_materialParameters];
			
			OOSingleTextureMaterial *dynamicMaterial = [[OOSingleTextureMaterial alloc] initWithName:@"dynamic" texture:atmosphere configuration:nil];
			[_atmosphereDrawable setMaterial:dynamicMaterial];
			[dynamicMaterial release];
		}
		if (shadersOn)  macros = [materialDefaults oo_dictionaryForKey:isMoon ? @"moon-dynamic-macros" : @"planet-dynamic-macros"];
		textureName = @"dynamic";
	}
	OOMaterial *material = nil;
	
#if OO_SHADERS

	if (shadersOn)
	{
		NSMutableDictionary *config = [[[materialDefaults oo_dictionaryForKey:@"planet-material"] mutableCopy] autorelease];
		[config setObject:[NSArray arrayWithObjects:diffuseMap, normalMap, nil] forKey:@"_oo_texture_objects"];
		material = [OOShaderMaterial shaderMaterialWithName:textureName
											  configuration:config
													 macros:macros
											  bindingTarget:self];
	}
#endif
	if (material == nil)
	{
		material = [[OOSingleTextureMaterial alloc] initWithName:textureName texture:diffuseMap configuration:nil];
		[material autorelease];
	}
	[_planetDrawable setMaterial:material];
}


- (BOOL) setUpPlanetFromTexture:(NSString *)textureName
{
	[self setTextureFileName:textureName];
	return YES;
}


- (OOMaterial *) material
{
	return [_planetDrawable material];
}


- (OOMaterial *) atmosphereMaterial
{
	return [_atmosphereDrawable material];
}

@end

#endif	// NEW_PLANETS
