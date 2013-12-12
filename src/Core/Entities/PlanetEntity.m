/*

PlanetEntity.m

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

#import "PlanetEntity.h"

#if !NEW_PLANETS

#import "OOOpenGLExtensionManager.h"

#import "Universe.h"
#import "AI.h"
#import "TextureStore.h"
#import "OOTexture.h"
#import "OOTextureInternal.h"	// For GL_TEXTURE_CUBE_MAP -- need to clean this up.
#import "OOPixMapTextureLoader.h"
#import "MyOpenGLView.h"
#import "ShipEntityAI.h"
#import "OOColor.h"
#import "OOCharacter.h"
#import "OOStringParsing.h"
#import "PlayerEntity.h"
#import "OOCollectionExtractors.h"
#import "OODebugFlags.h"
#import "OOGraphicsResetManager.h"


#if !OOLITE_MAC_OS_X
#define NSIntegerMapKeyCallBacks	NSIntMapKeyCallBacks
#define NSIntegerMapValueCallBacks	NSIntMapValueCallBacks
#endif


// straight C
static Vector base_vertex_array[MAX_PLANET_VERTICES];
static int base_terrain_array[MAX_PLANET_VERTICES];
static unsigned next_free_vertex;
static NSMapTable *sEdgeToVertex;

static int n_triangles[MAX_SUBDIVIDE];
static int triangle_start[MAX_SUBDIVIDE];
static GLuint vertex_index_array[3*(20+80+320+1280+5120+20480)];

static GLfloat	texture_uv_array[MAX_PLANET_VERTICES * 2];


@interface PlanetEntity (OOPrivate) <OOGraphicsResetClient>

- (double) sqrtZeroDistance;

- (void) drawModelWithVertexArraysAndSubdivision: (int) subdivide;

- (void) initialiseBaseVertexArray;


- (void) initialiseBaseTerrainArray:(int) percent_land;
- (void) paintVertex:(unsigned) vi :(int) seed;
- (void) scaleVertices;

- (id) initAsAtmosphereForPlanet:(PlanetEntity *)planet dictionary:(NSDictionary *)dict;
- (void) setTextureColorForPlanet:(BOOL)isMain inSystem:(BOOL)isLocal;

- (id) initMiniatureFromPlanet:(PlanetEntity*) planet withAlpha:(float) alpha;

- (void) loadTexture:(NSDictionary *)configuration;
- (OOTexture *) planetTextureWithInfo:(NSDictionary *)info;
- (OOTexture *) cloudTextureWithCloudColor:(OOColor *)cloudColor cloudImpress:(GLfloat)cloud_impress cloudBias:(GLfloat)cloud_bias;

- (void) deleteDisplayLists;

- (void) setUseTexturedModel:(BOOL)flag;

@end

static unsigned baseVertexIndexForEdge(GLushort va, GLushort vb, BOOL textured);


typedef struct
{
	unsigned			v;
	float				s;
	float				t;
} BaseFace;


static const Vector kUntexturedVertices[] =
{
	{ +0.000000, -0.850664, -0.525710 },
	{ +0.000000, -0.850664, +0.525710 },
	{ +0.000000, +0.850664, +0.525710 },
	{ +0.000000, +0.850664, -0.525710 },
	{ -0.525710, +0.000000, -0.850664 },
	{ +0.525710, +0.000000, -0.850664 },
	{ +0.525710, +0.000000, +0.850664 },
	{ -0.525710, +0.000000, +0.850664 },
	{ -0.850664, -0.525710, +0.000000 },
	{ -0.850664, +0.525710, +0.000000 },
	{ +0.850664, +0.525710, +0.000000 },
	{ +0.850664, -0.525710, +0.000000 }
};

static const BaseFace kUntexturedFaces[][3] =
{
	{ {  9, +0.600000, +0.666667 }, {  7, +0.800000, +0.666667 }, {  8, +0.800000, +0.333333 } },
	{ {  8, +0.800000, +0.333333 }, {  4, +0.600000, +0.333333 }, {  9, +0.600000, +0.666667 } },
	{ {  3, +0.400000, +0.666667 }, {  9, +0.600000, +0.666667 }, {  4, +0.600000, +0.333333 } },
	{ {  8, +0.800000, +0.333333 }, {  0, +0.500000, +0.000000 }, {  4, +0.600000, +0.333333 } },
	{ {  7, +0.800000, +0.666667 }, {  1, +1.000000, +0.333333 }, {  8, +0.800000, +0.333333 } },
	{ {  2, +0.500000, +1.000000 }, {  7, +0.800000, +0.666667 }, {  9, +0.600000, +0.666667 } },
	{ {  2, +0.500000, +1.000000 }, {  9, +0.600000, +0.666667 }, {  3, +0.400000, +0.666667 } },
	{ {  1, +1.000000, +0.333333 }, {  0, +0.500000, +0.000000 }, {  8, +0.800000, +0.333333 } },
	{ {  4, +0.600000, +0.333333 }, {  0, +0.500000, +0.000000 }, {  5, +0.400000, +0.333333 } },
	{ {  5, +0.400000, +0.333333 }, {  3, +0.400000, +0.666667 }, {  4, +0.600000, +0.333333 } },
	{ {  6, +1.000000, +0.666667 }, {  1, +1.000000, +0.333333 }, {  7, +0.800000, +0.666667 } },
	{ {  7, +0.800000, +0.666667 }, {  2, +0.500000, +1.000000 }, {  6, +1.000000, +0.666667 } },
	{ {  1, +0.000000, +0.333333 }, { 11, +0.200000, +0.333333 }, {  0, +0.500000, +0.000000 } },
	{ {  3, +0.400000, +0.666667 }, { 10, +0.200000, +0.666667 }, {  2, +0.500000, +1.000000 } },
	{ {  0, +0.500000, +0.000000 }, { 11, +0.200000, +0.333333 }, {  5, +0.400000, +0.333333 } },
	{ {  5, +0.400000, +0.333333 }, { 10, +0.200000, +0.666667 }, {  3, +0.400000, +0.666667 } },
	{ {  1, +0.000000, +0.333333 }, {  6, +0.000000, +0.666667 }, { 11, +0.200000, +0.333333 } },
	{ {  6, +0.000000, +0.666667 }, {  2, +0.500000, +1.000000 }, { 10, +0.200000, +0.666667 } },
	{ {  5, +0.400000, +0.333333 }, { 11, +0.200000, +0.333333 }, { 10, +0.200000, +0.666667 } },
	{ { 11, +0.200000, +0.333333 }, {  6, +0.000000, +0.666667 }, { 10, +0.200000, +0.666667 } }
};


static const Vector kTexturedVertices[] =
{
	{ +0.525731, +0.000000, +0.850651 },
	{ -0.525731, +0.000000, +0.850651 },
	{ +0.525731, +0.000000, -0.850651 },
	{ -0.525731, +0.000000, -0.850651 },
	{ +0.000000, +0.850651, +0.525731 },
	{ +0.000000, +0.850651, -0.525731 },
	{ +0.000000, -0.850651, +0.525731 },
	{ +0.000000, -0.850651, -0.525731 },
	{ -0.850651, +0.525731, +0.000000 },
	{ +0.850651, +0.525731, +0.000000 },
	{ -0.850651, -0.525731, +0.000000 },
	{ +0.850651, -0.525731, +0.000000 },
	{ +0.000000, +0.850651, -0.525731 },
	{ +0.525731, +0.000000, -0.850651 }
};

static const BaseFace kTexturedFaces[][3] =
{
	{ {  1, +0.400000, +0.666667 }, {  0, +0.600000, +0.666667 }, {  6, +0.500000, +0.333333 } },
	{ {  3, +0.100000, +0.333333 }, {  2, -0.100000, +0.333333 }, {  5, +0.000000, +0.666667 } },
	{ {  4, +0.500000, +1.000000 }, {  0, +0.600000, +0.666667 }, {  1, +0.400000, +0.666667 } },
	{ {  4, +0.500000, +1.000000 }, {  1, +0.400000, +0.666667 }, {  8, +0.200000, +0.666667 } },
	{ { 12, +1.000000, +0.666667 }, { 13, +0.900000, +0.333333 }, {  9, +0.800000, +0.666667 } },
	{ {  5, +0.000000, +0.666667 }, {  4, +0.500000, +1.000000 }, {  8, +0.200000, +0.666667 } },
	{ {  6, +0.500000, +0.333333 }, {  0, +0.600000, +0.666667 }, { 11, +0.700000, +0.333333 } },
	{ {  7, +0.500000, +0.000000 }, {  2, -0.100000, +0.333333 }, {  3, +0.100000, +0.333333 } },
	{ {  7, +0.500000, +0.000000 }, {  3, +0.100000, +0.333333 }, { 10, +0.300000, +0.333333 } },
	{ {  7, +0.500000, +0.000000 }, {  6, +0.500000, +0.333333 }, { 11, +0.700000, +0.333333 } },
	{ {  8, +0.200000, +0.666667 }, {  1, +0.400000, +0.666667 }, { 10, +0.300000, +0.333333 } },
	{ {  8, +0.200000, +0.666667 }, {  3, +0.100000, +0.333333 }, {  5, +0.000000, +0.666667 } },
	{ {  9, +0.800000, +0.666667 }, {  0, +0.600000, +0.666667 }, {  4, +0.500000, +1.000000 } },
	{ {  9, +0.800000, +0.666667 }, { 13, +0.900000, +0.333333 }, { 11, +0.700000, +0.333333 } },
	{ {  9, +0.800000, +0.666667 }, {  4, +0.500000, +1.000000 }, { 12, +1.000000, +0.666667 } },
	{ { 10, +0.300000, +0.333333 }, {  1, +0.400000, +0.666667 }, {  6, +0.500000, +0.333333 } },
	{ { 10, +0.300000, +0.333333 }, {  3, +0.100000, +0.333333 }, {  8, +0.200000, +0.666667 } },
	{ { 10, +0.300000, +0.333333 }, {  6, +0.500000, +0.333333 }, {  7, +0.500000, +0.000000 } },
	{ { 11, +0.700000, +0.333333 }, {  0, +0.600000, +0.666667 }, {  9, +0.800000, +0.666667 } },
	{ { 11, +0.700000, +0.333333 }, { 13, +0.900000, +0.333333 }, {  7, +0.500000, +0.000000 } }
};


@implementation PlanetEntity

- (id) init
{
	[self release];
	[NSException raise:NSInternalInconsistencyException format:@"%s, believed dead, called.", __PRETTY_FUNCTION__];
	return nil;
}


- (id) initAsAtmosphereForPlanet:(PlanetEntity *)planet dictionary:(NSDictionary *)dict
{
	BOOL	procGen = [UNIVERSE doProcedurallyTexturedPlanets];
	
	if (dict == nil)  dict = [NSDictionary dictionary];
	
	self = [super init];
	
	int percent_land = 100 - [dict oo_intForKey:@"percent_cloud" defaultValue:100 - (3 + (gen_rnd_number() & 31)+(gen_rnd_number() & 31))];
	
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
	
	
	clearSkyColor = [OOColor colorWithDescription:[dict objectForKey:@"atmosphere_color"]];
	cloudColor = [OOColor colorWithDescription:[dict objectForKey:@"cloud_color"]];
	polarClearSkyColor = [OOColor colorWithDescription:[dict objectForKey:@"polar_atmosphere_color"]];
	polarCloudColor = [OOColor colorWithDescription:[dict objectForKey:@"polar_cloud_color"]];
	cloudAlpha = OOClamp_0_1_f([dict oo_floatForKey:@"cloud_alpha" defaultValue:1.0]);
	
	if (clearSkyColor != nil)
	{
		[clearSkyColor getRed:&amb_land[0] green:&amb_land[1] blue:&amb_land[2] alpha:&amb_land[3]];
	}
	
	if (cloudColor != nil)
	{
		[cloudColor getRed:&amb_sea[0] green:&amb_sea[1] blue:&amb_sea[2] alpha:&amb_sea[3]];
	}
	
	if (polarClearSkyColor != nil)
	{
		[polarClearSkyColor getRed:&amb_polar_land[0] green:&amb_polar_land[1] blue:&amb_polar_land[2] alpha:&amb_polar_land[3]];
	}
	else if (clearSkyColor != nil)
	{
		memmove(amb_polar_land, amb_land, sizeof amb_polar_land);
		amb_polar_land[3] = OOClamp_0_1_f(amb_polar_land[3] * (POLAR_CLEAR_SKY_ALPHA / CLEAR_SKY_ALPHA));
	}
	
	if (polarCloudColor != nil)
	{
		[polarCloudColor getRed:&amb_polar_sea[0] green:&amb_polar_sea[1] blue:&amb_polar_sea[2] alpha:&amb_polar_sea[3]];
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
	
	if (procGen)
	{
		RANROTSeed ranrotSavedSeed = RANROTGetFullSeed();
		RNG_Seed saved_seed = currentRandomSeed();
		cloudColor = [OOColor colorWithRed: amb_sea[0] green: amb_sea[1] blue: amb_sea[2] alpha: amb_sea[3]];
		float cloud_bias = -0.01 * (float)percent_land;
		float cloud_impress = 1.0 - cloud_bias;
		
		_texture = [self cloudTextureWithCloudColor:cloudColor cloudImpress:cloud_impress cloudBias:cloud_bias];
		[_texture retain];
		isTextureImage = NO;
		
		setRandomSeed(saved_seed);
		RANROTSetFullSeed(ranrotSavedSeed);
	}
	
	if (!planet)
	{
		OOLogERR(@"planet.atmosphere.init.noPlanet", @"planet entity initAsAtmosphereForPlanet: no planet found.");
		return self;
	}
	
	[self setOwner: planet];
	
	position = [planet position];
	orientation = [planet orientation];
	
	if (planet->planet_type == STELLAR_TYPE_NORMAL_PLANET)
		collision_radius = planet->collision_radius + ATMOSPHERE_DEPTH; //  atmosphere is 500m deep only
	if (planet->planet_type == STELLAR_TYPE_MINIATURE)
		collision_radius = planet->collision_radius + ATMOSPHERE_DEPTH * PLANET_MINIATURE_FACTOR*2.0; //not to scale: invisible otherwise
	
	shuttles_on_ground = 0;
	last_launch_time = 0.0;
	shuttle_launch_interval = 3600.0;
	
	scanClass = CLASS_NO_DRAW;
	
	// orientation.w =  M_SQRT1_2; // is already planet->orientation
	// orientation.x =  M_SQRT1_2;
	// orientation.y =  0.0;
	// orientation.z =  0.0;
	
	planet_type =   STELLAR_TYPE_ATMOSPHERE;
	
	planet_seed =	ranrot_rand();	// random set-up for vertex colours
	
	[self setUseTexturedModel:YES];
	[self initialiseBaseVertexArray];
	[self initialiseBaseTerrainArray:percent_land];
	unsigned i;
	for (i =  0; i < next_free_vertex; i++)
	{
		[self paintVertex:i :planet_seed];
	}
	
	[self scaleVertices];

	// set speed of rotation
	rotational_velocity = [dict oo_floatForKey:@"atmosphere_rotational_velocity" defaultValue:[planet rotationalVelocity]*(0.9+(randf()*0.2))]; // 90-110% of planet rotation speed
	
	root_planet = planet;
	
	rotationAxis = vector_up_from_quaternion(orientation);
	
	[[OOGraphicsResetManager sharedManager] registerClient:self];
	
	return self;
}


- (void) miniaturize
{
	planet_type = STELLAR_TYPE_MINIATURE;
	shuttles_on_ground = 0;
	last_launch_time = 0.0;
	shuttle_launch_interval = 3600.0;
	[self setStatus:STATUS_COCKPIT_DISPLAY];
	collision_radius = [self collisionRadius] * PLANET_MINIATURE_FACTOR; // teeny tiny
	[self scaleVertices];
	if (atmosphere != nil)
	{
		atmosphere->collision_radius = collision_radius + ATMOSPHERE_DEPTH * PLANET_MINIATURE_FACTOR*2.0; //not to scale: invisible otherwise
		[atmosphere scaleVertices];
	}
	rotational_velocity = 0.04;
	rotationAxis = kBasisYVector;
}


- (id) initFromDictionary:(NSDictionary*)dict withAtmosphere:(BOOL)atmo andSeed:(Random_Seed)p_seed
{
	BOOL procGen = [UNIVERSE doProcedurallyTexturedPlanets];
	
	if (dict == nil)  dict = [NSDictionary dictionary];
	RANROTSeed ranrotSavedSeed = RANROTGetFullSeed();
	
	self = [super init];
	
	planet_type =  atmo ? STELLAR_TYPE_NORMAL_PLANET : STELLAR_TYPE_MOON;
	
	if (atmo)
		planet_seed = p_seed.a * 13 + p_seed.c * 11 + p_seed.e * 7;	// pseudo-random set-up for vertex colours
	else
		planet_seed = p_seed.a * 7 + p_seed.c * 11 + p_seed.e * 13;	// pseudo-random set-up for vertex colours
	
	OOTexture *texture = [dict oo_objectOfClass:[OOTexture class] forKey:@"_oo_textureObject"];
	if (texture != nil)
	{
		_texture = [texture retain];
		isTextureImage = [dict oo_boolForKey:@"_oo_isExplicitlyTextured"];
	}
	else
	{
		NSDictionary *textureSpec = [dict oo_textureSpecifierForKey:@"texture" defaultName:nil];
		if (textureSpec != nil)
		{
			[self loadTexture:textureSpec];
		}

// CIM: nothing actually uses textureSpec after the assignment below, so skip it
/*		if (textureSpec == nil && !procGen && !atmo)
		{
			// Moons use metal.png by default.
			textureSpec = OOTextureSpecFromObject(@"metal.png", nil);
			} */
		
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

	last_launch_time = [UNIVERSE getTime] + 30.0 - shuttle_launch_interval;   // debug - launch 30s after player enters universe

	collision_radius = radius_km * 10.0; // scale down by a factor of 100 !
	
	scanClass = CLASS_NO_DRAW;
	
	orientation.w =  M_SQRT1_2;
	orientation.x =  M_SQRT1_2;
	orientation.y =  0.0;
	orientation.z =  0.0;
	
	[self setUseTexturedModel:(procGen || _texture != nil)];
	
	int percent_land = [planetInfo oo_intForKey:@"percent_land" defaultValue:24 + (gen_rnd_number() % 48)];
	//if (isTextured)  percent_land =  atmo ? 0 :100; // moon/planet override
	
	// save the current random number generator seed
	RNG_Seed saved_seed = currentRandomSeed();
	
	// For historical reasons, stir the PRNG vertexCount times.
	unsigned i;
	for (i = 0; i < vertexCount; i++)  gen_rnd_number();
	
	[planetInfo setObject:[NSNumber numberWithFloat:0.01 * percent_land] forKey:@"land_fraction"];
	
	polar_color_factor = [dict oo_doubleForKey:@"polar_color_factor" defaultValue:0.5f];
	
	Vector land_hsb, sea_hsb, land_polar_hsb, sea_polar_hsb;
	
	if (isTextureImage)
	{
		// standard overlay colours.
		land_hsb.x = 0.0;	land_hsb.y = 0.0;	land_hsb.z = 1.0;	// non-saturated fully bright (white)
		sea_hsb.x = 0.0;	sea_hsb.y = 1.0;	sea_hsb.z = 1.0;	// fully-saturated fully bright (red)	
		// override the mainPlanet texture colour...
		[self setTextureColorForPlanet:!![dict objectForKey:@"mainForLocalSystem"] inSystem:[dict oo_boolForKey:@"mainForLocalSystem" defaultValue:NO]];
	}
	else
	{
		// random land & sea colours.
		land_hsb.x = gen_rnd_number() / 256.0;  land_hsb.y = gen_rnd_number() / 256.0;  land_hsb.z = 0.5 + gen_rnd_number() / 512.0;
		sea_hsb.x = gen_rnd_number() / 256.0;  sea_hsb.y = gen_rnd_number() / 256.0;  sea_hsb.z = 0.5 + gen_rnd_number() / 512.0;
		while (dot_product(land_hsb,sea_hsb) > .80) // make sure land and sea colors differ significantly
		{
			sea_hsb.x = gen_rnd_number() / 256.0;  sea_hsb.y = gen_rnd_number() / 256.0;  sea_hsb.z = 0.5 + gen_rnd_number() / 512.0;
		}
		
		// assign land_hsb and sea_hsb overrides from planetinfo.plist if they're there.
		ScanVectorFromString([dict objectForKey:@"land_hsb_color"], &land_hsb);
		ScanVectorFromString([dict objectForKey:@"sea_hsb_color"], &sea_hsb);
		
		// polar areas are brighter but have less color (closer to white)
		land_polar_hsb.x = land_hsb.x;  land_polar_hsb.y = (land_hsb.y / 4.0);  land_polar_hsb.z = 1.0 - (land_hsb.z / 10.0);
		sea_polar_hsb.x = sea_hsb.x;  sea_polar_hsb.y = (sea_hsb.y / 4.0);  sea_polar_hsb.z = 1.0 - (sea_hsb.z / 10.0);
		
		OOColor *amb_land_color = [OOColor colorWithHue:land_hsb.x saturation:land_hsb.y brightness:land_hsb.z alpha:1.0];
		OOColor *amb_sea_color = [OOColor colorWithHue:sea_hsb.x saturation:sea_hsb.y brightness:sea_hsb.z alpha:1.0];
		OOColor *amb_polar_land_color = [OOColor colorWithHue:land_polar_hsb.x saturation:land_polar_hsb.y brightness:land_polar_hsb.z alpha:1.0];
		OOColor *amb_polar_sea_color = [OOColor colorWithHue:sea_polar_hsb.x saturation:sea_polar_hsb.y brightness:sea_polar_hsb.z alpha:1.0];
		
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

	if (procGen && _texture == nil)
	{
		_texture = [self planetTextureWithInfo:planetInfo];
		isTextureImage = NO;
		[_texture retain];
	}
	
	[self initialiseBaseVertexArray];
	[self initialiseBaseTerrainArray:percent_land];
	
	for (i = 0; i < next_free_vertex; i++)
	{
		[self paintVertex:i :planet_seed];
	}
	
	[self scaleVertices];
	// set speed of rotation	
	if ([dict objectForKey:@"rotational_velocity"])
	{
		rotational_velocity = [dict oo_floatForKey:@"rotational_velocity" defaultValue:0.01f * randf()];	// 0.0 .. 0.01 avr 0.005
	}
	else
	{
		rotational_velocity = [planetInfo oo_floatForKey:@"rotation_speed" defaultValue:0.002 * (0.5+0.5*randf())]; // 0.001 .. 0.002 avr 0.0015
		rotational_velocity *= [planetInfo oo_floatForKey:@"rotation_speed_factor" defaultValue:1.0f];
	}

	// do atmosphere
	NSDictionary *atmoDict = dict;
	if (_texture != nil)  atmoDict = 	[NSDictionary dictionaryWithObjectsAndKeys:@"0", @"percent_cloud", [NSNumber numberWithFloat:[planetInfo oo_floatForKey:@"cloud_alpha" defaultValue:1.0]], @"cloud_alpha", nil];
	if (atmo)  atmosphere = [[PlanetEntity alloc] initAsAtmosphereForPlanet:self dictionary:atmoDict];
	
	setRandomSeed(saved_seed);
	RANROTSetFullSeed(ranrotSavedSeed);

	// set energy
	energy = collision_radius * 1000.0;
	
	root_planet = self;
	
	rotationAxis = vector_up_from_quaternion(orientation);

	/* MKW - rotate planet based on current time.
	 *     - do it here so that we catch all planets (OXP-added and otherwise! */
	int		deltaT = floor(fmod([PLAYER clockTimeAdjusted], 86400));
	quaternion_rotate_about_axis(&orientation, rotationAxis, rotational_velocity * deltaT);

	[self setStatus:STATUS_ACTIVE];
	
	[[OOGraphicsResetManager sharedManager] registerClient:self];
	
	return self;
}


- (void) dealloc
{
	[self deleteDisplayLists];
	
	DESTROY(atmosphere);
	DESTROY(_texture);
	DESTROY(_textureFileName);
	
	[[OOGraphicsResetManager sharedManager] unregisterClient:self];
	
	[super dealloc];
}


- (NSString*) descriptionComponents
{
	NSString *typeString;
	switch (planet_type)
	{
		case STELLAR_TYPE_MINIATURE:
			typeString = @"STELLAR_TYPE_MINIATURE";	break;
		case STELLAR_TYPE_NORMAL_PLANET:
			typeString = @"STELLAR_TYPE_NORMAL_PLANET";	break;
		case STELLAR_TYPE_ATMOSPHERE:
			typeString = @"STELLAR_TYPE_ATMOSPHERE";	break;
		case STELLAR_TYPE_MOON:
			typeString = @"STELLAR_TYPE_MOON";	break;
		
		default:
			typeString = @"UNKNOWN";
	}
	return [NSString stringWithFormat:@"ID: %u position: %@ type: %@ radius: %.3fkm", [self universalID], HPVectorDescription([self position]), typeString, 0.001 * [self radius]];
}


- (BOOL) canCollide
{
	switch (planet_type)
	{
		case STELLAR_TYPE_MINIATURE:
		case STELLAR_TYPE_ATMOSPHERE:
			return NO;
			break;
		case STELLAR_TYPE_MOON:
		case STELLAR_TYPE_NORMAL_PLANET:
		case STELLAR_TYPE_SUN:
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
		if ([ship behaviour] == BEHAVIOUR_LAND_ON_PLANET)
		{
			return NO;
		}
#ifndef NDEBUG
		if ([ship reportAIMessages])
		{
			HPVector p1 = ship->position;
			OOLog(@"planet.collide.shipHit", @"DEBUG: %@ %d collided with planet at (%.1f,%.1f,%.1f)",[ship name], [ship universalID], p1.x,p1.y,p1.z);
		}
#endif
	}

	return YES;
}


- (void) update:(OOTimeDelta) delta_t
{
	[super update:delta_t];
	sqrt_zero_distance = sqrt(cam_zero_distance);

	switch (planet_type)
	{
		case STELLAR_TYPE_NORMAL_PLANET:
			// we have atmosphere in any case.
			{
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
				else if (alt > 0 && alt <= atmo * 1.5)
				{
					/* Without this, if you leave the atmosphere at very low
					 * frame rates, you might still have skyalpha > 0 when you
					 * go sun-skimming. Since skyalpha > 0 simulates atmospheric
					 * friction and continually pumps heat into the ship, this
					 * is rapidly fatal - CIM */
					[UNIVERSE setSkyColorRed:0.0f
														 green:0.0f
															blue:0.0f
														 alpha:0.0f];
				}
			}
		case STELLAR_TYPE_MOON:
			{
				double ugt = [UNIVERSE getTime];

				if ((shuttles_on_ground > 0)&&(ugt > last_launch_time + shuttle_launch_interval))
				{
					[self launchShuttle];
					shuttles_on_ground--;
					last_launch_time = ugt;
				}
			}
		
		case STELLAR_TYPE_MINIATURE:
			// normal planetary rotation
			if (atmosphere) [atmosphere update:delta_t];
			quaternion_rotate_about_axis(&orientation, rotationAxis, rotational_velocity * delta_t);
			[self orientationChanged];
			break;

		case STELLAR_TYPE_ATMOSPHERE:
			{
				// atmospheric rotation
				quaternion_rotate_about_axis(&orientation, rotationAxis, rotational_velocity * delta_t);
				[self orientationChanged];
			}
			break;
		
		case STELLAR_TYPE_SUN:
			break;
	}
}


- (void) setPosition:(HPVector)posn
{
	position = posn;
	[atmosphere setPosition:posn];
}


- (void) setOrientation:(Quaternion)inOrientation
{
	rotationAxis = vector_up_from_quaternion(inOrientation);
	[super setOrientation:inOrientation];
	if (atmosphere) [atmosphere setOrientation:inOrientation];
}


- (void) setUseTexturedModel:(BOOL)flag
{
	if (flag)
	{
		useTexturedModel = YES;
		vertexCount = sizeof kTexturedVertices / sizeof *kTexturedVertices;
	}
	else
	{
		useTexturedModel = NO;
		vertexCount = sizeof kUntexturedVertices / sizeof *kTexturedVertices;
	}
}


// TODO: some translucent stuff is drawn in the opaque pass, which is Naughty.
- (void) drawImmediate:(bool)immediate translucent:(bool)translucent
{
	if ([UNIVERSE breakPatternHide] || translucent || immediate)  return;  // DON'T DRAW
	GLfloat radWithAtmosphere = [self radius] + ATMOSPHERE_DEPTH;
	if (radWithAtmosphere * radWithAtmosphere * 1.1 < cam_zero_distance)
	{
		// for some reason this check doesn't work when extremely close to
		// the planet and with the horizon near the side of the frame (FP
		// inaccuracy?)
		if (![UNIVERSE viewFrustumIntersectsSphereAt:cameraRelativePosition withRadius:radWithAtmosphere])
		{
			// Don't draw
			return;
		}
	}

	[self drawUnconditionally];
}


- (void) drawUnconditionally
{
	uint8_t	subdivideLevel =	2;		// 4 is probably the maximum!
	
	double  drawFactor = [[UNIVERSE gameView] viewSize].width / 100.0;
	double  drawRatio2 = drawFactor * collision_radius / sqrt_zero_distance; // equivalent to size on screen in pixels
	
	if (cam_zero_distance > 0.0)
	{
		subdivideLevel = 2 + floor(drawRatio2);
		if (subdivideLevel > 4)  subdivideLevel = 4;
	}
	
	if (planet_type == STELLAR_TYPE_MINIATURE)
	{
		subdivideLevel = [UNIVERSE reducedDetail]? 3 : 4;		// max detail or less
	}
		
	lastSubdivideLevel = subdivideLevel;	// record
	
	OOSetOpenGLState(OPENGL_STATE_OPAQUE);
	OOGL(glPushAttrib(GL_ENABLE_BIT));
	
//	OOGL(glEnable(GL_LIGHTING));
//	OOGL(glEnable(GL_LIGHT1));
	GLfloat specular[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	OOGL(glMaterialfv(GL_FRONT_AND_BACK, GL_SPECULAR, specular));
	OOGL(glMateriali(GL_FRONT_AND_BACK, GL_SHININESS, 0));
	
	/*

	The depth test gets disabled in parts of this and instead
	we rely on the painters algorithm instead.

	The depth buffer isn't granular enough to cope with huge objects at vast
	distances.

	*/
	
	BOOL ignoreDepthBuffer = (planet_type == STELLAR_TYPE_ATMOSPHERE);
	
	if (cam_zero_distance > collision_radius * collision_radius * 25) // is 'far away'
	{
		ignoreDepthBuffer |= YES;
	}
	
	[_texture ensureFinishedLoading];
	
	switch (planet_type)
	{
		case STELLAR_TYPE_ATMOSPHERE:
			if (root_planet)
			{
				subdivideLevel = root_planet->lastSubdivideLevel;	// copy it from the planet (stops jerky LOD and such)
			}
			GLMultOOMatrix(rotMatrix);	// rotate the clouds!
			OOGL(glEnable(GL_BLEND));
//			OOGL(glDisable(GL_LIGHTING));
			// Fall through.

		case STELLAR_TYPE_MOON:
		case STELLAR_TYPE_NORMAL_PLANET:
		case STELLAR_TYPE_MINIATURE:
			//if ((gDebugFlags & DEBUG_WIREFRAME_GRAPHICS)
			if ([UNIVERSE wireframeGraphics])
			{
				// Drop the detail level a bit, it still looks OK in wireframe and does not penalize
				// the system that much.
				subdivideLevel = 2;
				OOGLWireframeModeOn();
			}
			
			{
				GLfloat mat1[]		= { 1.0, 1.0, 1.0, 1.0 };	// opaque white
				
				if (_texture != nil)
				{
					if ([_texture isCubeMap])
					{
#if OO_TEXTURE_CUBE_MAP
						OOGL(glDisable(GL_TEXTURE_2D));
						OOGL(glEnable(GL_TEXTURE_CUBE_MAP));
#endif
					}
					else
					{
//						OOGL(glEnable(GL_TEXTURE_2D));
					}
					OOGL(glTexEnvfv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_COLOR, mat1));
					[_texture apply];
				}
				else
				{
					OOGL(glDisable(GL_TEXTURE_2D));
					[OOTexture applyNone];
				}

				OOGL(glShadeModel(GL_SMOOTH));
				
				// far enough away to draw flat ?
				if (ignoreDepthBuffer)
				{
					OOGL(glDisable(GL_DEPTH_TEST));
				}

				OOGL(glColor4fv(mat1));
				OOGL(glMaterialfv(GL_FRONT, GL_AMBIENT_AND_DIFFUSE, mat1));
				
				OOGL(glEnableClientState(GL_COLOR_ARRAY));
				OOGL(glColorPointer(4, GL_FLOAT, 0, vertexdata.color_array));
//				OOGL(glEnableClientState(GL_VERTEX_ARRAY));
				OOGL(glVertexPointer(3, GL_FLOAT, 0, vertexdata.vertex_array));
//				OOGL(glEnableClientState(GL_NORMAL_ARRAY));
				OOGL(glNormalPointer(GL_FLOAT, 0, vertexdata.normal_array));
				
				if (_texture != nil)
				{
					OOGL(glEnableClientState(GL_TEXTURE_COORD_ARRAY));
					if ([_texture isCubeMap])
					{
						OOGL(glTexCoordPointer(3, GL_FLOAT, 0, vertexdata.vertex_array));
					}
					else
					{
						OOGL(glTexCoordPointer(2, GL_FLOAT, 0, vertexdata.uv_array));
					}
				}
				else
				{
					OOGL(glDisableClientState(GL_TEXTURE_COORD_ARRAY));
				}
				
				if (displayListNames[subdivideLevel] != 0)
				{
					OOGL(glCallList(displayListNames[subdivideLevel]));
				}
				else
				{
					
					OOGL(displayListNames[subdivideLevel] = glGenLists(1));
					if (displayListNames[subdivideLevel] != 0)	// sanity check
					{
						OOGL(glNewList(displayListNames[subdivideLevel], GL_COMPILE_AND_EXECUTE));
						
						OOGL(glColorMaterial(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE));
						OOGL(glEnable(GL_COLOR_MATERIAL));
						
						[self drawModelWithVertexArraysAndSubdivision:subdivideLevel];
						
						OOGL(glDisable(GL_COLOR_MATERIAL));
						OOGL(glEndList());
					}
				}

#if OO_TEXTURE_CUBE_MAP
				if ([_texture isCubeMap])
				{
					OOGL(glDisable(GL_TEXTURE_CUBE_MAP));
					OOGL(glEnable(GL_TEXTURE_2D));
				}
#endif

			OOGL(glDisableClientState(GL_COLOR_ARRAY));
			OOGL(glDisableClientState(GL_TEXTURE_COORD_ARRAY));
			OOGL(glEnable(GL_DEPTH_TEST));

			}
			
			//if ((gDebugFlags & DEBUG_WIREFRAME_GRAPHICS)
			if ([UNIVERSE wireframeGraphics])
			{
				OOGLWireframeModeOff();
			}
//			OOGL(glDisableClientState(GL_VERTEX_ARRAY));
//			OOGL(glDisableClientState(GL_NORMAL_ARRAY));
			
			break;
			
		case STELLAR_TYPE_SUN:
			break;
	}

	if (ignoreDepthBuffer)
	{
		OOGL(glEnable(GL_DEPTH_TEST));
	}
	OOGL(glEnable(GL_TEXTURE_2D));
//	OOGL(glEnable(GL_LIGHTING));
	OOGL(glDisable(GL_BLEND));


	OOGL(glPopAttrib());
	OOVerifyOpenGLState();
	OOCheckOpenGLErrors(@"PlanetEntity after drawing %@", self);

	if (atmosphere)
	{
		OOGL(glPopMatrix());	// get old draw matrix back
		OOGL(glPushMatrix());	// and store it again
		OOGL(glTranslatef(cameraRelativePosition.x,cameraRelativePosition.y,cameraRelativePosition.z)); // centre on the planet
		// rotate
//		GLMultOOMatrix([atmosphere rotationMatrix]);
		// draw atmosphere entity
		[atmosphere drawImmediate:false translucent:false];
	}


}


#ifndef NDEBUG
- (PlanetEntity *) atmosphere
{
	return atmosphere;
}
#endif


- (int) planet_seed
{
	return planet_seed;
}


- (BOOL) isTextured
{
	return _texture != nil;
}


- (NSString *) textureFileName
{
	return _textureFileName;
}


- (void) setTextureColorForPlanet:(BOOL)isMain inSystem:(BOOL)isLocal
{	
	Vector land_hsb, land_polar_hsb;
	land_hsb.x = 0.0;	land_hsb.y = 0.0;	land_hsb.z = 1.0;	// white
	
	// the colour override should only apply to main planets
	if (isMain)
	{
		if (isLocal)  ScanVectorFromString([[UNIVERSE currentSystemData] objectForKey:@"texture_hsb_color"], &land_hsb);
		else  ScanVectorFromString([[UNIVERSE generateSystemData:[PLAYER target_system_seed]] objectForKey:@"texture_hsb_color"], &land_hsb);
	}
	
	land_polar_hsb.x = land_hsb.x;  land_polar_hsb.y = (land_hsb.y / 5.0);  land_polar_hsb.z = 1.0 - (land_hsb.z / 10.0);
	
	amb_sea[0] = amb_land[0] = [[OOColor colorWithHue:land_hsb.x saturation:land_hsb.y brightness:land_hsb.z alpha:1.0] redComponent];
	amb_sea[1] = amb_land[1] = [[OOColor colorWithHue:land_hsb.x saturation:land_hsb.y brightness:land_hsb.z alpha:1.0] blueComponent];
	amb_sea[2] = amb_land[2] = [[OOColor colorWithHue:land_hsb.x saturation:land_hsb.y brightness:land_hsb.z alpha:1.0] greenComponent];
	amb_sea[3] = amb_land[3] = 1.0;
	amb_polar_sea[0] =amb_polar_land[0] = [[OOColor colorWithHue:land_polar_hsb.x saturation:land_polar_hsb.y brightness:land_polar_hsb.z alpha:1.0] redComponent];
	amb_polar_sea[1] =amb_polar_land[1] = [[OOColor colorWithHue:land_polar_hsb.x saturation:land_polar_hsb.y brightness:land_polar_hsb.z alpha:1.0] blueComponent];
	amb_polar_sea[2] = amb_polar_land[2] = [[OOColor colorWithHue:land_polar_hsb.x saturation:land_polar_hsb.y brightness:land_polar_hsb.z alpha:1.0] greenComponent];
	amb_polar_sea[3] =amb_polar_land[3] = 1.0;
}


- (BOOL) setUpPlanetFromTexture:(NSString *)fileName
{
	if (fileName == nil)  return NO;
	
	[self loadTexture:OOTextureSpecFromObject(fileName, nil)];
	[self deleteDisplayLists];
	
	unsigned i;
	[self setUseTexturedModel:YES];
	
	// recolour main planet according to "texture_hsb_color"
	// this function is only called for local systems!
	[self setTextureColorForPlanet:([UNIVERSE planet] == self) inSystem:YES];
	
	[self initialiseBaseVertexArray];
	[self initialiseBaseTerrainArray:100];
	for (i =  0; i < next_free_vertex; i++)
	{
		[self paintVertex:i :planet_seed];
	}
	
	[self scaleVertices];
	
	GLfloat oldCloudAlpha = 0.0;
	if (atmosphere)
	{
		oldCloudAlpha = [atmosphere amb_sea][3] / CLOUD_ALPHA;
	}

	NSDictionary *atmo_dictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"0", @"percent_cloud", [NSNumber numberWithFloat:oldCloudAlpha], @"cloud_alpha", nil];
	[atmosphere autorelease];
	atmosphere = [self hasAtmosphere] ? [[PlanetEntity alloc] initAsAtmosphereForPlanet:self dictionary:atmo_dictionary] : nil;
	
	//rotationAxis = vector_up_from_quaternion(orientation);
	
	return [self isTextured];
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


- (OOStellarBodyType) planetType
{
	return planet_type;
}


- (void) setPlanetType:(OOStellarBodyType) pt
{
	planet_type = pt;
}


- (double) radius
{
	return collision_radius;
}


- (void) setRadius:(GLfloat) rad
{
	collision_radius = rad;
}

- (double) rotationalVelocity
{
	return rotational_velocity;
}

- (void) setRotationalVelocity:(double) v
{
	if (atmosphere) // change rotation speed proportionally
	{
		[atmosphere setRotationalVelocity:[atmosphere rotationalVelocity] * v / [self rotationalVelocity]];
	}
	rotational_velocity = v;
}


- (double) sqrtZeroDistance
{
	return sqrt_zero_distance;
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
	HPVector		launch_pos = position;
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
		{
			[shuttle_ship setSingleCrewWithRole:@"trader"];
		}
				
		[shuttle_ship setPosition:launch_pos];
		[shuttle_ship setOrientation:q1];

		[shuttle_ship setScanClass: CLASS_NEUTRAL];
		[shuttle_ship setCargoFlag:CARGO_FLAG_FULL_PLENTIFUL];
		[shuttle_ship switchAITo:@"oolite-shuttleAI.js"];
		[UNIVERSE addEntity:shuttle_ship];

		[shuttle_ship release];
	}
}


- (void) welcomeShuttle:(ShipEntity *) shuttle
{
	shuttles_on_ground++;
}


- (void) initialiseBaseVertexArray
{
	BOOL isTextured = [self isTextured];
	static BOOL lastOneWasTextured;
	
	if (lastOneWasTextured != isTextured)
	{
		if (sEdgeToVertex != NULL)
		{
			NSFreeMapTable(sEdgeToVertex);
			sEdgeToVertex = NULL;
		}
		lastOneWasTextured = isTextured;
	}
	
	if (sEdgeToVertex == NULL)
	{
		sEdgeToVertex = NSCreateMapTable(NSIntegerMapKeyCallBacks, NSIntegerMapValueCallBacks, 7680);	// make a new one
		next_free_vertex = 0;
		
		const Vector *vertices = NULL;
		const BaseFace (*faces)[3] = NULL;
		GLuint faceCount = 0;
		if (useTexturedModel)
		{
			vertices = kTexturedVertices;
			faces = kTexturedFaces;
			faceCount = sizeof kTexturedFaces / sizeof *kTexturedFaces;
		}
		else
		{
			vertices = kUntexturedVertices;
			faces = kUntexturedFaces;
			faceCount = sizeof kUntexturedFaces / sizeof *kUntexturedFaces;
		}
		
		// set first 12 or 14 vertices
		GLuint vi;
		for (vi = 0; vi < vertexCount; vi++)
		{
			base_vertex_array[next_free_vertex++] =  vertices[vi];
		}
		
		// set first 20 triangles
		triangle_start[0] = 0;
		n_triangles[0] = faceCount;
		GLuint fi;
		for (fi = 0; fi < faceCount; fi++)
		{
			unsigned j;
			for (j = 0; j < 3; j++)
			{
				vertex_index_array[fi * 3 + j] = faces[fi][j].v;
				texture_uv_array[faces[fi][j].v * 2 + 0] = faces[fi][j].s;
				texture_uv_array[faces[fi][j].v * 2 + 1] = faces[fi][j].t;
			}
		}
		
		// for the next levels of subdivision simply build up from the level below!...
		unsigned sublevel;
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
	unsigned i;
	for (i = 0; i < MAX_TRI_INDICES; i++)
	{
		vertexdata.index_array[i] = vertex_index_array[i];
	}
}

	
static unsigned baseVertexIndexForEdge(GLushort va, GLushort vb, BOOL textured)
{
	if (va < vb)
	{
		GLushort temp = va;
		va = vb;
		vb = temp;
	}
	void *key = (void *)(((uintptr_t)va << 16) | vb);
	uintptr_t num = (uintptr_t)NSMapGet(sEdgeToVertex, key);
	if (num != 0)
	{
		// Overall cache hit rate is just over 83 %.
		return (unsigned)num - 1;
	}
	else
	{
		unsigned vindex = next_free_vertex++;
		NSCAssert(vindex < sizeof base_vertex_array / sizeof *base_vertex_array, @"Vertex array overflow in planet setup.");
		
		// calculate position of new vertex
		Vector pos = vector_add(base_vertex_array[va], base_vertex_array[vb]);
		pos = vector_normal(pos);	// guaranteed non-zero
		base_vertex_array[vindex] = pos;
		
		if (textured)
		{
			//calculate new texture coordinates
			NSPoint	uva = (NSPoint){ texture_uv_array[va * 2], texture_uv_array[va * 2 + 1] };
			NSPoint	uvb = (NSPoint){ texture_uv_array[vb * 2], texture_uv_array[vb * 2 + 1] };
			
			// if either of these is the polar vertex treat it specially to help with polar distortion:
			if (uva.y == 0.0 || uva.y == 1.0)  uva.x = uvb.x;
			if (uvb.y == 0.0 || uvb.y == 1.0)  uvb.x = uva.x;
			
			texture_uv_array[vindex * 2] = 0.5 * (uva.x + uvb.x);
			texture_uv_array[vindex * 2 + 1] = 0.5 * (uva.y + uvb.y);
		}
		
		// add new edge to the look-up
		num = vindex + 1;
		NSMapInsertKnownAbsent(sEdgeToVertex, key, (void *)num);
		return vindex;
	}
}


- (void) initialiseBaseTerrainArray:(int) percent_land
{
	RANROTSeed saved_seed = RANROTGetFullSeed();

	// set first 12 or 14 vertices
	if (percent_land >= 0)
	{
		GLuint vi;
		for (vi = 0; vi < vertexCount; vi++)
		{
			if (gen_rnd_number() < 256 * percent_land / 100)
				base_terrain_array[vi] = 0;  // land
			else
				base_terrain_array[vi] = 100;  // sea

		}
	}
	
	// for the next levels of subdivision simply build up from the level below!...
	BOOL isTextured = [self isTextured];
	
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
				uint32_t s1 = 0xffff0000 * base_vertex_array[v01].x;
				uint32_t s2 = 0x00ffff00 * base_vertex_array[v01].y;
				uint32_t s3 = 0x0000ffff * base_vertex_array[v01].z;
				ranrot_srand(s1+s2+s3);
				base_terrain_array[v01] = (ranrot_rand() & 4) *25;
			}
			// v12
			if (base_terrain_array[v1] == base_terrain_array[v2])
				base_terrain_array[v12] = base_terrain_array[v1];
			else
			{
				uint32_t s1 = 0xffff0000 * base_vertex_array[v12].x;
				uint32_t s2 = 0x00ffff00 * base_vertex_array[v12].y;
				uint32_t s3 = 0x0000ffff * base_vertex_array[v12].z;
				ranrot_srand(s1+s2+s3);
				base_terrain_array[v12] = (ranrot_rand() & 4) *25;
			}
			// v20
			if (base_terrain_array[v2] == base_terrain_array[v0])
				base_terrain_array[v20] = base_terrain_array[v2];
			else
			{
				uint32_t s1 = 0xffff0000 * base_vertex_array[v20].x;
				uint32_t s2 = 0x00ffff00 * base_vertex_array[v20].y;
				uint32_t s3 = 0x0000ffff * base_vertex_array[v20].z;
				ranrot_srand(s1+s2+s3);
				base_terrain_array[v20] = (ranrot_rand() & 4) *25;
			}
		}
	}

	RANROTSetFullSeed(saved_seed);
}


- (void) paintVertex:(unsigned) vi :(int) seed
{
	RANROTSeed saved_seed = RANROTGetFullSeed();
	BOOL isTextured = _texture != nil;
	
	GLfloat paint_land[4] = { 0.2, 0.9, 0.0, 1.0};
	GLfloat paint_sea[4] = { 0.0, 0.2, 0.9, 1.0};
	GLfloat paint_color[4];
	Vector	v = base_vertex_array[vi];
	int		r = isTextured ? 0 : base_terrain_array[vi];	// use land color (0) for textured planets
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
	if (planet_type == STELLAR_TYPE_ATMOSPHERE)	// do alphas
	{
		paint_land[3] = (1.0 - pole_blend)*amb_land[3] + pole_blend*amb_polar_land[3];
		paint_sea[3] = (1.0 - pole_blend)*amb_sea[3] + pole_blend*amb_polar_sea[3];
	}
	
	ranrot_srand((uint32_t)(seed+v.x*1000+v.y*100+v.z*10));
	
	for (i = 0; i < 3; i++)
	{
		double cv = (ranrot_rand() % 100)*0.01;	//  0..1 ***** DON'T CHANGE THIS LINE, '% 100' MAY NOT BE EFFICIENT BUT THE PATTERNING IS GOOD.
		paint_land[i] += (cv - 0.5)*0.1;
		paint_sea[i] += (cv - 0.5)*0.1;
	}
	
	for (i = 0; i < 4; i++)
	{
		if (planet_type == STELLAR_TYPE_ATMOSPHERE && isTextured)
			paint_color[i] = 1.0;
		else
			paint_color[i] = (r * paint_sea[i])*0.01 + ((100 - r) * paint_land[i])*0.01;
		// finally initialise the color array entry
		vertexdata.color_array[vi*4 + i] = paint_color[i];
	}

	RANROTSetFullSeed(saved_seed);
}


- (void) scaleVertices
{
	NSUInteger vi;
	for (vi = 0; vi < next_free_vertex; vi++)
	{
		Vector	v = base_vertex_array[vi];
		vertexdata.normal_array[vi] = v;
		vertexdata.vertex_array[vi] = make_vector(v.x * collision_radius, v.y * collision_radius, v.z * collision_radius);
		
		vertexdata.uv_array[vi * 2] = texture_uv_array[vi * 2];
		vertexdata.uv_array[vi * 2 + 1] = texture_uv_array[vi * 2 + 1];
	}
}


- (void) deleteDisplayLists
{
	unsigned i;
	for (i = 0; i < MAX_SUBDIVIDE; i++)
	{
		if (displayListNames[i] != 0)
		{
			glDeleteLists(displayListNames[i], 1);
			displayListNames[i] = 0;
		}
	}
}


- (void)resetGraphicsState
{
	[self deleteDisplayLists];
}


- (BOOL) isExplicitlyTextured
{
	return isTextureImage;
}


- (OOTexture *) texture
{
	return _texture;
}


- (void) loadTexture:(NSDictionary *)configuration
{
	[_texture release];
	_texture = [OOTexture textureWithConfiguration:configuration extraOptions:kOOTextureAllowCubeMap | kOOTextureRepeatS];
	[_texture retain];
	
	[_textureFileName release];
	if (_texture != nil)
	{
		_textureFileName = [[configuration oo_stringForKey:@"name"] copy];
		isTextureImage = YES;
	}
	else
	{
		_textureFileName = nil;
		isTextureImage = NO;
	}
}


/*	Ideally, these would use OOPlanetTextureGenerator. However, it isn't
	designed to use separate invocations for diffuse and cloud generation,
	while old-style PlanetEntity calls these from different places for
	different objects.
	-- Ahruman 2010-06-04
*/
- (OOTexture *) planetTextureWithInfo:(NSDictionary *)info
{
	unsigned char *data;
	GLuint width, height;
	
	fillRanNoiseBuffer();
	if (![TextureStore getPlanetTextureNameFor:info
									  intoData:&data
										 width:&width
										height:&height])
	{
		return nil;
	}
	
	OOPixMap pm = OOMakePixMap(data, width, height, kOOPixMapRGBA, 0, 0);
	OOTextureGenerator *loader = [[OOPixMapTextureLoader alloc] initWithPixMap:pm
																textureOptions:kOOTextureDefaultOptions | kOOTextureRepeatS
																  freeWhenDone:YES];
	[loader autorelease];
	
	return [OOTexture textureWithGenerator:loader];
}


- (OOTexture *) cloudTextureWithCloudColor:(OOColor *)cloudColor cloudImpress:(GLfloat)cloud_impress cloudBias:(GLfloat)cloud_bias
{
	unsigned char *data;
	GLuint width, height;
	
	fillRanNoiseBuffer();
	if (![TextureStore getCloudTextureNameFor:cloudColor
											 :cloud_impress
											 :cloud_bias
									 intoData:&data
										width:&width
									   height:&height])
	{
		return nil;
	}
	
	OOPixMap pm = OOMakePixMap(data, width, height, kOOPixMapRGBA, 0, 0);
	OOTextureGenerator *loader = [[OOPixMapTextureLoader alloc] initWithPixMap:pm
																textureOptions:kOOTextureDefaultOptions | kOOTextureRepeatS
																  freeWhenDone:YES];
	[loader autorelease];
	
	return [OOTexture textureWithGenerator:loader];
}


#ifndef NDEBUG
- (NSSet *) allTextures
{
	if (_texture != nil)  return [NSSet setWithObject:_texture];
	else  return nil;
}
#endif


- (BOOL)isPlanet
{
	return YES;
}


- (BOOL) isVisible
{
	return YES;
}

@end

#endif	// !NEW_PLANETS
