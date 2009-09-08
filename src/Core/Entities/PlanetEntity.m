/*

PlanetEntity.m

Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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

#import "PlanetEntity.h"
#import "OOOpenGLExtensionManager.h"

#import "Universe.h"
#import "AI.h"
#import "TextureStore.h"
#import "MyOpenGLView.h"
#import "ShipEntityAI.h"
#import "OOColor.h"
#import "OOCharacter.h"
#import "OOStringParsing.h"
#import "PlayerEntity.h"
#import "OOCollectionExtractors.h"

#define kOOLogUnconvertedNSLog @"unclassified.PlanetEntity"


#define LIM500  500.0*500.0 * NO_DRAW_DISTANCE_FACTOR*NO_DRAW_DISTANCE_FACTOR
#define LIM4K   4000.0*4000.0 * NO_DRAW_DISTANCE_FACTOR*NO_DRAW_DISTANCE_FACTOR
#define LIM8K   8000.0*8000.0 * NO_DRAW_DISTANCE_FACTOR*NO_DRAW_DISTANCE_FACTOR
#define LIM16K  16000.0*16000.0 * NO_DRAW_DISTANCE_FACTOR*NO_DRAW_DISTANCE_FACTOR


static double		corona_speed_factor;	// multiply delta_t by this before adding it to corona_stage
static double		corona_stage;			// 0.0 -> 1.0
static GLfloat		rvalue[729];			// stores random values for adjusting colors in the corona


// straight c
static Vector base_vertex_array[10400];
static int base_terrain_array[10400];
static int next_free_vertex;
NSMutableDictionary*	edge_to_vertex = nil;

static int n_triangles[MAX_SUBDIVIDE];
static int triangle_start[MAX_SUBDIVIDE];
static GLuint vertex_index_array[3*(20+80+320+1280+5120+20480)];

static GLfloat	texture_uv_array[10400 * 2];
static float corona_blending;


@interface PlanetEntity (OOPrivate)

- (id) initAsAtmosphereForPlanet:(PlanetEntity *)planet;
- (id) initAsAtmosphereForPlanet:(PlanetEntity *)planet dictionary:(NSDictionary *)dict;
- (void) setTextureColorForPlanet:(BOOL)isMain inSystem:(BOOL)isLocal;
@end


@implementation PlanetEntity

- (id) init
{
	unsigned		i;
	unsigned		percent_land;
	
	self = [super init];
	
	isTextured = NO;
	textureFile = nil;
	
	collision_radius = 25000.0; //  25km across
	
	scanClass = CLASS_NO_DRAW;
	
	orientation.w =  M_SQRT1_2;		// represents a 90 degree rotation around x axis
	orientation.x =  M_SQRT1_2;		// (I hope!)
	orientation.y =  0.0;
	orientation.z =  0.0;
	
	planet_type = PLANET_TYPE_GREEN;
	
	shuttles_on_ground = 0;
	last_launch_time = 0.0;
	shuttle_launch_interval = 3600.0;
	
	for (i = 0; i < 5; i++)
		displayListNames[i] = 0;	// empty for now!
	
	[self setModelName:@"icosahedron.dat"];
	
	[self rescaleTo:1.0];
	
	planet_seed = 54321;
	
	ranrot_srand(planet_seed);
	percent_land = (ranrot_rand() % 50);
	
	for (i = 0; i < vertexCount; i++)
	{
		if (Ranrot() % 100 < percent_land)  r_seed[i] = 0;  // land
		else  r_seed[i] = 1;  // sea
	}
	
	polar_color_factor = 1.0;
	
	amb_land[0] = 0.0;
	amb_land[1] = 1.0;
	amb_land[2] = 0.0;
	amb_land[3] = 1.0;
	amb_sea[0] = 0.0;
	amb_sea[1] = 0.0;
	amb_sea[2] = 1.0;
	amb_sea[3] = 1.0;
	amb_polar_land[0] = 0.9;
	amb_polar_land[1] = 0.9;
	amb_polar_land[2] = 0.9;
	amb_polar_land[3] = 1.0;
	amb_polar_sea[0] = 1.0;
	amb_polar_sea[1] = 1.0;
	amb_polar_sea[2] = 1.0;
	amb_polar_sea[3] = 1.0;
	
	isPlanet = YES;
	
	root_planet = self;
	
	textureData = NULL;
	
	rotationAxis = kBasisYVector;
	
	return self;
}


- (BOOL) setSunColor:(OOColor*)sun_color
{
	if (sun_color == nil) return NO;
	
	OOCGFloat	hue, sat, bri, alf;
	OOColor		*color;

	[sun_color getHue:&hue saturation:&sat brightness:&bri alpha:&alf];
	hue /=360;

	float hue_drift = 0.34f * abs(randf() - randf());

	// set the lighting color for the sun
	GLfloat		r,g,b,a;
	[sun_color getGLRed:&r green:&g blue:&b alpha:&a];

	GLfloat		sun_ambient[] = { 0.0, 0.0, 0.0, 1.0};	// real ambient light inside gl_LightModel.ambient
	sun_diffuse[0] = 0.5 * (1.0 + r);	// paler
	sun_diffuse[1] = 0.5 * (1.0 + g);	// paler
	sun_diffuse[2] = 0.5 * (1.0 + b);	// paler
	sun_diffuse[3] = 1.0;
	sun_specular[0] = r;
	sun_specular[1] = g;
	sun_specular[2] = b;
	sun_specular[3] = 1.0;

	OOGL(glLightfv(GL_LIGHT1, GL_AMBIENT, sun_ambient));
	OOGL(glLightfv(GL_LIGHT1, GL_DIFFUSE, sun_diffuse));
	OOGL(glLightfv(GL_LIGHT1, GL_SPECULAR, sun_specular));

	// main disc less saturation more brightness
	color = [OOColor colorWithCalibratedHue: hue saturation: sat * 0.333 brightness: 1.0 alpha: alf];
	amb_land[0] = [color redComponent];
	amb_land[1] = [color greenComponent];
	amb_land[2] = [color blueComponent];
	amb_land[3] = 1.0;
	
	// nearest corona much more saturation
	hue += hue_drift;
	if (hue > 1.0)	hue -= 1.0;
	color = [OOColor colorWithCalibratedHue:hue saturation: sat * 0.625 brightness:(bri + 2.0)/3.0 alpha:alf];
	amb_polar_land[0] = [color redComponent];
	amb_polar_land[1] = [color greenComponent];
	amb_polar_land[2] = [color blueComponent];
	amb_polar_land[3] = 1.0;
	
	// next corona slightly more saturation
	hue += hue_drift;
	if (hue > 1.0)	hue -= 1.0;
	color = [OOColor colorWithCalibratedHue:hue saturation:sat brightness:bri alpha:alf];
	amb_sea[0] = [color redComponent];
	amb_sea[1] = [color greenComponent];
	amb_sea[2] = [color blueComponent];
	amb_sea[3] = 1.0;
	
	// last corona, highest saturation, less bright
	hue += hue_drift;
	if (hue > 1.0)	hue -= 1.0;
	// saturation = 1 would shift white to red
	color = [OOColor colorWithCalibratedHue:hue saturation:OOClamp_0_1_f(sat*1.3) brightness:bri * 0.75 alpha:alf*0.6];
	amb_polar_sea[0] = [color redComponent];
	amb_polar_sea[1] = [color greenComponent];
	amb_polar_sea[2] = [color blueComponent];
	amb_polar_sea[3] = 1.0;

	return YES;
}


- (id) initSunWithColor:(OOColor *)sun_color andDictionary:(NSDictionary *) dict
{
	int			i;
	
	self = [super init];
	
	isTextured = NO;
#ifndef NO_SHADERS
	isShadered = NO;
#endif
	
	collision_radius = 100000.0; //  100km across
	
	scanClass = CLASS_NO_DRAW;
	planet_type =   PLANET_TYPE_SUN;
	shuttles_on_ground = 0;
	last_launch_time = 0.0;
	shuttle_launch_interval = 3600.0;
	
	for (i = 0; i < 5; i++)  displayListNames[i] = 0;	// empty for now!
	
	[self setSunColor:sun_color];
	
	corona_blending=OOClamp_0_1_f([dict oo_floatForKey:@"corona_hues" defaultValue:1.0f]);
	corona_speed_factor=[dict oo_floatForKey:@"corona_shimmer" defaultValue:-1.0];
	if(corona_speed_factor<0)
	{
		// from .22222 to 2
		corona_speed_factor = 1.0 / (0.5 + 2.0 * (randf() + randf()));
	}
	else
	{
		//on average:  0 = .25 , 1 = 2.25  -  the same sun should give the same random component
		corona_speed_factor=OOClamp_0_1_f(corona_speed_factor) * 2.0 + randf() * randf();
	}
	corona_stage = 0.0;
	for (i = 0; i < 729; i++)
		rvalue[i] = randf();
	
	// set up the radius properties
	[self changeSunProperty:@"sun_radius" withDictionary:dict];
	
	isPlanet = YES;
	root_planet = self;	
	textureData = NULL;	
	return self;
}


- (id) initAsAtmosphereForPlanet:(PlanetEntity *)planet
{
	return [self initAsAtmosphereForPlanet:planet dictionary:nil];
}


- (id) initAsAtmosphereForPlanet:(PlanetEntity *)planet dictionary:(NSDictionary *)dict
{
	int		i;
	int		percent_land;
	
#if ALLOW_PROCEDURAL_PLANETS
	BOOL	procGen = [UNIVERSE doProcedurallyTexturedPlanets];
#endif
	
	if (dict == nil)  dict = [NSDictionary dictionary];
	
	self = [super init];
	
	percent_land = 100 - [dict oo_intForKey:@"percent_cloud" defaultValue:100 - (3 + (gen_rnd_number() & 31)+(gen_rnd_number() & 31))];
	
	polar_color_factor = 1.0;
	
#define CLEAR_SKY_ALPHA			0.05
#define CLOUD_ALPHA				0.50
#define POLAR_CLEAR_SKY_ALPHA	0.34
#define POLAR_CLOUD_ALPHA		0.75
	
	amb_land[0] = gen_rnd_number() / 256.0;
	amb_land[1] = gen_rnd_number() / 256.0;
	amb_land[2] = gen_rnd_number() / 256.0;
	amb_land[3] = CLEAR_SKY_ALPHA;  			// blue sky, zero clouds
	amb_sea[0] = 0.5 + gen_rnd_number() / 512.0;
	amb_sea[1] = 0.5 + gen_rnd_number() / 512.0;
	amb_sea[2] = 0.5 + gen_rnd_number() / 512.0;
	amb_sea[3] = CLOUD_ALPHA;  					// 50% opaque clouds
	amb_polar_land[0] = gen_rnd_number() / 256.0;
	amb_polar_land[1] = gen_rnd_number() / 256.0;
	amb_polar_land[2] = gen_rnd_number() / 256.0;
	amb_polar_land[3] = POLAR_CLEAR_SKY_ALPHA;	// 34% gray clouds
	amb_polar_sea[0] = 0.9 + gen_rnd_number() / 2560.0;
	amb_polar_sea[1] = 0.9 + gen_rnd_number() / 2560.0;
	amb_polar_sea[2] = 0.9 + gen_rnd_number() / 2560.0;
	amb_polar_sea[3] = POLAR_CLOUD_ALPHA;		// 75% clouds
	
	// Colour overrides from dictionary
	OOColor		*clearSkyColor = nil;
	OOColor		*cloudColor = nil;
	OOColor		*polarClearSkyColor = nil;
	OOColor		*polarCloudColor = nil;
	float		cloudAlpha;
	
	
	clearSkyColor = [OOColor colorWithDescription:[dict objectForKey:@"clear_sky_color"]];
	cloudColor = [OOColor colorWithDescription:[dict objectForKey:@"cloud_color"]];
	polarClearSkyColor = [OOColor colorWithDescription:[dict objectForKey:@"polar_clear_sky_color"]];
	polarCloudColor = [OOColor colorWithDescription:[dict objectForKey:@"polar_cloud_color"]];
	cloudAlpha = OOClamp_0_1_f([dict oo_floatForKey:@"cloud_alpha" defaultValue:1.0]);
	
	if (clearSkyColor != nil)
	{
		[clearSkyColor getGLRed:&amb_land[0] green:&amb_land[1] blue:&amb_land[2] alpha:&amb_land[3]];
	}
	
	if (cloudColor != nil)
	{
		[cloudColor getGLRed:&amb_sea[0] green:&amb_sea[1] blue:&amb_sea[2] alpha:&amb_sea[3]];
	}
	
	if (polarClearSkyColor != nil)
	{
		[polarClearSkyColor getGLRed:&amb_polar_land[0] green:&amb_polar_land[1] blue:&amb_polar_land[2] alpha:&amb_polar_land[3]];
	}
	else if (clearSkyColor != nil)
	{
		memmove(amb_polar_land, amb_land, sizeof amb_polar_land);
		amb_polar_land[3] = OOClamp_0_1_f(amb_polar_land[3] * (POLAR_CLEAR_SKY_ALPHA / CLEAR_SKY_ALPHA));
	}
	
	if (polarCloudColor != nil)
	{
		[polarCloudColor getGLRed:&amb_polar_sea[0] green:&amb_polar_sea[1] blue:&amb_polar_sea[2] alpha:&amb_polar_sea[3]];
	}
	else if (cloudColor != nil)
	{
		memmove(amb_polar_sea, amb_sea, sizeof amb_polar_sea);
		amb_polar_sea[3] *= (POLAR_CLOUD_ALPHA / CLOUD_ALPHA);
	}
	
	//amb_land[3] is already 0.05
	amb_sea[3] *= cloudAlpha;
	amb_polar_land[3] *= cloudAlpha;
	amb_polar_sea[3] *= cloudAlpha;
	
	amb_sea[3] = OOClamp_0_1_f(amb_sea[3]);
	amb_polar_sea[3] = OOClamp_0_1_f(amb_polar_sea[3]);
	
	atmosphere = nil;
	
#if ALLOW_PROCEDURAL_PLANETS
	if (procGen)
	{
		RANROTSeed ranrotSavedSeed = RANROTGetFullSeed();
		RNG_Seed saved_seed = currentRandomSeed();
		cloudColor = [OOColor colorWithCalibratedRed: amb_sea[0] green: amb_sea[1] blue: amb_sea[2] alpha: amb_sea[3]];
		float cloud_bias = -0.01 * (float)percent_land;
		float cloud_impress = 1.0 - cloud_bias;
	
		textureName = [TextureStore getCloudTextureNameFor:cloudColor :cloud_impress :cloud_bias intoData: &textureData];
		isTextured = (textureName != 0);
		setRandomSeed(saved_seed);
		RANROTSetFullSeed(ranrotSavedSeed);
	}
	else
#endif
	{
		textureName = 0;
		isTextured = NO;
	}
#ifndef NO_SHADERS
	isShadered = NO;
	shader_program = NULL_SHADER;
#endif
	if (!planet)
	{
		OOLogERR(@"planet.atmosphere.init.noPlanet", @"planet entity initAsAtmosphereForPlanet: no planet found.");
		return self;
	}
	
	[self setOwner: planet];
	
	position = planet->position;
	orientation = planet->orientation;
	
	if (planet->planet_type == PLANET_TYPE_GREEN)
		collision_radius = planet->collision_radius + ATMOSPHERE_DEPTH; //  atmosphere is 500m deep only
	if (planet->planet_type == PLANET_TYPE_MINIATURE)
		collision_radius = planet->collision_radius + ATMOSPHERE_DEPTH * PLANET_MINIATURE_FACTOR*2.0; //not to scale: invisible otherwise
	
	shuttles_on_ground = 0;
	last_launch_time = 0.0;
	shuttle_launch_interval = 3600.0;

	scanClass = CLASS_NO_DRAW;
	
	orientation.w =  M_SQRT1_2;
	orientation.x =  M_SQRT1_2;
	orientation.y =  0.0;
	orientation.z =  0.0;
	
	planet_type =   PLANET_TYPE_ATMOSPHERE;
	
	planet_seed =	ranrot_rand();	// random set-up for vertex colours
	
	for (i = 0; i < 5; i++)
		displayListNames[i] = 0;	// empty for now!
	
	[self setModelName:(isTextured)? @"icostextured.dat" : @"icosahedron.dat"];
	[self rescaleTo:1.0];
	[self initialiseBaseVertexArray];
	[self initialiseBaseTerrainArray:percent_land];
	for (i =  0; i < next_free_vertex; i++)
		[self paintVertex:i :planet_seed];
	
	[self scaleVertices];

	// set speed of rotation
	rotational_velocity = [dict oo_floatForKey:@"atmosphere_rotational_velocity" defaultValue:0.01f + 0.02f * randf()]; // 0.01 .. 0.03 avr 0.02
	
	isPlanet = YES;
	
	root_planet = planet;
	
	rotationAxis = kBasisYVector;
	
	return self;
}


- (id) initWithSeed:(Random_Seed) p_seed
{
	// this is exclusively called to initialise the main planet
	NSMutableDictionary*   planetInfo = [NSMutableDictionary dictionaryWithDictionary:[UNIVERSE generateSystemData:p_seed]];
#if ALLOW_PROCEDURAL_PLANETS
	if (![UNIVERSE doProcedurallyTexturedPlanets])
#endif
	{
		//only allow .png textures with procedural textures
		[planetInfo removeObjectForKey:@"texture"];
	}

	[planetInfo oo_setBool:equal_seeds(p_seed, [UNIVERSE systemSeed]) forKey:@"mainForLocalSystem"];
	return [self initPlanetFromDictionary:planetInfo withAtmosphere:YES andSeed:p_seed];
}


- (void) miniaturize
{
	shuttles_on_ground = 0;
	last_launch_time = 0.0;
	shuttle_launch_interval = 3600.0;
	[self setStatus:STATUS_COCKPIT_DISPLAY];
	planet_type = PLANET_TYPE_MINIATURE;
	collision_radius = [self collisionRadius] * PLANET_MINIATURE_FACTOR; // teeny tiny
	[self rescaleTo:1.0];
	[self scaleVertices];
	if (!!atmosphere)
	{
		atmosphere->collision_radius = collision_radius + ATMOSPHERE_DEPTH * PLANET_MINIATURE_FACTOR*2.0; //not to scale: invisible otherwise
		[atmosphere rescaleTo:1.0];
		[atmosphere scaleVertices];
	}
	rotational_velocity = 0.04;
	rotationAxis = kBasisYVector;
}


- (id) initMiniatureFromPlanet:(PlanetEntity*) planet
{
	return [self initMiniatureFromPlanet:planet withAlpha:1.0f];
}


- (id) initMiniatureFromPlanet:(PlanetEntity*) planet withAlpha:(float) alpha
{
	int		i;
	
	if (!planet)  return nil;
	
	self = [super init];
	
	isTextured = [planet isTextured];
	textureName = [planet textureName];	
	planet_seed = [planet planet_seed];
	
	shuttles_on_ground = 0;
	last_launch_time = 0.0;
	shuttle_launch_interval = 3600.0;
	
	collision_radius = [planet collisionRadius] * PLANET_MINIATURE_FACTOR; // teeny tiny
	
	scanClass = CLASS_NO_DRAW;
	[self setStatus:STATUS_COCKPIT_DISPLAY];
	
	orientation = planet->orientation;
	
	if ([planet planetType] == PLANET_TYPE_ATMOSPHERE)
	{
		planet_type = PLANET_TYPE_ATMOSPHERE;
		rotational_velocity = 0.02;
	}
	else
	{
		planet_type = PLANET_TYPE_MINIATURE;
		rotational_velocity = 0.04;
	}
	
	for (i = 0; i < 5; i++)
		displayListNames[i] = 0;	// empty for now!
	
	[self setModelName:(isTextured)? @"icostextured.dat" : @"icosahedron.dat"];
	
	[self rescaleTo:1.0];
	
	for (i = 0; i < 3; i++)
	{
		amb_land[i] =		[planet amb_land][i];
		amb_sea[i] =		[planet amb_sea][i];
		amb_polar_land[i] =	[planet amb_polar_land][i];
		amb_polar_sea[i] =	[planet amb_polar_sea][i];
	}
	//alpha channel
	amb_land[i] =		[planet amb_land][i] * alpha;
	amb_sea[i] =		[planet amb_sea][i] * alpha;
	amb_polar_land[i] =	[planet amb_polar_land][i] * alpha;
	amb_polar_sea[i] =	[planet amb_polar_sea][i] * alpha;

	
	vertexdata=planet->vertexdata;
	[self scaleVertices];
	
	if (planet->atmosphere)
	{
		// copy clouds but make fainter if isTextureImage
		atmosphere = [[PlanetEntity alloc] initMiniatureFromPlanet:planet->atmosphere withAlpha:planet->isTextureImage ? 0.6f : 1.0f ];
		atmosphere->collision_radius = collision_radius + ATMOSPHERE_DEPTH * PLANET_MINIATURE_FACTOR*2.0; //not to scale: invisible otherwise
		[atmosphere rescaleTo:1.0];
		[atmosphere scaleVertices];

		isPlanet = YES;
		root_planet = self;
	}

	rotationAxis = kBasisYVector;
	
	return self;
}

- (id) initPlanetFromDictionary:(NSDictionary*) dict 

{
	return [self initPlanetFromDictionary:dict withAtmosphere:YES andSeed:[UNIVERSE systemSeed]];
}

- (id) initPlanetFromDictionary:(NSDictionary*)dict withAtmosphere:(BOOL)atmo andSeed:(Random_Seed)p_seed
{
	int		i;
	int		percent_land;
	BOOL	procGen = NO;
#if ALLOW_PROCEDURAL_PLANETS
	procGen = [UNIVERSE doProcedurallyTexturedPlanets];
#endif
	
	if (dict == nil)  dict = [NSDictionary dictionary];
	RANROTSeed ranrotSavedSeed = RANROTGetFullSeed();
	
	self = [super init];
	
	if (atmo)
		planet_seed = p_seed.a * 13 + p_seed.c * 11 + p_seed.e * 7;	// pseudo-random set-up for vertex colours
	else
		planet_seed = p_seed.a * 7 + p_seed.c * 11 + p_seed.e * 13;	// pseudo-random set-up for vertex colours
	
	isTextureImage = NO;
	textureFile = nil;
	if ([dict objectForKey:@"texture"])
	{
		textureFile = [[dict oo_stringForKey:@"texture"] retain];
		textureName = [TextureStore getTextureNameFor:textureFile];
		isTextureImage = isTextured = (textureName != 0);
	}
	else
	{
		if (procGen)
		{
			//generate the texture later
			isTextured = NO;
		}
		else
		{
			textureName = atmo ? 0: [TextureStore getTextureNameFor:@"metal.png"];
			isTextured = (textureName != 0);
		}
	}
	
	NSString *seedStr = [dict oo_stringForKey:@"seed"];
	if (seedStr != nil)
	{
		Random_Seed seed = RandomSeedFromString(seedStr);
		if (!is_nil_seed(seed))
		{
			p_seed = seed;
		}
		else
		{
			OOLogERR(@"planet.fromDict", @"could not interpret \"%@\" as planet seed, using default.", seedStr);
		}
	}
	
	seed_for_planet_description(p_seed);
	
	NSMutableDictionary	*planetInfo = [NSMutableDictionary dictionaryWithDictionary:[UNIVERSE generateSystemData:p_seed]];
	int	radius_km = [dict oo_intForKey:KEY_RADIUS 
						defaultValue:[planetInfo oo_intForKey:KEY_RADIUS]];
	int techlevel = [dict oo_intForKey:KEY_TECHLEVEL
						defaultValue:[planetInfo oo_intForKey:KEY_TECHLEVEL]];
	
	shuttles_on_ground = 1 + floor(techlevel * 0.5);
	last_launch_time = 0.0;
	shuttle_launch_interval = 3600.0 / shuttles_on_ground; // all are launched in an hour

	last_launch_time = 30.0 - shuttle_launch_interval;   // debug - launch 30s after player enters universe

	collision_radius = radius_km * 10.0; // scale down by a factor of 100 !
	
	scanClass = CLASS_NO_DRAW;
	
	orientation.w =  M_SQRT1_2;
	orientation.x =  M_SQRT1_2;
	orientation.y =  0.0;
	orientation.z =  0.0;
	
	planet_type =  atmo ? PLANET_TYPE_GREEN : PLANET_TYPE_MOON;
	
	for (i = 0; i < 5; i++)
		displayListNames[i] = 0;	// empty for now!
	
	[self setModelName:(procGen || isTextured) ? @"icostextured.dat" : @"icosahedron.dat"];
	
	[self rescaleTo:1.0];
	
	percent_land = [planetInfo oo_intForKey:@"percent_land" defaultValue:24 + (gen_rnd_number() % 48)];
	//if (isTextured)  percent_land =  atmo ? 0 :100; // moon/planet override
	
	// save the current random number generator seed
	RNG_Seed saved_seed = currentRandomSeed();
	
	for (i = 0; i < vertexCount; i++)
	{
		if (gen_rnd_number() < 256 * percent_land / 100)
			r_seed[i] = 0;  // land
		else
			r_seed[i] = 100;  // sea
	}
	
	[planetInfo setObject:[NSNumber numberWithFloat:0.01 * percent_land] forKey:@"land_fraction"];
	
	polar_color_factor = [dict oo_doubleForKey:@"polar_color_factor" defaultValue:0.5f];
	
	Vector land_hsb, sea_hsb, land_polar_hsb, sea_polar_hsb;
	
	if (!isTextured)
	{
		land_hsb.x = gen_rnd_number() / 256.0;  land_hsb.y = gen_rnd_number() / 256.0;  land_hsb.z = 0.5 + gen_rnd_number() / 512.0;
		sea_hsb.x = gen_rnd_number() / 256.0;  sea_hsb.y = gen_rnd_number() / 256.0;  sea_hsb.z = 0.5 + gen_rnd_number() / 512.0;
		while (dot_product(land_hsb,sea_hsb) > .80) // make sure land and sea colors differ significantly
		{
			sea_hsb.x = gen_rnd_number() / 256.0;  sea_hsb.y = gen_rnd_number() / 256.0;  sea_hsb.z = 0.5 + gen_rnd_number() / 512.0;
		}
	}
	else
	{
		land_hsb.x = 0.0;	land_hsb.y = 0.0;	land_hsb.z = 1.0;	// non-saturated fully bright (white)
		sea_hsb.x = 0.0;	sea_hsb.y = 1.0;	sea_hsb.z = 1.0;	// fully-saturated fully bright (red)
	}
	
	if (isTextureImage)
	{
		// override the mainPlanet texture colour...
		[self setTextureColorForPlanet:!![dict objectForKey:@"mainForLocalSystem"] inSystem:[dict oo_boolForKey:@"mainForLocalSystem" defaultValue:NO]];
	}
	else
	{
		// possibly get land_hsb and sea_hsb from planetinfo.plist entry
		ScanVectorFromString([dict objectForKey:@"land_hsb_color"], &land_hsb);
		ScanVectorFromString([dict objectForKey:@"sea_hsb_color"], &sea_hsb);
		
		// polar areas are brighter but have less color (closer to white)
		land_polar_hsb.x = land_hsb.x;  land_polar_hsb.y = (land_hsb.y / 4.0);  land_polar_hsb.z = 1.0 - (land_hsb.z / 10.0);
		sea_polar_hsb.x = sea_hsb.x;  sea_polar_hsb.y = (sea_hsb.y / 4.0);  sea_polar_hsb.z = 1.0 - (sea_hsb.z / 10.0);
		
		OOColor* amb_land_color = [OOColor colorWithCalibratedHue:land_hsb.x saturation:land_hsb.y brightness:land_hsb.z alpha:1.0];
		OOColor* amb_sea_color = [OOColor colorWithCalibratedHue:sea_hsb.x saturation:sea_hsb.y brightness:sea_hsb.z alpha:1.0];
		OOColor* amb_polar_land_color = [OOColor colorWithCalibratedHue:land_polar_hsb.x saturation:land_polar_hsb.y brightness:land_polar_hsb.z alpha:1.0];
		OOColor* amb_polar_sea_color = [OOColor colorWithCalibratedHue:sea_polar_hsb.x saturation:sea_polar_hsb.y brightness:sea_polar_hsb.z alpha:1.0];
		
		amb_land[0] = [amb_land_color redComponent];
		amb_land[1] = [amb_land_color blueComponent];
		amb_land[2] = [amb_land_color greenComponent];
		amb_land[3] = 1.0;
		amb_sea[0] = [amb_sea_color redComponent];
		amb_sea[1] = [amb_sea_color blueComponent];
		amb_sea[2] = [amb_sea_color greenComponent];
		amb_sea[3] = 1.0;
		amb_polar_land[0] = [amb_polar_land_color redComponent];
		amb_polar_land[1] = [amb_polar_land_color blueComponent];
		amb_polar_land[2] = [amb_polar_land_color greenComponent];
		amb_polar_land[3] = 1.0;
		amb_polar_sea[0] = [amb_polar_sea_color redComponent];
		amb_polar_sea[1] = [amb_polar_sea_color blueComponent];
		amb_polar_sea[2] = [amb_polar_sea_color greenComponent];
		amb_polar_sea[3] = 1.0;
		
		[planetInfo setObject:amb_land_color forKey:@"land_color"];
		[planetInfo setObject:amb_sea_color forKey:@"sea_color"];
		[planetInfo setObject:amb_polar_land_color forKey:@"polar_land_color"];
		[planetInfo setObject:amb_polar_sea_color forKey:@"polar_sea_color"];
	}

#if ALLOW_PROCEDURAL_PLANETS
	if (procGen)
	{
		if (!isTextured)
		{
		fillRanNoiseBuffer();
		textureName = [TextureStore getPlanetTextureNameFor: planetInfo intoData: &textureData];
		isTextured = (textureName != 0);
#ifndef NO_SHADERS
		isShadered = NO;
#if OLD_SHADERS
		if (UNIVERSE)
		{
			NSDictionary* shader_info = [[UNIVERSE descriptions] objectForKey:@"planet-surface-shader"];
			if (shader_info)
			{
				NSLog(@"TESTING: creating planet shader from:\n%@", shader_info);
				shader_program = [TextureStore shaderProgramFromDictionary:shader_info];
				isShadered = (shader_program != NULL_SHADER);
				normalMapTextureName = [TextureStore getPlanetNormalMapNameFor: planetInfo intoData: &normalMapTextureData];
				NSLog(@"TESTING: planet-surface-shader: %d normalMapTextureName: %d", (int)shader_program, (int)normalMapTextureName);
			}
		}
#endif
#endif
		}
	}
	else
#endif
	{
#ifndef NO_SHADERS
		isShadered = NO;
		shader_program = NULL_SHADER;
#endif
	}
	
	
	[self initialiseBaseVertexArray];
	
	[self initialiseBaseTerrainArray:percent_land];
	
	for (i =  0; i < next_free_vertex; i++)
		[self paintVertex:i :planet_seed];
	
	[self scaleVertices];
	// set speed of rotation	
	if ([dict objectForKey:@"rotational_velocity"])
	{
		rotational_velocity = [dict oo_floatForKey:@"rotational_velocity" defaultValue:0.01f * randf()];	// 0.0 .. 0.01 avr 0.005
	}
	else
	{
		rotational_velocity = [planetInfo oo_floatForKey:@"rotation_speed" defaultValue:0.005 * randf()]; // 0.0 .. 0.005 avr 0.0025
		rotational_velocity *= [planetInfo oo_floatForKey:@"rotation_speed_factor" defaultValue:1.0f];
	}

	// do atmosphere
	atmosphere = atmo ? [[PlanetEntity alloc] initAsAtmosphereForPlanet:self dictionary:dict] : nil;
	
	setRandomSeed(saved_seed);
	RANROTSetFullSeed(ranrotSavedSeed);

	// set energy
	energy = collision_radius * 1000.0;
	
	isPlanet = YES;
	
	root_planet = self;
	
	rotationAxis = kBasisYVector;
	
	return self;
}


- (id) initMoonFromDictionary:(NSDictionary*) dict
{
	return [self initPlanetFromDictionary:dict withAtmosphere:NO andSeed:[UNIVERSE systemSeed]];
}


- (void) dealloc
{
	[atmosphere release];
	if (textureData)  
	{
		free(textureData);
		textureData = NULL;
	}
	if (normalMapTextureData)
	{
		free(normalMapTextureData);
		normalMapTextureData = NULL;
	}
	[super dealloc];
}


- (NSString*) descriptionComponents
{
	NSString *typeString;
	switch (planet_type)
	{
		case PLANET_TYPE_MINIATURE:
			typeString = @"PLANET_TYPE_MINIATURE";	break;
		case PLANET_TYPE_SUN:
			typeString = @"PLANET_TYPE_SUN";	break;
		case PLANET_TYPE_GREEN:
			typeString = @"PLANET_TYPE_GREEN";	break;
		case PLANET_TYPE_ATMOSPHERE:
			typeString = @"PLANET_TYPE_ATMOSPHERE";	break;
		case PLANET_TYPE_MOON:
			typeString = @"PLANET_TYPE_MOON";	break;
		default :
			typeString = @"UNKNOWN";
	}
	return [NSString stringWithFormat:@"ID: %u position: %@ type: %@ radius: %.3fkm", [self universalID], VectorDescription([self position]), typeString, 0.001 * [self radius]];
}


- (BOOL) canCollide
{
	switch (planet_type)
	{
		case PLANET_TYPE_MINIATURE:
		case PLANET_TYPE_ATMOSPHERE:
			return NO;
			break;
		case PLANET_TYPE_MOON:
		case PLANET_TYPE_GREEN:
		case PLANET_TYPE_SUN:
			return YES;
			break;
	}
	return YES;
}


- (BOOL) checkCloseCollisionWith:(Entity *)other
{
#ifndef NDEBUG
	if (gDebugFlags & DEBUG_COLLISIONS)
		OOLog(@"planet.collide", @"PLANET Collision!");
#endif
	
	if (!other)
		return NO;
	if (other->isShip)
	{
		ShipEntity *ship = (ShipEntity *)other;
		if ([ship isShuttle])
		{
			[ship landOnPlanet:self];
			return NO;
		}
#ifndef NDEBUG
		if ([ship reportAIMessages])
		{
			Vector p1 = ship->position;
			OOLog(@"planet.collide.shipHit", @"DEBUG: %@ %d collided with planet at (%.1f,%.1f,%.1f)",[ship name], [ship universalID], p1.x,p1.y,p1.z);
		}
#endif
	}

	return YES;
}


- (void) update:(OOTimeDelta) delta_t
{
	[super update:delta_t];
	sqrt_zero_distance = sqrt(zero_distance);

	switch (planet_type)
	{
		case PLANET_TYPE_MOON:
		case PLANET_TYPE_GREEN:
			{
				double ugt = [UNIVERSE getTime];

				if ((shuttles_on_ground > 0)&&(ugt > last_launch_time + shuttle_launch_interval))
				{
					[self launchShuttle];
					shuttles_on_ground--;
					last_launch_time = ugt;
				}
			}
		
		case PLANET_TYPE_MINIATURE:
			// normal planetary rotation
			//quaternion_rotate_about_y(&orientation, rotational_velocity * delta_t);
			quaternion_rotate_about_axis(&orientation, rotationAxis, rotational_velocity * delta_t);
			[self orientationChanged];
			
			if (atmosphere)
			{
				[atmosphere update:delta_t];
				double alt = sqrt_zero_distance - collision_radius;
				double atmo = 10.0 * (atmosphere->collision_radius - collision_radius);	// effect starts at 10x the height of the clouds

				if ((alt > 0)&&(alt <= atmo))
				{
					double aleph = (atmo - alt) / atmo;
					if (aleph < 0.0) aleph = 0.0;
					if (aleph > 1.0) aleph = 1.0;
					
					[UNIVERSE setSkyColorRed:0.8 * aleph * aleph
									   green:0.8 * aleph * aleph
										blue:0.9 * aleph
									   alpha:aleph];
				}
			}
			break;

		case PLANET_TYPE_ATMOSPHERE:
			{
				// atmospheric rotation
				quaternion_rotate_about_y(&orientation, rotational_velocity * delta_t);
				[self orientationChanged];
			}
			break;
		
		case PLANET_TYPE_SUN:
			{
				PlayerEntity	*player = [PlayerEntity sharedPlayer];
				assert(player != nil);
				rotMatrix = OOMatrixForBillboard(position, [player position]);
				
				if (throw_sparks&&(planet_type == PLANET_TYPE_SUN)&&(velocity.z > 0))	// going NOVA!
				{
					if (velocity.x >= 0.0)	// countdown
					{
						velocity.x -= delta_t;
						if (corona_speed_factor < 5.0)
							corona_speed_factor += 0.75 * delta_t;
					}
					else
					{
						if (velocity.y <= 60.0)	// expand for a minute
						{
							double sky_bri = 1.0 - 1.5 * velocity.y;
							if (sky_bri < 0)
							{
								[UNIVERSE setSkyColorRed:0.0f		// back to black
												   green:0.0f
													blue:0.0f
												   alpha:0.0f];
							}
							else
							{
								[UNIVERSE setSkyColorRed:sky_bri	// whiteout
												   green:sky_bri
													blue:sky_bri
												   alpha:1.0f];
							}
							if (sky_bri == 1.0)
								OOLog(@"sun.nova.start", @"DEBUG: NOVA original radius %.1f", collision_radius);
							amb_land[0] = 1.0;	amb_land[1] = 1.0;	amb_land[2] = 1.0;	amb_land[3] = 1.0;
							velocity.y += delta_t;
							[self setRadius: collision_radius + delta_t * velocity.z];
						}
						else
						{
							OOLog(@"sun.nova.end", @"DEBUG: NOVA final radius %.1f", collision_radius);
							// reset at the new size
							velocity = kZeroVector;
							throw_sparks = YES;	// keep throw_sparks at YES to indicate the higher temperature
						}
					}
				}
				
				// update corona
				if (![UNIVERSE reducedDetail])
				{
					corona_stage += corona_speed_factor * delta_t;
					if (corona_stage > 1.0)
					{
						 int i;
						 corona_stage -= 1.0;
						 for (i = 0; i < 360; i++)
						 {
							rvalue[i] = rvalue[360 + i];
							rvalue[360 + i] = randf();
						 }
					}
				}

			}
			break;
	}
}


- (void) setPosition:(Vector)posn
{
	position = posn;
	if (atmosphere)
		[atmosphere setPosition:posn];
}


- (void) setPosition:(GLfloat) x:(GLfloat) y:(GLfloat) z
{
	position.x = x;
	position.y = y;
	position.z = z;
	if (atmosphere)
		[atmosphere setPosition:position];
}


- (void) setOrientation:(Quaternion)inOrientation
{
	rotationAxis = quaternion_rotate_vector(inOrientation, kBasisYVector);
	[super setOrientation:inOrientation];
}


- (void) setModelName:(NSString *)modelName
{
	double  old_collision_radius = collision_radius;
	[super setModelName:modelName];
	collision_radius = old_collision_radius;	// preserve the radius
}



// TODO: some translucent stuff is drawn in the opaque pass, which is Naughty.
- (void) drawEntity:(BOOL) immediate :(BOOL) translucent;
{
	int		subdivideLevel =	2;		// 4 is probably the maximum!
	
	double  drawFactor = [[UNIVERSE gameView] viewSize].width / 100.0;
	double  drawRatio2 = drawFactor * collision_radius / sqrt_zero_distance; // equivalent to size on screen in pixels

	if ([UNIVERSE breakPatternHide])   return; // DON'T DRAW

	if (zero_distance > 0.0)
	{
		subdivideLevel = 2 + floor(drawRatio2);
		if (subdivideLevel > 4)
			subdivideLevel = 4;
	}
	
	if (planet_type == PLANET_TYPE_MINIATURE)
		subdivideLevel = [UNIVERSE reducedDetail]? 3 : 4 ;		// max detail or less
		
	lastSubdivideLevel = subdivideLevel;	// record
	
	OOGL(glFrontFace(GL_CW));		// face culling - front faces are AntiClockwise!

	/*

	The depth test gets disabled in parts of this and instead
	we rely on the painters algorithm instead.

	The depth buffer isn't granular enough to cope with huge objects at vast
	distances.

	*/
	
	BOOL ignoreDepthBuffer = (planet_type == PLANET_TYPE_ATMOSPHERE);
	
	if (zero_distance > collision_radius * collision_radius * 25) // is 'far away'
		ignoreDepthBuffer |= YES;

	switch (planet_type)
	{
		case PLANET_TYPE_ATMOSPHERE:
			if (root_planet)
			{
				subdivideLevel = root_planet->lastSubdivideLevel;	// copy it from the planet (stops jerky LOD and such)
			}
			GLMultOOMatrix(rotMatrix);	// rotate the clouds!
		case PLANET_TYPE_MOON:
		case PLANET_TYPE_GREEN:
		case PLANET_TYPE_MINIATURE:
			//if ((gDebugFlags & DEBUG_WIREFRAME_GRAPHICS)
			if ([UNIVERSE wireframeGraphics])
			{
				// Drop the detail level a bit, it still looks OK in wireframe and does not penalize
				// the system that much.
				subdivideLevel = 2;
				GLDebugWireframeModeOn();
			}
				
			if (!translucent)
			{
				GLfloat mat1[]		= { 1.0, 1.0, 1.0, 1.0 };	// opaque white

				if (!isTextured)
					OOGL(glDisable(GL_TEXTURE_2D));	// stop any problems from this being left on!
				else
				{
					OOGL(glEnable(GL_TEXTURE_2D));
					OOGL(glTexEnvfv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_COLOR, mat1));
					OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT));	//wrap around horizontally
				}

				OOGL(glShadeModel(GL_SMOOTH));
				
				// far enough away to draw flat ?
				if (ignoreDepthBuffer)
				{
					OOGL(glDisable(GL_DEPTH_TEST));
				}

				OOGL(glColor4fv(mat1));
				OOGL(glMaterialfv(GL_FRONT, GL_AMBIENT_AND_DIFFUSE, mat1));

				OOGL(glFrontFace(GL_CCW));
				if (displayListNames[subdivideLevel] != 0)
				{
					
					OOGL(glDisableClientState(GL_INDEX_ARRAY));
					OOGL(glDisableClientState(GL_EDGE_FLAG_ARRAY));
					
					if (isTextured)
					{
						OOGL(glEnableClientState(GL_COLOR_ARRAY));
						OOGL(glColorPointer(4, GL_FLOAT, 0, vertexdata.color_array));
						
						OOGL(glEnableClientState(GL_TEXTURE_COORD_ARRAY));
						OOGL(glTexCoordPointer(2, GL_FLOAT, 0, vertexdata.uv_array));
						OOGL(glBindTexture(GL_TEXTURE_2D, textureName));
						OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT));	//wrap around horizontally
					}
					else
					{
						OOGL(glDisableClientState(GL_TEXTURE_COORD_ARRAY));
						
						OOGL(glEnableClientState(GL_COLOR_ARRAY));
						OOGL(glColorPointer(4, GL_FLOAT, 0, vertexdata.color_array));
					}
					
					OOGL(glEnableClientState(GL_VERTEX_ARRAY));
					OOGL(glVertexPointer(3, GL_FLOAT, 0, vertexdata.vertex_array));
					OOGL(glEnableClientState(GL_NORMAL_ARRAY));
					OOGL(glNormalPointer(GL_FLOAT, 0, vertexdata.normal_array));
					
					OOGL(glCallList(displayListNames[subdivideLevel]));
					
				}
				else
				{
					OOGL(glDisableClientState(GL_INDEX_ARRAY));
					OOGL(glDisableClientState(GL_EDGE_FLAG_ARRAY));
					
#ifndef NO_SHADERS
					if (isShadered)
					{
						GLint locator;
						OOGL(glUseProgramObjectARB(shader_program));	// shader ON!
						OOGL(glEnableClientState(GL_COLOR_ARRAY));
						OOGL(glColorPointer(4, GL_FLOAT, 0, vertexdata.color_array));
						
						OOGL(glEnableClientState(GL_TEXTURE_COORD_ARRAY));
						OOGL(glTexCoordPointer(2, GL_FLOAT, 0, vertexdata.uv_array));
						
						OOGL(glActiveTextureARB(GL_TEXTURE1_ARB));
						OOGL(glBindTexture(GL_TEXTURE_2D, normalMapTextureName));
						OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT));	//wrap around horizontally
						OOGL(locator = glGetUniformLocationARB(shader_program, "tex1"));
						if (locator == -1)
						{
								OOLogERR(@"planet.shaders.noUniform", @"GLSL couldn't find location of tex0 in shader_program %d", shader_program);
						}
						else
						{
							OOGL(glUniform1iARB(locator, 1));	// associate texture unit number i with texture 1
							
						}
						
						OOGL(glActiveTextureARB(GL_TEXTURE0_ARB));
						OOGL(glBindTexture(GL_TEXTURE_2D, textureName));
						OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT));	//wrap around horizontally
						OOGL(locator = glGetUniformLocationARB(shader_program, "tex0"));
						if (locator == -1)
						{
							OOLogERR(@"planet.shaders.noUniform", @"GLSL couldn't find location of tex0 in shader_program %d", shader_program);
						}
						else
						{
							OOGL(glUniform1iARB(locator, 0));// associate texture unit number i with texture 0
							
						}
					}
					else
#endif
					{
						if (isTextured)
						{
							OOGL(glEnableClientState(GL_COLOR_ARRAY));		// test shading
							OOGL(glColorPointer(4, GL_FLOAT, 0, vertexdata.color_array));
							
							OOGL(glEnableClientState(GL_TEXTURE_COORD_ARRAY));
							OOGL(glTexCoordPointer(2, GL_FLOAT, 0, vertexdata.uv_array));
							OOGL(glBindTexture(GL_TEXTURE_2D, textureName));
							OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT));	//wrap around horizontally
						}
						else
						{
							OOGL(glDisableClientState(GL_TEXTURE_COORD_ARRAY));
							
							OOGL(glEnableClientState(GL_COLOR_ARRAY));
							OOGL(glColorPointer(4, GL_FLOAT, 0, vertexdata.color_array));
						}
					}
					
					OOGL(glEnableClientState(GL_VERTEX_ARRAY));
					OOGL(glVertexPointer(3, GL_FLOAT, 0, vertexdata.vertex_array));
					OOGL(glEnableClientState(GL_NORMAL_ARRAY));
					OOGL(glNormalPointer(GL_FLOAT, 0, vertexdata.normal_array));
					
#ifndef NO_SHADERS
					if (isShadered)
					{
						OOGL(glColor4fv(mat1));
						OOGL(glMaterialfv(GL_FRONT, GL_AMBIENT_AND_DIFFUSE, mat1));
						OOGL(glColorMaterial(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE));
						OOGL(glEnable(GL_COLOR_MATERIAL));
						
						[self drawModelWithVertexArraysAndSubdivision:subdivideLevel];
						
						OOGL(glDisable(GL_COLOR_MATERIAL));
						OOGL(glUseProgramObjectARB(NULL_SHADER));	// shader OFF
					}
					else
#endif
					{
						OOGL(displayListNames[subdivideLevel] = glGenLists(1));
						if (displayListNames[subdivideLevel] != 0)	// sanity check
						{
							OOGL(glNewList(displayListNames[subdivideLevel], GL_COMPILE));
							
							OOGL(glColor4fv(mat1));
							OOGL(glMaterialfv(GL_FRONT, GL_AMBIENT_AND_DIFFUSE, mat1));
							OOGL(glColorMaterial(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE));
							OOGL(glEnable(GL_COLOR_MATERIAL));
							
							[self drawModelWithVertexArraysAndSubdivision:subdivideLevel];
							
							OOGL(glDisable(GL_COLOR_MATERIAL));
							OOGL(glEndList());
						}
					}
					
				}
				OOGL(glFrontFace(GL_CW));

				OOGL(glMaterialfv(GL_FRONT, GL_AMBIENT_AND_DIFFUSE, mat1));


				if (atmosphere)
				{
					OOGL(glDisable(GL_DEPTH_TEST));

					OOGL(glPopMatrix());	// get old draw matrix back
					OOGL(glPushMatrix());	// and store it again
					OOGL(glTranslatef(position.x,position.y,position.z)); // centre on the planet
					// rotate
					GLMultOOMatrix([atmosphere rotationMatrix]);
					// draw atmosphere entity
					[atmosphere drawEntity:immediate :translucent];

					OOGL(glEnable(GL_DEPTH_TEST));
				}
				else if (ignoreDepthBuffer)
				{
					OOGL(glEnable(GL_DEPTH_TEST));
				}

			}
			
			//if ((gDebugFlags & DEBUG_WIREFRAME_GRAPHICS)
			if ([UNIVERSE wireframeGraphics])
			{
				GLDebugWireframeModeOff();
			}
			break;

		case PLANET_TYPE_SUN:
			if (!translucent)
			{
				int steps = 2 * (MAX_SUBDIVIDE - subdivideLevel);

				// far enough away to draw flat ?
				if (ignoreDepthBuffer)
				{
					OOGL(glDisable(GL_DEPTH_TEST));
				}

				OOGL(glDisable(GL_TEXTURE_2D));
				OOGL(glDisable(GL_LIGHTING));
				OOGL(glColor4fv(amb_land));
				
				// FIXME: use vertex arrays
				OOGLBEGIN(GL_TRIANGLE_FAN);
					GLDrawBallBillboard(collision_radius, steps, sqrt_zero_distance);
				OOGLEND();

				if (![UNIVERSE reducedDetail])
				{
					OOGL(glDisable(GL_DEPTH_TEST));
					if (zero_distance < lim4k)
					{
						GLfloat col1[4] = { amb_polar_land[0], amb_polar_land[1], amb_polar_land[2], 0.75};
						drawActiveCorona(collision_radius, collision_radius + cor4k, steps, sqrt_zero_distance, col1, 6);
					}
					if (zero_distance < lim8k)
					{
						GLfloat col1[4] = { amb_sea[0], amb_sea[1], amb_sea[2], 0.625};
						drawActiveCorona(collision_radius, collision_radius + cor8k, steps, sqrt_zero_distance, col1, 3);
					}
					if (zero_distance < lim16k)
					{
						GLfloat col1[4] = { amb_polar_sea[0], amb_polar_sea[1], amb_polar_sea[2], 0.5};
						drawActiveCorona(collision_radius, collision_radius + cor16k, steps, sqrt_zero_distance, col1, 0);
					}
					OOGL(glEnable(GL_DEPTH_TEST));
				}
				OOGL(glEnable(GL_LIGHTING));

				// far enough away to draw flat ?
				if (ignoreDepthBuffer)
				{
					OOGL(glEnable(GL_DEPTH_TEST));
				}

			}
			break;
	}
	OOGL(glFrontFace(GL_CCW));			// face culling - front faces are AntiClockwise!
	CheckOpenGLErrors(@"PlanetEntity after drawing %@", self);
}


void drawActiveCorona(GLfloat inner_radius, GLfloat outer_radius, GLfloat step, GLfloat z_distance, GLfloat *col4v1, int rv)
{
	if (EXPECT_NOT(inner_radius >= z_distance))  return;	// inside the sphere
	
	NSRange activity = { 0.34, 1.0 };
	
	GLfloat				si, ci;
	GLfloat				s0, c0, s1, c1;
	
	GLfloat				r = inner_radius;
	GLfloat				c = outer_radius;
	GLfloat				z = z_distance;
	GLfloat				x = sqrt(z * z - r * r);
	
	GLfloat				r1 = r * x / z;
	GLfloat				z1 = r * r / z;
	
	GLfloat				r0 = c * x / z;
	GLfloat				z0 = c * r / z;
	
	GLfloat				rv0, rv1, rv2;
	GLfloat				pt0, pt1;
	
	unsigned short		i;
	GLfloat				theta = 0.0f, delta;
	
	delta = step * M_PI / 180.0f;	// Convert step from degrees to radians
	pt0=(1.0 - corona_stage) * corona_blending;
	pt1=corona_stage * corona_blending;
	
	OOGL(glShadeModel(GL_SMOOTH));
	OOGLBEGIN(GL_TRIANGLE_STRIP);
		for (i = 0; i < 360; i += step)
		{
			si = sinf(theta);
			ci = cosf(theta);
			theta += delta;
			
			rv0 = pt0 * rvalue[i + rv] + pt1 * rvalue[i + rv + 360];
			rv1 = pt0 * rvalue[i + rv + 1] + pt1 * rvalue[i + rv + 361];
			rv2 = pt0 * rvalue[i + rv + 2] + pt1 * rvalue[i + rv + 362];

			s1 = r1 * si;
			c1 = r1 * ci;
			glColor4f(col4v1[0] * (activity.location + rv0*activity.length), col4v1[1] * (activity.location + rv1*activity.length), col4v1[2] * (activity.location + rv2*activity.length), col4v1[3]);
			glVertex3f(s1, c1, -z1);

			s0 = r0 * si;
			c0 = r0 * ci;
			glColor4f(col4v1[0], col4v1[1], col4v1[2], 0);
			glVertex3f(s0, c0, -z0);
		}
	
		rv0 = pt0 * rvalue[rv] + pt1 * rvalue[360 + rv];
		rv1 = pt0 * rvalue[1 + rv] + pt1 * rvalue[361 + rv];
		rv2 = pt0 * rvalue[2 + rv] + pt1 * rvalue[362 + rv];
		
		glColor4f(col4v1[0] * (activity.location + rv0*activity.length), col4v1[1] * (activity.location + rv1*activity.length), col4v1[2] * (activity.location + rv2*activity.length), col4v1[3]);
		glVertex3f(0.0, r1, -z1);	//repeat the zero value to close
		glColor4f(col4v1[0], col4v1[1], col4v1[2], 0);
		glVertex3f(0.0, r0, -z0);	//repeat the zero value to close
	OOGLEND();
}


- (int*) r_seed
{
	return r_seed;
}


- (int) planet_seed
{
	return planet_seed;
}


- (BOOL) isTextured
{
	return isTextured;
}


- (GLuint) textureName
{
	return textureName;
}


- (NSString *) textureFileName
{
	return textureFile;
}


- (BOOL) changeSunProperty:(NSString *)key withDictionary:(NSDictionary*) dict
{
	id	object = [dict objectForKey:key];
	static GLfloat oldRadius = 0.0;
	if ([key isEqualToString:@"sun_radius"])
	{
		oldRadius =	[object doubleValue];	// clamp corona_flare in case planetinfo.plist / savegame contains the wrong value
		[self setRadius: oldRadius + (0.66*MAX_CORONAFLARE * OOClamp_0_1_f([dict oo_floatForKey:@"corona_flare" defaultValue:0.0f]))];
		collision_radius = oldRadius;								
	}
	else if ([key isEqualToString:@"corona_flare"])
	{
		double rad = collision_radius;
		[self setRadius: rad + (0.66*MAX_CORONAFLARE * OOClamp_0_1_f([object floatValue]))];
		collision_radius = rad;
	}
	else if ([key isEqualToString:@"corona_shimmer"])
	{
		corona_speed_factor=OOClamp_0_1_f([object floatValue]) * 2.0 + randf() * randf();
	}
	else if ([key isEqualToString:@"corona_hues"])
	{
		corona_blending=OOClamp_0_1_f([object floatValue]);
	}
	else if ([key isEqualToString:@"sun_gone_nova"])
	{

		if ([dict oo_boolForKey:key])
		{
			[self setGoingNova:YES inTime:0];
		}
		else
		{
			[self setGoingNova:NO inTime:0];
			// oldRadius is always the radius we had before going nova...
			[self setRadius: oldRadius + (0.66*MAX_CORONAFLARE * OOClamp_0_1_f([dict oo_floatForKey:@"corona_flare" defaultValue:0.0f]))];
			collision_radius = oldRadius;

		}
	}
	else
	{
		OOLogWARN(@"script.warning", @"Change to property '%@' not applied, will apply only after leaving this system.",key);
		return NO;
	}
	return YES;
}


- (void) setTextureColorForPlanet:(BOOL)isMain inSystem:(BOOL)isLocal
{	
	Vector land_hsb, land_polar_hsb;
	land_hsb.x = 0.0;	land_hsb.y = 0.0;	land_hsb.z = 1.0;	// white
	
	// the colour override should only apply to main planets
	if (isMain)
	{
		if (isLocal)
			ScanVectorFromString([[UNIVERSE currentSystemData] objectForKey:@"texture_hsb_color"], &land_hsb);
		else
			ScanVectorFromString([[UNIVERSE generateSystemData:[[PlayerEntity sharedPlayer] target_system_seed]] objectForKey:@"texture_hsb_color"], &land_hsb);
	}
	
	land_polar_hsb.x = land_hsb.x;  land_polar_hsb.y = (land_hsb.y / 5.0);  land_polar_hsb.z = 1.0 - (land_hsb.z / 10.0);
	
	amb_sea[0] = amb_land[0] = [[OOColor colorWithCalibratedHue:land_hsb.x saturation:land_hsb.y brightness:land_hsb.z alpha:1.0] redComponent];
	amb_sea[1] = amb_land[1] = [[OOColor colorWithCalibratedHue:land_hsb.x saturation:land_hsb.y brightness:land_hsb.z alpha:1.0] blueComponent];
	amb_sea[2] = amb_land[2] = [[OOColor colorWithCalibratedHue:land_hsb.x saturation:land_hsb.y brightness:land_hsb.z alpha:1.0] greenComponent];
	amb_sea[3] = amb_land[3] = 1.0;
	amb_polar_sea[0] =amb_polar_land[0] = [[OOColor colorWithCalibratedHue:land_polar_hsb.x saturation:land_polar_hsb.y brightness:land_polar_hsb.z alpha:1.0] redComponent];
	amb_polar_sea[1] =amb_polar_land[1] = [[OOColor colorWithCalibratedHue:land_polar_hsb.x saturation:land_polar_hsb.y brightness:land_polar_hsb.z alpha:1.0] blueComponent];
	amb_polar_sea[2] = amb_polar_land[2] = [[OOColor colorWithCalibratedHue:land_polar_hsb.x saturation:land_polar_hsb.y brightness:land_polar_hsb.z alpha:1.0] greenComponent];
	amb_polar_sea[3] =amb_polar_land[3] = 1.0;
}


- (BOOL) setUpPlanetFromTexture:(NSString *)fileName
{
	GLuint tName=[TextureStore getTextureNameFor:fileName];
	if (tName == 0) return NO;
	int		i;
	BOOL wasTextured=isTextured;
	//if(!!textureFile) [textureFile release];
	textureFile=[[NSString stringWithString:fileName] retain];
	textureName = tName;
	isTextureImage = isTextured = YES;

#if ALLOW_PROCEDURAL_PLANETS
	// We always need to reset the model in order to repaint it - otherwise if someone
	// has specified colour overrides in an OXP, those overrides affect the texture!
	// What if someone -wants- to re-colour a planetary texture using an OXP?
	// -- Micha 20090419
	//if (![UNIVERSE doProcedurallyTexturedPlanets])
#endif
	{
		[self setModelName:@"icostextured.dat" ];
		[self rescaleTo:1.0];
		for (i = 0; i < vertexCount; i++) r_seed[i] = 0;  // land
		// recolour main planet according to "texture_hsb_color"
		// this function is only called for local systems!
		[self setTextureColorForPlanet:([UNIVERSE planet] == self) inSystem:YES];

		[self initialiseBaseVertexArray];
		[self initialiseBaseTerrainArray:100];
		for (i =  0; i < next_free_vertex; i++)
			[self paintVertex:i :planet_seed];
	}

	if(wasTextured)
	{
		if (textureData)
		{
			free(textureData);
			textureData = NULL;
		}
		if (normalMapTextureData)
		{
			free(normalMapTextureData);
			normalMapTextureData = NULL;
		}
	}
	[self scaleVertices];

	NSMutableDictionary *atmo_dictionary = [NSMutableDictionary dictionary];
	[atmo_dictionary setObject:[NSNumber numberWithInt:0] forKey:@"percent_cloud"];
	[atmosphere autorelease];
	atmosphere = [[PlanetEntity alloc] initAsAtmosphereForPlanet:self dictionary:atmo_dictionary];

	rotationAxis = kBasisYVector;

	return isTextured;
}

- (double) polar_color_factor
{
	return polar_color_factor;
}


- (GLfloat *) amb_land
{
	return amb_land;
}


- (GLfloat *) amb_polar_land
{
	return amb_polar_land;
}


- (GLfloat *) amb_sea
{
	return amb_sea;
}


- (GLfloat *) amb_polar_sea
{
	return amb_polar_sea;
}


- (OOPlanetType) planetType
{
	return planet_type;
}


- (void) setPlanetType:(OOPlanetType) pt
{
	planet_type = pt;
}


- (double) radius
{
	return collision_radius;
}


- (void) setRadius:(double) rad
{
	collision_radius = rad;
	cor4k =		rad * 4 / 100;				lim4k =		cor4k	* cor4k	* NO_DRAW_DISTANCE_FACTOR*NO_DRAW_DISTANCE_FACTOR;
	cor8k =		rad * 8 / 100;				lim8k =		cor8k	* cor8k	* NO_DRAW_DISTANCE_FACTOR*NO_DRAW_DISTANCE_FACTOR;
	cor16k =	rad * rad * 16/ 10000000;	lim16k =	cor16k	* cor16k* NO_DRAW_DISTANCE_FACTOR*NO_DRAW_DISTANCE_FACTOR;
}


- (double) sqrtZeroDistance
{
	return sqrt_zero_distance;
}


- (void) rescaleTo:(double) rad
{
	int i;
	
	for (i = 0; i < vertexCount; i++)
	{
		vertices[i] = vector_multiply_scalar(vector_normal(vertices[i]), rad);
	}
}


- (BOOL) hasAtmosphere
{
	return atmosphere != nil;
}


- (void) drawModelWithVertexArraysAndSubdivision: (int) subdivide
{
	OOGL(glDrawElements(GL_TRIANGLES, 3 * n_triangles[subdivide], GL_UNSIGNED_INT, &vertexdata.index_array[triangle_start[subdivide]]));
}


- (void) launchShuttle
{
	ShipEntity  *shuttle_ship;
	Quaternion  q1;
	Vector		launch_pos = position;
	double		start_distance = collision_radius + 125.0;

	quaternion_set_random(&q1);

	Vector vf = vector_forward_from_quaternion(q1);

	launch_pos.x += start_distance * vf.x;
	launch_pos.y += start_distance * vf.y;
	launch_pos.z += start_distance * vf.z;

	shuttle_ship = [UNIVERSE newShipWithRole:@"shuttle"];   // retain count = 1
	if (shuttle_ship)
	{
		if (![shuttle_ship crew])
			[shuttle_ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: @"trader"
				andOriginalSystem: [UNIVERSE systemSeed]]]];
				
		[shuttle_ship setPosition:launch_pos];
		[shuttle_ship setOrientation:q1];

		[shuttle_ship setScanClass: CLASS_NEUTRAL];

		[shuttle_ship setCargoFlag:CARGO_FLAG_FULL_PLENTIFUL];

		[shuttle_ship setStatus:STATUS_IN_FLIGHT];

		[UNIVERSE addEntity:shuttle_ship];
		[[shuttle_ship getAI] setStateMachine:@"risingShuttleAI.plist"];	// must happen after adding to the universe!

		[shuttle_ship release];
	}
}


- (void) welcomeShuttle:(ShipEntity *) shuttle
{
	shuttles_on_ground++;
}


+ (void) resetBaseVertexArray
{
	if (edge_to_vertex)
		[edge_to_vertex release];
	edge_to_vertex = nil;
}


static BOOL last_one_was_textured;

- (void) initialiseBaseVertexArray
{
	int i;
	NSAutoreleasePool* mypool = [[NSAutoreleasePool alloc] init];	// use our own pool since this routine is quite hard on memory

	if (last_one_was_textured != isTextured)
	{
		[PlanetEntity resetBaseVertexArray];
		last_one_was_textured = isTextured;
	}
	
	if (edge_to_vertex == nil)
	{
		edge_to_vertex = [[NSMutableDictionary dictionaryWithCapacity:7680] retain];	// make a new one

		int vi,fi;
		next_free_vertex = 0;
		
		// set first 12 or 14 vertices
		
		for (vi = 0; vi < vertexCount; vi++)
			base_vertex_array[next_free_vertex++] =  vertices[vi];
		
		// set first 20 triangles
		
		triangle_start[0] = 0;
		n_triangles[0] = faceCount;
		for (fi = 0; fi < faceCount; fi++)
		{
			vertex_index_array[fi * 3 + 0] = faces[fi].vertex[0];
			vertex_index_array[fi * 3 + 1] = faces[fi].vertex[1];
			vertex_index_array[fi * 3 + 2] = faces[fi].vertex[2];
			if (isTextured)
			{
				texture_uv_array[faces[fi].vertex[0] * 2]		= faces[fi].s[0];
				texture_uv_array[faces[fi].vertex[0] * 2 + 1]	= faces[fi].t[0];
				texture_uv_array[faces[fi].vertex[1] * 2]		= faces[fi].s[1];
				texture_uv_array[faces[fi].vertex[1] * 2 + 1]	= faces[fi].t[1];
				texture_uv_array[faces[fi].vertex[2] * 2]		= faces[fi].s[2];
				texture_uv_array[faces[fi].vertex[2] * 2 + 1]	= faces[fi].t[2];
			}
		}
		
		// for the next levels of subdivision simply build up from the level below!...
		
		int sublevel;
		for (sublevel = 0; sublevel < MAX_SUBDIVIDE - 1; sublevel++)
		{
			int newlevel = sublevel + 1;
			triangle_start[newlevel] = triangle_start[sublevel] + n_triangles[sublevel] * 3;
			n_triangles[newlevel] = n_triangles[sublevel] * 4;

			int tri;
			for (tri = 0; tri < n_triangles[sublevel]; tri++)
			{
				// get the six vertices for this group of four triangles
				int v0 = vertex_index_array[triangle_start[sublevel] + tri * 3 + 0];
				int v1 = vertex_index_array[triangle_start[sublevel] + tri * 3 + 1];
				int v2 = vertex_index_array[triangle_start[sublevel] + tri * 3 + 2];
				int v01 = baseVertexIndexForEdge(v0, v1, isTextured);	// sets it up if required
				int v12 = baseVertexIndexForEdge(v1, v2, isTextured);	// ..
				int v20 = baseVertexIndexForEdge(v2, v0, isTextured);	// ..
				// v0 v01 v20
				vertex_index_array[triangle_start[newlevel] + tri * 12 + 0] = v0;
				vertex_index_array[triangle_start[newlevel] + tri * 12 + 1] = v01;
				vertex_index_array[triangle_start[newlevel] + tri * 12 + 2] = v20;
				// v01 v1 v12
				vertex_index_array[triangle_start[newlevel] + tri * 12 + 3] = v01;
				vertex_index_array[triangle_start[newlevel] + tri * 12 + 4] = v1;
				vertex_index_array[triangle_start[newlevel] + tri * 12 + 5] = v12;
				// v20 v12 v2
				vertex_index_array[triangle_start[newlevel] + tri * 12 + 6] = v20;
				vertex_index_array[triangle_start[newlevel] + tri * 12 + 7] = v12;
				vertex_index_array[triangle_start[newlevel] + tri * 12 + 8] = v2;
				// v01 v12 v20
				vertex_index_array[triangle_start[newlevel] + tri * 12 + 9] = v01;
				vertex_index_array[triangle_start[newlevel] + tri * 12 +10] = v12;
				vertex_index_array[triangle_start[newlevel] + tri * 12 +11] = v20;

			}
		}
	}
	
	// all done - copy the indices to the instance
	for (i = 0; i < MAX_TRI_INDICES; i++)
		vertexdata.index_array[i] = vertex_index_array[i];

	[mypool release];
}


int baseVertexIndexForEdge(int va, int vb, BOOL textured)
{
	NSString* key = [[NSString alloc] initWithFormat:@"%d:%d", (va < vb)? va:vb, (va < vb)? vb:va];
	NSObject* num = [edge_to_vertex objectForKey:key];
	if (num)
	{
		[key release];
		return [(NSNumber*)num intValue];
	}
	else
	{
		int vindex = next_free_vertex++;

		// calculate position of new vertex
		base_vertex_array[vindex] = base_vertex_array[va];
		base_vertex_array[vindex].x += base_vertex_array[vb].x;
		base_vertex_array[vindex].y += base_vertex_array[vb].y;
		base_vertex_array[vindex].z += base_vertex_array[vb].z;
		base_vertex_array[vindex] = vector_normal(base_vertex_array[vindex]);	// guaranteed non-zero

		if (textured)
		{
			//calculate new texture coordinates
			
			NSPoint	uva = NSMakePoint(texture_uv_array[va * 2], texture_uv_array[va * 2 + 1]);
			NSPoint	uvb = NSMakePoint(texture_uv_array[vb * 2], texture_uv_array[vb * 2 + 1]);
			
			// if either of these is the polar vertex treat it specially to help with polar distortion:
			if ((uva.y == 0.0)||(uva.y == 1.0))
				uva.x = uvb.x;
			if ((uvb.y == 0.0)||(uvb.y == 1.0))
				uvb.x = uva.x;
			
			texture_uv_array[vindex * 2] = 0.5 * (uva.x + uvb.x);
			texture_uv_array[vindex * 2 + 1] = 0.5 * (uva.y + uvb.y);
		}
		
		// add new edge to the look-up
		[edge_to_vertex setObject:[NSNumber numberWithInt:vindex] forKey:key];
		[key release];
		return vindex;
	}
}


- (void) initialiseBaseTerrainArray:(int) percent_land
{
	int vi;
	// set first 12 or 14 vertices
	if (percent_land >= 0)
	{
		for (vi = 0; vi < vertexCount; vi++)
		{
			if (gen_rnd_number() < 256 * percent_land / 100)
				base_terrain_array[vi] = 0;  // land
			else
				base_terrain_array[vi] = 100;  // sea

		}
	}
	
	// for the next levels of subdivision simply build up from the level below!...
	
	int sublevel;
	for (sublevel = 0; sublevel < MAX_SUBDIVIDE - 1; sublevel++)
	{
		int tri;
		for (tri = 0; tri < n_triangles[sublevel]; tri++)
		{
			// get the six vertices for this group of four triangles
			int v0 = vertex_index_array[triangle_start[sublevel] + tri * 3 + 0];
			int v1 = vertex_index_array[triangle_start[sublevel] + tri * 3 + 1];
			int v2 = vertex_index_array[triangle_start[sublevel] + tri * 3 + 2];
			int v01 = baseVertexIndexForEdge(v0, v1, isTextured);	// sets it up if required
			int v12 = baseVertexIndexForEdge(v1, v2, isTextured);	// ..
			int v20 = baseVertexIndexForEdge(v2, v0, isTextured);	// ..
			// v01
			if (base_terrain_array[v0] == base_terrain_array[v1])
				base_terrain_array[v01] = base_terrain_array[v0];
			else
			{
				int s1 = 0xffff0000 * base_vertex_array[v01].x;
				int s2 = 0x00ffff00 * base_vertex_array[v01].y;
				int s3 = 0x0000ffff * base_vertex_array[v01].z;
				ranrot_srand(s1+s2+s3);
				base_terrain_array[v01] = (ranrot_rand() & 4) *25;
			}
			// v12
			if (base_terrain_array[v1] == base_terrain_array[v2])
				base_terrain_array[v12] = base_terrain_array[v1];
			else
			{
				int s1 = 0xffff0000 * base_vertex_array[v12].x;
				int s2 = 0x00ffff00 * base_vertex_array[v12].y;
				int s3 = 0x0000ffff * base_vertex_array[v12].z;
				ranrot_srand(s1+s2+s3);
				base_terrain_array[v12] = (ranrot_rand() & 4) *25;
			}
			// v20
			if (base_terrain_array[v2] == base_terrain_array[v0])
				base_terrain_array[v20] = base_terrain_array[v2];
			else
			{
				int s1 = 0xffff0000 * base_vertex_array[v20].x;
				int s2 = 0x00ffff00 * base_vertex_array[v20].y;
				int s3 = 0x0000ffff * base_vertex_array[v20].z;
				ranrot_srand(s1+s2+s3);
				base_terrain_array[v20] = (ranrot_rand() & 4) *25;
			}
		}
	}
}


- (void) paintVertex:(int) vi :(int) seed
{
	GLfloat paint_land[4] = { 0.2, 0.9, 0.0, 1.0};
	GLfloat paint_sea[4] = { 0.0, 0.2, 0.9, 1.0};
	GLfloat paint_color[4];
	Vector	v = base_vertex_array[vi];
	int		r = (isTextured)? 0 : base_terrain_array[vi];	// use land color (0) for textured planets
	int i;
	double pole_blend = v.z * v.z * polar_color_factor;
	if (pole_blend < 0.0)	pole_blend = 0.0;
	if (pole_blend > 1.0)	pole_blend = 1.0;
	
	paint_land[0] = (1.0 - pole_blend)*amb_land[0] + pole_blend*amb_polar_land[0];
	paint_land[1] = (1.0 - pole_blend)*amb_land[1] + pole_blend*amb_polar_land[1];
	paint_land[2] = (1.0 - pole_blend)*amb_land[2] + pole_blend*amb_polar_land[2];
	paint_sea[0] = (1.0 - pole_blend)*amb_sea[0] + pole_blend*amb_polar_sea[0];
	paint_sea[1] = (1.0 - pole_blend)*amb_sea[1] + pole_blend*amb_polar_sea[1];
	paint_sea[2] = (1.0 - pole_blend)*amb_sea[2] + pole_blend*amb_polar_sea[2];
	if (planet_type == PLANET_TYPE_ATMOSPHERE)	// do alphas
	{
		paint_land[3] = (1.0 - pole_blend)*amb_land[3] + pole_blend*amb_polar_land[3];
		paint_sea[3] = (1.0 - pole_blend)*amb_sea[3] + pole_blend*amb_polar_sea[3];
	}
	
	ranrot_srand(seed+v.x*1000+v.y*100+v.z*10);
	
	for (i = 0; i < 3; i++)
	{
		double cv = (ranrot_rand() % 100)*0.01;	//  0..1 ***** DON'T CHANGE THIS LINE, '% 100' MAY NOT BE EFFICIENT BUT THE PATTERNING IS GOOD.
		paint_land[i] += (cv - 0.5)*0.1;
		paint_sea[i] += (cv - 0.5)*0.1;
	}
	
	for (i = 0; i < 4; i++)
	{
		if (planet_type == PLANET_TYPE_ATMOSPHERE && isTextured)
			paint_color[i] = 1.0;
		else
			paint_color[i] = (r * paint_sea[i])*0.01 + ((100 - r) * paint_land[i])*0.01;
		// finally initialise the color array entry
		vertexdata.color_array[vi*4 + i] = paint_color[i];
	}
}


- (void) scaleVertices
{
	int vi;
	for (vi = 0; vi < next_free_vertex; vi++)
	{
		Vector	v = base_vertex_array[vi];
		vertexdata.normal_array[vi] = v;
		vertexdata.vertex_array[vi] = make_vector(v.x * collision_radius, v.y * collision_radius, v.z * collision_radius);
		
		vertexdata.uv_array[vi * 2] = texture_uv_array[vi * 2];
		vertexdata.uv_array[vi * 2 + 1] = texture_uv_array[vi * 2 + 1];
	}
}


double longitudeFromVector(Vector v)
{
	double lon = 0.0;
	if (v.z != 0.0)
	{
		if (v.z > 0)
			lon = -atan(v.x / v.z);
		else
			lon = -M_PI - atan(v.x / v.z);
	}
	else
	{
		if (v.x > 0)
			lon = -0.5 * M_PI;
		else
			lon = -1.5 * M_PI;
	}
	while (lon < 0)
		lon += 2 * M_PI;
	return lon;
}


- (BOOL) willGoNova
{
	return throw_sparks;
}


- (BOOL) goneNova
{
	return throw_sparks && velocity.x <= 0;
}


- (void) setGoingNova:(BOOL) yesno inTime:(double)interval
{
	throw_sparks = yesno;
	if (throw_sparks)
	{
		OOLog(@"script.debug.setSunNovaIn", @"NOVA activated! time until Nova : %.1f s", interval);
		velocity.x = fmax(interval, 0.0);
	}
	
	velocity.y = 0;
	velocity.z = 10000;
}

@end
