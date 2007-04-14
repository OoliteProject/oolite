/*

Entity.h

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

Base class for entities, i.e. drawable world objects.

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


#import "OOCocoa.h"
#import "OOMaths.h"
#import "OOCacheManager.h"
#import "OOTypes.h"
#import "OOWeakReference.h"


#define DEBUG_ALL					0xffffffff
#define DEBUG_LINKED_LISTS			0x00000001
#define DEBUG_ENTITIES				0x00000002
#define DEBUG_COLLISIONS			0x00000004
// 0x8 is now unused
#define DEBUG_OCTREE				0x00000010
#define DEBUG_OCTREE_TEXT			0x00000020

#define MAX_VERTICES_PER_ENTITY		320
#define MAX_FACES_PER_ENTITY		512
#define MAX_TEXTURES_PER_ENTITY		8
#define MAX_VERTICES_PER_FACE		16

#define	NUM_VERTEX_ARRAY_RANGES		16

#define NO_DRAW_DISTANCE_FACTOR		512.0
#define ABSOLUTE_NO_DRAW_DISTANCE2	(2500.0 * 2500.0 * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR)
// ie. the furthest away thing we can draw is at 1280km (a 2.5km wide object would disappear at that range)


#define SCANNER_MAX_RANGE			25600.0
#define SCANNER_MAX_RANGE2			655360000.0

#define CLOSE_COLLISION_CHECK_MAX_RANGE2 1000000000.0


@class Universe, Geometry, CollisionRegion;


typedef struct
{
	GLfloat					red;
	GLfloat					green;
	GLfloat					blue;
	
	Vector					normal;
	
	int						n_verts;
	
	GLint					vertex[MAX_VERTICES_PER_FACE];
	
	Str255					textureFileStr255;
	GLuint					texName;
	GLfloat					s[MAX_VERTICES_PER_FACE];
	GLfloat					t[MAX_VERTICES_PER_FACE];
} Face;


typedef struct
{
	GLint					index_array[3 * MAX_FACES_PER_ENTITY];	// triangles
	GLfloat					texture_uv_array[ 3 * MAX_FACES_PER_ENTITY * 2];
	Vector					vertex_array[3 * MAX_FACES_PER_ENTITY];
	Vector					normal_array[3 * MAX_FACES_PER_ENTITY];
	
	GLuint					texName;
	
	int						n_triangles;
} EntityData;	// per texture


typedef struct
{
	long					rangeSize;		// # of bytes in this VAR block
	void					*dataBlockPtr;	// ptr to the memory that we're making VAR
	BOOL					forceUpdate;	// true if data in VAR block needs updating
	BOOL					activated;		// set to true the first time we use it
} VertexArrayRangeType;


typedef struct
{
	double					timeframe;		// universal time for this frame
	Vector					position;		// position
	Quaternion				q_rotation;		// rotation
	Vector					k;				// direction vectors
} Frame;


extern int debug;


@interface Entity: NSObject <OOWeakReferenceSupport>
{
    // the base object for ships/stations/anything actually
	//////////////////////////////////////////////////////
	//
	// @public variables:
	//
	// we forego encapsulation for some variables in order to
	// lose the overheads of Obj-C accessor methods...
	//
@public
	uint32_t				isParticle: 1,
							isRing: 1,
							isShip: 1,
							isStation: 1,
							isPlanet: 1,
							isPlayer: 1,
							isSky: 1,
							isWormhole: 1,
							isSubentity: 1,
							hasMoved: 1,
							hasRotated: 1,
							hasCollided: 1,
							isSunlit: 1,
							collisionTestFilter: 1,
							isSmoothShaded: 1,
#if GL_APPLE_vertex_array_object
							usingVAR: 1,
#endif
							throw_sparks: 1,
							materialsReady: 1;
	
	OOScanClass				scanClass;
	OOEntityStatus			status;
	
	double					zero_distance;
	double					no_draw_distance;		// 10 km initially
	GLfloat					collision_radius;
	GLfloat					actual_radius;
	Vector					position;
	Quaternion				q_rotation;
	
	int						zero_index;
	
	// Linked lists of entites, sorted by position on each (world) axis
	Entity					*x_previous, *x_next;
	Entity					*y_previous, *y_next;
	Entity					*z_previous, *z_next;
	
	Entity					*collision_chain;
	
	OOUniversalID			shadingEntityID;
	
	Vector					relativePosition;
	
	Entity*					collider;
	
	OOUniversalID			universalID;			// used to reference the entity
	
	CollisionRegion			*collisionRegion;		// initially nil - then maintained
	
@protected
	Vector					lastPosition;
	Quaternion				lastQRotation;
	
	GLfloat					distanceTravelled;		// set to zero initially
	
    Matrix					rotation;
    gl_matrix				rotMatrix;
    
	Vector					velocity;
	
	Quaternion				subentityRotationalVelocity;
	
	// positions+rotations for trails and trackbacks
	Frame					track[256];
	int						trackIndex;
	double					trackTime;
	NSLock					*trackLock;
	
	GLfloat					energy;
	GLfloat					maxEnergy;
	
	NSMutableArray			*collidingEntities;
    
    int						n_vertices, n_faces;
    Vector					vertices[MAX_VERTICES_PER_ENTITY];
	
    Vector					vertex_normal[MAX_VERTICES_PER_ENTITY];
	
    Face					faces[MAX_FACES_PER_ENTITY];
	BoundingBox				boundingBox;
	GLfloat					mass;
    GLuint					displayListName;
    
    NSString				*basefile;
	
	OOUniversalID			owner;
	
	int						n_textures;
	EntityData				entityData;
	NSRange					triangle_range[MAX_TEXTURES_PER_ENTITY];
	Str255					texture_file[MAX_TEXTURES_PER_ENTITY];
	GLuint					texture_name[MAX_TEXTURES_PER_ENTITY];
	
	// COMMON OGL STUFF
#if GL_APPLE_vertex_array_object
	GLuint					gVertexArrayRangeObjects[NUM_VERTEX_ARRAY_RANGES];	// OpenGL's VAR object references
	VertexArrayRangeType	gVertexArrayRangeData[NUM_VERTEX_ARRAY_RANGES];		// our info about each VAR block
#endif
	
	OOWeakReference			*weakSelf;
}

- (id) init;
- (void) dealloc;

- (void) addToLinkedLists;
- (void) removeFromLinkedLists;

- (BOOL) checkLinkedLists;
- (void) updateLinkedLists;

- (void) wasAddedToUniverse;
- (void) wasRemovedFromUniverse;

- (void) warnAboutHostiles;

- (CollisionRegion*) collisionRegion;
- (void) setCollisionRegion:(CollisionRegion*)region;

- (void) setUniversalID:(OOUniversalID)uid;
- (OOUniversalID) universalID;

- (BOOL) throwingSparks;
- (void) setThrowSparks:(BOOL)value;
- (void) throwSparks;

- (BOOL) isSmoothShaded;
- (void) setSmoothShaded:(BOOL)value;

- (void) setOwner:(Entity *)ent;
- (Entity *)owner;

- (void) setModelName:(NSString *)modelName;
- (NSString *)modelName;

- (void) setPosition:(Vector)posn;
- (void) setPositionX:(GLfloat)x y:(GLfloat)y z:(GLfloat)z;
- (Vector) position;
- (Vector) viewpointPosition;
- (Vector) viewpointOffset;

- (double) zeroDistance;
- (Vector) relativePosition;
- (NSComparisonResult) compareZeroDistance:(Entity *)otherEntity;

- (Geometry*) geometry;
- (BoundingBox) boundingBox;

- (GLfloat) mass;

- (void) setQRotation:(Quaternion) quat;
- (Quaternion) QRotation;

- (void) setVelocity:(Vector)vel;
- (Vector) velocity;
- (double) speed;

- (GLfloat) distanceTravelled;
- (void) setDistanceTravelled:(GLfloat)value;

- (void) setStatus:(OOEntityStatus)stat;
- (OOEntityStatus) status;

- (void) setScanClass:(OOScanClass)sClass;
- (OOScanClass) scanClass;

- (void) setEnergy:(GLfloat)amount;
- (GLfloat) energy;

- (void) setMaxEnergy:(GLfloat)amount;
- (GLfloat) maxEnergy;

- (void) applyRoll:(GLfloat)roll andClimb:(GLfloat)climb;
- (void) applyRoll:(GLfloat)roll climb:(GLfloat) climb andYaw:(GLfloat)yaw;
- (void) moveForward:(double)amount;

- (GLfloat *) rotationMatrix;
- (GLfloat *) drawRotationMatrix;

- (BOOL) canCollide;
- (double) collisionRadius;
- (void) setCollisionRadius:(double)amount;
- (NSMutableArray *)collisionArray;

- (void) drawEntity:(BOOL)immediate :(BOOL)translucent;
- (void) drawSubEntity:(BOOL)immediate :(BOOL)translucent;
- (void) reloadTextures;
- (void) initialiseTextures;
- (void) regenerateDisplayList;
- (void) generateDisplayList;

- (void) update:(double) delta_t;
- (void) saveToLastFrame;
- (void) savePosition:(Vector)pos atTime:(double)t_time atIndex:(int)t_index;
- (void) saveFrame:(Frame)frame atIndex:(int)t_index;
- (void) resetFramesFromFrame:(Frame) resetFrame withVelocity:(Vector) vel1;
- (BOOL) resetToTime:(double) t_frame;
- (Frame) frameAtTime:(double) t_frame;	// timeframe is relative to now ie. -0.5 = half a second ago.
- (Frame) frameAtTime:(double) t_frame fromFrame:(Frame) frame_zero;	// t_frame is relative to now ie. -0.5 = half a second ago.

- (void) setUpVertexArrays;

- (double) findCollisionRadius;

- (BoundingBox) findBoundingBoxRelativeToPosition:(Vector)opv InVectors:(Vector) _i :(Vector) _j :(Vector) _k;

- (BOOL) checkCloseCollisionWith:(Entity *)other;

- (void) takeEnergyDamage:(double) amount from:(Entity *) ent becauseOf:(Entity *) other;

- (void) fakeTexturesWithImageFile: (NSString *) textureFile andMaxSize:(NSSize) maxSize;

- (NSString *) toString;

- (void)dumpState;		// General "describe situtation verbosely in log" command.
- (void)dumpSelfState;	// Subclasses should override this, not -dumpState, and call throught to super first.

#if GL_APPLE_vertex_array_object
// COMMON OGL ROUTINES
- (BOOL) OGL_InitVAR;
- (void) OGL_AssignVARMemory:(long) size :(void *) data :(Byte) whichVAR;
- (void) OGL_UpdateVAR;
#endif

@end


// keep track of various OpenGL states
//
BOOL mygl_texture_2d;
//
void my_glEnable(GLenum gl_state);
void my_glDisable(GLenum gl_state);

// log a list of current states
//
void LogOpenGLState();

// check for OpenGL errors, reporting them if where is not nil
//
BOOL CheckOpenGLErrors(NSString* where);
