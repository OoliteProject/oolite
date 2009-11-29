/*

OOPlanetEntity.m

Oolite
Copyright (C) 2004-2009 Giles C Williams and contributors

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
#import "OOPlanetDrawable.h"

#import "AI.h"
#import "Universe.h"
#import "ShipEntity.h"
#import "OOCharacter.h"

#import "OOMaths.h"
#import "OOStringParsing.h"
#import "OOCollectionExtractors.h"

#import "OOPlanetTextureGenerator.h"
#import "OOSingleTextureMaterial.h"


@interface OOPlanetEntity (Private)

- (void) setUpColorParametersWithSourceInfo:(NSDictionary *)sourceInfo targetInfo:(NSMutableDictionary *)planetInfo;

@end


@implementation OOPlanetEntity

// this is exclusively called to initialise the main planet.
- (id) initAsMainPlanet;
{
	Random_Seed seed = [UNIVERSE systemSeed];
	
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
	
	scanClass = CLASS_NO_DRAW;
	
	int percent_land = [planetInfo oo_intForKey:@"percent_land" defaultValue:24 + (gen_rnd_number() % 48)];
	[planetInfo setObject:[NSNumber numberWithFloat:0.01 * percent_land] forKey:@"land_fraction"];
	
	// Stir the rnd PRNG once for backwards compatibility, then save seed.
	gen_rnd_number();
	RNG_Seed savedRndSeed = currentRandomSeed();
	
	_planetDrawable = [[OOPlanetDrawable alloc] init];
	
	// Load material parameters.
	NSString *textureName = [dict oo_stringForKey:@"texture"];
	if (textureName != nil)
	{
		[_planetDrawable setTextureName:textureName];
	}
	else
	{
		[self setUpColorParametersWithSourceInfo:dict targetInfo:planetInfo];
		OOTexture *texture = [OOPlanetTextureGenerator planetTextureWithInfo:planetInfo];
		OOSingleTextureMaterial *material = [[OOSingleTextureMaterial alloc] initWithName:@"dynamic" texture:texture configuration:nil];
		[_planetDrawable setMaterial:material];
		[material release];
	}
	
	collision_radius = radius_km * 10.0;	// Scale down by a factor of 100
	orientation = (Quaternion){ M_SQRT1_2, M_SQRT1_2, 0, 0 };	// FIXME: do we want to do something more interesting here?
	_rotationAxis = kBasisYVector;
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
	
	if (atmosphere)
	{
		// FIXME: atmospheres are not usable right now.
	//	_atmosphereDrawable = [[OOPlanetDrawable atmosphereWithRadius:collision_radius + ATMOSPHERE_DEPTH eccentricity:0.0] retain];
	}
	
	// set energy
	energy = collision_radius * 1000.0;
	
	setRandomSeed(savedRndSeed);
	RANROTSetFullSeed(savedRanrotSeed);
	
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


static OOColor *ColorWithHSBColor(Vector c)
{
	return [OOColor colorWithCalibratedHue:c.x saturation:c.y brightness:c.z alpha:1.0];
}


- (void) setUpColorParametersWithSourceInfo:(NSDictionary *)sourceInfo targetInfo:(NSMutableDictionary *)targetInfo
{
	// Stir the PRNG twelve times for backwards compatibility.
	unsigned i;
	for (i = 0; i < 12; i++)
	{
		gen_rnd_number();
	}
	
//	float polarColorFactor = [sourceInfo oo_floatForKey:@"polar_color_factor" defaultValue:0.5];
	
	Vector landHSB, seaHSB, landPolarHSB, seaPolarHSB;
	
	landHSB = RandomHSBColor();
	do
	{
		seaHSB = RandomHSBColor();
	}
	while (dot_product(landHSB, seaHSB) > .80); // make sure land and sea colors differ significantly
	
	// possibly get landHSB and seaHSB from planetinfo.plist entry
	ScanVectorFromString([sourceInfo oo_stringForKey:@"land_hsb_color"], &landHSB);
	ScanVectorFromString([sourceInfo oo_stringForKey:@"sea_hsb_color"], &seaHSB);
	
	// polar areas are brighter but have less color (closer to white)
	landPolarHSB = LighterHSBColor(landHSB);
	seaPolarHSB = LighterHSBColor(seaHSB);
	
	[targetInfo setObject:ColorWithHSBColor(landHSB) forKey:@"land_color"];
	[targetInfo setObject:ColorWithHSBColor(seaHSB) forKey:@"sea_color"];
	[targetInfo setObject:ColorWithHSBColor(landPolarHSB) forKey:@"polar_land_color"];
	[targetInfo setObject:ColorWithHSBColor(seaPolarHSB) forKey:@"polar_sea_color"];
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
	
	_planetDrawable = [planet->_planetDrawable copy];
	[_planetDrawable setRadius:collision_radius];
	
	// FIXME: in old planet code, atmosphere (if textured) is set to 0.6 alpha.
	_atmosphereDrawable = [planet->_atmosphereDrawable copy];
	[_atmosphereDrawable setRadius:collision_radius + ATMOSPHERE_DEPTH * PLANET_MINIATURE_FACTOR * 2.0]; //not to scale: invisible otherwise
	
	return self;
}


- (void) dealloc
{
	DESTROY(_planetDrawable);
	DESTROY(_atmosphereDrawable);
	
	[super dealloc];
}


- (NSString*) descriptionComponents
{
	return [NSString stringWithFormat:@"position: %@ radius: %g m", VectorDescription([self position]), [self radius]];
}


- (double) radius
{
	return collision_radius;
}


- (OOPlanetType) planetType
{
	if (_miniature)  return PLANET_TYPE_MINIATURE;
	if (_atmosphereDrawable != nil)  return PLANET_TYPE_ATMOSPHERE;
	return PLANET_TYPE_GREEN;
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
	else
	{
		// Miniature
		quaternion_rotate_about_axis(&orientation, _rotationAxis, _rotationalVelocity * delta_t);
		[self orientationChanged];
		
		// FIXME: update atmosphere
	}
}


- (void) drawEntity:(BOOL)immediate :(BOOL)translucent
{
	if (translucent || [UNIVERSE breakPatternHide])   return; // DON'T DRAW
	
	if ([UNIVERSE wireframeGraphics])  GLDebugWireframeModeOn();
	
	[_planetDrawable calculateLevelOfDetailForViewDistance:zero_distance];
	[_atmosphereDrawable setLevelOfDetail:[_planetDrawable levelOfDetail]];
	
	[_planetDrawable renderOpaqueParts];
	[_atmosphereDrawable renderOpaqueParts];
	
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
		[shuttle_ship setStatus:STATUS_IN_FLIGHT];
		
		[UNIVERSE addEntity:shuttle_ship];
		[[shuttle_ship getAI] setStateMachine:@"risingShuttleAI.plist"];	// must happen after adding to the universe!
		
		[shuttle_ship release];
		
		_shuttlesOnGround--;
		_lastLaunchTime = [UNIVERSE getTime];
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

@end
