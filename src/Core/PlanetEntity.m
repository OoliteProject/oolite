//
//  PlanetEntity.m
/*
 *
 *  Oolite
 *
 *  Created by Giles Williams on Sat Apr 03 2004.
 *  Copyright (c) 2004 for aegidian.org. All rights reserved.
 *

Copyright (c) 2004, Giles C Williams
All rights reserved.

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Noncommercial. You may not use this work for commercial purposes.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/

#import "PlanetEntity.h"
#import "entities.h"
#import "OOOpenGL.h"

#import "AI.h"
#import "Universe.h"
#import "TextureStore.h"
#import "MyOpenGLView.h"
#import "ShipEntity (AI).h"
#import "OOColor.h"
#import "OOCharacter.h"

#define LIM500  500.0*500.0 * NO_DRAW_DISTANCE_FACTOR*NO_DRAW_DISTANCE_FACTOR
#define LIM4K   4000.0*4000.0 * NO_DRAW_DISTANCE_FACTOR*NO_DRAW_DISTANCE_FACTOR
#define LIM8K   8000.0*8000.0 * NO_DRAW_DISTANCE_FACTOR*NO_DRAW_DISTANCE_FACTOR
#define LIM16K  16000.0*16000.0 * NO_DRAW_DISTANCE_FACTOR*NO_DRAW_DISTANCE_FACTOR

// straight c
static Vector base_vertex_array[10400];
static int base_terrain_array[10400];
static int next_free_vertex;
NSMutableDictionary*	edge_to_vertex = nil;

static int n_triangles[MAX_SUBDIVIDE];
static int triangle_start[MAX_SUBDIVIDE];
static GLuint vertex_index_array[3*(20+80+320+1280+5120+20480)];

static GLfloat	texture_uv_array[10400 * 2];


@implementation PlanetEntity

static BOOL sinTableIsSetup = NO;
void setUpSinTable()
{
	if (!sinTableIsSetup)
	{
		int i;
		for (i = 0; i < 450; i++)
			sin_value[i] = sin(i * PI / 180);
		cos_value = &sin_value[90];
	}
	sinTableIsSetup = YES;
}

- (id) init
{
	int		i;
	int		percent_land;
	double  aleph =  1.0 / sqrt(2.0);
	//
	self = [super init];
	//
	isTextured = NO;
	//
    collision_radius = 25000.0; //  25km across
	//
	setUpSinTable();
	//
	scan_class = CLASS_NO_DRAW;
	//
	q_rotation.w =  aleph;		// represents a 90 degree rotation around x axis
	q_rotation.x =  aleph;		// (I hope!)
	q_rotation.y =  0.0;
	q_rotation.z =  0.0;
	//
	planet_type =   PLANET_TYPE_GREEN;
	//
	shuttles_on_ground = 0;
	last_launch_time = 0.0;
	shuttle_launch_interval = 60 * 60;
	//
	for (i = 0; i < 5; i++)
		displayListNames[i] = 0;	// empty for now!
	//
	[self setModel:@"icosahedron.dat"];
	//
	[self rescaleTo:1.0];
	//
	planet_seed = 54321;
	//
	ranrot_srand(planet_seed);
	percent_land = (ranrot_rand() % 50);
	//NSLog(@"Planet surface is %d percent land.",percent_land);
	for (i = 0; i < n_vertices; i++)
	{
		if (ranrot_rand() % 100 < percent_land)
			r_seed[i] = 0;  // land
		else
			r_seed[i] = 1;  // sea
	}
	//
	polar_color_factor = 1.0;
	//
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
	//
	isPlanet = YES;
	//
	root_planet = self;
	//
	textureData = (unsigned char *)nil;
	//
    return self;
}

- (id) initAsSunWithColor:(OOColor *) sun_color
{
	int		i;
	float	hue, sat, bri, alf;
	OOColor *color;
	//
	self = [super init];
    //
	isTextured = NO;
	//
    collision_radius = 100000.0; //  100km across
	//
	lim4k =		LIM4K;
	lim8k =		LIM8K;
	lim16k =	LIM16K;
	//
	setUpSinTable();
	//
	scan_class = CLASS_NO_DRAW;
	//
	planet_type =   PLANET_TYPE_SUN;
	//
	shuttles_on_ground = 0;
	last_launch_time = 0.0;
	shuttle_launch_interval = 60 * 60;
	//
	for (i = 0; i < 5; i++)
		displayListNames[i] = 0;	// empty for now!
	//
	[sun_color getHue:&hue saturation:&sat brightness:&bri alpha:&alf];
	//
	float hue_drift = 0.34 * (randf() - randf());

	// set the lighting color for the sun
	GLfloat r,g,b,a;
	[sun_color getRed:&r green:&g blue:&b alpha:&a];

	GLfloat	sun_ambient[] = { 0.0, 0.0, 0.0, 1.0};	// ambient light about 5%
	sun_diffuse[0] = 0.5 * (1.0 + r);	// paler
	sun_diffuse[1] = 0.5 * (1.0 + g);	// paler
	sun_diffuse[2] = 0.5 * (1.0 + b);	// paler
	sun_diffuse[3] = 1.0;	// paler
	sun_specular[0] = r;
	sun_specular[1] = g;
	sun_specular[2] = b;
	sun_specular[3] = 1.0;

	glLightfv(GL_LIGHT1, GL_AMBIENT, sun_ambient);
	glLightfv(GL_LIGHT1, GL_DIFFUSE, sun_diffuse);
	glLightfv(GL_LIGHT1, GL_SPECULAR, sun_specular);

	//
	// main disc less saturation more brightness
	color = [OOColor colorWithCalibratedHue: hue saturation: sat * 0.333 brightness: 1.0 alpha: alf];
	amb_land[0] = [color redComponent];
	amb_land[1] = [color greenComponent];
	amb_land[2] = [color blueComponent];
	amb_land[3] = 1.0;
	//
	// nearest corona much more saturation
	hue += hue_drift;
	if (hue < 0.0)	hue += 1.0;
	if (hue > 1.0)	hue -= 1.0;
	color = [OOColor colorWithCalibratedHue:hue saturation: sat * 0.625 brightness:(bri + 2.0)/3.0 alpha:alf];
	amb_polar_land[0] = [color redComponent];
	amb_polar_land[1] = [color greenComponent];
	amb_polar_land[2] = [color blueComponent];
	amb_polar_land[3] = 1.0;
	//
	// next corona slightly more saturation
	hue += hue_drift;
	if (hue < 0.0)	hue += 1.0;
	if (hue > 1.0)	hue -= 1.0;
	color = [OOColor colorWithCalibratedHue:hue saturation:sat brightness:bri alpha:alf];
	amb_sea[0] = [color redComponent];
	amb_sea[1] = [color greenComponent];
	amb_sea[2] = [color blueComponent];
	amb_sea[3] = 1.0;
	//
	// next corona 100% saturation less bright
	hue += hue_drift;
	if (hue < 0.0)	hue += 1.0;
	if (hue > 1.0)	hue -= 1.0;
	color = [OOColor colorWithCalibratedHue:hue saturation:1.0 brightness:bri * 0.75 alpha:alf];
	amb_polar_sea[0] = [color redComponent];
	amb_polar_sea[1] = [color greenComponent];
	amb_polar_sea[2] = [color blueComponent];
	amb_polar_sea[3] = 1.0;
	//
	corona_speed_factor = 1.0 / (0.5 + 2.0 * (randf() + randf()));
	corona_stage = 0.0;
	for (i = 0; i < 729; i++)
		rvalue[i] = randf();
	//
	isPlanet = YES;
	//
	root_planet = self;
	//
	textureData = (unsigned char *)nil;
	//
    return self;
}

- (id) initAsAtmosphereForPlanet:(PlanetEntity *) planet inUniverse:(Universe*) uni
{
    int		i;
	int		percent_land;
	double  aleph =  1.0 / sqrt(2.0);
	//
	BOOL	procGen = [uni doProcedurallyTexturedPlanets];
	//
	self = [super init];
	//
	percent_land = 3 + (gen_rnd_number() & 31)+(gen_rnd_number() & 31);
	//NSLog(@"Atmosphere is %d percent clear.",percent_land);
	//
	polar_color_factor = 1.0;
	//
	amb_land[0] = gen_rnd_number() / 256.0;
	amb_land[1] = gen_rnd_number() / 256.0;
	amb_land[2] = gen_rnd_number() / 256.0;
	amb_land[3] = 0.05;  // bluesky .. zero clouds
	amb_sea[0] = 0.5 + gen_rnd_number() / 512.0;
	amb_sea[1] = 0.5 + gen_rnd_number() / 512.0;
	amb_sea[2] = 0.5 + gen_rnd_number() / 512.0;
	amb_sea[3] = 0.50;  // 50% opaque clouds
	amb_polar_land[0] = gen_rnd_number() / 256.0;
	amb_polar_land[1] = gen_rnd_number() / 256.0;
	amb_polar_land[2] = gen_rnd_number() / 256.0;
	amb_polar_land[3] = 0.34;	// 25% gray clouds
	amb_polar_sea[0] = 0.9 + gen_rnd_number() / 2560.0;
	amb_polar_sea[1] = 0.9 + gen_rnd_number() / 2560.0;
	amb_polar_sea[2] = 0.9 + gen_rnd_number() / 2560.0;
	amb_polar_sea[3] = 0.75;	// 75% clouds

	atmosphere = nil;
	
	OOColor* cloudColor = [OOColor colorWithCalibratedRed: amb_sea[0] green: amb_sea[1] blue: amb_sea[2] alpha: 1.0];
	float cloud_bias = -0.01 * (float)percent_land;
	float cloud_impress = 1.0 - cloud_bias;
	
    //
	if (procGen)
	{
		textureName = [TextureStore getCloudTextureNameFor:cloudColor :cloud_impress :cloud_bias intoData: &textureData];
		isTextured = (textureName != 0);
	}
	else
	{
		textureName = 0;
		isTextured = NO;
	}
	//
    if (!planet)
    {
    	NSLog(@"ERROR Planetentity initAsAtmosphereForPlanet:NULL");
    	return self;
    }
	//
	[self setOwner: planet];
    //
	position = planet->position;
	q_rotation = planet->q_rotation;
	
	if (planet->planet_type == PLANET_TYPE_GREEN)
		collision_radius = planet->collision_radius + ATMOSPHERE_DEPTH; //  atmosphere is 500m deep only
	if (planet->planet_type == PLANET_TYPE_MINIATURE)
		collision_radius = planet->collision_radius + ATMOSPHERE_DEPTH * PLANET_MINIATURE_FACTOR; //  atmosphere is 500m deep only
	//
	shuttles_on_ground = 0;
	last_launch_time = 0.0;
	shuttle_launch_interval = 60 * 60;

	scan_class = CLASS_NO_DRAW;
	//
	q_rotation.w =  aleph;		// represents a 90 degree rotation around x axis
	q_rotation.x =  aleph;		// (I hope!)
	q_rotation.y =  0.0;
	q_rotation.z =  0.0;
	//
	planet_type =   PLANET_TYPE_ATMOSPHERE;
	//
	planet_seed =	ranrot_rand();	// random set-up for vertex colours
	//
	for (i = 0; i < 5; i++)
		displayListNames[i] = 0;	// empty for now!
	//
	[self setModel:(isTextured)? @"icostextured.dat" : @"icosahedron.dat"];
	//
	[self rescaleTo:1.0];

//	NSLog(@"DEBUG atmosphere testing [PlanetEntity initialiseBaseVertexArray]");
	[self initialiseBaseVertexArray];

//	NSLog(@"DEBUG atmosphere testing [PlanetEntity initialiseBaseTerrainArray:%d]", percent_land);
	[self initialiseBaseTerrainArray:percent_land];

//	NSLog(@"DEBUG atmosphere painting %d vertices", next_free_vertex);
	for (i =  0; i < next_free_vertex; i++)
		[self paintVertex:i :planet_seed];

//	NSLog(@"DEBUG atmosphere scaling %d vertices", next_free_vertex);
	[self scaleVertices];

	// set speed of rotation
	rotational_velocity = 0.01 + 0.02 * randf();	// 0.01 .. 0.03 avr 0.02;

	//
	usingVAR = [self OGL_InitVAR];
	//
	if (usingVAR)
		[self OGL_AssignVARMemory:sizeof(VertexData) :(void *)&vertexdata :0];
	//
	isPlanet = YES;
	//
	root_planet = planet;
	//
    return self;
}

- (id) initAsCoronaForPlanet:(PlanetEntity *) planet
{
	self = [super init];
    //
	isTextured = NO;
	//
	if (!planet)
    {
    	NSLog(@"ERROR Planetentity initAsCoronaForPlanet:NULL");
    	return self;
    }
    //
	position = planet->position;
	quaternion_set_identity(&q_rotation);
    collision_radius = planet->collision_radius + ATMOSPHERE_DEPTH * 2; //  atmosphere is 5000m deep only
	//
	shuttles_on_ground = 0;
	last_launch_time = 0.0;
	shuttle_launch_interval = 60 * 60;
	//
	scan_class = CLASS_NO_DRAW;
	//
	planet_type = PLANET_TYPE_CORONA;
	//
	amb_land[0] = 0.85;
	amb_land[1] = 0.85;
	amb_land[2] = 1.0;
	amb_land[3] = 1.0;  // blue color

	atmosphere = nil;

	[self setOwner:planet];
	//
	isPlanet = YES;
	//
	root_planet = planet;
	//
    return self;
}

- (id) initWithSeed:(Random_Seed) p_seed fromUniverse:(Universe *) uni
{
    int		i;
	int		percent_land;
	double  aleph =  1.0 / sqrt(2.0);
	//
	BOOL procGen = [uni doProcedurallyTexturedPlanets];
	//
	self = [super init];
    //
	isTextured = NO;
	textureName = [TextureStore getTextureNameFor:@"metal.png"];	//debug texture
	//
	planet_seed = p_seed.a * 13 + p_seed.c * 11 + p_seed.e * 7;	// pseudo-random set-up for vertex colours
	//
	seed_for_planet_description(p_seed);
	//
	NSMutableDictionary*   planetinfo = [NSMutableDictionary dictionaryWithDictionary:[uni generateSystemData:p_seed]];
	int radius_km =		[(NSNumber *)[planetinfo objectForKey:KEY_RADIUS] intValue];
	int techlevel =		[(NSNumber *)[planetinfo objectForKey:KEY_TECHLEVEL] intValue];
	//NSLog(@"Generating planet %@ with radius %dkm",[planetinfo objectForKey:KEY_NAME],radius_km);
	if ([planetinfo objectForKey:@"texture"])
	{
		textureName = [TextureStore getTextureNameFor:(NSString*)[planetinfo objectForKey:@"texture"]];
		isTextured = (textureName != 0);
	}

	shuttles_on_ground = 1 + floor(techlevel * 0.5);
	last_launch_time = 0.0;
	shuttle_launch_interval = 3600.0 / shuttles_on_ground; // all are launched in an hour
	last_launch_time = -(ranrot_rand() % 60) * shuttle_launch_interval/60.0;
	last_launch_time = 30.0 - shuttle_launch_interval;   // debug - launch 30s after player enters universe

	//NSLog(@"shuttles on ground:%d launch_interval:%.1f minutes", shuttles_on_ground, shuttle_launch_interval/60);

    //collision_radius = 25000.0; //  25km across
	collision_radius = radius_km * 10.0; // scale down by a factor of 100 !
	//
	scan_class = CLASS_NO_DRAW;
	//
	q_rotation.w =  aleph;		// represents a 90 degree rotation around x axis
	q_rotation.x =  aleph;		// (I hope!)
	q_rotation.y =  0.0;
	q_rotation.z =  0.0;
	//
	planet_type =   PLANET_TYPE_GREEN;  // generic planet type
	//
	for (i = 0; i < 5; i++)
		displayListNames[i] = 0;	// empty for now!
	//
	[self setModel:(procGen)? @"icostextured.dat" : @"icosahedron.dat"];
	//
	[self rescaleTo:1.0];
	//

	percent_land = 24 + (gen_rnd_number() % 48);

	//// possibly get percent_land from planetinfo.plist entry
	//
	if ([planetinfo objectForKey:@"percent_land"])
	{
		percent_land = [(NSNumber *)[planetinfo objectForKey:@"percent_land"] intValue];
	}

	// save the current random number generator seed
	RNG_Seed saved_seed = currentRandomSeed();

	//NSLog(@"Planet surface is %d percent land.",percent_land);
	for (i = 0; i < n_vertices; i++)
	{
		if (gen_rnd_number() < 256 * percent_land / 100)
			r_seed[i] = 0;  // land
		else
			r_seed[i] = 100;  // sea
	}
	[planetinfo setObject:[NSNumber numberWithFloat:0.01 * percent_land] forKey:@"land_fraction"];
	//
	polar_color_factor = 1.0;
	//
	Vector land_hsb, sea_hsb, land_polar_hsb, sea_polar_hsb;

	land_hsb.x = gen_rnd_number() / 256.0;  land_hsb.y = gen_rnd_number() / 256.0;  land_hsb.z = 0.5 + gen_rnd_number() / 512.0;
	sea_hsb.x = gen_rnd_number() / 256.0;  sea_hsb.y = gen_rnd_number() / 256.0;  sea_hsb.z = 0.5 + gen_rnd_number() / 512.0;
	while (dot_product(land_hsb,sea_hsb) > .80) // make sure land and sea colors differ significantly
	{
		sea_hsb.x = gen_rnd_number() / 256.0;  sea_hsb.y = gen_rnd_number() / 256.0;  sea_hsb.z = 0.5 + gen_rnd_number() / 512.0;
	}

	//// possibly get land_hsb and sea_hsb from planetinfo.plist entry
	//
	if ([planetinfo objectForKey:@"land_hsb_color"])
		land_hsb = [Entity vectorFromString:(NSString *)[planetinfo objectForKey:@"land_hsb_color"]];
	if ([planetinfo objectForKey:@"sea_hsb_color"])
		sea_hsb = [Entity vectorFromString:(NSString *)[planetinfo objectForKey:@"sea_hsb_color"]];
	//
	////

	// polar areas are brighter but have less color (closer to white)
	//
	land_polar_hsb.x = land_hsb.x;  land_polar_hsb.y = (land_hsb.y / 5.0);  land_polar_hsb.z = 1.0 - (land_hsb.z / 10.0);
	sea_polar_hsb.x = sea_hsb.x;  sea_polar_hsb.y = (sea_hsb.y / 5.0);  sea_polar_hsb.z = 1.0 - (sea_hsb.z / 10.0);

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

	[planetinfo setObject:amb_land_color forKey:@"land_color"];
	[planetinfo setObject:amb_sea_color forKey:@"sea_color"];
	[planetinfo setObject:amb_polar_land_color forKey:@"polar_land_color"];
	[planetinfo setObject:amb_polar_sea_color forKey:@"polar_sea_color"];
	
	if (procGen)
	{
		textureName = [TextureStore getPlanetTextureNameFor: planetinfo intoData: &textureData];
		isTextured = (textureName != 0);
	}
	else
	{
		textureName = 0;
		isTextured = NO;
	}

//	NSLog(@"DEBUG testing [PlanetEntity initialiseBaseVertexArray]");
	[self initialiseBaseVertexArray];

//	NSLog(@"DEBUG testing [PlanetEntity initialiseBaseTerrainArray:%d]", percent_land);
	setRandomSeed(saved_seed);
	[self initialiseBaseTerrainArray:percent_land];

//	NSLog(@"DEBUG painting %d vertices", next_free_vertex);
	for (i =  0; i < next_free_vertex; i++)
		[self paintVertex:i :planet_seed];

//	NSLog(@"DEBUG scaling %d vertices", next_free_vertex);
	[self scaleVertices];

	// set speed of rotation
	rotational_velocity = 0.005 * randf();	// 0.0 .. 0.005 avr 0.0025;
	if ([planetinfo objectForKey:@"rotation_speed"])
		rotational_velocity = [[planetinfo objectForKey:@"rotation_speed"] floatValue];
	if ([planetinfo objectForKey:@"rotation_speed_factor"])
		rotational_velocity *= [[planetinfo objectForKey:@"rotation_speed_factor"] floatValue];
	// do atmosphere
	//
	[self setUniverse:uni];
	atmosphere = [[PlanetEntity alloc] initAsAtmosphereForPlanet:self inUniverse:uni];
	[atmosphere setUniverse:universe];

	//
	usingVAR = [self OGL_InitVAR];
	//
	if (usingVAR)
		[self OGL_AssignVARMemory:sizeof(VertexData) :(void *)&vertexdata :0];
	//
	//
	isPlanet = YES;
	//
	root_planet = self;
	//
    return self;
}

- (id) initMiniatureFromPlanet:(PlanetEntity*) planet inUniverse:(Universe*) uni
{    
    int		i;
	double  aleph =  1.0 / sqrt(2.0);
	//
	self = [super init];
    //
	isTextured = [planet isTextured];
	textureName = [planet textureName];	//debug texture
	//
	planet_seed = [planet planet_seed];	// pseudo-random set-up for vertex colours
	
	shuttles_on_ground = 0;
	last_launch_time = 8400.0;
	shuttle_launch_interval = 8400.0;
	
	//NSLog(@"shuttles on ground:%d launch_interval:%.1f minutes", shuttles_on_ground, shuttle_launch_interval/60);
	
	collision_radius = [planet collisionRadius] * PLANET_MINIATURE_FACTOR; // teeny tiny
	//
	scan_class = CLASS_NO_DRAW;
	status = STATUS_COCKPIT_DISPLAY;
	//
	q_rotation.w =  aleph;		// represents a 90 degree rotation around x axis
	q_rotation.x =  aleph;		// (I hope!)
	q_rotation.y =  0.0;
	q_rotation.z =  0.0;
	//
	planet_type = PLANET_TYPE_MINIATURE;  // generic planet type
	//
	for (i = 0; i < 5; i++)
		displayListNames[i] = 0;	// empty for now!
	//
	[self setModel:(isTextured)? @"icostextured.dat" : @"icosahedron.dat"];
	//
	[self rescaleTo:1.0];
	//
	for (i = 0; i < 4; i++)
	{
		amb_land[i] =		[planet amb_land][i];
		amb_sea[i] =		[planet amb_sea][i];
		amb_polar_land[i] =	[planet amb_polar_land][i];
		amb_polar_sea[i] =	[planet amb_polar_sea][i];
	}
		
	[self initialiseBaseVertexArray];
	
	int* planet_r_seed = [planet r_seed];
	for (i = 0; i < n_vertices; i++)
		r_seed[i] = planet_r_seed[i];  // land or sea
	[self initialiseBaseTerrainArray: -1];	// use the vertices we just set up
	
	for (i =  0; i < next_free_vertex; i++)
		[self paintVertex:i :planet_seed];
	
	[self scaleVertices];
	
	// set speed of rotation
	rotational_velocity = 0.05;
	
	// do atmosphere
	//
	atmosphere = [[PlanetEntity alloc] initAsAtmosphereForPlanet:self inUniverse:uni];
	[atmosphere setUniverse:universe];

	//
	usingVAR = [self OGL_InitVAR];
	//
	if (usingVAR)
		[self OGL_AssignVARMemory:sizeof(VertexData) :(void *)&vertexdata :0];
	//
	//
	isPlanet = YES;
	//
	root_planet = self;
	//
    return self;
}

- (id) initPlanetFromDictionary:(NSDictionary*) dict inUniverse:(Universe *) uni
{
    int		i;
	int		percent_land;
	double  aleph =  1.0 / sqrt(2.0);
	//
	BOOL procGen = [uni doProcedurallyTexturedPlanets];
	//
	self = [super init];
	//
	Random_Seed	p_seed = [uni systemSeed];
    //
	if ([dict objectForKey:@"texture"])
	{
		textureName = [TextureStore getTextureNameFor:(NSString*)[dict objectForKey:@"texture"]];
		isTextured = (textureName != 0);
	}
	else
	{
		if (procGen)
		{
			textureName = [TextureStore getPlanetTextureNameFor: dict intoData: &textureData];
			isTextured = (textureName != 0);
		}
		else
		{
			textureName = 0;
			isTextured = NO;
		}
	}
    //
	if ([dict objectForKey:@"seed"])
	{
		NSArray* tokens = [Entity scanTokensFromString:(NSString*)[dict objectForKey:@"seed"]];
		if ([tokens count] != 6)
			NSLog(@"ERROR planet seed '%@' requires 6 values", [dict objectForKey:@"seed"]);
		else
		{
			p_seed.a = [[tokens objectAtIndex:0] intValue];
			p_seed.b = [[tokens objectAtIndex:1] intValue];
			p_seed.c = [[tokens objectAtIndex:2] intValue];
			p_seed.d = [[tokens objectAtIndex:3] intValue];
			p_seed.e = [[tokens objectAtIndex:4] intValue];
			p_seed.f = [[tokens objectAtIndex:5] intValue];
		}
		planet_seed = p_seed.a * 13 + p_seed.c * 11 + p_seed.e * 7;	// pseudo-random set-up for vertex colours
		//
	}
	//
	seed_for_planet_description(p_seed);
	//
	NSDictionary*   planetinfo = [uni generateSystemData:p_seed];
	int radius_km =		[(NSNumber *)[planetinfo objectForKey:KEY_RADIUS] intValue];
	if ([dict objectForKey:@"radius"])
	{
		radius_km = [[dict objectForKey:@"radius"] intValue];
	}

	shuttles_on_ground = 0;
	last_launch_time = 0.0;
	shuttle_launch_interval = 3600.0 / shuttles_on_ground; // all are launched in an hour
	last_launch_time = 3600.0;

	//NSLog(@"shuttles on ground:%d launch_interval:%.1f minutes", shuttles_on_ground, shuttle_launch_interval/60);

	collision_radius = radius_km * 10.0; // scale down by a factor of 100 !
	//
	scan_class = CLASS_NO_DRAW;
	//
	q_rotation.w =  aleph;		// represents a 90 degree rotation around x axis
	q_rotation.x =  aleph;		// (I hope!)
	q_rotation.y =  0.0;
	q_rotation.z =  0.0;
	//
	planet_type =   PLANET_TYPE_GREEN;  // generic planet type
	//
	for (i = 0; i < 5; i++)
		displayListNames[i] = 0;	// empty for now!
	//
	[self setModel:(isTextured)? @"icostextured.dat" : @"icosahedron.dat"];
	//
	[self rescaleTo:1.0];
	//

	percent_land = (gen_rnd_number() % 48);
	if ([dict objectForKey:@"percent_land"])
	{
		percent_land = [(NSNumber *)[dict objectForKey:@"percent_land"] intValue];
	}
	if (isTextured)
		percent_land = 0;

	// save the current random number generator seed
	RNG_Seed saved_seed = currentRandomSeed();

	//NSLog(@"Planet surface is %d percent land.",percent_land);
	for (i = 0; i < n_vertices; i++)
	{
		if (gen_rnd_number() < 256 * percent_land / 100)
			r_seed[i] = 0;  // land
		else
			r_seed[i] = 100;  // sea
	}
	//
	polar_color_factor = 1.0;
	if ([dict objectForKey:@"polar_color_factor"])
		polar_color_factor = [[dict objectForKey:@"polar_color_factor"] doubleValue];
	//
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

	//// possibly get land_hsb and sea_hsb from planetinfo.plist entry
	//
	if ([dict objectForKey:@"land_hsb_color"])
	{
		land_hsb = [Entity vectorFromString:(NSString *)[dict objectForKey:@"land_hsb_color"]];
	}
	if ([dict objectForKey:@"sea_hsb_color"])
	{
		sea_hsb = [Entity vectorFromString:(NSString *)[dict objectForKey:@"sea_hsb_color"]];
	}
	//
	////

	// polar areas are brighter but have less color (closer to white)
	//
	land_polar_hsb.x = land_hsb.x;  land_polar_hsb.y = (land_hsb.y / 5.0);  land_polar_hsb.z = 1.0 - (land_hsb.z / 10.0);
	sea_polar_hsb.x = sea_hsb.x;  sea_polar_hsb.y = (sea_hsb.y / 5.0);  sea_polar_hsb.z = 1.0 - (sea_hsb.z / 10.0);

	amb_land[0] = [[OOColor colorWithCalibratedHue:land_hsb.x saturation:land_hsb.y brightness:land_hsb.z alpha:1.0] redComponent];
	amb_land[1] = [[OOColor colorWithCalibratedHue:land_hsb.x saturation:land_hsb.y brightness:land_hsb.z alpha:1.0] blueComponent];
	amb_land[2] = [[OOColor colorWithCalibratedHue:land_hsb.x saturation:land_hsb.y brightness:land_hsb.z alpha:1.0] greenComponent];
	amb_land[3] = 1.0;
	amb_sea[0] = [[OOColor colorWithCalibratedHue:sea_hsb.x saturation:sea_hsb.y brightness:sea_hsb.z alpha:1.0] redComponent];
	amb_sea[1] = [[OOColor colorWithCalibratedHue:sea_hsb.x saturation:sea_hsb.y brightness:sea_hsb.z alpha:1.0] blueComponent];
	amb_sea[2] = [[OOColor colorWithCalibratedHue:sea_hsb.x saturation:sea_hsb.y brightness:sea_hsb.z alpha:1.0] greenComponent];
	amb_sea[3] = 1.0;
	amb_polar_land[0] = [[OOColor colorWithCalibratedHue:land_polar_hsb.x saturation:land_polar_hsb.y brightness:land_polar_hsb.z alpha:1.0] redComponent];
	amb_polar_land[1] = [[OOColor colorWithCalibratedHue:land_polar_hsb.x saturation:land_polar_hsb.y brightness:land_polar_hsb.z alpha:1.0] blueComponent];
	amb_polar_land[2] = [[OOColor colorWithCalibratedHue:land_polar_hsb.x saturation:land_polar_hsb.y brightness:land_polar_hsb.z alpha:1.0] greenComponent];
	amb_polar_land[3] = 1.0;
	amb_polar_sea[0] = [[OOColor colorWithCalibratedHue:sea_polar_hsb.x saturation:sea_polar_hsb.y brightness:sea_polar_hsb.z alpha:1.0] redComponent];
	amb_polar_sea[1] = [[OOColor colorWithCalibratedHue:sea_polar_hsb.x saturation:sea_polar_hsb.y brightness:sea_polar_hsb.z alpha:1.0] blueComponent];
	amb_polar_sea[2] = [[OOColor colorWithCalibratedHue:sea_polar_hsb.x saturation:sea_polar_hsb.y brightness:sea_polar_hsb.z alpha:1.0] greenComponent];
	amb_polar_sea[3] = 1.0;

//	NSLog(@"DEBUG testing [PlanetEntity initialiseBaseVertexArray]");
	[self initialiseBaseVertexArray];

//	NSLog(@"DEBUG testing [PlanetEntity initialiseBaseTerrainArray:%d]", percent_land);
	setRandomSeed(saved_seed);
	[self initialiseBaseTerrainArray:percent_land];

//	NSLog(@"DEBUG painting %d vertices", next_free_vertex);
	for (i =  0; i < next_free_vertex; i++)
		[self paintVertex:i :planet_seed];

//	NSLog(@"DEBUG scaling %d vertices", next_free_vertex);
	[self scaleVertices];

	// set speed of rotation
	rotational_velocity = 0.01 * randf();	// 0.0 .. 0.01 avr 0.005;
	if ([dict objectForKey:@"rotational_velocity"])
		rotational_velocity = [[dict objectForKey:@"rotational_velocity"] doubleValue];

	// do atmosphere
	//
	atmosphere = [[PlanetEntity alloc] initAsAtmosphereForPlanet:self inUniverse:uni];
	[atmosphere setUniverse:universe];

	// set energy
	energy = collision_radius * 1000.0;

	//
	usingVAR = [self OGL_InitVAR];
	//
	if (usingVAR)
		[self OGL_AssignVARMemory:sizeof(VertexData) :(void *)&vertexdata :0];
	//
	isPlanet = YES;
	//
	root_planet = self;
	//
    return self;
}

- (id) initMoonFromDictionary:(NSDictionary*) dict inUniverse:(Universe *) uni
{
    int		i;
	int		percent_land;
	double  aleph =  1.0 / sqrt(2.0);
	//
	self = [super init];
	//
	Random_Seed	p_seed = [uni systemSeed];
    //
	planet_seed = p_seed.a * 7 + p_seed.c * 11 + p_seed.e * 13;	// pseudo-random set-up for vertex colours
	//
	if ([dict objectForKey:@"texture"])
	{
		textureName = [TextureStore getTextureNameFor:(NSString*)[dict objectForKey:@"texture"]];
		isTextured = (textureName != 0);
	}
	else
	{
		isTextured = NO;
		textureName = [TextureStore getTextureNameFor:@"metal.png"];	//debug texture
	}
    //
	if ([dict objectForKey:@"seed"])
	{
		NSArray* tokens = [Entity scanTokensFromString:(NSString*)[dict objectForKey:@"seed"]];
		if ([tokens count] != 6)
			NSLog(@"ERROR planet seed '%@' requires 6 values", [dict objectForKey:@"seed"]);
		else
		{
			p_seed.a = [[tokens objectAtIndex:0] intValue];
			p_seed.b = [[tokens objectAtIndex:1] intValue];
			p_seed.c = [[tokens objectAtIndex:2] intValue];
			p_seed.d = [[tokens objectAtIndex:3] intValue];
			p_seed.e = [[tokens objectAtIndex:4] intValue];
			p_seed.f = [[tokens objectAtIndex:5] intValue];
		}
	}
	//
	seed_for_planet_description(p_seed);
	//
	NSDictionary*   planetinfo = [uni generateSystemData:p_seed];
	int radius_km =		[(NSNumber *)[planetinfo objectForKey:KEY_RADIUS] intValue];
	if ([dict objectForKey:@"radius"])
	{
		radius_km = [[dict objectForKey:@"radius"] intValue];
	}

	shuttles_on_ground = 0;
	last_launch_time = 0.0;
	shuttle_launch_interval = 3600.0 / shuttles_on_ground; // all are launched in an hour
	last_launch_time = 3600.0;

	//NSLog(@"shuttles on ground:%d launch_interval:%.1f minutes", shuttles_on_ground, shuttle_launch_interval/60);

	collision_radius = radius_km * 10.0; // scale down by a factor of 100 !
	//
	scan_class = CLASS_NO_DRAW;
	//
	q_rotation.w =  aleph;		// represents a 90 degree rotation around x axis
	q_rotation.x =  aleph;		// (I hope!)
	q_rotation.y =  0.0;
	q_rotation.z =  0.0;
	//
	planet_type =   PLANET_TYPE_GREEN;  // generic planet type
	//
	for (i = 0; i < 5; i++)
		displayListNames[i] = 0;	// empty for now!
	//
	[self setModel:(isTextured)? @"icostextured.dat" : @"icosahedron.dat"];
	//
	[self rescaleTo:1.0];
	//

	percent_land = (gen_rnd_number() % 48);
	if ([dict objectForKey:@"percent_land"])
	{
		percent_land = [(NSNumber *)[dict objectForKey:@"percent_land"] intValue];
	}
	if (isTextured)
		percent_land = 100;

	// save the current random number generator seed
	RNG_Seed saved_seed = currentRandomSeed();

	//NSLog(@"Planet surface is %d percent land.",percent_land);
	for (i = 0; i < n_vertices; i++)
	{
		if (gen_rnd_number() < 256 * percent_land / 100)
			r_seed[i] = 0;  // land
		else
			r_seed[i] = 100;  // sea
	}
	//
	polar_color_factor = 1.0;
	if ([dict objectForKey:@"polar_color_factor"])
		polar_color_factor = [[dict objectForKey:@"polar_color_factor"] doubleValue];
	//
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

	//// possibly get land_hsb and sea_hsb from planetinfo.plist entry
	//
	if ([dict objectForKey:@"land_hsb_color"])
	{
		land_hsb = [Entity vectorFromString:(NSString *)[dict objectForKey:@"land_hsb_color"]];
	}
	if ([dict objectForKey:@"sea_hsb_color"])
	{
		sea_hsb = [Entity vectorFromString:(NSString *)[dict objectForKey:@"sea_hsb_color"]];
	}
	//
	////

	// polar areas are brighter but have less color (closer to white)
	//
	land_polar_hsb.x = land_hsb.x;  land_polar_hsb.y = (land_hsb.y / 5.0);  land_polar_hsb.z = 1.0 - (land_hsb.z / 10.0);
	sea_polar_hsb.x = sea_hsb.x;  sea_polar_hsb.y = (sea_hsb.y / 5.0);  sea_polar_hsb.z = 1.0 - (sea_hsb.z / 10.0);

	amb_land[0] = [[OOColor colorWithCalibratedHue:land_hsb.x saturation:land_hsb.y brightness:land_hsb.z alpha:1.0] redComponent];
	amb_land[1] = [[OOColor colorWithCalibratedHue:land_hsb.x saturation:land_hsb.y brightness:land_hsb.z alpha:1.0] blueComponent];
	amb_land[2] = [[OOColor colorWithCalibratedHue:land_hsb.x saturation:land_hsb.y brightness:land_hsb.z alpha:1.0] greenComponent];
	amb_land[3] = 1.0;
	amb_sea[0] = [[OOColor colorWithCalibratedHue:sea_hsb.x saturation:sea_hsb.y brightness:sea_hsb.z alpha:1.0] redComponent];
	amb_sea[1] = [[OOColor colorWithCalibratedHue:sea_hsb.x saturation:sea_hsb.y brightness:sea_hsb.z alpha:1.0] blueComponent];
	amb_sea[2] = [[OOColor colorWithCalibratedHue:sea_hsb.x saturation:sea_hsb.y brightness:sea_hsb.z alpha:1.0] greenComponent];
	amb_sea[3] = 1.0;
	amb_polar_land[0] = [[OOColor colorWithCalibratedHue:land_polar_hsb.x saturation:land_polar_hsb.y brightness:land_polar_hsb.z alpha:1.0] redComponent];
	amb_polar_land[1] = [[OOColor colorWithCalibratedHue:land_polar_hsb.x saturation:land_polar_hsb.y brightness:land_polar_hsb.z alpha:1.0] blueComponent];
	amb_polar_land[2] = [[OOColor colorWithCalibratedHue:land_polar_hsb.x saturation:land_polar_hsb.y brightness:land_polar_hsb.z alpha:1.0] greenComponent];
	amb_polar_land[3] = 1.0;
	amb_polar_sea[0] = [[OOColor colorWithCalibratedHue:sea_polar_hsb.x saturation:sea_polar_hsb.y brightness:sea_polar_hsb.z alpha:1.0] redComponent];
	amb_polar_sea[1] = [[OOColor colorWithCalibratedHue:sea_polar_hsb.x saturation:sea_polar_hsb.y brightness:sea_polar_hsb.z alpha:1.0] blueComponent];
	amb_polar_sea[2] = [[OOColor colorWithCalibratedHue:sea_polar_hsb.x saturation:sea_polar_hsb.y brightness:sea_polar_hsb.z alpha:1.0] greenComponent];
	amb_polar_sea[3] = 1.0;

//	NSLog(@"DEBUG testing [PlanetEntity initialiseBaseVertexArray]");
	[self initialiseBaseVertexArray];

//	NSLog(@"DEBUG testing [PlanetEntity initialiseBaseTerrainArray:%d]", percent_land);
	setRandomSeed(saved_seed);
	[self initialiseBaseTerrainArray:percent_land];

//	NSLog(@"DEBUG painting %d vertices", next_free_vertex);
	for (i =  0; i < next_free_vertex; i++)
		[self paintVertex:i :planet_seed];

//	NSLog(@"DEBUG scaling %d vertices", next_free_vertex);
	[self scaleVertices];

	// set speed of rotation
	rotational_velocity = 0.01 * randf();	// 0.0 .. 0.01 avr 0.005;
	if ([dict objectForKey:@"rotational_velocity"])
		rotational_velocity = [[dict objectForKey:@"rotational_velocity"] doubleValue];

	// do NO atmosphere
	//
	atmosphere = nil;

	energy = collision_radius * 1000.0;

	//
	usingVAR = [self OGL_InitVAR];
	//
	if (usingVAR)
		[self OGL_AssignVARMemory:sizeof(VertexData) :(void *)&vertexdata :0];
	//
	isPlanet = YES;
	//
	root_planet = self;
	//
    return self;
}

- (void) setUniverse:(Universe *)univ
{
    [super setUniverse: univ];
	if (atmosphere)
		[atmosphere setUniverse:univ];
}

- (void) dealloc
{
    if (atmosphere)
		[atmosphere release];
	if (textureData)
		free((void *) textureData);
	[super dealloc];
}

- (NSString*) description
{
	NSString* type_string;
	switch (planet_type)
	{
		case PLANET_TYPE_MINIATURE :
			type_string = @"PLANET_TYPE_MINIATURE";	break;
		case PLANET_TYPE_SUN :
			type_string = @"PLANET_TYPE_SUN";	break;
		case PLANET_TYPE_GREEN :
			type_string = @"PLANET_TYPE_GREEN";	break;
		case PLANET_TYPE_CORONA :
			type_string = @"PLANET_TYPE_CORONA";	break;
		case PLANET_TYPE_ATMOSPHERE :
			type_string = @"PLANET_TYPE_ATMOSPHERE";	break;
		default :
			type_string = @"UNKNOWN";
	}
	NSString* result = [[NSString alloc] initWithFormat:@"<PlanetEntity %@ diameter %.3fkm>", type_string, 0.001 * collision_radius];
	return [result autorelease];
}

- (BOOL) canCollide
{
	switch (planet_type)
	{
		case PLANET_TYPE_MINIATURE :
		case PLANET_TYPE_ATMOSPHERE :
		case PLANET_TYPE_CORONA :
			return NO;
			break;
		case PLANET_TYPE_GREEN :
		case PLANET_TYPE_SUN :
			return YES;
			break;
	}
	return YES;
}

- (BOOL) checkCloseCollisionWith:(Entity *)other
{
	if (debug & DEBUG_COLLISIONS)
		NSLog(@"PLANET Collision!");
	
	if (!other)
		return NO;
	if (other->isShip)
	{
		ShipEntity *ship = (ShipEntity *)other;
		if ([[ship roles] isEqual:@"shuttle"])
		{
			[ship landOnPlanet];
			if ([ship reportAImessages])
				NSLog(@"DEBUG %@ landed on planet %@", other, self);
			return NO;
		}
		if ([ship reportAImessages])
		{
			Vector p1 = ship->position;
			NSLog(@"DEBUG %@ %d collided with planet at (%.1f,%.1f,%.1f)",[ship name], [ship universal_id], p1.x,p1.y,p1.z);
		}
	}

	return YES;
}


- (void) update:(double) delta_t
{
	if (usingVAR)
		[self OGL_UpdateVAR];

	[super update:delta_t];
	sqrt_zero_distance = sqrt(zero_distance);

	switch (planet_type)
	{
		case PLANET_TYPE_GREEN :
		{
			double ugt = [universe getTime];

			if ((shuttles_on_ground > 0)&&(ugt > last_launch_time + shuttle_launch_interval))
			{
				[self launchShuttle];
				shuttles_on_ground--;
				last_launch_time = ugt;
			}
		}
		//
		case PLANET_TYPE_MINIATURE :
		// normal planetary rotation
		quaternion_rotate_about_y( &q_rotation, rotational_velocity * delta_t);
		quaternion_normalise(&q_rotation);
		quaternion_into_gl_matrix(q_rotation, rotMatrix);

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
				[universe setSky_clear_color:0.8 * aleph * aleph :0.8 * aleph * aleph :0.9 * aleph :aleph];	// test - blue
			}
		}
		break;

		case PLANET_TYPE_ATMOSPHERE :
		{
			// atmospheric rotation
			quaternion_rotate_about_y( &q_rotation, rotational_velocity * delta_t);
			quaternion_normalise(&q_rotation);
			quaternion_into_gl_matrix(q_rotation, rotMatrix);
		}
		break;

		case PLANET_TYPE_CORONA :
		case PLANET_TYPE_SUN :
		{
			// new billboard routine (working at last!)
			PlayerEntity* player = (PlayerEntity*)[universe entityZero];
			Vector v0 = position;
			Vector p0 = (player)? player->position: make_vector( 0.0f, 0.0f, 0.0f);
			v0.x -= p0.x;	v0.y -= p0.y;	v0.z -= p0.z; // vector from player to position

			if (v0.x||v0.y||v0.z)
				v0 = unit_vector(&v0);
			else
				v0.z = 1.0;
			//equivalent of v_forward

			Vector arb1;
			if ((v0.x == 0.0)&&(v0.y == 0.0))
			{
				arb1.x = 1.0;   arb1.y = 0.0; arb1.z = 0.0; // arbitrary axis - not aligned with v0
			}
			else
			{
				arb1.x = 0.0;   arb1.y = 0.0; arb1.z = 1.0;
			}

			Vector v1 = cross_product( v0, arb1 ); // 90 degrees to (v0 x arb1)
			//equivalent of v_right

			Vector v2 = cross_product( v0, v1 );   // 90 degrees to (v0 x v1)
			//equivalent of v_up

			vectors_into_gl_matrix( v0, v1, v2, rotMatrix);

			if (planet_type == PLANET_TYPE_CORONA)
			{
				Vector v_sun = [universe sun]->position;
				Vector v_p = (player)? player->position: make_vector( 0.0f, 0.0f, 0.0f);
				v_sun.x -= v_p.x;	v_sun.y -= v_p.y;	v_sun.z -= v_p.z;
				if (v_sun.x||v_sun.y||v_sun.z)
					v_sun = unit_vector(&v_sun);
				else
					v_sun.z = 1.0;
				polar_color_factor = dot_product( v_sun, v0);
			}

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
							[universe setSky_clear_color:0 :0 :0 :0];	// back to black
						else
							[universe setSky_clear_color:sky_bri :sky_bri :sky_bri : 1];	// whiteout
						if (sky_bri == 1.0)
							NSLog(@"DEBUG NOVA original radius %.1f", collision_radius);
						amb_land[0] = 1.0;	amb_land[1] = 1.0;	amb_land[2] = 1.0;	amb_land[3] = 1.0;
						velocity.y += delta_t;
						[self setRadius: collision_radius + delta_t * velocity.z];
					}
					else
					{
						NSLog(@"DEBUG NOVA final radius %.1f", collision_radius);
						// reset at the new size
						velocity = make_vector( 0.0f, 0.0f, 0.0f);
						throw_sparks = YES;	// keep throw_sparks at YES to indicate the higher temperature
					}
				}
			}

			// update corona
			if (![universe reducedDetail])
			{
				corona_stage += corona_speed_factor * delta_t;
				if (corona_stage > 1.0)
				{
					 int i;
					 corona_stage -= 1.0;
					 for (i = 0; i < 369; i++)
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


- (void) setPosition:(Vector) posn
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

- (void) setModel:(NSString *) modelName
{
    double  old_collision_radius = collision_radius;
    [super setModel:modelName];
	collision_radius = old_collision_radius;	// preserve the radius
	//NSLog(@"Planet collision radius preserved!");
}


- (void) drawEntity:(BOOL) immediate :(BOOL) translucent;
{
	int		subdivideLevel =	2;		// 4 is probably the maximum!

	double  drawFactor = [(MyOpenGLView *)[universe gameView] viewSize].width / 100.0;
	double  drawRatio2 = drawFactor * collision_radius / sqrt_zero_distance; // equivalent to size on screen in pixels

	if ([universe breakPatternHide])   return; // DON'T DRAW

	if (zero_distance > 0.0)
	{
		subdivideLevel = 2 + floor(drawRatio2);
		if (subdivideLevel > 4)
			subdivideLevel = 4;
	}
	
	if (planet_type == PLANET_TYPE_MINIATURE)
		subdivideLevel = [universe reducedDetail]? 3 : 4 ;		// max detail or less
		
	lastSubdivideLevel = subdivideLevel;	// record
	
	glFrontFace(GL_CW);			// face culling - front faces are AntiClockwise!

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
		case PLANET_TYPE_ATMOSPHERE :
			if (root_planet)
				subdivideLevel = root_planet->lastSubdivideLevel;	// copy it from the planet (stops jerky LOD and such)
			glMultMatrixf(rotMatrix);	// rotate the clouds!
		case PLANET_TYPE_GREEN :
		case PLANET_TYPE_MINIATURE :
			if (!translucent)
			{
				GLfloat mat1[]		= { 1.0, 1.0, 1.0, 1.0 };	// opaque white

				if (!isTextured)
					glDisable(GL_TEXTURE_2D);	// stop any problems from this being left on!
				else
				{
					glEnable(GL_TEXTURE_2D);
					glTexEnvfv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_COLOR, mat1);
					glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);	//wrap around horizontally
				}

				glShadeModel(GL_SMOOTH);
				
				// far enough away to draw flat ?
				if (ignoreDepthBuffer)
					glDisable(GL_DEPTH_TEST);

				glColor4fv(mat1);
				glMaterialfv(GL_FRONT, GL_AMBIENT_AND_DIFFUSE, mat1);

				glFrontFace(GL_CCW);
				if (displayListNames[subdivideLevel] != 0)
				{
					//
					glDisableClientState(GL_INDEX_ARRAY);
					glDisableClientState(GL_EDGE_FLAG_ARRAY);
					//
					if (!isTextured)
					{
						glDisableClientState(GL_TEXTURE_COORD_ARRAY);
						//
						glEnableClientState(GL_COLOR_ARRAY);
						glColorPointer( 4, GL_FLOAT, 0, vertexdata.color_array);
					}
					else
					{
						glEnableClientState(GL_COLOR_ARRAY);		// test shading
						glColorPointer( 4, GL_FLOAT, 0, vertexdata.color_array);
						//
						glEnableClientState(GL_TEXTURE_COORD_ARRAY);
						glTexCoordPointer( 2, GL_FLOAT, 0, vertexdata.uv_array);
						glBindTexture(GL_TEXTURE_2D, textureName);
						glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
						glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);	//wrap around horizontally
					}
					//
					glEnableClientState(GL_VERTEX_ARRAY);
					glVertexPointer( 3, GL_FLOAT, 0, vertexdata.vertex_array);
					glEnableClientState(GL_NORMAL_ARRAY);
					glNormalPointer(GL_FLOAT, 0, vertexdata.normal_array);
					//
					glCallList(displayListNames[subdivideLevel]);
					//
				}
				else
				{
					glDisableClientState(GL_INDEX_ARRAY);
					glDisableClientState(GL_EDGE_FLAG_ARRAY);
					if (!isTextured)
					{
						glDisableClientState(GL_TEXTURE_COORD_ARRAY);
						//
						glEnableClientState(GL_COLOR_ARRAY);
						glColorPointer( 4, GL_FLOAT, 0, vertexdata.color_array);
					}
					else
					{
						glEnableClientState(GL_COLOR_ARRAY);		// test shading
						glColorPointer( 4, GL_FLOAT, 0, vertexdata.color_array);
						//
						glEnableClientState(GL_TEXTURE_COORD_ARRAY);
						glTexCoordPointer( 2, GL_FLOAT, 0, vertexdata.uv_array);
						glBindTexture(GL_TEXTURE_2D, textureName);
						glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
						glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);	//wrap around horizontally
					}
					//
					glEnableClientState(GL_VERTEX_ARRAY);
					glVertexPointer( 3, GL_FLOAT, 0, vertexdata.vertex_array);
					glEnableClientState(GL_NORMAL_ARRAY);
					glNormalPointer(GL_FLOAT, 0, vertexdata.normal_array);
					//
					displayListNames[subdivideLevel] = glGenLists(1);
					if (displayListNames[subdivideLevel] != 0)	// sanity check
					{
						//NSLog(@"Generating planet data for subdivide %d",subdivideLevel);
						glNewList(displayListNames[subdivideLevel], GL_COMPILE);
						//
						glColor4fv(mat1);
						glMaterialfv(GL_FRONT, GL_AMBIENT_AND_DIFFUSE, mat1);
						glColorMaterial(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE);
						glEnable(GL_COLOR_MATERIAL);
						//
						[self drawModelWithVertexArraysAndSubdivision:subdivideLevel];
						//
						glDisable(GL_COLOR_MATERIAL);
						//
						glEndList();
					}
				}
				glFrontFace(GL_CW);

				glMaterialfv(GL_FRONT, GL_AMBIENT_AND_DIFFUSE, mat1);


				if (atmosphere)
				{
					glDisable(GL_DEPTH_TEST);

					glPopMatrix();	// get old draw matrix back
					glPushMatrix();	// and store it again
					glTranslatef(position.x,position.y,position.z); // centre on the planet
					// rotate
					glMultMatrixf([atmosphere rotationMatrix]);
					// draw atmosphere entity
					[atmosphere drawEntity:immediate :translucent];

					glEnable(GL_DEPTH_TEST);
				}
				else if (ignoreDepthBuffer)
					glEnable(GL_DEPTH_TEST);

			}
			break;

		case PLANET_TYPE_SUN :
			if (!translucent)
			{
				int steps = 2 * (MAX_SUBDIVIDE - subdivideLevel);

				// far enough away to draw flat ?
				if (ignoreDepthBuffer)
					glDisable(GL_DEPTH_TEST);

				glDisable(GL_TEXTURE_2D);
				glDisable(GL_LIGHTING);
				glColor4fv( amb_land);

				glBegin(GL_TRIANGLE_FAN);
					drawBallVertices( collision_radius, steps, sqrt_zero_distance);
				glEnd();

				if (![universe reducedDetail])
				{
					glDisable(GL_DEPTH_TEST);
					if (zero_distance < lim4k)
					{
						GLfloat col1[4] = { amb_polar_land[0], amb_polar_land[1], amb_polar_land[2], 0.75};
						drawActiveCorona( collision_radius, collision_radius + cor4k, steps, sqrt_zero_distance, col1, 6);
					}
					if (zero_distance < lim8k)
					{
						GLfloat col1[4] = { amb_sea[0], amb_sea[1], amb_sea[2], 0.625};
						drawActiveCorona( collision_radius, collision_radius + cor8k, steps, sqrt_zero_distance, col1, 3);
					}
					if (zero_distance < lim16k)
					{
						GLfloat col1[4] = { amb_polar_sea[0], amb_polar_sea[1], amb_polar_sea[2], 0.5};
						drawActiveCorona( collision_radius, collision_radius + cor16k, steps, sqrt_zero_distance, col1, 0);
					}
					glEnable(GL_DEPTH_TEST);
				}
				glEnable(GL_LIGHTING);

				// far enough away to draw flat ?
				if (ignoreDepthBuffer)
					glEnable(GL_DEPTH_TEST);

			}
			break;

		case PLANET_TYPE_CORONA :
			if (!translucent)
			{
				Entity* my_owner = [universe entityForUniversalID:owner];
				GLfloat bri = 1.0 + polar_color_factor;
				GLfloat r = 0.42 * bri;
				GLfloat g = 0.42 * bri;
				GLfloat b = 0.5 * bri;

				GLfloat amb_1[4]		= {1.0, 1.0,	1.0,	1.0 };
				double  r0 = (my_owner)? my_owner->collision_radius: 5000;

				GLfloat col1[4] = { r, g, b, 1.0};
				GLfloat col2[4] = { r, g, b, 0.0};

				glDisable(GL_LIGHTING);
				glDisable(GL_DEPTH_TEST);
				glMaterialfv(GL_FRONT, GL_AMBIENT_AND_DIFFUSE, amb_1);

				drawCorona( r0, collision_radius, 6 - subdivideLevel, sqrt_zero_distance, col1, col2);

				glEnable(GL_DEPTH_TEST);
				glEnable(GL_LIGHTING);
			}
			break;
	}
	glFrontFace(GL_CCW);			// face culling - front faces are AntiClockwise!
	checkGLErrors([NSString stringWithFormat:@"PlanetEntity after drawing %@", self]);
}

void drawBall (double radius, int step, double z_distance)
{
	if ((radius <= 0)||(step < 1))
		return;
	if (radius >= z_distance) // inside the sphere
		return;
	int i;
	double s, c;
	double r = radius * z_distance / sqrt( z_distance * z_distance - radius * radius);
	glBegin(GL_TRIANGLE_FAN);
	glVertex3i( 0, 0, 0);
	for ( i = 0; i < 360; i += step )
	{
		s = r * sin_value[i];
		c = r * cos_value[i];
		glVertex3f(s,c,0.0);
	}
	glVertex3f( 0.0, r, 0.0);	//repeat the zero value to close
	glEnd();
}

void drawBallVertices (double radius, int step, double z_distance)
{
	if ((radius <= 0)||(step < 1))
		return;
	if (radius >= z_distance) // inside the sphere
		return;
	int i;
	GLfloat s, c;
	GLfloat r = radius * z_distance / sqrt( z_distance * z_distance - radius * radius);
	glVertex3i( 0, 0, 0);
	for ( i = 0; i < 360; i += step )
	{
		s = r * sin_value[i];
		c = r * cos_value[i];
		glVertex3f(s,c,0.0);
	}
	glVertex3f( 0.0, r, 0.0);	//repeat the zero value to close
}

void drawCorona (double inner_radius, double outer_radius, int step, double z_distance, GLfloat* col4v1, GLfloat* col4v2)
{
	if (inner_radius >= z_distance) // inside the sphere
		return;
	int i;
	GLfloat s0, c0, s1, c1;

	double r = inner_radius;
	double c = outer_radius;
	double z = z_distance;
	double x = sqrt( z * z - r * r);

	GLfloat r1 = r * x / z;
	GLfloat z1 = r * r / z;

	GLfloat r0 = c * x / z;
	GLfloat z0 = c * r / z;

//	NSLog(@"DEBUG r1 = %.4f  z1 = %.4f  r0 = %.4f  z0 = %.4f", r1, z1, r0, z0);

	glBegin(GL_TRIANGLE_STRIP);
	for ( i = 0; i < 360; i += step )
	{
		s1 = r1 * sin_value[i];
		c1 = r1 * cos_value[i];
		glColor4fv(col4v1);
		glVertex3f( s1, c1, -z1);
		s0 = r0 * sin_value[i];
		c0 = r0 * cos_value[i];
		glColor4fv(col4v2);
		glVertex3f( s0, c0, -z0);
	}
	glColor4fv(col4v1);
	glVertex3f( 0.0, r1, -z1);	//repeat the zero value to close
	glColor4fv(col4v2);
	glVertex3f( 0.0, r0, -z0);	//repeat the zero value to close
	glEnd();
}

void drawActiveCorona (double inner_radius, double outer_radius, int step, double z_distance, GLfloat* col4v1, int rv)
{
	if (inner_radius >= z_distance) // inside the sphere
		return;
	int i;

	NSRange activity = NSMakeRange(0.34, 1.0);

	GLfloat s0, c0, s1, c1;

	double r = inner_radius;
	double c = outer_radius;
	double z = z_distance;
	double x = sqrt( z * z - r * r);

	GLfloat r1 = r * x / z;
	GLfloat z1 = r * r / z;

	GLfloat r0 = c * x / z;
	GLfloat z0 = c * r / z;

//	NSLog(@"DEBUG r1 = %.4f  z1 = %.4f  r0 = %.4f  z0 = %.4f", r1, z1, r0, z0);

	GLfloat rv0, rv1, rv2;

	glBegin(GL_TRIANGLE_STRIP);
	for ( i = 0; i < 360; i += step )
	{
		rv0 = (1.0 - corona_stage) * rvalue[i + rv] + corona_stage * rvalue[i + rv + 360];
		rv1 = (1.0 - corona_stage) * rvalue[i + rv + 1] + corona_stage * rvalue[i + rv + 361];
		rv2 = (1.0 - corona_stage) * rvalue[i + rv + 2] + corona_stage * rvalue[i + rv + 362];

		s1 = r1 * sin_value[i];
		c1 = r1 * cos_value[i];
		glColor4f( col4v1[0] * (activity.location + rv0*activity.length), col4v1[1] * (activity.location + rv1*activity.length), col4v1[2] * (activity.location + rv2*activity.length), col4v1[3]);
		glVertex3f( s1, c1, -z1);

		s0 = r0 * sin_value[i];
		c0 = r0 * cos_value[i];
		glColor4f( col4v1[0], col4v1[1], col4v1[2], 0);
		glVertex3f( s0, c0, -z0);
	}

	rv0 = (1.0 - corona_stage) * rvalue[rv] + corona_stage * rvalue[360 + rv];
	rv1 = (1.0 - corona_stage) * rvalue[1 + rv] + corona_stage * rvalue[361 + rv];
	rv2 = (1.0 - corona_stage) * rvalue[2 + rv] + corona_stage * rvalue[362 + rv];

	glColor4f( col4v1[0] * (activity.location + rv0*activity.length), col4v1[1] * (activity.location + rv1*activity.length), col4v1[2] * (activity.location + rv2*activity.length), col4v1[3]);
	glVertex3f( 0.0, r1, -z1);	//repeat the zero value to close
	glColor4f( col4v1[0], col4v1[1], col4v1[2], 0);
	glVertex3f( 0.0, r0, -z0);	//repeat the zero value to close
	glEnd();
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


- (int) getPlanetType
{
	return planet_type;
}

- (void) setPlanetType:(int) pt
{
	planet_type = pt;
}

- (double) getRadius
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

- (double) getSqrt_zero_distance
{
	return sqrt_zero_distance;
}

- (void) rescaleTo:(double) rad
{
    int i;
	Vector  vert;

    for (i = 0; i < n_vertices; i++)
    {
		vert = vertices[i];			// not guaranteed non-zero
        if ((vert.x == 0.0)&&(vert.y == 0.0)&&(vert.z == 0.0))
			continue;
		vert = unit_vector(&vert);	// guaranteed non-zero
		vert.x *= rad;
		vert.y *= rad;
		vert.z *= rad;
		vertices[i] = vert;
	}
}

- (void) drawModelWithVertexArraysAndSubdivision: (int) subdivide
{
#ifdef GNUSTEP
// TODO: Find a suitable replacement fn for APPLE
#else
	if (usingVAR)
		glBindVertexArrayAPPLE(gVertexArrayRangeObjects[0]);
#endif

	glDrawElements( GL_TRIANGLES, 3 * n_triangles[subdivide], GL_UNSIGNED_INT, &vertexdata.index_array[triangle_start[subdivide]]);
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

	shuttle_ship = [universe getShipWithRole:@"shuttle"];   // retain count = 1
	if (shuttle_ship)
	{
		if (![shuttle_ship crew])
			[shuttle_ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: @"trader"
				andOriginalSystem: [universe systemSeed]
				inUniverse: universe]]];
				
		[shuttle_ship setPosition:launch_pos];
		[shuttle_ship setQRotation:q1];

		[shuttle_ship setScanClass: CLASS_NEUTRAL];

		[shuttle_ship setCargoFlag:CARGO_FLAG_FULL_PLENTIFUL];

		[shuttle_ship setStatus:STATUS_IN_FLIGHT];

		//[shuttle_ship setReportAImessages:YES]; // debug

		[universe addEntity:shuttle_ship];
		[[shuttle_ship getAI] setStateMachine:@"risingShuttleAI.plist"];	// must happen after adding to the universe!

		//NSLog(@"Planet %@ in universe %@ Launching shuttle: %@ %d", self, universe, [shuttle_ship name], [shuttle_ship universal_id]);

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

//	if (isTextured)
//		NSLog(@"DEBUG %@ creating textured vertex data texture_uv_array = <%x>", self, texture_uv_array);
//	else
//		NSLog(@"DEBUG %@ creating plain vertex data", self);

	if (edge_to_vertex == nil)
	{
		edge_to_vertex = [[NSMutableDictionary dictionaryWithCapacity:7680] retain];	// make a new one

		int vi,fi;
		next_free_vertex = 0;
		//
		// set first 12 or 14 vertices
		//
		for (vi = 0; vi < n_vertices; vi++)
			base_vertex_array[next_free_vertex++] =  vertices[vi];
		//
		// set first 20 triangles
		//
		triangle_start[0] = 0;
		n_triangles[0] = n_faces;
		for (fi = 0; fi < n_faces; fi++)
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
		//
		// for the next levels of subdivision simply build up from the level below!...
		//
		int sublevel;
		for (sublevel = 0; sublevel < MAX_SUBDIVIDE - 1; sublevel++)
		{
			int newlevel = sublevel + 1;
			triangle_start[newlevel] = triangle_start[sublevel] + n_triangles[sublevel] * 3;
			n_triangles[newlevel] = n_triangles[sublevel] * 4;
			//

//			NSLog(@"Building new level of subdivision - level %d.", newlevel);

			int tri;
			for (tri = 0; tri < n_triangles[sublevel]; tri++)
			{
				// get the six vertices for this group of four triangles
				int v0 = vertex_index_array[triangle_start[sublevel] + tri * 3 + 0];
				int v1 = vertex_index_array[triangle_start[sublevel] + tri * 3 + 1];
				int v2 = vertex_index_array[triangle_start[sublevel] + tri * 3 + 2];
				int v01 = baseVertexIndexForEdge( v0, v1, isTextured);	// sets it up if required
				int v12 = baseVertexIndexForEdge( v1, v2, isTextured);	// ..
				int v20 = baseVertexIndexForEdge( v2, v0, isTextured);	// ..
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

//			NSLog(@"Current total number of vertices %d.", next_free_vertex);
		}
	}

//	NSLog(@"edge_to_vertex %@", edge_to_vertex);

	// all done - copy the indices to the instance
	//
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
		base_vertex_array[vindex] = unit_vector(&base_vertex_array[vindex]);	// guaranteed non-zero

//		NSLog(@"%d [%@]= (%.3f,%.3f,%.3f)",	vindex, key, base_vertex_array[vindex].x, base_vertex_array[vindex].y, base_vertex_array[vindex].z);

		if (textured)
		{
			//calculate new texture coordinates
			//
			NSPoint	uva = NSMakePoint( texture_uv_array[va * 2], texture_uv_array[va * 2 + 1]);
			NSPoint	uvb = NSMakePoint( texture_uv_array[vb * 2], texture_uv_array[vb * 2 + 1]);
			//
			// if either of these is the polar vertex treat it specially to help with polar distortion:
			if ((uva.y == 0.0)||(uva.y == 1.0))
				uva.x = uvb.x;
			if ((uvb.y == 0.0)||(uvb.y == 1.0))
				uvb.x = uva.x;
			//
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
		for (vi = 0; vi < n_vertices; vi++)
		{
			if (gen_rnd_number() < 256 * percent_land / 100)
				base_terrain_array[vi] = 0;  // land
			else
				base_terrain_array[vi] = 100;  // sea

		}
	}
	//
	// for the next levels of subdivision simply build up from the level below!...
	//
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
			int v01 = baseVertexIndexForEdge( v0, v1, isTextured);	// sets it up if required
			int v12 = baseVertexIndexForEdge( v1, v2, isTextured);	// ..
			int v20 = baseVertexIndexForEdge( v2, v0, isTextured);	// ..
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
	//
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
		paint_color[i] = (r * paint_sea[i])*0.01 + ((100 - r) * paint_land[i])*0.01;
		if ((planet_type == PLANET_TYPE_ATMOSPHERE) && isTextured)
			paint_color[i] = 1.0;

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
		vertexdata.vertex_array[vi] = make_vector( v.x * collision_radius, v.y * collision_radius, v.z * collision_radius);
		//
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
			lon = -atan( v.x / v.z);
		else
			lon = -PI - atan( v.x / v.z);
	}
	else
	{
		if (v.x > 0)
			lon = -0.5 * PI;
		else
			lon = -1.5 * PI;
	}
	while (lon < 0)
		lon += 2 * PI;
	return lon;
}

- (BOOL) willGoNova
{
	return throw_sparks;
}

- (BOOL) goneNova
{
	return throw_sparks&&(velocity.x <= 0);
}

- (void) setGoingNova:(BOOL) yesno inTime:(double)interval
{
	throw_sparks = yesno;
	if ((throw_sparks)&&(interval >= 0.0))
		velocity.x = interval;
	velocity.y = 0;
	velocity.z = 10000;
}

#ifdef WIN32
// No over-ride of Entity's version of the method is required for non-Win32 platforms.
- (void) reloadTextures
{
	//NSLog(@"PlanetEntity::reloadTextures called, clearing planet draw lists and calling super");

	int i;
	// Clear out the planet's various detail level display lists.
	for (i = 0; i < MAX_SUBDIVIDE; i++)
	{
		glDeleteLists(displayListNames[i], 1);
		displayListNames[i] = 0;
	}

	// Don't know if this will help for planets, but it shouldn't hurt.
	[super reloadTextures];
}

#endif


@end
