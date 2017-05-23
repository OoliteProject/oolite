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

#if NEW_PLANETS

#define NEW_ATMOSPHERE 1

#import "OOPlanetDrawable.h"

#import "AI.h"
#import "Universe.h"
#import "ShipEntity.h"
#import "PlayerEntity.h"
#import "ShipEntityAI.h"
#import "OOCharacter.h"

#import "OOMaths.h"
#import "ResourceManager.h"
#import "OOStringParsing.h"
#import "OOCollectionExtractors.h"
#import "OOSystemDescriptionManager.h"

#import "OOPlanetTextureGenerator.h"
#import "OOStandaloneAtmosphereGenerator.h"
#import "OOSingleTextureMaterial.h"
#import "OOShaderMaterial.h"
#import "OOEntityFilterPredicate.h"
#import "OOGraphicsResetManager.h"
#import "OOStringExpander.h"
#import "OOOpenGLMatrixManager.h"

@interface OOPlanetEntity (Private) <OOGraphicsResetClient>

- (void) setUpTerrainParametersWithSourceInfo:(NSDictionary *)sourceInfo targetInfo:(NSMutableDictionary *)targetInfo;
- (void) setUpLandParametersWithSourceInfo:(NSDictionary *)sourceInfo targetInfo:(NSMutableDictionary *)targetInfo;
- (void) setUpAtmosphereParametersWithSourceInfo:(NSDictionary *)sourceInfo targetInfo:(NSMutableDictionary *)targetInfo;
- (void) setUpColorParametersWithSourceInfo:(NSDictionary *)sourceInfo targetInfo:(NSMutableDictionary *)targetInfo isAtmosphere:(BOOL)isAtmosphere;
- (void) setUpTypeParametersWithSourceInfo:(NSDictionary *)sourceInfo targetInfo:(NSMutableDictionary *)targetInfo;

@end


@implementation OOPlanetEntity

// this is exclusively called to initialise the main planet.
- (id) initAsMainPlanetForSystem:(OOSystemID)s
{
	NSMutableDictionary *planetInfo = [[UNIVERSE generateSystemData:s] mutableCopy];
	[planetInfo autorelease];
	
	[planetInfo oo_setBool:YES forKey:@"mainForLocalSystem"];
	if (s != [PLAYER systemID])
	{
		[planetInfo oo_setBool:YES forKey:@"isMiniature"];
	}
	return [self initFromDictionary:planetInfo withAtmosphere:[planetInfo oo_boolForKey:@"has_atmosphere" defaultValue:YES] andSeed:[[UNIVERSE systemManager] getRandomSeedForSystem:s inGalaxy:[PLAYER galaxyNumber]] forSystem:s];
}


static const double kMesosphere = 10.0 * ATMOSPHERE_DEPTH;	// atmosphere effect starts at 10x the height of the clouds


- (id) initFromDictionary:(NSDictionary *)dict withAtmosphere:(BOOL)atmosphere andSeed:(Random_Seed)seed forSystem:(OOSystemID)systemID
{
	if (dict == nil)  dict = [NSDictionary dictionary];
	RANROTSeed savedRanrotSeed = RANROTGetFullSeed();
	
	self = [self init];
	if (self == nil)  return nil;
	
	scanClass = CLASS_NO_DRAW;
	
	NSMutableDictionary *planetInfo = [[UNIVERSE generateSystemData:systemID] mutableCopy];
	[planetInfo autorelease];

	[self setUpTypeParametersWithSourceInfo:dict targetInfo:planetInfo];

	[self setUpTerrainParametersWithSourceInfo:dict targetInfo:planetInfo];


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

	_name = nil;
	[self setName:OOExpand([dict oo_stringForKey:KEY_PLANETNAME defaultValue:[planetInfo oo_stringForKey:KEY_PLANETNAME defaultValue:@"%H"]])];
	
	int radius_km = [dict oo_intForKey:KEY_RADIUS defaultValue:[planetInfo oo_intForKey:KEY_RADIUS]];
	collision_radius = radius_km * 10.0;	// Scale down by a factor of 100
	OOTechLevelID techLevel = [dict oo_intForKey:KEY_TECHLEVEL defaultValue:[planetInfo oo_intForKey:KEY_TECHLEVEL]];
	
	if (techLevel > 14)  techLevel = 14;
	_shuttlesOnGround = 1 + techLevel / 2;
	_shuttleLaunchInterval = 3600.0 / (double)_shuttlesOnGround;	// All are launched in one hour.
	_lastLaunchTime = [UNIVERSE getTime] + 30.0 - _shuttleLaunchInterval;	// launch 30s after player enters universe.
																			// make delay > 0 to allow scripts adding a station nearby.
	
	int percent_land = [planetInfo oo_intForKey:@"percent_land" defaultValue:24 + (gen_rnd_number() % 48)];
	[planetInfo setObject:[NSNumber numberWithFloat:0.01 * percent_land] forKey:@"land_fraction"];

	int percent_ice = [planetInfo oo_intForKey:@"percent_ice" defaultValue:5];
	[planetInfo setObject:[NSNumber numberWithFloat:0.01 * percent_ice] forKey:@"polar_fraction"];

	
	RNG_Seed savedRndSeed = currentRandomSeed();
	
	_planetDrawable = [[OOPlanetDrawable alloc] init];
	
	// Load material parameters, including atmosphere.
	RANROTSeed planetNoiseSeed = RANROTGetFullSeed();
	[planetInfo setObject:[NSValue valueWithBytes:&planetNoiseSeed objCType:@encode(RANROTSeed)] forKey:@"noise_map_seed"];
	[self setUpLandParametersWithSourceInfo:dict targetInfo:planetInfo];
	
	_airColor = nil;	// default to no air
	
#if NEW_ATMOSPHERE
	if (atmosphere)
	{
		// shader atmosphere always has a radius of collision_radius + ATMOSPHERE_DEPTH. For texture atmosphere, we need to check
		// if a shader atmosphere is also used. If yes, set its radius to just cover the planet so that it doesn't conflict with 
		// the shader atmosphere at the planet edges. If no shader atmosphere is used, then set it to the standard radius
		double atmosphereRadius = [UNIVERSE detailLevel] >= DETAIL_LEVEL_EXTRAS ? collision_radius : collision_radius + ATMOSPHERE_DEPTH;
		_atmosphereDrawable = [[OOPlanetDrawable atmosphereWithRadius:atmosphereRadius] retain];
		_atmosphereShaderDrawable = [[OOPlanetDrawable atmosphereWithRadius:collision_radius + ATMOSPHERE_DEPTH] retain];
		
		// convert the atmosphere settings to generic 'material parameters'
		percent_land = 100 - [dict oo_intForKey:@"percent_cloud" defaultValue:100 - (3 + (gen_rnd_number() & 31)+(gen_rnd_number() & 31))];
		[planetInfo setObject:[NSNumber numberWithFloat:0.01 * percent_land] forKey:@"cloud_fraction"];
		[self setUpAtmosphereParametersWithSourceInfo:dict targetInfo:planetInfo];
		// planetInfo now contains a valid air_color
		_airColor = [planetInfo objectForKey:@"air_color"];
		// OOLog (@"planet.debug",@" translated air colour:%@ cloud colour:%@ polar cloud color:%@", [_airColor rgbaDescription],[(OOColor *)[planetInfo objectForKey:@"cloud_color"] rgbaDescription],[(OOColor *)[planetInfo objectForKey:@"polar_cloud_color"] rgbaDescription]);

		_materialParameters = [planetInfo dictionaryWithValuesForKeys:[NSArray arrayWithObjects:@"cloud_fraction", @"air_color",  @"cloud_color", @"polar_cloud_color", @"cloud_alpha", @"land_fraction", @"land_color", @"sea_color", @"polar_land_color", @"polar_sea_color", @"noise_map_seed", @"economy", @"polar_fraction", @"isMiniature", @"perlin_3d", nil]];
	}
	else
#else
	// NEW_ATMOSPHERE is 0? still differentiate between normal planets and moons.
	if (atmosphere)
	{
		_atmosphereDrawable = [[OOPlanetDrawable atmosphereWithRadius:collision_radius + ATMOSPHERE_DEPTH] retain];
		_airColor = [[OOColor colorWithRed:0.8f green:0.8f blue:0.9f alpha:1.0f] retain];
	}
	if (YES) // create _materialParameters when NEW_ATMOSPHERE is set to 0
#endif
	{
		_materialParameters = [planetInfo dictionaryWithValuesForKeys:[NSArray arrayWithObjects:@"land_fraction", @"land_color", @"sea_color", @"polar_land_color", @"polar_sea_color", @"noise_map_seed", @"economy", @"polar_fraction",  @"isMiniature", @"perlin_3d", nil]];
	}
	[_materialParameters retain];
	
	_mesopause2 = (atmosphere) ? (kMesosphere + collision_radius) * (kMesosphere + collision_radius) : 0.0;
	
	_textureName = [[dict oo_stringForKey:@"texture"] retain];
	[self setUpPlanetFromTexture:_textureName];
	[_planetDrawable setRadius:collision_radius];	
		
	// Orientation should be handled by the code that calls this planetEntity. Starting with a default value anyway.
	orientation = (Quaternion){ M_SQRT1_2, M_SQRT1_2, 0, 0 };
	_atmosphereOrientation = kIdentityQuaternion;
	_rotationAxis = vector_up_from_quaternion(orientation);
	
	// set speed of rotation.
	if ([dict objectForKey:@"rotational_velocity"])
	{
		_rotationalVelocity = [dict oo_floatForKey:@"rotational_velocity" defaultValue:0.01f * randf()];	// 0.0 .. 0.01 avr 0.005
	}
	else
	{
		_rotationalVelocity = [planetInfo oo_floatForKey:@"rotation_speed" defaultValue:0.005f * randf()]; // 0.0 .. 0.005 avr 0.0025
		_rotationalVelocity *= [planetInfo oo_floatForKey:@"rotation_speed_factor" defaultValue:1.0f];
	}

	_atmosphereRotationalVelocity = [dict oo_floatForKey:@"atmosphere_rotational_velocity" defaultValue:0.01f * randf()];

	// set energy
	energy = collision_radius * 1000.0f;
	
	setRandomSeed(savedRndSeed);
	RANROTSetFullSeed(savedRanrotSeed);
	
	// rotate planet based on current time, needs to be done here - backported from PlanetEntity.
	int		deltaT = floor(fmod([PLAYER clockTimeAdjusted], 86400));
	quaternion_rotate_about_axis(&orientation, _rotationAxis, _rotationalVelocity * deltaT);
	quaternion_rotate_about_axis(&_atmosphereOrientation, kBasisYVector, _atmosphereRotationalVelocity * deltaT);
	
	
#ifdef OO_DUMP_PLANETINFO
#define CPROP(PROP)	OOLog(@"planetinfo.record",@#PROP " = %@;",[(OOColor *)[planetInfo objectForKey:@#PROP] descriptionComponents]);
#define FPROP(PROP)	OOLog(@"planetinfo.record",@#PROP " = %f;",[planetInfo oo_floatForKey:@"" #PROP]);
	CPROP(air_color);
	FPROP(cloud_alpha);
	CPROP(cloud_color);
	FPROP(cloud_fraction);
	CPROP(land_color);
	FPROP(land_fraction);
	CPROP(polar_cloud_color);
	CPROP(polar_land_color);
	CPROP(polar_sea_color);
	CPROP(sea_color);
	OOLog(@"planetinfo.record",@"rotation_speed = %f",_rotationalVelocity);
#endif

	[self setStatus:STATUS_ACTIVE];
	
	[[OOGraphicsResetManager sharedManager] registerClient:self];

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
	return (Vector){ c.h/360, c.s, c.b };
}


static OOColor *ColorWithHSBColor(Vector c)
{
	return [OOColor colorWithHue:c.x saturation:c.y brightness:c.z alpha:1.0];
}


- (void) setUpTypeParametersWithSourceInfo:(NSDictionary *)sourceInfo targetInfo:(NSMutableDictionary *)targetInfo
{
	[targetInfo oo_setBool:[sourceInfo oo_boolForKey:@"mainForLocalSystem"] forKey:@"mainForLocalSystem"];
	[targetInfo oo_setBool:[sourceInfo oo_boolForKey:@"isMiniature"] forKey:@"isMiniature"];

}


- (void) setUpTerrainParametersWithSourceInfo:(NSDictionary *)sourceInfo targetInfo:(NSMutableDictionary *)targetInfo
{
	NSArray *keys = [NSArray arrayWithObjects:@"atmosphere_rotational_velocity",@"rotational_velocity",@"cloud_alpha",@"has_atmosphere",@"percent_cloud",@"percent_ice",@"percent_land",@"radius",@"seed",nil];
	NSString *key = nil;
	foreach (key, keys) {
		id sval = [sourceInfo objectForKey:key];
		if (sval != nil) {
			[targetInfo setObject:sval forKey:key];
		}
	}

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
	
	Vector	landHSB, seaHSB, landPolarHSB, seaPolarHSB;
	OOColor	*color;
	
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
		color = [OOColor colorWithDescription:[sourceInfo objectForKey:@"land_color"]];
		if (color != nil) landHSB = HSBColorWithColor(color);
		else ScanVectorFromString([sourceInfo oo_stringForKey:@"land_hsb_color"], &landHSB);
		
		color = [OOColor colorWithDescription:[sourceInfo objectForKey:@"sea_color"]];
		if (color != nil) seaHSB = HSBColorWithColor(color);
		else ScanVectorFromString([sourceInfo oo_stringForKey:@"sea_hsb_color"], &seaHSB);
		
		// polar areas are brighter but have less colour (closer to white)
		color = [OOColor colorWithDescription:[sourceInfo objectForKey:@"polar_land_color"]];
		if (color != nil)
		{
			landPolarHSB = HSBColorWithColor(color);
		}
		else 
		{
			landPolarHSB = LighterHSBColor(landHSB);
		}

		color = [OOColor colorWithDescription:[sourceInfo objectForKey:@"polar_sea_color"]];
		if (color != nil)
		{
			seaPolarHSB = HSBColorWithColor(color);
		}
		else
		{
			seaPolarHSB = LighterHSBColor(seaHSB);
		}
		
		[targetInfo setObject:ColorWithHSBColor(landHSB) forKey:@"land_color"];
		[targetInfo setObject:ColorWithHSBColor(seaHSB) forKey:@"sea_color"];
		[targetInfo setObject:ColorWithHSBColor(landPolarHSB) forKey:@"polar_land_color"];
		[targetInfo setObject:ColorWithHSBColor(seaPolarHSB) forKey:@"polar_sea_color"];
	}
	else
	{
		landHSB = RandomHSBColor();	// NB: randomcolor is called twice to make the cloud colour similar to the old one.

		// add a cloud_color tinge to sky blue({0.66, 0.3, 1}).
		seaHSB = vector_add(landHSB,((Vector){1.333, 0.6, 2}));	// 1 part cloud, 2 parts sky blue
		scale_vector(&seaHSB, 0.333);
				
		float cloudAlpha = OOClamp_0_1_f([sourceInfo oo_floatForKey:@"cloud_alpha" defaultValue:1.0f]);
		[targetInfo setObject:[NSNumber numberWithFloat:cloudAlpha] forKey:@"cloud_alpha"];
		
		// planetinfo overrides
		color = [OOColor colorWithDescription:[sourceInfo objectForKey:@"atmosphere_color"]];
		if (color != nil) seaHSB = HSBColorWithColor(color);
		color = [OOColor colorWithDescription:[sourceInfo objectForKey:@"cloud_color"]];
	if (color != nil) landHSB = HSBColorWithColor(color);
		
		// polar areas: brighter, less saturation
		landPolarHSB = vector_add(landHSB,LighterHSBColor(landHSB));
		scale_vector(&landPolarHSB, 0.5);
		
		color = [OOColor colorWithDescription:[sourceInfo objectForKey:@"polar_cloud_color"]];
		if (color != nil) landPolarHSB = HSBColorWithColor(color);
		
		[targetInfo setObject:ColorWithHSBColor(seaHSB) forKey:@"air_color"];
		[targetInfo setObject:ColorWithHSBColor(landHSB) forKey:@"cloud_color"];
		[targetInfo setObject:ColorWithHSBColor(landPolarHSB) forKey:@"polar_cloud_color"];
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
	_atmosphereOrientation = planet->_atmosphereOrientation;
	_rotationalVelocity = 0.04;
	
	_miniature = YES;
	
	_planetDrawable = [planet->_planetDrawable copy];
	[_planetDrawable setRadius:collision_radius];
	
	// FIXME: in old planet code, atmosphere (if textured) is set to 0.6 alpha.
	_atmosphereDrawable = [planet->_atmosphereDrawable copy];
	_atmosphereShaderDrawable = [planet->_atmosphereShaderDrawable copy];
	[_atmosphereDrawable setRadius:collision_radius + ATMOSPHERE_DEPTH * PLANET_MINIATURE_FACTOR * 2.0]; //not to scale: invisible otherwise
	if (_atmosphereShaderDrawable)  [_atmosphereShaderDrawable setRadius:collision_radius + ATMOSPHERE_DEPTH * PLANET_MINIATURE_FACTOR * 2.0];
	
	[_planetDrawable setLevelOfDetail:0.8f];
	[_atmosphereDrawable setLevelOfDetail:0.8f];
	if (_atmosphereShaderDrawable)  [_atmosphereShaderDrawable setLevelOfDetail:0.8f];
	
	return self;
}


- (void) dealloc
{
	DESTROY(_name);
	DESTROY(_planetDrawable);
	DESTROY(_atmosphereDrawable);
	DESTROY(_atmosphereShaderDrawable);
	//DESTROY(_airColor);	// this CTDs on loading savegames.. :(
	DESTROY(_materialParameters);
	DESTROY(_textureName);
	
	[[OOGraphicsResetManager sharedManager] unregisterClient:self];

	[super dealloc];
}


- (NSString*) descriptionComponents
{
	return [NSString stringWithFormat:@"position: %@ radius: %g m", HPVectorDescription([self position]), [self radius]];
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


- (instancetype) miniatureVersion
{
	return [[[[self class] alloc] initAsMiniatureVersionOfPlanet:self] autorelease];
}


- (void) update:(OOTimeDelta) delta_t
{
	[super update:delta_t];
	
	if (EXPECT(!_miniature))
	{
		BOOL canDrawShaderAtmosphere = _atmosphereShaderDrawable && [UNIVERSE detailLevel] >= DETAIL_LEVEL_EXTRAS;
		if (EXPECT_NOT(_atmosphereDrawable && cam_zero_distance < _mesopause2))
		{
			NSAssert(_airColor != nil, @"Expected a non-nil air colour for normal planet. Exiting.");
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
				OOColor	*mixColor = [OOColor colorWithRed:(EXPECT_NOT(alt > 0.98) ? 30.0f : 0.1f)
													green:0.1f
													 blue:0.1f
													alpha:aleph];
															  
				// occlusion rate: .9 is 18 degrees after the terminus, where twilight ends.
				// 1 is the terminus, 1.033 is 6 degrees before the terminus, where the sky begins to redden
				double rate = ([PLAYER occlusionLevel] - 0.97)/0.06; // from 0.97 to 1.03

				if (EXPECT(rate <= 1.0 && rate > 0.0))
				{
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
				}
				else
				{
					if (PLAYER->isSunlit && _airColor != nil) mixColor = _airColor;
				}
				[UNIVERSE setSkyColorRed:[mixColor redComponent] * aleph2
								   green:[mixColor greenComponent] * aleph2
									blue:[mixColor blueComponent] * aleph
								   alpha:aleph];
				double atmosphereRadius = canDrawShaderAtmosphere ? collision_radius : collision_radius + (ATMOSPHERE_DEPTH * alt);
				[_atmosphereDrawable setRadius:atmosphereRadius];
				if (_atmosphereShaderDrawable)  [_atmosphereShaderDrawable setRadius:collision_radius + (ATMOSPHERE_DEPTH * alt)];
				// apply air resistance for the ship, not the camera. Although setSkyColorRed
				// has already set the air resistance to aleph, override it immediately
				[UNIVERSE setAirResistanceFactor:OOClamp_0_1_f(1.0 - trueAlt)];
			}
		}
		else
		{
			if (EXPECT_NOT([_atmosphereDrawable radius] < collision_radius + ATMOSPHERE_DEPTH))
			{
				[_atmosphereDrawable setRadius:collision_radius + ATMOSPHERE_DEPTH];
				if (_atmosphereShaderDrawable)  [_atmosphereShaderDrawable setRadius:collision_radius + ATMOSPHERE_DEPTH];
			}
			if (canDrawShaderAtmosphere && [_atmosphereDrawable radius] != collision_radius)
			{
				// if shader atmo is in use, force texture atmo radius to just collision_radius for cosmetic purposes
				[_atmosphereDrawable setRadius:collision_radius];
			}
			[UNIVERSE setAirResistanceFactor:0.0f];	// out of atmosphere - no air friction
		}
		
		double time = [UNIVERSE getTime];
		
		if (_shuttlesOnGround > 0 && time > _lastLaunchTime + _shuttleLaunchInterval)  [self launchShuttle];
	}
	
	quaternion_rotate_about_axis(&orientation, _rotationAxis, _rotationalVelocity * delta_t);
	// atmosphere orientation is relative to the orientation of the planet
	quaternion_rotate_about_axis(&_atmosphereOrientation, kBasisYVector, _atmosphereRotationalVelocity * delta_t);

	[self orientationChanged];
	
	// FIXME: update atmosphere rotation
}


- (BOOL) isFinishedLoading
{
	OOMaterial *material = [self material];
	if (material != nil && ![material isFinishedLoading])  return NO;
	material = [self atmosphereMaterial];
	if (material != nil && ![material isFinishedLoading])  return NO;
	material = [self atmosphereShaderMaterial];
	if (material != nil && ![material isFinishedLoading])  return NO;
	return YES;
}


- (void) drawImmediate:(bool)immediate translucent:(bool)translucent
{
	BOOL canDrawShaderAtmosphere = _atmosphereShaderDrawable && [UNIVERSE detailLevel] >= DETAIL_LEVEL_EXTRAS;
	
	if ([UNIVERSE breakPatternHide])   return; // DON'T DRAW
	if (_miniature && ![self isFinishedLoading])  return; // For responsiveness, don't block to draw as miniature.

	// too far away to be drawn
	if (magnitude(cameraRelativePosition) > [self radius]*3000) {
		return;
	}
	if (![UNIVERSE viewFrustumIntersectsSphereAt:cameraRelativePosition withRadius:([self radius] + ATMOSPHERE_DEPTH)])
	{
		// Don't draw
		return;
	}
	
	if ([UNIVERSE wireframeGraphics])  OOGLWireframeModeOn();
	
	if (!_miniature)
	{
		[_planetDrawable calculateLevelOfDetailForViewDistance:cam_zero_distance];
		[_atmosphereDrawable setLevelOfDetail:[_planetDrawable levelOfDetail]];
		if (canDrawShaderAtmosphere)  [_atmosphereShaderDrawable setLevelOfDetail:[_planetDrawable levelOfDetail]];
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
		if (_atmosphereDrawable != nil)
		{
			OOGLPushModelView();
			OOGLMultModelView(OOMatrixForQuaternionRotation(_atmosphereOrientation));
			[_atmosphereDrawable renderTranslucentPartsOnOpaquePass];
			if (canDrawShaderAtmosphere)  [_atmosphereShaderDrawable renderTranslucentPartsOnOpaquePass];
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
			if (_atmosphereDrawable != nil)
			{
				OOGLPushModelView();
				OOGLMultModelView(OOMatrixForQuaternionRotation(_atmosphereOrientation));
				[_atmosphereDrawable renderTranslucentParts];
				if (canDrawShaderAtmosphere)  [_atmosphereShaderDrawable renderTranslucentParts];
				OOGLPopModelView();
			}
		}
		else
		{
			[_planetDrawable renderOpaqueParts];
		}
	}
#endif
	
	if ([UNIVERSE wireframeGraphics])  OOGLWireframeModeOff();
}


- (BOOL) checkCloseCollisionWith:(Entity *)other
{
	if (!other)
		return NO;
	if (other->isShip)
	{
		ShipEntity *ship = (ShipEntity *)other;
		if ([ship behaviour] == BEHAVIOUR_LAND_ON_PLANET)
		{
			return NO;
		}
	}
	
	return YES;
}


- (BOOL) planetHasStation
{
	// find the nearest station...
	ShipEntity	*station =  nil;
	station = [UNIVERSE nearestShipMatchingPredicate:IsStationPredicate
										   parameter:nil
									relativeToEntity:self];
	
	if (station && HPdistance([station position], position) < 4 * collision_radius) // there is a station in range.
	{
		return YES;
	}
	return NO;
}


- (void) launchShuttle
{
	if (_shuttlesOnGround == 0)  
	{
		return;
	}
	if ([PLAYER status] == STATUS_START_GAME)
	{
		// don't launch if game not started
		return;
	}
	if (self != [UNIVERSE planet] && ![self planetHasStation])
	{
		// don't launch shuttles when no station is nearby.
		_shuttlesOnGround = 0;
		return;
	}
	
	Quaternion  q1;
	quaternion_set_random(&q1);
	float start_distance = collision_radius + 125.0f;
	HPVector launch_pos = HPvector_add(position, vectorToHPVector(vector_multiply_scalar(vector_forward_from_quaternion(q1), start_distance)));
	
	ShipEntity *shuttle_ship = [UNIVERSE newShipWithRole:@"shuttle"];   // retain count = 1
	if (shuttle_ship)
	{
		if ([[shuttle_ship crew] count] == 0)
		{
			[shuttle_ship setSingleCrewWithRole:@"trader"];
		}
		
		[shuttle_ship setPosition:launch_pos];
		[shuttle_ship setOrientation:q1];
		
		[shuttle_ship setScanClass: CLASS_NEUTRAL];
		[shuttle_ship setCargoFlag:CARGO_FLAG_FULL_PLENTIFUL];
		[shuttle_ship switchAITo:@"oolite-shuttleAI.js"];
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


- (BOOL) isVisible
{
	return YES;
}


- (double) rotationalVelocity
{
	return _rotationalVelocity;
}


- (void) setRotationalVelocity:(double) v
{
	if ([self hasAtmosphere])
	{
		// FIXME: change atmosphere rotation speed proportionally
	}
	_rotationalVelocity = v;
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


- (void)resetGraphicsState
{
	// reset the texture if graphics mode changes
	[self setUpPlanetFromTexture:_textureName];
}


- (void) setTextureFileName:(NSString *)textureName
{
	BOOL isMoon = _atmosphereDrawable == nil;
	
	OOTexture *diffuseMap = nil;
	OOTexture *normalMap = nil;
	NSDictionary *macros = nil;
	NSDictionary *materialDefaults = [ResourceManager materialDefaults];
	
#if OO_SHADERS
	OOGraphicsDetail detailLevel = [UNIVERSE detailLevel];
	BOOL shadersOn = detailLevel >= DETAIL_LEVEL_EXTRAS;
#else
	const BOOL shadersOn = NO;
#endif
	
	if (textureName != nil)
	{
		NSDictionary *spec = [NSDictionary dictionaryWithObjectsAndKeys:textureName, @"name", @"yes", @"repeat_s", @"linear", @"min_filter", @"yes", @"cube_map", nil];
		diffuseMap = [OOTexture textureWithConfiguration:spec];
		if (diffuseMap == nil)  return;		// OOTexture will have logged a file-not-found warning.
		if (shadersOn)  
		{
			[diffuseMap ensureFinishedLoading]; // only know if it is a cube map if it's loaded
			if ([diffuseMap isCubeMap])
			{
				macros = [materialDefaults oo_dictionaryForKey:isMoon ? @"moon-customized-cubemap-macros" : @"planet-customized-cubemap-macros"];
			}
			else
			{
				macros = [materialDefaults oo_dictionaryForKey:isMoon ? @"moon-customized-macros" : @"planet-customized-macros"];
			}
		}
		else textureName = @"dynamic";

	}
	else
	{
		[OOPlanetTextureGenerator generatePlanetTexture:&diffuseMap
									   secondaryTexture:(detailLevel >= DETAIL_LEVEL_EXTRAS) ? &normalMap : NULL
											   withInfo:_materialParameters];

		if (shadersOn)
		{
			macros = [materialDefaults oo_dictionaryForKey:isMoon ? @"moon-dynamic-macros" : @"planet-dynamic-macros"];
		}
		textureName = @"dynamic";
	}

	/* Generate atmosphere texture */
	if (!isMoon)
	{
		if (shadersOn)
		{
			NSMutableDictionary *aConfig = [[[materialDefaults oo_dictionaryForKey:@"atmosphere-material"] mutableCopy] autorelease];
			[aConfig setObject:[NSArray arrayWithObjects:diffuseMap, normalMap, nil] forKey:@"_oo_texture_objects"];
			
			NSDictionary *amacros = [materialDefaults oo_dictionaryForKey:@"atmosphere-dynamic-macros"];
			
			OOMaterial *dynamicShaderMaterial = [OOShaderMaterial shaderMaterialWithName:@"dynamic"
																	configuration:aConfig
																	macros:amacros
																	bindingTarget:self];
																	
			if (dynamicShaderMaterial == nil)
			{
				DESTROY(_atmosphereShaderDrawable);
			}
			else
			{
				[_atmosphereShaderDrawable setMaterial:dynamicShaderMaterial];
			}
		}
		
		OOLog(@"texture.planet.generate",@"Preparing atmosphere for planet %@",self);
		/* Generate a standalone atmosphere texture */
		OOTexture *atmosphere = nil;
		[OOStandaloneAtmosphereGenerator generateAtmosphereTexture:&atmosphere
														withInfo:_materialParameters];
		
		OOLog(@"texture.planet.generate",@"Planet %@ has atmosphere %@",self,atmosphere);
		
		OOSingleTextureMaterial *dynamicMaterial = [[OOSingleTextureMaterial alloc] initWithName:@"dynamic" texture:atmosphere configuration:nil];
		[_atmosphereDrawable setMaterial:dynamicMaterial];
		[dynamicMaterial release];
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


- (OOMaterial *) atmosphereShaderMaterial
{
	if(!_atmosphereShaderDrawable)  return nil;
	return [_atmosphereShaderDrawable material];
}


- (NSString *) name
{
	return _name;
}


- (void) setName:(NSString *)name
{
	[_name release];
	_name = [name retain];
}

@end

#endif	// NEW_PLANETS
