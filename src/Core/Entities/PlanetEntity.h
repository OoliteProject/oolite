/*

PlanetEntity.h

Entity subclass representing a planet or an atmosphere.

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

#import "OOStellarBody.h"

#if !NEW_PLANETS

#import "Entity.h"
#import "legacy_random.h"
#import "OOColor.h"

@class OOTexture;


#define MAX_TRI_INDICES			3*(20+80+320+1280+5120+20480)
#define MAX_PLANET_VERTICES		10400


typedef struct
{
	Vector					vertex_array[MAX_PLANET_VERTICES + 2];
	GLfloat					color_array[4*MAX_PLANET_VERTICES];
	GLfloat					uv_array[2*MAX_PLANET_VERTICES];
	Vector					normal_array[MAX_PLANET_VERTICES];
	GLuint					index_array[MAX_TRI_INDICES];
} VertexData;


#define PlanetEntity OOPlanetEntity


@interface PlanetEntity: Entity <OOStellarBody>
{
@private
	OOStellarBodyType		planet_type;
	
	uint8_t					lastSubdivideLevel;
	BOOL					useTexturedModel;
	BOOL					isTextureImage;			// is the texture explicitly specified (as opposed to synthesized)?
	NSString				*_textureFileName;
	OOTexture				*_texture;
	
	int						planet_seed;
	double					polar_color_factor;
	
	double					rotational_velocity;
	
	GLfloat					amb_land[4];
	GLfloat					amb_polar_land[4];
	GLfloat					amb_sea[4];
	GLfloat					amb_polar_sea[4];
	
	PlanetEntity			*atmosphere;			// secondary sphere used to show atmospheric details
	PlanetEntity			*root_planet;			// link back to owning planet (not retained)
	
	int						shuttles_on_ground;			// starting number of shuttles
	double					last_launch_time;			// space launches out by about 15 minutes
	double					shuttle_launch_interval;	// space launches out by about 15 minutes
	
	double					sqrt_zero_distance;
	
	GLuint					displayListNames[MAX_SUBDIVIDE];
	GLuint					vertexCount;
	VertexData				vertexdata;
	
	Vector					rotationAxis;
}

- (id) initFromDictionary:(NSDictionary*)dict withAtmosphere:(BOOL)atmo andSeed:(Random_Seed)p_seed;
- (void) miniaturize;

- (BOOL) setUpPlanetFromTexture:(NSString *)fileName;

- (int) planet_seed;
- (BOOL) isTextured;
- (BOOL) isExplicitlyTextured;		// Specified texture, not synthesized.
- (OOTexture *) texture;
- (NSString *) textureFileName;

- (double) polar_color_factor;
- (GLfloat *) amb_land;
- (GLfloat *) amb_polar_land;
- (GLfloat *) amb_sea;
- (GLfloat *) amb_polar_sea;

- (OOStellarBodyType) planetType;
- (void) setPlanetType:(OOStellarBodyType) pt;


- (double) radius;	// metres
- (void) setRadius:(GLfloat) rad;
- (double) rotationalVelocity;
- (void) setRotationalVelocity:(double) v;

- (BOOL) hasAtmosphere;

- (void) launchShuttle;

- (void) welcomeShuttle:(ShipEntity *) shuttle;

- (void) drawUnconditionally;

#ifndef NDEBUG
- (PlanetEntity *) atmosphere;
#endif

@end


#endif	// !NEW_PLANETS
