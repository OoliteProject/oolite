//
//  PlanetEntity.h
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

#import <Foundation/Foundation.h>

#import "entities.h"

#define PLANET_TYPE_GREEN		100
#define PLANET_TYPE_SUN			200
#define PLANET_TYPE_ATMOSPHERE  300
#define PLANET_TYPE_CORONA		400

#define ATMOSPHERE_DEPTH		500.0

#define MAX_SUBDIVIDE			6
#define MAX_TRI_INDICES			3*(20+80+320+1280+5120+20480)

typedef struct
{
	Vector					vertex_array[10400 + 2];
	GLfloat					color_array[4*10400];
	GLfloat					uv_array[2*10400];
	Vector					normal_array[10400];
	GLuint					index_array[MAX_TRI_INDICES];
}	VertexData;

@interface PlanetEntity : Entity {
	
	@public
		GLfloat		sun_diffuse[4];
		GLfloat		sun_specular[4];
		
	@protected
		int planet_type;
		int r_seed[MAX_VERTICES_PER_ENTITY];
		GLuint		displayListNames[MAX_SUBDIVIDE];	// 0 -> 20 verts
														// 1 -> 80 verts
														// 2 -> 320 verts
														// 3 -> 1280 verts
														// 4 -> 5120 verts
														// 5 -> 20480 verts !!
		
		BOOL		isTextured;
		GLuint		textureName;
	
		int			planet_seed;
		double		polar_color_factor;
		
		double		rotational_velocity;
		
		GLfloat		amb_land[4];
		GLfloat		amb_polar_land[4];
		GLfloat		amb_sea[4];
		GLfloat		amb_polar_sea[4];
		
		PlanetEntity*   atmosphere;				// secondary sphere used to show atmospheric details
		
		int			shuttles_on_ground;			// starting number of shuttles
		double		last_launch_time;			// space launches out by about 15 minutes
		double		shuttle_launch_interval;	// space launches out by about 15 minutes
		
		double		sqrt_zero_distance;
		
		// the normal array can be the base_vertex_array
		// the index array can come from the vertex_index_array
		VertexData				vertexdata;
		
		double	cor4k, lim4k;
		double	cor8k, lim8k;
		double	cor16k, lim16k;
}

// straight c
double		sin_value[360];
double		corona_speed_factor;	// multiply delta_t by this before adding it to corona_stage
double		corona_stage;			// 0.0 -> 1.0
GLfloat		rvalue[729];			// stores random values for adjusting colors in the corona
	

- (id) initAsSunWithColor:(NSColor *) sun_color;
- (id) initAsAtmosphereForPlanet:(PlanetEntity *) planet;
- (id) initAsCoronaForPlanet:(PlanetEntity *) planet;
- (id) initWithSeed:(Random_Seed) p_seed fromUniverse:(Universe *) uni;

- (id) initPlanetFromDictionary:(NSDictionary*) dict inUniverse:(Universe *) uni;
- (id) initMoonFromDictionary:(NSDictionary*) dict inUniverse:(Universe *) uni;

void drawBall (double radius, int step, double z_distance);
void drawBallVertices (double radius, int step, double z_distance);
void drawCorona (double inner_radius, double outer_radius, int step, double z_distance, GLfloat* col4v1, GLfloat* col4v2);
void drawActiveCorona (double inner_radius, double outer_radius, int step, double z_distance, GLfloat* col4v1, int rv);

- (double) polar_color_factor;
- (GLfloat *) amb_land;
- (GLfloat *) amb_polar_land;
- (GLfloat *) amb_sea;
- (GLfloat *) amb_polar_sea;

- (int) getPlanetType;
- (void) setPlanetType:(int) pt;

- (double) getRadius;
- (double) getSqrt_zero_distance;

- (void) setRadius:(double) rad;

- (void) rescaleTo:(double) rad;

- (void) drawModelWithVertexArraysAndSubdivision: (int) subdivide;

- (void) launchShuttle;

- (void) welcomeShuttle:(ShipEntity *) shuttle;

+ (void) resetBaseVertexArray;
- (void) initialiseBaseVertexArray;

int baseVertexIndexForEdge(int va, int vb, BOOL textured);

- (void) initialiseBaseTerrainArray:(int) percent_land;
- (void) paintVertex:(int) vi :(int) seed;
- (void) scaleVertices;

double longitudeFromVector(Vector v);

- (BOOL) willGoNova;
- (BOOL) goneNova;
- (void) setGoingNova:(BOOL) yesno inTime:(double)interval;

@end
