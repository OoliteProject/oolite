/*

Entity.h

Base class for entities, i.e. drawable world objects.

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


#import "OOCocoa.h"
#import "OOMaths.h"
#import "OOCacheManager.h"
#import "OOTypes.h"
#import "OOWeakReference.h"

@class Universe, CollisionRegion, ShipEntity, OOVisualEffectEntity;


#ifndef NDEBUG

extern uint32_t gLiveEntityCount;
extern size_t gTotalEntityMemory;

#endif


#define NO_DRAW_DISTANCE_FACTOR		1024.0
#define ABSOLUTE_NO_DRAW_DISTANCE2	(2500.0 * 2500.0 * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR)
// ie. the furthest away thing we can draw is at 1280km (a 2.5km wide object would disappear at that range)


#define SCANNER_MAX_RANGE			25600.0
#define SCANNER_MAX_RANGE2			655360000.0

#define CLOSE_COLLISION_CHECK_MAX_RANGE2 1000000000.0


#define ENTRY(label, value) label = value,

typedef enum OOEntityStatus
{
	#include "OOEntityStatus.tbl"
} OOEntityStatus;


#ifndef OO_SCANCLASS_TYPE
#define OO_SCANCLASS_TYPE
typedef enum OOScanClass OOScanClass;
#endif

enum OOScanClass
{
	#include "OOScanClass.tbl"
};

#undef ENTRY


@interface Entity: OOWeakRefObject
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
	OOUniversalID			universalID;			// used to reference the entity
	
	unsigned				isShip: 1,
							isStation: 1,
							isPlayer: 1,
							isWormhole: 1,
							isSubEntity: 1,
							hasMoved: 1,
							hasRotated: 1,
							hasCollided: 1,
							isSunlit: 1,
							collisionTestFilter: 2,
							throw_sparks: 1,
							isImmuneToBreakPatternHide: 1,
							isExplicitlyNotMainStation: 1,
							isVisualEffect: 1;
	
	OOScanClass				scanClass;
	
	GLfloat					zero_distance;
	GLfloat					cam_zero_distance;
	GLfloat					no_draw_distance;		// 10 km initially
	GLfloat					collision_radius;
	HPVector					position; // use high-precision vectors for global position
	Vector						cameraRelativePosition;
	Quaternion				orientation;
	
	int						zero_index;
	
	// Linked lists of entites, sorted by position on each (world) axis
	Entity					*x_previous, *x_next;
	Entity					*y_previous, *y_next;
	Entity					*z_previous, *z_next;
	
	Entity					*collision_chain;
	
	OOUniversalID			shadingEntityID;
	
	Entity					*collider;
	
	CollisionRegion			*collisionRegion;		// initially nil - then maintained
	
@protected
	HPVector					lastPosition;
	Quaternion				lastOrientation;
	
	GLfloat					distanceTravelled;		// set to zero initially
	
	OOMatrix				rotMatrix;
	
	Vector					velocity;
	
	GLfloat					energy;
	GLfloat					maxEnergy;
	
	BoundingBox				boundingBox;
	GLfloat					mass;
	
	NSMutableArray			*collidingEntities;
	
	OOTimeAbsolute			spawnTime;
	
	struct JSObject			*_jsSelf;
	
@private
	NSUInteger				_sessionID;
	
	OOWeakReference			*_owner;
	OOEntityStatus			_status;
}

// The session in which the entity was created.
- (NSUInteger) sessionID;

- (BOOL) isShip;
- (BOOL) isDock;
- (BOOL) isStation;
- (BOOL) isSubEntity;
- (BOOL) isPlayer;
- (BOOL) isPlanet;
- (BOOL) isSun;
- (BOOL) isStellarObject;
- (BOOL) isSky;
- (BOOL) isWormhole;
- (BOOL) isEffect;
- (BOOL) isVisualEffect;
- (BOOL) isWaypoint;

- (BOOL) validForAddToUniverse;
- (void) addToLinkedLists;
- (void) removeFromLinkedLists;

- (void) updateLinkedLists;

- (void) wasAddedToUniverse;
- (void) wasRemovedFromUniverse;

- (void) warnAboutHostiles;

- (CollisionRegion *) collisionRegion;
- (void) setCollisionRegion:(CollisionRegion*)region;

- (void) setUniversalID:(OOUniversalID)uid;
- (OOUniversalID) universalID;

- (BOOL) throwingSparks;
- (void) setThrowSparks:(BOOL)value;
- (void) throwSparks;

- (void) setOwner:(Entity *)ent;
- (id) owner;
- (ShipEntity *) parentEntity;		// owner if self is subentity of owner, otherwise nil.
- (ShipEntity *) rootShipEntity;	// like parentEntity, but recursive.

- (void) setPosition:(HPVector)posn;
- (void) setPositionX:(OOHPScalar)x y:(OOHPScalar)y z:(OOHPScalar)z;
- (HPVector) position;
- (Vector) cameraRelativePosition;
// gets a low-position relative vector
- (Vector) vectorTo:(Entity *)entity;

- (HPVector) absolutePositionForSubentity;
- (HPVector) absolutePositionForSubentityOffset:(HPVector) offset;

- (double) zeroDistance;
- (double) camZeroDistance;
- (NSComparisonResult) compareZeroDistance:(Entity *)otherEntity;

- (BoundingBox) boundingBox;

- (GLfloat) mass;

- (Quaternion) orientation;
- (void) setOrientation:(Quaternion) quat;
- (Quaternion) normalOrientation;	// Historical wart: orientation.w is reversed for player; -normalOrientation corrects this.
- (void) setNormalOrientation:(Quaternion) quat;
- (void) orientationChanged;

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

- (OOMatrix) rotationMatrix;
- (OOMatrix) drawRotationMatrix;
- (OOMatrix) transformationMatrix;
- (OOMatrix) drawTransformationMatrix;

- (BOOL) canCollide;
- (GLfloat) collisionRadius;
- (void) setCollisionRadius:(GLfloat)amount;
- (NSMutableArray *)collisionArray;

- (void) update:(OOTimeDelta)delta_t;

- (void) applyVelocity:(OOTimeDelta)delta_t;
- (BOOL) checkCloseCollisionWith:(Entity *)other;

- (void) takeEnergyDamage:(double)amount from:(Entity *)ent becauseOf:(Entity *)other;

- (void) dumpState;		// General "describe situtation verbosely in log" command.
- (void) dumpSelfState;	// Subclasses should override this, not -dumpState, and call throught to super first.

// Subclass repsonsibilities
- (double) findCollisionRadius;
- (void) drawImmediate:(bool)immediate translucent:(bool)translucent;
- (BOOL) isVisible;
- (BOOL) isInSpace;
- (BOOL) isImmuneToBreakPatternHide;

// For shader bindings.
- (GLfloat) universalTime;
- (GLfloat) spawnTime;
- (GLfloat) timeElapsedSinceSpawn;

#ifndef NDEBUG
- (NSString *) descriptionForObjDumpBasic;
- (NSString *) descriptionForObjDump;

- (NSSet *) allTextures;
#endif

@end

@protocol OOHUDBeaconIcon;

// Methods that must be supported by entities with beacons, regardless of type.
@protocol OOBeaconEntity

- (NSComparisonResult) compareBeaconCodeWith:(Entity <OOBeaconEntity>*) other;
- (NSString *) beaconCode;
- (void) setBeaconCode:(NSString *)bcode;
- (NSString *) beaconLabel;
- (void) setBeaconLabel:(NSString *)blabel;
- (BOOL) isBeacon;
- (id <OOHUDBeaconIcon>) beaconDrawable;
- (Entity <OOBeaconEntity> *) prevBeacon;
- (Entity <OOBeaconEntity> *) nextBeacon;
- (void) setPrevBeacon:(Entity <OOBeaconEntity> *)beaconShip;
- (void) setNextBeacon:(Entity <OOBeaconEntity> *)beaconShip;
- (BOOL) isJammingScanning;

@end


enum
{
	// Values used for unknown strings.
	kOOEntityStatusDefault		= STATUS_INACTIVE,
	kOOScanClassDefault			= CLASS_NOT_SET
};

NSString *OOStringFromEntityStatus(OOEntityStatus status) CONST_FUNC;
OOEntityStatus OOEntityStatusFromString(NSString *string) PURE_FUNC;

NSString *OOStringFromScanClass(OOScanClass scanClass) CONST_FUNC;
OOScanClass OOScanClassFromString(NSString *string) PURE_FUNC;
