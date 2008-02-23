/*

Entity.m

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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

#import "Entity.h"
#import "EntityOOJavaScriptExtensions.h"
#import "PlayerEntity.h"
#import "PlanetEntity.h"

#import "OOMaths.h"
#import "Geometry.h"
#import "Universe.h"
#import "GameController.h"
#import "ResourceManager.h"
#import "OOConstToString.h"

#import "CollisionRegion.h"

#import "NSScannerOOExtensions.h"

#define kOOLogUnconvertedNSLog @"unclassified.Entity"


static NSString * const kOOLogEntityAddToList				= @"entity.linkedList.add";
static NSString * const kOOLogEntityAddToListError			= @"entity.linkedList.add.error";
static NSString * const kOOLogEntityRemoveFromList			= @"entity.linkedList.remove";
static NSString * const kOOLogEntityRemoveFromListError		= @"entity.linkedList.remove.error";
	   NSString * const kOOLogEntityVerificationError		= @"entity.linkedList.verify.error";
static NSString * const kOOLogEntityUpdateError				= @"entity.linkedList.update.error";


@interface Entity (OOPrivate)

- (BOOL) checkLinkedLists;

@end


@implementation Entity

- (id) init
{
    self = [super init];
    
	orientation	= kIdentityQuaternion;
	rotMatrix	= OOMatrixForQuaternionRotation(orientation);
    
	position = kZeroVector;
	
	no_draw_distance = 100000.0;  //  10 km
	
	collidingEntities = [[NSMutableArray alloc] init];
	
	scanClass = CLASS_NOT_SET;
    status = STATUS_COCKPIT_DISPLAY;
	
	spawnTime = [UNIVERSE getTime];
	
	isSunlit = YES;
	
    return self;
}


- (void) dealloc
{
	[UNIVERSE ensureEntityReallyRemoved:self];
	[collidingEntities release];
	[trackLock release];
	[collisionRegion release];
	[self deleteJSSelf];
	
	[super dealloc];
}


- (NSString *)descriptionComponents
{
	return [NSString stringWithFormat:@"ID: %u position: %@ scanClass: %@ status: %@", [self universalID], VectorDescription([self position]), ScanClassToString([self scanClass]), EntityStatusToString([self status])];
}


- (BOOL)isShip
{
	return isShip;
}


- (BOOL)isStation
{
	return isStation;
}


- (BOOL)isSubEntity
{
	return isSubentity;
}


- (BOOL)isPlayer
{
	return isPlayer;
}


- (BOOL)isPlanet
{
	return isPlanet;
}


- (BOOL)isSun
{
	return isPlanet && [(PlanetEntity *)self planetType] == PLANET_TYPE_SUN;
}


- (BOOL)isWormhole
{
	return isWormhole;
}


- (BOOL) validForAddToUniverse
{
	return YES;
}


- (void) addToLinkedLists
{
#ifndef NDEBUG
	if (gDebugFlags & DEBUG_LINKED_LISTS)
		OOLog(kOOLogEntityAddToList, @"DEBUG adding entity %@ to linked lists", self);
#endif
	//
	// insert at the start
	if (UNIVERSE)
	{
		x_previous = nil; x_next = UNIVERSE->x_list_start;
		// move UP the list
		while ((x_next)&&(x_next->position.x - x_next->collision_radius < position.x - collision_radius))
		{
			x_previous = x_next;
			x_next = x_next->x_next;
		}	
		if (x_next)		x_next->x_previous = self;
		if (x_previous) x_previous->x_next = self;
		else			UNIVERSE->x_list_start = self;
		
		y_previous = nil; y_next = UNIVERSE->y_list_start;
		// move UP the list
		while ((y_next)&&(y_next->position.y - y_next->collision_radius < position.y - collision_radius))
		{
			y_previous = y_next;
			y_next = y_next->y_next;
		}	
		if (y_next)		y_next->y_previous = self;
		if (y_previous) y_previous->y_next = self;
		else			UNIVERSE->y_list_start = self;

		z_previous = nil; z_next = UNIVERSE->z_list_start;
		// move UP the list
		while ((z_next)&&(z_next->position.z - z_next->collision_radius < position.z - collision_radius))
		{
			z_previous = z_next;
			z_next = z_next->z_next;
		}	
		if (z_next)		z_next->z_previous = self;
		if (z_previous) z_previous->z_next = self;
		else			UNIVERSE->z_list_start = self;
				
	}
	
#ifndef NDEBUG
	if (gDebugFlags & DEBUG_LINKED_LISTS)
	{
		if (![self checkLinkedLists])
		{
			OOLog(kOOLogEntityAddToListError, @"DEBUG LINKED LISTS - problem encountered while adding %@ to linked lists", self);
			[UNIVERSE obj_dump];
		
			exit(-1);
		}
	}
#endif
}


- (void) removeFromLinkedLists
{
#ifndef NDEBUG
	if (gDebugFlags & DEBUG_LINKED_LISTS)
		OOLog(kOOLogEntityRemoveFromList, @"DEBUG removing entity %@ from linked lists", self);
#endif
	
	if ((x_next == nil)&&(x_previous == nil))	// removed already!
		return;

	// make sure the starting point is still correct
	if (UNIVERSE)
	{
		if ((UNIVERSE->x_list_start == self)&&(x_next))
				UNIVERSE->x_list_start = x_next;
		if ((UNIVERSE->y_list_start == self)&&(y_next))
				UNIVERSE->y_list_start = y_next;
		if ((UNIVERSE->z_list_start == self)&&(z_next))
				UNIVERSE->z_list_start = z_next;
	}
	//
	if (x_previous)		x_previous->x_next = x_next;
	if (x_next)			x_next->x_previous = x_previous;
	//
	if (y_previous)		y_previous->y_next = y_next;
	if (y_next)			y_next->y_previous = y_previous;
	//
	if (z_previous)		z_previous->z_next = z_next;
	if (z_next)			z_next->z_previous = z_previous;
	//
	x_previous = nil;	x_next = nil;
	y_previous = nil;	y_next = nil;
	z_previous = nil;	z_next = nil;

#ifndef NDEBUG
	if (gDebugFlags & DEBUG_LINKED_LISTS)
	{
		if (![self checkLinkedLists])
		{
			OOLog(kOOLogEntityRemoveFromListError, @"DEBUG LINKED LISTS - problem encountered while removing %@ from linked lists", self);
			[UNIVERSE obj_dump];
		
			exit(-1);
		}
	}
#endif
}


- (BOOL) checkLinkedLists
{
	// DEBUG check for loops
	if (UNIVERSE->n_entities > 0)
	{
		int n;
		Entity	*check, *last;
		//
		last = nil;
		//
		n = UNIVERSE->n_entities;
		check = UNIVERSE->x_list_start;
		while ((n--)&&(check))
		{
			last = check;
			check = check->x_next;
		}
		if ((check)||(n > 0))
		{
			OOLog(kOOLogEntityVerificationError, @"Broken x_next %@ list (%d) ***", UNIVERSE->x_list_start, n);
			return NO;
		}
		//
		n = UNIVERSE->n_entities;
		check = last;
		while ((n--)&&(check))	check = check->x_previous;
		if ((check)||(n > 0))
		{
			OOLog(kOOLogEntityVerificationError, @"Broken x_previous %@ list (%d) ***", UNIVERSE->x_list_start, n);
			return NO;
		}
		//
		n = UNIVERSE->n_entities;
		check = UNIVERSE->y_list_start;
		while ((n--)&&(check))
		{
			last = check;
			check = check->y_next;
		}
		if ((check)||(n > 0))
		{
			OOLog(kOOLogEntityVerificationError, @"Broken y_next %@ list (%d) ***", UNIVERSE->y_list_start, n);
			return NO;
		}
		//
		n = UNIVERSE->n_entities;
		check = last;
		while ((n--)&&(check))	check = check->y_previous;
		if ((check)||(n > 0))
		{
			OOLog(kOOLogEntityVerificationError, @"Broken y_previous %@ list (%d) ***", UNIVERSE->y_list_start, n);
			return NO;
		}
		//
		n = UNIVERSE->n_entities;
		check = UNIVERSE->z_list_start;
		while ((n--)&&(check))
		{
			last = check;
			check = check->z_next;
		}
		if ((check)||(n > 0))
		{
			OOLog(kOOLogEntityVerificationError, @"Broken z_next %@ list (%d) ***", UNIVERSE->z_list_start, n);
			return NO;
		}
		//
		n = UNIVERSE->n_entities;
		check = last;
		while ((n--)&&(check))	check = check->z_previous;
		if ((check)||(n > 0))
		{
			OOLog(kOOLogEntityVerificationError, @"Broken z_previous %@ list (%d) ***", UNIVERSE->z_list_start, n);
			return NO;
		}
	}
	return YES;
}


- (void) updateLinkedLists
{
	if (!UNIVERSE)
		return;	// not in the UNIVERSE - don't do this!
	if ((x_next == nil)&&(x_previous == nil))
		return;	// not in the lists - don't do this!
	
#ifndef NDEBUG
	if (gDebugFlags & DEBUG_LINKED_LISTS)
	{
		if (![self checkLinkedLists])
		{
			OOLog(kOOLogEntityVerificationError, @"DEBUG LINKED LISTS problem encountered before updating linked lists for %@", self);
			[UNIVERSE obj_dump];
		
			exit(-1);
		}
	}
#endif
	
	// update position in linked list for position.x
	// take self out of list..
	if (x_previous)		x_previous->x_next = x_next;
	if (x_next)			x_next->x_previous = x_previous;
	// sink DOWN the list
	while ((x_previous)&&(x_previous->position.x - x_previous->collision_radius > position.x - collision_radius))
	{
		x_next = x_previous;
		x_previous = x_previous->x_previous;
	}
	// bubble UP the list
	while ((x_next)&&(x_next->position.x - x_next->collision_radius < position.x - collision_radius))
	{
		x_previous = x_next;
		x_next = x_next->x_next;
	}
	if (x_next)		// insert self into the list before x_next..
		x_next->x_previous = self;
	if (x_previous)	// insert self into the list after x_previous..
		x_previous->x_next = self;
	if ((x_previous == nil)&&(UNIVERSE))	// if we're the first then tell the UNIVERSE!
			UNIVERSE->x_list_start = self;
	
	// update position in linked list for position.y
	// take self out of list..
	if (y_previous)		y_previous->y_next = y_next;
	if (y_next)			y_next->y_previous = y_previous;
	// sink DOWN the list
	while ((y_previous)&&(y_previous->position.y - y_previous->collision_radius > position.y - collision_radius))
	{
		y_next = y_previous;
		y_previous = y_previous->y_previous;
	}
	// bubble UP the list
	while ((y_next)&&(y_next->position.y - y_next->collision_radius < position.y - collision_radius))
	{
		y_previous = y_next;
		y_next = y_next->y_next;
	}
	if (y_next)		// insert self into the list before y_next..
		y_next->y_previous = self;
	if (y_previous)	// insert self into the list after y_previous..
		y_previous->y_next = self;
	if ((y_previous == nil)&&(UNIVERSE))	// if we're the first then tell the UNIVERSE!
			UNIVERSE->y_list_start = self;
	
	// update position in linked list for position.z
	// take self out of list..
	if (z_previous)		z_previous->z_next = z_next;
	if (z_next)			z_next->z_previous = z_previous;
	// sink DOWN the list
	while ((z_previous)&&(z_previous->position.z - z_previous->collision_radius > position.z - collision_radius))
	{
		z_next = z_previous;
		z_previous = z_previous->z_previous;
	}
	// bubble UP the list
	while ((z_next)&&(z_next->position.z - z_next->collision_radius < position.z - collision_radius))
	{
		z_previous = z_next;
		z_next = z_next->z_next;
	}
	if (z_next)		// insert self into the list before z_next..
		z_next->z_previous = self;
	if (z_previous)	// insert self into the list after z_previous..
		z_previous->z_next = self;
	if ((z_previous == nil)&&(UNIVERSE))	// if we're the first then tell the UNIVERSE!
			UNIVERSE->z_list_start = self;
	
	// done
#ifndef NDEBUG
	if (gDebugFlags & DEBUG_LINKED_LISTS)
	{
		if (![self checkLinkedLists])
		{
			OOLog(kOOLogEntityUpdateError, @"DEBUG LINKED LISTS problem encountered after updating linked lists for %@", self);
			[UNIVERSE obj_dump];
		
			exit(-1);
		}
	}
#endif
}


- (void) wasAddedToUniverse
{
	// Do nothing
}


- (void) wasRemovedFromUniverse
{
	// Do nothing
}


- (void) warnAboutHostiles
{
	// do nothing for now, this can be expanded in sub classes
	OOLog(@"general.error.subclassResponsibility.Entity-warnAboutHostiles", @"***** Entity does nothing in warnAboutHostiles");
}


- (CollisionRegion*) collisionRegion
{
	return collisionRegion;
}


- (void) setCollisionRegion: (CollisionRegion*) region
{
	if (collisionRegion) [collisionRegion release];
	collisionRegion = [region retain];
}


- (void) setUniversalID:(OOUniversalID)uid
{
	universalID = uid;
}


- (OOUniversalID) universalID
{
	return universalID;
}


- (BOOL) throwingSparks
{
	return throw_sparks;
}


- (void) setThrowSparks:(BOOL) value
{
	throw_sparks = value;
}


- (void) throwSparks;
{
	// do nothing for now
}


- (void) setOwner:(Entity *)ent
{
	if (ent != nil)
	{
		OOUniversalID	owner_id = [ent universalID];
		
		if ([UNIVERSE entityForUniversalID:owner_id] == ent)	// check to make sure it's kosher
			owner = owner_id;
		else
			owner = NO_TARGET;
	}
	else  owner = NO_TARGET;
}


- (id) owner
{
	return [UNIVERSE entityForUniversalID:owner];
}


- (void) setPosition:(Vector) posn
{
	position = posn;
}


- (void) setPositionX:(GLfloat)x y:(GLfloat)y z:(GLfloat)z
{
	position.x = x;
	position.y = y;
	position.z = z;
}


- (double) zeroDistance
{
	return zero_distance;
}


- (Vector) relativePosition
{
	return relativePosition;
}


- (NSComparisonResult) compareZeroDistance:(Entity *)otherEntity;
{
	if ((otherEntity)&&(zero_distance > otherEntity->zero_distance))
		return NSOrderedAscending;
	else
		return NSOrderedDescending;
}


- (BoundingBox) boundingBox
{
	return boundingBox;
}


- (GLfloat) mass
{
	return mass;
}


- (void) setOrientation:(Quaternion) quat
{
	orientation = quat;
	[self orientationChanged];
}


- (Quaternion) orientation
{
	return orientation;
}


- (void) orientationChanged
{
	quaternion_normalize(&orientation);
	rotMatrix = OOMatrixForQuaternionRotation(orientation);
}


- (void) setVelocity:(Vector) vel
{
	velocity = vel;
}


- (Vector) velocity
{
	return velocity;
}


- (double) speed
{
	return magnitude2(velocity);
}


- (GLfloat) distanceTravelled
{
	return distanceTravelled;
}


- (void) setDistanceTravelled: (GLfloat) value
{
	distanceTravelled = value;
}


- (void) setStatus:(OOEntityStatus) stat
{
	status = stat;
}


- (OOEntityStatus) status
{
	return status;
}


- (void) setScanClass:(OOScanClass)sClass
{
	scanClass = sClass;
}


- (OOScanClass) scanClass
{
	return scanClass;
}


- (void) setEnergy:(GLfloat) amount
{
	energy = amount;
}


- (GLfloat) energy
{
	return energy;
}


- (void) setMaxEnergy:(GLfloat)amount
{
	maxEnergy = amount;
}


- (GLfloat) maxEnergy
{
	return maxEnergy;
}


- (void) applyRoll:(GLfloat) roll andClimb:(GLfloat) climb
{
	if ((roll == 0.0)&&(climb == 0.0)&&(!hasRotated))
		return;

	if (roll)
		quaternion_rotate_about_z(&orientation, -roll);
	if (climb)
		quaternion_rotate_about_x(&orientation, -climb);
	
	[self orientationChanged];
}


- (void) applyRoll:(GLfloat) roll climb:(GLfloat) climb andYaw:(GLfloat) yaw
{
	if ((roll == 0.0)&&(climb == 0.0)&&(yaw == 0.0)&&(!hasRotated))
		return;

	if (roll)
		quaternion_rotate_about_z(&orientation, -roll);
	if (climb)
		quaternion_rotate_about_x(&orientation, -climb);
	if (yaw)
		quaternion_rotate_about_y(&orientation, -yaw);

	[self orientationChanged];
}


- (void) moveForward:(double) amount
{
    Vector		forward = vector_forward_from_quaternion(orientation);
	distanceTravelled += amount;
	position.x += amount * forward.x;
	position.y += amount * forward.y;
	position.z += amount * forward.z;
}


- (OOMatrix) rotationMatrix
{
    return rotMatrix;
}


- (OOMatrix) drawRotationMatrix
{
    return rotMatrix;
}


- (Vector) position
{
    return position;
}


- (BOOL) canCollide
{
	return YES;
}


- (GLfloat) collisionRadius
{
	return collision_radius;
}


- (void) setCollisionRadius:(GLfloat) amount
{
	collision_radius = amount;
}


- (NSMutableArray *) collisionArray
{
	return collidingEntities;
}


- (void) update:(OOTimeDelta) delta_t
{
	PlayerEntity *player = [PlayerEntity sharedPlayer];
	if (player)
	{
		if (status != STATUS_COCKPIT_DISPLAY)
			relativePosition = vector_between(player->position, position);
		else
			relativePosition = position;
		//
		zero_distance = magnitude2(relativePosition);
	}
	else
		zero_distance = -1;

	hasMoved = !vector_equal(position, lastPosition);
	hasRotated = !quaternion_equal(orientation, lastOrientation);
	lastPosition = position;
	lastOrientation = orientation;
}


- (void) saveToLastFrame
{
	double t_now = [UNIVERSE getTime];
	if (t_now >= trackTime + 0.1)		// update every 1/10 of a second
	{
		// save previous data
		trackTime = t_now;
		track[trackIndex].position =	position;
		track[trackIndex].orientation =	orientation;
		track[trackIndex].timeframe =	trackTime;
		track[trackIndex].k =	vector_forward_from_quaternion(orientation);
		trackIndex = (trackIndex + 1 ) & 0xff;
	}
}


- (void) savePosition:(Vector)pos atTime:(double)t_time atIndex:(int)t_index
{
	trackTime = t_time;
	track[t_index].position = pos;
	track[t_index].timeframe =	t_time;
	trackIndex = (t_index + 1 ) & 0xff;
}


- (void) saveFrame:(Frame)frame atIndex:(int)t_index
{
	track[t_index] = frame;
	trackTime = frame.timeframe;
	trackIndex = (t_index + 1 ) & 0xff;
}

// reset frames
//
- (void) resetFramesFromFrame:(Frame) resetFrame withVelocity:(Vector) vel1
{
	Vector		v1 = make_vector(0.1 * vel1.x, 0.1 * vel1.y, 0.1 * vel1.z);
	double		t_now = [UNIVERSE getTime];
	Vector		pos = resetFrame.position;
	Vector		vk = resetFrame.k;
	Quaternion	qr = resetFrame.orientation;
	int i;
	for (i = 0; i < 256; i++)
	{
		track[255-i].position = make_vector(pos.x - i * v1.x, pos.y - i * v1.y, pos.z - i * v1.z);
		track[255-i].timeframe = t_now - 0.1 * i;
		track[255-i].orientation = qr;
		track[255-i].k = vk;
	}
	trackTime = t_now;
	trackIndex = 0;
}


- (BOOL) resetToTime:(double) t_frame	// timeframe is relative to now ie. -0.5 = half a second ago.
{
	if (t_frame >= 0)
		return NO;

	Frame	selectedFrame = [self frameAtTime:t_frame];
	[self setPosition:selectedFrame.position];
	[self setOrientation:selectedFrame.orientation];
	return YES;
}


- (Frame) frameAtTime:(double) t_frame	// t_frame is relative to now ie. -0.5 = half a second ago.
{
	Frame result;
	result.position = position;
	result.orientation = orientation;
	result.timeframe = [UNIVERSE getTime];
	result.k = vector_forward_from_quaternion(orientation);
	//
	if (t_frame >= 0.0)
		return result;
	//
	double moment_in_time = [UNIVERSE getTime] + t_frame;
	if (moment_in_time >= trackTime)					// between the last saved frame and now
	{
		int t1 = (trackIndex - 1)&0xff;	// last saved moment
		double period = result.timeframe - trackTime;
		double f0 = (result.timeframe - moment_in_time)/period;
		double f1 = 1.0 - f0;
		Vector posn;
		posn.x =	f0 * result.position.x + f1 * track[t1].position.x;
		posn.y =	f0 * result.position.y + f1 * track[t1].position.y;
		posn.z =	f0 * result.position.z + f1 * track[t1].position.z;
		Quaternion qrot;
		qrot.w =	f0 * result.orientation.w + f1 * track[t1].orientation.w;
		qrot.x =	f0 * result.orientation.x + f1 * track[t1].orientation.x;
		qrot.y =	f0 * result.orientation.y + f1 * track[t1].orientation.y;
		qrot.z =	f0 * result.orientation.z + f1 * track[t1].orientation.z;
		result.position = posn;
		result.orientation = qrot;
		result.timeframe = moment_in_time;
		result.k = vector_forward_from_quaternion(qrot);
		return result;
	}
	//
	if (moment_in_time < track[trackIndex].timeframe)	// more than 256 frames back
	{
		return track[trackIndex];
	}
	//
	int t1 = (trackIndex - 1)&0xff;
	while (moment_in_time < track[t1].timeframe)
		t1 = (t1 - 1) & 0xff;
	int t0 = (t1 + 1) & 0xff;
	// interpolate between t0 and t1
	double period = track[0].timeframe - track[1].timeframe;
	double f0 = (track[t0].timeframe - moment_in_time)/period;
	double f1 = 1.0 - f0;
	Vector posn;
	posn.x =	f0 * track[t0].position.x + f1 * track[t1].position.x;
	posn.y =	f0 * track[t0].position.y + f1 * track[t1].position.y;
	posn.z =	f0 * track[t0].position.z + f1 * track[t1].position.z;
	Quaternion qrot;
	qrot.w =	f0 * track[t0].orientation.w + f1 * track[t1].orientation.w;
	qrot.x =	f0 * track[t0].orientation.x + f1 * track[t1].orientation.x;
	qrot.y =	f0 * track[t0].orientation.y + f1 * track[t1].orientation.y;
	qrot.z =	f0 * track[t0].orientation.z + f1 * track[t1].orientation.z;
	result.position = posn;
	result.orientation = qrot;
	result.timeframe = moment_in_time;
	result.k = vector_forward_from_quaternion(qrot);
	return result;
}


- (Frame) frameAtTime:(double) t_frame fromFrame:(Frame) frame_zero	// t_frame is relative to now ie. -0.5 = half a second ago.
{
	Frame result = frame_zero;
	//
	if (t_frame >= 0.0)
		return result;
	//
	double moment_in_time = [UNIVERSE getTime] + t_frame;
	if (moment_in_time > trackTime)					// between the last saved frame and now
	{
		Frame fr1 = track[(trackIndex - 1)&0xff];	// last saved moment
		double period = (moment_in_time - t_frame) - trackTime;
		double f1 =	-t_frame/period;
		double f0 =	1.0 - f1;
		
		Vector posn;
		posn.x =	f0 * result.position.x + f1 * fr1.position.x;
		posn.y =	f0 * result.position.y + f1 * fr1.position.y;
		posn.z =	f0 * result.position.z + f1 * fr1.position.z;
		Quaternion qrot;
		qrot.w =	f0 * result.orientation.w + f1 * fr1.orientation.w;
		qrot.x =	f0 * result.orientation.x + f1 * fr1.orientation.x;
		qrot.y =	f0 * result.orientation.y + f1 * fr1.orientation.y;
		qrot.z =	f0 * result.orientation.z + f1 * fr1.orientation.z;
		result.position = posn;
		result.orientation = qrot;
		result.timeframe = moment_in_time;
		result.k = vector_forward_from_quaternion(qrot);
		return result;
	}
	//
	if (moment_in_time < track[trackIndex].timeframe)	// more than 256 frames back
	{
		return track[trackIndex];
	}
	//
	int t1 = (trackIndex - 1)&0xff;
	while (moment_in_time < track[t1].timeframe)
		t1 = (t1 - 1) & 0xff;
	int t0 = (t1 + 1) & 0xff;
	// interpolate between t0 and t1
	double period = track[t0].timeframe - track[t1].timeframe;
	double f0 = (moment_in_time - track[t1].timeframe)/period;
	double f1 = 1.0 - f0;
	
	Vector posn;
	posn.x =	f0 * track[t0].position.x + f1 * track[t1].position.x;
	posn.y =	f0 * track[t0].position.y + f1 * track[t1].position.y;
	posn.z =	f0 * track[t0].position.z + f1 * track[t1].position.z;
	Quaternion qrot;
	qrot.w =	f0 * track[t0].orientation.w + f1 * track[t1].orientation.w;
	qrot.x =	f0 * track[t0].orientation.x + f1 * track[t1].orientation.x;
	qrot.y =	f0 * track[t0].orientation.y + f1 * track[t1].orientation.y;
	qrot.z =	f0 * track[t0].orientation.z + f1 * track[t1].orientation.z;
	result.position = posn;
	result.orientation = qrot;
	result.timeframe = moment_in_time;
	result.k = vector_forward_from_quaternion(qrot);
	return result;
}


- (BOOL) checkCloseCollisionWith:(Entity *)other
{
	return YES;
}


- (double)findCollisionRadius
{
	OOLogGenericSubclassResponsibility();
	return 0;
}


- (Geometry *)geometry
{
	OOLogGenericSubclassResponsibility();
	return nil;
}


- (void) drawEntity:(BOOL)immediate :(BOOL)translucent
{
	OOLogGenericSubclassResponsibility();
}


- (void) takeEnergyDamage:(double) amount from:(Entity *) ent becauseOf:(Entity *) other
{
	
}


- (void)dumpState
{
	if (OOLogWillDisplayMessagesInClass(@"dumpState"))
	{
		OOLog(@"dumpState", @"State for %@:", self);
		OOLogPushIndent();
		OOLogIndent();
		NS_DURING
			[self dumpSelfState];
		NS_HANDLER
		NS_ENDHANDLER
		OOLogPopIndent();
	}
}


- (void)dumpSelfState
{
	NSMutableArray		*flags = nil;
	NSString			*flagsString = nil;
	
	OOLog(@"dumpState.entity", @"Universal ID: %u", universalID);
	OOLog(@"dumpState.entity", @"Scan class: %@", ScanClassToString(scanClass));
	OOLog(@"dumpState.entity", @"Status: %@", EntityStatusToString(status));
	OOLog(@"dumpState.entity", @"Position: %@", VectorDescription(position));
	OOLog(@"dumpState.entity", @"Orientation: %@", QuaternionDescription(orientation));
	OOLog(@"dumpState.entity", @"Distance travelled: %g", distanceTravelled);
	OOLog(@"dumpState.entity", @"Energy: %g of %g", energy, maxEnergy);
	OOLog(@"dumpState.entity", @"Mass: %g", mass);
	if (owner != NO_TARGET)  OOLog(@"dumpState.entity", @"Owner: %@", [UNIVERSE entityForUniversalID:owner]);
	
	flags = [NSMutableArray array];
	#define ADD_FLAG_IF_SET(x)		if (x) { [flags addObject:@#x]; }
	ADD_FLAG_IF_SET(isParticle);
	ADD_FLAG_IF_SET(isRing);
	ADD_FLAG_IF_SET(isShip);
	ADD_FLAG_IF_SET(isStation);
	ADD_FLAG_IF_SET(isPlanet);
	ADD_FLAG_IF_SET(isPlayer);
	ADD_FLAG_IF_SET(isSky);
	ADD_FLAG_IF_SET(isWormhole);
	ADD_FLAG_IF_SET(isSubentity);
	ADD_FLAG_IF_SET(hasMoved);
	ADD_FLAG_IF_SET(hasRotated);
	ADD_FLAG_IF_SET(isSunlit);
	ADD_FLAG_IF_SET(collisionTestFilter);
	ADD_FLAG_IF_SET(throw_sparks);
	flagsString = [flags count] ? [flags componentsJoinedByString:@", "] : @"none";
	OOLog(@"dumpState.entity", @"Flags: %@", flagsString);
}


- (void)subEntityReallyDied:(ShipEntity *)sub
{
	OOLog(@"entity.bug", @"%s called for non-ship entity %p by %p", __FUNCTION__, self, sub);
}


// For shader bindings.
- (GLfloat)universalTime
{
	return [UNIVERSE getTime];
}


- (GLfloat)spawnTime
{
	return spawnTime;
}


- (GLfloat)timeElapsedSinceSpawn
{
	return [UNIVERSE getTime] - spawnTime;
}


- (id) rootEntity
{
	return self;
}

@end
