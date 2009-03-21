/*

PlanetEntity.h

Entity subclass representing a planet. Or a sun. Or an atmosphere. Basically
anything big and ball-shaped.

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

#import "OOSelfDrawingEntity.h"
#import "legacy_random.h"
#import "OOColor.h"


typedef enum
{
	PLANET_TYPE_GREEN,
	PLANET_TYPE_SUN,
	PLANET_TYPE_ATMOSPHERE,
	PLANET_TYPE_MOON,
	PLANET_TYPE_MINIATURE
} OOPlanetType;


#define ATMOSPHERE_DEPTH		500.0
#define PLANET_MINIATURE_FACTOR	0.00185

#define MAX_SUBDIVIDE			6	// 0 -> 20 verts
									// 1 -> 80 verts
									// 2 -> 320 verts
									// 3 -> 1280 verts
									// 4 -> 5120 verts
									// 5 -> 20480 verts !!
#define MAX_TRI_INDICES			3*(20+80+320+1280+5120+20480)


@class ShipEntity;


typedef struct
{
	Vector					vertex_array[10400 + 2];
	GLfloat					color_array[4*10400];
	GLfloat					uv_array[2*10400];
	Vector					normal_array[10400];
	GLuint					index_array[MAX_TRI_INDICES];
}	VertexData;

@interface PlanetEntity: OOSelfDrawingEntity
{
@public
	GLfloat					sun_diffuse[4];
	GLfloat					sun_specular[4];
	
	int						lastSubdivideLevel;
	
@protected
	OOPlanetType			planet_type;
	int						r_seed[MAX_VERTICES_PER_ENTITY];
	GLuint					displayListNames[MAX_SUBDIVIDE];
	
	BOOL					isTextured;
	GLuint					textureName;
	unsigned char			*textureData;
	
#ifndef NO_SHADERS
	BOOL					isShadered;
	GLhandleARB				shader_program;
#endif

	GLuint					normalMapTextureName;
	unsigned char			*normalMapTextureData;
	
	int						planet_seed;
	double					polar_color_factor;
	
	double					rotational_velocity;
	
	GLfloat					amb_land[4];
	GLfloat					amb_polar_land[4];
	GLfloat					amb_sea[4];
	GLfloat					amb_polar_sea[4];
	
	PlanetEntity			*atmosphere;			// secondary sphere used to show atmospheric details
	PlanetEntity			*root_planet;			// link back to owning planet
	
	int						shuttles_on_ground;			// starting number of shuttles
	double					last_launch_time;			// space launches out by about 15 minutes
	double					shuttle_launch_interval;	// space launches out by about 15 minutes
	
	double					sqrt_zero_distance;
	
	// the normal array can be the base_vertex_array
	// the index array can come from the vertex_index_array
	VertexData				vertexdata;
	
	double					cor4k, lim4k;
	double					cor8k, lim8k;
	double					cor16k, lim16k;
	
	Vector					rotationAxis;
}

// straight c
double		corona_speed_factor;	// multiply delta_t by this before adding it to corona_stage
double		corona_stage;			// 0.0 -> 1.0
GLfloat		rvalue[729];			// stores random values for adjusting colors in the corona
	
- (id) initAsSunWithColor:(OOColor *) sun_color;
- (id) initWithSeed:(Random_Seed) p_seed;
- (id) initMiniatureFromPlanet:(PlanetEntity*) planet;

- (id) initMoonFromDictionary:(NSDictionary*) dict;
- (id) initPlanetFromDictionary:(NSDictionary*) dict;
- (id) initPlanetFromDictionary:(NSDictionary*) dict withAtmosphere: (BOOL) atmo andSeed:(Random_Seed) p_seed;
- (BOOL) setUpPlanetFromTexture:(NSString *)fileName;

void drawActiveCorona(GLfloat inner_radius, GLfloat outer_radius, GLfloat step, GLfloat z_distance, GLfloat* col4v1, int rv);

- (int*) r_seed;
- (int) planet_seed;
- (BOOL) isTextured;
- (GLuint) textureName;

- (double) polar_color_factor;
- (GLfloat *) amb_land;
- (GLfloat *) amb_polar_land;
- (GLfloat *) amb_sea;
- (GLfloat *) amb_polar_sea;

- (OOPlanetType) planetType;
- (void) setPlanetType:(OOPlanetType) pt;


- (double) radius;	// metres
- (void) setRadius:(double) rad;
- (void) rescaleTo:(double) rad;

- (double) sqrtZeroDistance;

- (BOOL) hasAtmosphere;

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
