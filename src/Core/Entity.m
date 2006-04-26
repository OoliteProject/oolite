//
//  Entity.m
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
#import "Entity.h"

#import "vector.h"
#import "Geometry.h"
#import "Universe.h"
#import "GameController.h"
#import "TextureStore.h"
#import "ResourceManager.h"

#import "CollisionRegion.h" // gets rid of a compilation warning

#import "ScannerExtension.h"

// global flag for VAR
BOOL global_usingVAR;
BOOL global_testForVAR;

static  Universe	*data_store_universe;

@implementation Entity

// class methods, they set the underlying data_storage universe
+ (void) setDataStore:(Universe *)univ
{
	if (univ)
		data_store_universe = univ;
	//NSLog(@"--- Universe for Data Storage set to %@", univ);

	global_usingVAR = NO;
	global_testForVAR = YES;
}

+ (Universe *) dataStore
{
	return data_store_universe;
}

+ (Vector) vectorFromString:(NSString*) xyzString
{
	GLfloat xyz[] = {0.0, 0.0, 0.0};
	int i = 0;
	BOOL failed = NO;
	NSString* error = @"No error";
	NSScanner*	scanner = [NSScanner scannerWithString:xyzString];
	while ((![scanner isAtEnd])&&(i < 3)&&(!failed))
	{
		float value;
		if ([scanner scanFloat:&value])
			xyz[i++] = value;
		else
		{
			failed = YES;
			error = @"Could not scan a float value.";
		}
	}
	if (i < 3)
	{
		failed = YES;
		error = @"Found less than three float values.";
	}
	if (failed)
	{
		NSLog(@"***** ERROR cannot make vector from '%@' because '%@'", xyzString, error);
	}
	return make_vector( xyz[0], xyz[1], xyz[2]);
}

+ (Quaternion) quaternionFromString:(NSString*) wxyzString
{
	Quaternion result;
	GLfloat wxyz[] = {1.0, 0.0, 0.0, 0.0};
	int i = 0;
	BOOL failed = NO;
	NSString* error = @"No error";
	NSScanner* scanner = [NSScanner scannerWithString:wxyzString];
	while ((![scanner isAtEnd])&&(i < 4)&&(!failed))
	{
		float value;
		if ([scanner scanFloat:&value])
			wxyz[i++] = value;
		else
		{
			failed = YES;
			error = @"Could not scan a float value.";
		}
	}
	if (i < 4)
	{
		failed = YES;
		error = @"Found less than four float values.";
	}
	result.w = wxyz[0];
	result.x = wxyz[1];
	result.y = wxyz[2];
	result.z = wxyz[3];
	if (failed)
	{
		NSLog(@"***** ERROR cannot make quaternion from '%@' because '%@'", wxyzString, error);
	}
	return result;
}

+ (Random_Seed) seedFromString:(NSString*) abcdefString
{
	Random_Seed result;
	int abcdef[] = { 0, 0, 0, 0, 0, 0};
	int i = 0;
	BOOL failed = NO;
	NSString* error = @"No error";
	NSScanner* scanner = [NSScanner scannerWithString: abcdefString];
	while ((![scanner isAtEnd])&&(i < 6)&&(!failed))
	{
		int value;
		if ([scanner scanInt:&value])
			abcdef[i++] = value;
		else
		{
			failed = YES;
			error = @"Could not scan a int value.";
		}
	}
	if (i < 6)
	{
		failed = YES;
		error = @"Found less than six int values.";
	}
	result.a = abcdef[0];
	result.b = abcdef[1];
	result.c = abcdef[2];
	result.d = abcdef[3];
	result.e = abcdef[4];
	result.f = abcdef[5];
	if (failed)
	{
		NSLog(@"***** ERROR cannot make Random_Seed from '%@' because '%@'", abcdefString, error);
	}
	return result;
}

+ (BOOL) scanVector:(Vector *) vector_ptr andQuaternion:(Quaternion *) quaternion_ptr fromString:(NSString*) xyzwxyzString
{
	GLfloat xyzwxyz[] = { 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0};
	int i = 0;
	BOOL failed = NO;
	NSString* error = @"No error";
	NSScanner* scanner = [NSScanner scannerWithString:xyzwxyzString];
	while ((![scanner isAtEnd])&&(i < 7)&&(!failed))
	{
		float value;
		if ([scanner scanFloat:&value])
			xyzwxyz[i++] = value;
		else
		{
			failed = YES;
			error = @"Could not scan a float value.";
		}
	}
	if (i < 7)
	{
		failed = YES;
		error = @"Found less than seven float values.";
	}
	if (failed)
	{
		NSLog(@"***** ERROR cannot make quaternion from '%@' because '%@'", xyzwxyzString, error);
		return NO;
	}
	vector_ptr->x = xyzwxyz[0];
	vector_ptr->y = xyzwxyz[1];
	vector_ptr->z = xyzwxyz[2];
	quaternion_ptr->w = xyzwxyz[3];
	quaternion_ptr->x = xyzwxyz[4];
	quaternion_ptr->y = xyzwxyz[5];
	quaternion_ptr->z = xyzwxyz[6];
	return YES;
}

+ (NSMutableArray *) scanTokensFromString:(NSString*) values
{
	NSMutableArray* result = [NSMutableArray arrayWithCapacity:8];
	if (!values)
	{
		return result;	// nothing scanned
	}
	NSScanner* scanner = [NSScanner scannerWithString:values];
	NSCharacterSet* space_set = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	NSString* token;
	while (![scanner isAtEnd])
	{
		[scanner ooliteScanCharactersFromSet:space_set intoString:(NSString * *)nil];
		if ([scanner ooliteScanUpToCharactersFromSet:space_set intoString:&token])
			[result addObject:[NSString stringWithString:token]];
	}
	return result;
}


- (id) init
{
    self = [super init];
    //
    quaternion_set_identity(&q_rotation);
    quaternion_into_gl_matrix(q_rotation, rotMatrix);
    //
	position = make_vector( 0.0f, 0.0f, 0.0f);
	//
	zero_distance = 0.0;  //  10 km
	no_draw_distance = 100000.0;  //  10 km
	//
	distance_travelled = 0.0;
	//
	energy =	0.0;
	//
	collision_radius = 0.0;
	//
	collidingEntities = [(NSMutableArray *)[NSMutableArray alloc] initWithCapacity:16];   // alloc automatically retains
	//
	scan_class = CLASS_NOT_SET;
	//
	universal_id = NO_TARGET;
	universe = nil;
	//
	is_smooth_shaded = NO;
    //
    n_vertices = 0;
    n_faces = 0;
    //
    displayListName = 0;
    //
    status = STATUS_DEMO;
    //
    basefile = @"No Model";
	//
	throw_sparks = NO;
	//
	usingVAR = NO;
	//
	isParticle = NO;
	isRing = NO;
	isShip = NO;
	isStation = NO;
	isPlanet = NO;
	isPlayer = NO;
	isSky = NO;
	isSubentity = NO;
	//
	isSunlit = YES;
	shadingEntityID = NO_TARGET;
	//
	collision_region = nil;
	//
	collisionTestFilter = NO;
	x_next = x_previous = nil;
	y_next = y_previous = nil;
	z_next = z_previous = nil;
	//
	collision_chain = nil;
	//
    return self;
}

- (void) dealloc
{
	// universe is a mere reference. It is neither retained nor released.
    if (basefile)	[basefile release];
	if (collidingEntities)	[collidingEntities release];
	if (trackLock) [trackLock release];
	if (collision_region) [collision_region release];
	[super dealloc];
}

- (void) removeFromLinkedLists
{
	if (x_previous)		x_previous->x_next = x_next;
	if (x_next)			x_next->x_previous = x_previous;
	//
	if (y_previous)		y_previous->y_next = y_next;
	if (y_next)			y_next->y_previous = y_previous;
	//
	if (z_previous)		z_previous->z_next = z_next;
	if (z_next)			z_next->z_previous = z_previous;
	//
	x_previous = x_next = nil;
	y_previous = y_next = nil;
	z_previous = z_next = nil;
}

- (void) updateLinkedLists
{
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
	if ((x_previous == nil)&&(universe))
			universe->x_list_start = self;
	
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
	if ((y_previous == nil)&&(universe))
			universe->y_list_start = self;
	
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
	if ((z_previous == nil)&&(universe))
			universe->z_list_start = self;
	
	// done
}

- (void) warnAboutHostiles
{
	// do nothing for now, this can be expanded in sub classes
	NSLog(@"***** Entity does nothing in warnAboutHostiles");
}

- (Universe *) universe
{
	return universe;
}

- (void) setUniverse:(Universe *)univ
{
	universe = univ;
}

- (CollisionRegion*) collision_region
{
	return collision_region;
}

- (void) setCollisionRegion: (CollisionRegion*) region
{
	if (collision_region) [collision_region release];
	collision_region = [region retain];
}

- (void) setUniversal_id:(int)uid
{
	universal_id = uid;
}

- (int) universal_id
{
	return universal_id;
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

- (BOOL) isSmoothShaded
{
	return is_smooth_shaded;
}
- (void) setSmoothShaded:(BOOL) value
{
	is_smooth_shaded = value;
}

- (void) setOwner:(Entity *) ent
{
	int	owner_id = [ent universal_id];
	if (!universe)
	{
		[self setUniverse:[ent universe]];
		owner = owner_id;
	}
	else
	{
		if ([universe entityForUniversalID:owner_id] == ent)	// check to make sure it's kosher
			owner = owner_id;
		else
			owner = NO_TARGET;
	}
}

- (Entity *) owner
{
	return [universe entityForUniversalID:owner];
}


- (void) setModel:(NSString *) modelName
{
	// use our own pool to save big memory
	NSAutoreleasePool* mypool = [[NSAutoreleasePool alloc] init];
	// clear old data
	if (basefile)	[basefile release];
    basefile = [modelName retain];
	//
	[self regenerateDisplayList];
    //
    [self loadData:basefile];
    //
    [self checkNormalsAndAdjustWinding];
    //
	// set the collision radius
	//
	collision_radius = [self findCollisionRadius];
	actual_radius = collision_radius;
	//NSLog(@"Entity with model '%@' collision radius set to %f",modelName, collision_radius);
	//
	[mypool release];
}
- (NSString *) getModel
{
	return basefile;
}

- (void) setPosition:(Vector) posn
{
	position.x = posn.x;
	position.y = posn.y;
	position.z = posn.z;
}

- (void) setPosition:(GLfloat) x:(GLfloat) y:(GLfloat) z
{
	position.x = x;
	position.y = y;
	position.z = z;
}

- (double) getZeroDistance
{
//	NSLog(@"DEBUG %@ %.1f", self, zero_distance);
	return zero_distance;
}

- (Vector) relative_position
{
	return relative_position;
}

- (NSComparisonResult) compareZeroDistance:(Entity *)otherEntity;
{
	if ((otherEntity)&&(zero_distance > otherEntity->zero_distance))
		return NSOrderedAscending;
	else
		return NSOrderedDescending;
}

- (Geometry*) getGeometry
{
	Geometry* result = [(Geometry *)[Geometry alloc] initWithCapacity: n_faces];
	int i;
	for (i = 0; i < n_faces; i++)
	{
		Triangle tri;
		tri.v[0] = vertices[faces[i].vertex[0]];
		tri.v[1] = vertices[faces[i].vertex[1]];
		tri.v[2] = vertices[faces[i].vertex[2]];
		[result addTriangle: tri];
	}
	return [result autorelease];
}

- (BoundingBox) getBoundingBox
{
	return boundingBox;
}

- (GLfloat) mass
{
	return mass;
}

- (void) setQRotation:(Quaternion) quat
{
	q_rotation = quat;
    quaternion_into_gl_matrix(q_rotation, rotMatrix);
}

- (Quaternion) QRotation
{
	return q_rotation;
}

- (void) setVelocity:(Vector) vel
{
	velocity = vel;
}

- (Vector) getVelocity
{
	return velocity;
}

- (double) getVelocityAsSpeed
{
	return sqrt(velocity.x * velocity.x + velocity.y * velocity.y + velocity.z * velocity.z);
}

- (double) distance_travelled
{
	return distance_travelled;
}

- (void) setDistanceTravelled: (double) value
{
	distance_travelled = value;
}

- (void) setStatus:(int) stat
{
	status = stat;
}

- (int) getStatus
{
	return status;
}

- (void) setScanClass:(int) s_class
{
	scan_class = s_class;
}

- (int) scanClass
{
	return scan_class;
}

- (void) setEnergy:(double) amount
{
	energy = amount;
}

- (double) getEnergy
{
	return energy;
}




- (void) applyRoll:(GLfloat) roll andClimb:(GLfloat) climb
{
	if ((roll == 0.0)&&(climb == 0.0)&&(!has_rotated))
		return;

	if (roll)
		quaternion_rotate_about_z( &q_rotation, -roll);
	if (climb)
		quaternion_rotate_about_x( &q_rotation, -climb);

    quaternion_normalise(&q_rotation);
    quaternion_into_gl_matrix(q_rotation, rotMatrix);
}

- (void) applyRoll:(GLfloat) roll climb:(GLfloat) climb andYaw:(GLfloat) yaw
{
	if ((roll == 0.0)&&(climb == 0.0)&&(yaw == 0.0)&&(!has_rotated))
		return;

	if (roll)
		quaternion_rotate_about_z( &q_rotation, -roll);
	if (climb)
		quaternion_rotate_about_x( &q_rotation, -climb);
	if (yaw)
		quaternion_rotate_about_y( &q_rotation, -yaw);

    quaternion_normalise(&q_rotation);
    quaternion_into_gl_matrix(q_rotation, rotMatrix);
}

- (void) moveForward:(double) amount
{
    Vector		forward = vector_forward_from_quaternion(q_rotation);
	distance_travelled += amount;
	position.x += amount * forward.x;
	position.y += amount * forward.y;
	position.z += amount * forward.z;
}

- (GLfloat *) rotationMatrix
{
    return rotMatrix;
}

- (GLfloat *) drawRotationMatrix
{
    return rotMatrix;
}

- (Vector) getPosition
{
    return position;
}

- (Vector) getViewpointPosition
{
    return position;
}

- (Vector) getViewpointOffset
{
	return make_vector( 0.0f, 0.0f, 0.0f);
}

- (BOOL) canCollide
{
	return YES;
}

- (double) collisionRadius
{
	return collision_radius;
}

- (void) setCollisionRadius:(double) amount
{
	collision_radius = amount;
}

- (NSMutableArray *) collisionArray
{
	return collidingEntities;
}


- (void) drawEntity:(BOOL) immediate :(BOOL) translucent
{
    // draw the thing !
    //
    int ti;
    GLfloat mat_ambient[] = { 1.0, 1.0, 1.0, 1.0 };
    GLfloat mat_no[] =		{ 0.0, 0.0, 0.0, 1.0 };

	NS_DURING

		if (is_smooth_shaded)
			glShadeModel(GL_SMOOTH);
		else
			glShadeModel(GL_FLAT);

		if (!translucent)
		{
			if (basefile)
			{
				// calls moved here because they are unsupported in display lists
				//
				glDisableClientState(GL_COLOR_ARRAY);
				glDisableClientState(GL_INDEX_ARRAY);
				glDisableClientState(GL_EDGE_FLAG_ARRAY);
				//
				glEnableClientState(GL_VERTEX_ARRAY);
				glEnableClientState(GL_NORMAL_ARRAY);
				glEnableClientState(GL_TEXTURE_COORD_ARRAY);

				glVertexPointer( 3, GL_FLOAT, 0, entityData.vertex_array);
				glNormalPointer( GL_FLOAT, 0, entityData.normal_array);
				glTexCoordPointer( 2, GL_FLOAT, 0, entityData.texture_uv_array);

				if (immediate)
				{

#ifdef GNUSTEP
           			// TODO: Find out what these APPLE functions can be replaced with
#else
					if (usingVAR)
						glBindVertexArrayAPPLE(gVertexArrayRangeObjects[0]);
#endif

					//
					// gap removal (draws flat polys)
					//
					glDisable(GL_TEXTURE_2D);
					GLfloat amb_diff0[] = { 0.5, 0.5, 0.5, 1.0};
					glMaterialfv( GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE, amb_diff0);
					glMaterialfv( GL_FRONT_AND_BACK, GL_EMISSION, mat_no);
					glColor4f( 0.25, 0.25, 0.25, 1.0);	// gray
					glDepthMask(GL_FALSE); // don't write to depth buffer
					glDrawArrays( GL_TRIANGLES, 0, entityData.n_triangles);	// draw in gray to mask the edges
					glDepthMask(GL_TRUE);

					//
					// now the textures ...
					//
					glEnable(GL_TEXTURE_2D);
					glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
					glMaterialfv( GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE, mat_ambient);
					glMaterialfv( GL_FRONT_AND_BACK, GL_EMISSION, mat_no);

					for (ti = 1; ti <= n_textures; ti++)
					{
						glBindTexture(GL_TEXTURE_2D, texture_name[ti]);
						glDrawArrays( GL_TRIANGLES, triangle_range[ti].location, triangle_range[ti].length);
					}
				}
				else
				{
					if (displayListName != 0)
					{
						glCallList(displayListName);
					}
					else
					{
						[self initialiseTextures];
						[self generateDisplayList];
					}
				}
			}
			else
			{
				NSLog(@"ERROR no basefile for entity %@");
			//	NSBeep();	// appkit dependency
			}
		}
		glShadeModel(GL_SMOOTH);
		checkGLErrors([NSString stringWithFormat:@"Entity after drawing %@", self]);

	NS_HANDLER

		NSLog(@"***** [Entity drawEntity::] encountered exception: %@ : %@ *****",[localException name], [localException reason]);
		NSLog(@"***** Removing entity %@ from universe *****", self);
		[universe removeEntity:self];
		if ([[localException name] hasPrefix:@"Oolite"])
			[universe handleOoliteException:localException];	// handle these ourself
		else
			[localException raise];	// pass these on

	NS_ENDHANDLER
}

- (void) drawSubEntity:(BOOL) immediate :(BOOL) translucent
{
	Entity* my_owner = [universe entityForUniversalID:owner];
	if (my_owner)
	{
		// this test provides an opportunity to do simple LoD culling
		//
		zero_distance = my_owner->zero_distance;
		if (zero_distance > no_draw_distance)
		{
			//NSLog(@"DEBUG - sub entity '%@' too far away to draw", self);
			return; // TOO FAR AWAY
		}
	}
	if (status == STATUS_ACTIVE)
	{
		Vector abspos = position;  // STATUS_ACTIVE means it is in control of it's own orientation
		Entity*		father = my_owner;
		GLfloat*	r_mat = [father drawRotationMatrix];
		while (father)
		{
			mult_vector_gl_matrix(&abspos, r_mat);
			Vector pos = father->position;
			abspos.x += pos.x;	abspos.y += pos.y;	abspos.z += pos.z;
			father = [father owner];
			r_mat = [father drawRotationMatrix];
		}
		glPopMatrix();  // one down
		glPushMatrix();
				// position and orientation is absolute
		glTranslated( abspos.x, abspos.y, abspos.z);

		glMultMatrixf(rotMatrix);

		[self drawEntity:immediate :translucent];
	}
	else
	{
		glPushMatrix();

		glTranslated( position.x, position.y, position.z);
		glMultMatrixf(rotMatrix);

		[self drawEntity:immediate :translucent];

		glPopMatrix();
	}
}

- (void) reloadTextures
{
#ifdef WIN32
    int fi;

	//NSLog(@"Entity::reloadTextures called on [%@]", [self description]);

	// Force the entity to reload the textures for each face by clearing the face's texture name.
    for (fi = 0; fi < n_faces; fi++)
        faces[fi].texName = 0;

	// Force the display list to be regenerated next time a frame is drawn.
	[self regenerateDisplayList];
#endif
}


- (void) initialiseTextures
{
    // roll out each face and texture in turn
    //
    int fi,ti ;

    for (fi = 0; fi < n_faces; fi++)
    {
		NSString* texture = [NSString stringWithUTF8String:(char*)faces[fi].textureFileStr255];
        if ((faces[fi].texName == 0)&&(texture))
        {
            // load texture into Universe texturestore
            //NSLog(@"Off to load %@", texture);
            if (universe)
            {
                faces[fi].texName = [[universe textureStore] getTextureNameFor: texture];
            }
        }
    }

	for (ti = 1; ti <= n_textures; ti++)
	{
		if (!texture_name[ti])
		{
			texture_name[ti] = [[universe textureStore] getTextureNameFor: [NSString stringWithUTF8String: (char*)texture_file[ti]]];
//			NSLog(@"DEBUG (initialiseTextures) Processed textureFile : %@ to texName : %d", entityData[ti].textureFile, entityData[ti].texName);
		}
	}
}

- (void) regenerateDisplayList
{
	glDeleteLists(displayListName,1);
	displayListName = 0;
}

- (void) generateDisplayList
{
    displayListName = glGenLists(1);
    if (displayListName != 0)
    {
        glNewList(displayListName, GL_COMPILE);
        [self drawEntity:YES:NO];	//	immediate YES	translucent NO
        glEndList();
		//
		checkGLErrors([NSString stringWithFormat:@"Entity after generateDisplayList for %@", self]);
		//
    }
}

- (void) update:(double) delta_t
{
	Entity* player = [universe entityZero];
	if (player)
	{
		Vector p0 = player->position;
		relative_position = make_vector( position.x - p0.x, position.y - p0.y, position.z - p0.z);
		zero_distance = magnitude2(relative_position);
	}
	else
		zero_distance = -1;

	has_moved = ((position.x != last_position.x)||(position.y != last_position.y)||(position.z != last_position.z));
	last_position = position;
	has_rotated = ((q_rotation.w != last_q_rotation.w)||(q_rotation.x != last_q_rotation.x)||(q_rotation.y != last_q_rotation.y)||(q_rotation.z != last_q_rotation.z));
	last_q_rotation = q_rotation;
}

- (void) saveToLastFrame
{
	double t_now = [universe getTime];
	if (t_now >= track_time + 0.1)		// update every 1/10 of a second
	{
		// save previous data
		track_time = t_now;
		track[track_index].position =	position;
		track[track_index].q_rotation =	q_rotation;
		track[track_index].timeframe =	track_time;
		track[track_index].k =	vector_forward_from_quaternion(q_rotation);
		track_index = (track_index + 1 ) & 0xff;
	}
}

- (void) savePosition:(Vector)pos atTime:(double)t_time atIndex:(int)t_index
{
	track_time = t_time;
	track[t_index].position = pos;
	track[t_index].timeframe =	t_time;
	track_index = (t_index + 1 ) & 0xff;
}

- (void) saveFrame:(Frame)frame atIndex:(int)t_index
{
	track[t_index] = frame;
	track_time = frame.timeframe;
	track_index = (t_index + 1 ) & 0xff;
}

// reset frames
//
- (void) resetFramesFromFrame:(Frame) resetFrame withVelocity:(Vector) vel1
{
	Vector v1 = make_vector( 0.1 * vel1.x, 0.1 * vel1.y, 0.1 * vel1.z);
	double t_now = [universe getTime];
	Frame setFrame = resetFrame;
	setFrame.timeframe = t_now;
	track_time = t_now;
	int i;
	int index = (track_index - 1) & 0xff;
	for (i = 0; i < 256; i++)
	{
		track[index] = setFrame;
		setFrame.position.x -= v1.x;
		setFrame.position.y -= v1.y;
		setFrame.position.z -= v1.z;
		setFrame.timeframe -= 0.1;
		index --;
		index &= 0xff;
	}
}

- (BOOL) resetToTime:(double) t_frame	// timeframe is relative to now ie. -0.5 = half a second ago.
{
	if (t_frame >= 0)
		return NO;

	Frame	selectedFrame = [self frameAtTime:t_frame];
	[self setPosition:selectedFrame.position];
	[self setQRotation:selectedFrame.q_rotation];
	return YES;
}

- (Frame) frameAtTime:(double) t_frame	// t_frame is relative to now ie. -0.5 = half a second ago.
{
	Frame result;
	result.position = position;
	result.q_rotation = q_rotation;
	result.timeframe = [universe getTime];
	result.k = vector_forward_from_quaternion(q_rotation);
	//
	if (t_frame >= 0.0)
		return result;
	//
	double moment_in_time = [universe getTime] + t_frame;
	if (moment_in_time >= track_time)					// between the last saved frame and now
	{
		int t1 = (track_index - 1)&0xff;	// last saved moment
		double period = result.timeframe - track_time;
		double f0 = (result.timeframe - moment_in_time)/period;
		double f1 = 1.0 - f0;
		Vector posn;
		posn.x =	f0 * result.position.x + f1 * track[t1].position.x;
		posn.y =	f0 * result.position.y + f1 * track[t1].position.y;
		posn.z =	f0 * result.position.z + f1 * track[t1].position.z;
		Quaternion qrot;
		qrot.w =	f0 * result.q_rotation.w + f1 * track[t1].q_rotation.w;
		qrot.x =	f0 * result.q_rotation.x + f1 * track[t1].q_rotation.x;
		qrot.y =	f0 * result.q_rotation.y + f1 * track[t1].q_rotation.y;
		qrot.z =	f0 * result.q_rotation.z + f1 * track[t1].q_rotation.z;
		result.position = posn;
		result.q_rotation = qrot;
		result.timeframe = moment_in_time;
		result.k = vector_forward_from_quaternion(qrot);
		return result;
	}
	//
	if (moment_in_time < track[track_index].timeframe)	// more than 256 frames back
	{
		return track[track_index];
	}
	//
	int t1 = (track_index - 1)&0xff;
	while (moment_in_time < track[t1].timeframe)
		t1 = (t1 - 1) & 0xff;
	int t0 = (t1 + 1) & 0xff;
	// interpolate between t0 and t1
	double period = track[0].timeframe - track[1].timeframe;
	double f0 = (track[t0].timeframe - moment_in_time)/period;
	double f1 = 1 - f0;
	Vector posn;
	posn.x =	f0 * track[t0].position.x + f1 * track[t1].position.x;
	posn.y =	f0 * track[t0].position.y + f1 * track[t1].position.y;
	posn.z =	f0 * track[t0].position.z + f1 * track[t1].position.z;
	Quaternion qrot;
	qrot.w =	f0 * track[t0].q_rotation.w + f1 * track[t1].q_rotation.w;
	qrot.x =	f0 * track[t0].q_rotation.x + f1 * track[t1].q_rotation.x;
	qrot.y =	f0 * track[t0].q_rotation.y + f1 * track[t1].q_rotation.y;
	qrot.z =	f0 * track[t0].q_rotation.z + f1 * track[t1].q_rotation.z;
	result.position = posn;
	result.q_rotation = qrot;
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
	double moment_in_time = [universe getTime] + t_frame;
	if (moment_in_time > track_time)					// between the last saved frame and now
	{
		Frame fr1 = track[(track_index - 1)&0xff];	// last saved moment
		double period = (moment_in_time - t_frame) - track_time;
		double f1 =	-t_frame/period;
		double f0 =	1.0 - f1;
//		NSLog(@"DEBUG m-i-t:%.3f track_time:%.3f t_frame:%.3f period:%.3f f0:f1 %.3f:%.3f",
//					moment_in_time, track_time, t_frame, period, f0, f1);
		Vector posn;
		posn.x =	f0 * result.position.x + f1 * fr1.position.x;
		posn.y =	f0 * result.position.y + f1 * fr1.position.y;
		posn.z =	f0 * result.position.z + f1 * fr1.position.z;
		Quaternion qrot;
		qrot.w =	f0 * result.q_rotation.w + f1 * fr1.q_rotation.w;
		qrot.x =	f0 * result.q_rotation.x + f1 * fr1.q_rotation.x;
		qrot.y =	f0 * result.q_rotation.y + f1 * fr1.q_rotation.y;
		qrot.z =	f0 * result.q_rotation.z + f1 * fr1.q_rotation.z;
		result.position = posn;
		result.q_rotation = qrot;
		result.timeframe = moment_in_time;
		result.k = vector_forward_from_quaternion(qrot);
		return result;
	}
	//
	if (moment_in_time < track[track_index].timeframe)	// more than 256 frames back
	{
		return track[track_index];
	}
	//
	int t1 = (track_index - 1)&0xff;
	while (moment_in_time < track[t1].timeframe)
		t1 = (t1 - 1) & 0xff;
	int t0 = (t1 + 1) & 0xff;
	// interpolate between t0 and t1
	double period = track[t0].timeframe - track[t1].timeframe;
	double f0 = (moment_in_time - track[t1].timeframe)/period;
	double f1 = 1.0 - f0;
//		NSLog(@"DEBUG m-i-t:%.3f t0.timeframe:%.3f t1.timeframe:%.3f period:%.3f f0:f1 %.3f:%.3f",
//					moment_in_time, track[t0].timeframe, track[t1].timeframe, period, f0, f1);
	Vector posn;
	posn.x =	f0 * track[t0].position.x + f1 * track[t1].position.x;
	posn.y =	f0 * track[t0].position.y + f1 * track[t1].position.y;
	posn.z =	f0 * track[t0].position.z + f1 * track[t1].position.z;
	Quaternion qrot;
	qrot.w =	f0 * track[t0].q_rotation.w + f1 * track[t1].q_rotation.w;
	qrot.x =	f0 * track[t0].q_rotation.x + f1 * track[t1].q_rotation.x;
	qrot.y =	f0 * track[t0].q_rotation.y + f1 * track[t1].q_rotation.y;
	qrot.z =	f0 * track[t0].q_rotation.z + f1 * track[t1].q_rotation.z;
	result.position = posn;
	result.q_rotation = qrot;
	result.timeframe = moment_in_time;
	result.k = vector_forward_from_quaternion(qrot);
	return result;
}

- (NSDictionary*) modelData
{
	NSMutableDictionary*	mdict = [NSMutableDictionary dictionaryWithCapacity:8];
	[mdict setObject:[NSNumber numberWithInt: n_vertices]	forKey:@"n_vertices"];
	[mdict setObject:[NSData dataWithBytes: vertices		length: sizeof(Vector)*n_vertices]	forKey:@"vertices"];
	[mdict setObject:[NSData dataWithBytes: vertex_normal	length: sizeof(Vector)*n_vertices]	forKey:@"normals"];
	[mdict setObject:[NSNumber numberWithInt: n_faces] forKey:@"n_faces"];
	[mdict setObject:[NSData dataWithBytes: faces			length: sizeof(Face)*n_faces]		forKey:@"faces"];
	return [NSDictionary dictionaryWithDictionary:mdict];
}

- (void) setModelFromModelData:(NSDictionary*) dict
{
	n_vertices = [[dict objectForKey:@"n_vertices"] intValue];
	n_faces = [[dict objectForKey:@"n_faces"] intValue];
	NSData* vdata = (NSData*)[dict objectForKey:@"vertices"];
	NSData* ndata = (NSData*)[dict objectForKey:@"normals"];
	NSData* fdata = (NSData*)[dict objectForKey:@"faces"];
	if ((vdata) && (ndata) && (fdata))
	{
		Vector* vbytes = (Vector*)[vdata bytes];
		Vector* nbytes = (Vector*)[ndata bytes];
		Face* fbytes = (Face*)[fdata bytes];
		int i;
		for (i = 0; i < n_vertices; i++)
		{
			vertices[i] = vbytes[i];
			vertex_normal[i] = nbytes[i];
		}
		for (i = 0; i < n_faces; i++)
		{
			faces[i] = fbytes[i];
		}
	}
	else
	{
		NSLog(@"ERROR setModelFromData: FAILED");
		// should throw an oolite-fatal-exception here
		NSException* myException = [NSException
			exceptionWithName: OOLITE_EXCEPTION_FATAL
			reason:[NSString stringWithFormat:@"Failed during [Entity setModelFromModelData: %@]", dict]
			userInfo:nil];
		[myException raise];
	}
}

- (void) loadData:(NSString *) filename
{
    NSScanner		*scanner;
    NSString		*data = nil;
    NSMutableArray	*lines;
    BOOL			failFlag = NO;
    NSString		*failString = @"***** ";
    int	i, j;

	NSString*		data_key = [NSString stringWithFormat:@"%@>>data", filename];

	BOOL using_preloaded = NO;

	if (data_store_universe)
	{
		if ([[data_store_universe preloadedDataFiles] objectForKey:filename])
		{
//			NSLog(@"Reusing data for %@ from [data_store_universe preloadedDataFiles]", filename);
			data = (NSString *)[[data_store_universe preloadedDataFiles] objectForKey:filename];
			using_preloaded = YES;
		}
		else
		{
			data = [ResourceManager stringFromFilesNamed:filename inFolder:@"Models"];
			if (data != nil)
				[[data_store_universe preloadedDataFiles] setObject:data forKey:filename];
		}
	}

	if ([[data_store_universe preloadedDataFiles] objectForKey:data_key])
	{
//		NSLog(@"DEBUG setting model %@ from saved vertex data", filename);
		[self setModelFromModelData:(NSDictionary *)[[data_store_universe preloadedDataFiles] objectForKey:data_key]];
	}
	else
	{

		// failsafe in case the stored data fails
		if (data == nil)
		{
			data = [ResourceManager stringFromFilesNamed:filename inFolder:@"Models"];
			using_preloaded = NO;
		}

		if (data == nil)
		{
			NSLog(@"ERROR - could not find %@", filename);
			failFlag = YES;
			// ERROR model file not found
			NSException* myException = [NSException
				exceptionWithName:@"OoliteException"
				reason:[NSString stringWithFormat:@"No model called '%@' could be found in %@.", filename, [ResourceManager paths]]
				userInfo:nil];
			[myException raise];
		}

		// strip out comments and commas between values
		//
		lines = [NSMutableArray arrayWithArray:[data componentsSeparatedByString:@"\n"]];
		for (i = 0; i < [ lines count]; i++)
		{
			NSString *line = [lines objectAtIndex:i];
			NSArray *parts;
			//
			// comments
			//
			parts = [line componentsSeparatedByString:@"#"];
			line = [parts objectAtIndex:0];
			parts = [line componentsSeparatedByString:@"//"];
			line = [parts objectAtIndex:0];
			//
			// commas
			//
			line = [[line componentsSeparatedByString:@","] componentsJoinedByString:@" "];
			//
			[lines replaceObjectAtIndex:i withObject:line];
		}
		data = [lines componentsJoinedByString:@"\n"];

		//NSLog(@"More data:\n%@",data);

		scanner = [NSScanner scannerWithString:data];

		// get number of vertices
		//
		[scanner setScanLocation:0];	//reset
		if ([scanner scanString:@"NVERTS" intoString:(NSString **)nil])
		{
			int n_v;
			if ([scanner scanInt:&n_v])
				n_vertices = n_v;
			else
			{
				failFlag = YES;
				failString = [NSString stringWithFormat:@"%@Failed to read value of NVERTS\n",failString];
			}
		}
		else
		{
			failFlag = YES;
			failString = [NSString stringWithFormat:@"%@Failed to read NVERTS\n",failString];
		}

		if (n_vertices > MAX_VERTICES_PER_ENTITY)
		{
			NSLog(@"ERROR - model %@ has too many vertices (model has %d, maximum is %d)", filename, n_vertices, MAX_VERTICES_PER_ENTITY);
			failFlag = YES;
			// ERROR model file not found
			NSException* myException = [NSException
				exceptionWithName:@"OoliteException"
				reason:[NSString stringWithFormat:@"ERROR - model %@ has too many vertices (model has %d, maximum is %d)", filename, n_vertices, MAX_VERTICES_PER_ENTITY]
				userInfo:nil];
			[myException raise];
		}

		// get number of faces
		//
		//[scanner setScanLocation:0];	//reset
		if ([scanner scanString:@"NFACES" intoString:(NSString **)nil])
		{
			int n_f;
			if ([scanner scanInt:&n_f])
				n_faces = n_f;
			else
			{
				failFlag = YES;
				failString = [NSString stringWithFormat:@"%@Failed to read value of NFACES\n",failString];
			}
		}
		else
		{
			failFlag = YES;
			failString = [NSString stringWithFormat:@"%@Failed to read NFACES\n",failString];
		}

		if (n_faces > MAX_FACES_PER_ENTITY)
		{
			NSLog(@"ERROR - model %@ has too many faces (model has %d, maximum is %d)", filename, n_faces, MAX_FACES_PER_ENTITY);
			failFlag = YES;
			// ERROR model file not found
			NSException* myException = [NSException
				exceptionWithName:@"OoliteException"
				reason:[NSString stringWithFormat:@"ERROR - model %@ has too many faces (model has %d, maximum is %d)", filename, n_faces, MAX_FACES_PER_ENTITY]
				userInfo:nil];
			[myException raise];
		}

		// get vertex data
		//
		//[scanner setScanLocation:0];	//reset
		if ([scanner scanString:@"VERTEX" intoString:(NSString **)nil])
		{
			for (j = 0; j < n_vertices; j++)
			{
				float x, y, z;
				if (!failFlag)
				{
					if (![scanner scanFloat:&x])
						failFlag = YES;
					if (![scanner scanFloat:&y])
						failFlag = YES;
					if (![scanner scanFloat:&z])
						failFlag = YES;
					if (!failFlag)
					{
						vertices[j].x = x;	vertices[j].y = y;	vertices[j].z = z;
					}
					else
					{
						failString = [NSString stringWithFormat:@"%@Failed to read a value for vertex[%d] in VERTEX\n", failString, j];
					}
				}
			}
		}
		else
		{
			failFlag = YES;
			failString = [NSString stringWithFormat:@"%@Failed to find VERTEX data\n",failString];
		}

		// get face data
		//
		if ([scanner scanString:@"FACES" intoString:(NSString **)nil])
		{
			for (j = 0; j < n_faces; j++)
			{
				int r, g, b;
				float nx, ny, nz;
				int n_v;
				if (!failFlag)
				{
					// colors
					//
					if (![scanner scanInt:&r])
						failFlag = YES;
					if (![scanner scanInt:&g])
						failFlag = YES;
					if (![scanner scanInt:&b])
						failFlag = YES;
					if (!failFlag)
					{
						faces[j].red = r/255.0;    faces[j].green = g/255.0;    faces[j].blue = b/255.0;
					}
					else
					{
						failString = [NSString stringWithFormat:@"%@Failed to read a color for face[%d] in FACES\n", failString, j];
					}

					// normal
					//
					if (![scanner scanFloat:&nx])
						failFlag = YES;
					if (![scanner scanFloat:&ny])
						failFlag = YES;
					if (![scanner scanFloat:&nz])
						failFlag = YES;
					if (!failFlag)
					{
						faces[j].normal.x = nx;    faces[j].normal.y = ny;    faces[j].normal.z = nz;
					}
					else
					{
						failString = [NSString stringWithFormat:@"%@Failed to read a normal for face[%d] in FACES\n", failString, j];
					}

					// vertices
					//
					if ([scanner scanInt:&n_v])
					{
						faces[j].n_verts = n_v;
					}
					else
					{
						failFlag = YES;
						failString = [NSString stringWithFormat:@"%@Failed to read number of vertices for face[%d] in FACES\n", failString, j];
					}
					//
					if (!failFlag)
					{
						int vi;
						for (i = 0; i < n_v; i++)
						{
							if ([scanner scanInt:&vi])
							{
								faces[j].vertex[i] = vi;
							}
							else
							{
								failFlag = YES;
								failString = [NSString stringWithFormat:@"%@Failed to read vertex[%d] for face[%d] in FACES\n", failString, i, j];
							}
						}
					}
				}
			}
		}
		else
		{
			failFlag = YES;
			failString = [NSString stringWithFormat:@"%@Failed to find FACES data\n",failString];
		}

		// get textures data
		//
		if ([scanner scanString:@"TEXTURES" intoString:(NSString **)nil])
		{
			for (j = 0; j < n_faces; j++)
			{
				NSString	*texfile;
				float	max_x, max_y;
				float	s, t;
				if (!failFlag)
				{
					// texfile
					//
					[scanner scanCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:(NSString **)nil];
					if (![scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&texfile])
					{
						failFlag = YES;
						failString = [NSString stringWithFormat:@"%@Failed to read texture filename for face[%d] in TEXTURES\n", failString, j];
					}
					else
					{
//						faces[j].textureFile = [texfile retain];
						strlcpy( (char*)faces[j].textureFileStr255, [texfile UTF8String], 256);
//						NSLog(@"DEBUG TEST strlcpy of '%@' result = '%s'", texfile, faces[j].textureFileStr255);
					}
					faces[j].texName = 0;

					// texture size
					//
				   if (!failFlag)
					{
						if (![scanner scanFloat:&max_x])
							failFlag = YES;
						if (![scanner scanFloat:&max_y])
							failFlag = YES;
						if (failFlag)
							failString = [NSString stringWithFormat:@"%@Failed to read texture size for max_x and max_y in face[%d] in TEXTURES\n", failString, j];
					}

					// vertices
					//
					if (!failFlag)
					{
						for (i = 0; i < faces[j].n_verts; i++)
						{
							if (![scanner scanFloat:&s])
								failFlag = YES;
							if (![scanner scanFloat:&t])
								failFlag = YES;
							if (!failFlag)
							{
								faces[j].s[i] = s / max_x;    faces[j].t[i] = t / max_y;
							}
							else
								failString = [NSString stringWithFormat:@"%@Failed to read s t coordinates for vertex[%d] in face[%d] in TEXTURES\n", failString, i, j];
						}
					}
				}
			}
		}
		else
		{
			failFlag = YES;
			failString = [NSString stringWithFormat:@"%@Failed to find TEXTURES data\n",failString];
		}

		// check normals before creating new textures
		//
		[self checkNormalsAndAdjustWinding];

		if ((failFlag)&&([failString rangeOfString:@"TEXTURES"].location != NSNotFound))
		{
			//NSLog(@"Off to make new textures!");
			[self fakeTexturesWithImageFile:@"metal.png" andMaxSize:NSMakeSize(256.0,256.0)];

			// dump out data for ships with faked textures
			//if (isShip)
			//	//NSLog(@"Faked Texture coordinates for this model :\n\n%@\n\n", [self toString]);
		}

		if (failFlag)
			NSLog([NSString stringWithFormat:@"%@ ..... from %@ %@", failString, filename, (using_preloaded)? @"(from preloaded data)" : @"(from file)"]);

		// check for smooth chading and recalculate normals
		//
		if (is_smooth_shaded)
			[self calculateVertexNormals];
		//

		// save the resulting data for possible reuse
		//
		if (![[data_store_universe preloadedDataFiles] objectForKey: data_key])
		{
			[[data_store_universe preloadedDataFiles] setObject:[self modelData] forKey: data_key];
		}
	}

	// set the collision radius
	//
	collision_radius = [self findCollisionRadius];
	actual_radius = collision_radius;

	// set up vertex arrays for drawing
	//
	[self setUpVertexArrays];
	//

	//
	usingVAR = [self OGL_InitVAR];
	//
	if (usingVAR)
	{
		[self OGL_AssignVARMemory:sizeof(EntityData) :(void *)&entityData :0];
	}
	//

}

- (void) checkNormalsAndAdjustWinding
{
    Vector calculatedNormal;
    int i, j;
    for (i = 0; i < n_faces; i++)
    {
        Vector v0, v1, v2, norm;
        v0 = vertices[faces[i].vertex[0]];
        v1 = vertices[faces[i].vertex[1]];
        v2 = vertices[faces[i].vertex[2]];
        norm = faces[i].normal;
		calculatedNormal = normal_to_surface (v2, v1, v0);
        if ((norm.x == 0.0)&&(norm.y == 0.0)&&(norm.z == 0.0))
		{
			//NSLog(@"Using calculated normal for face %d", i);
			faces[i].normal = normal_to_surface (v0, v1, v2);
			norm = normal_to_surface (v0, v1, v2);
		}
        if ((norm.x*calculatedNormal.x < 0)||(norm.y*calculatedNormal.y < 0)||(norm.z*calculatedNormal.z < 0))
        {
            // normal lies in the WRONG direction!
            // reverse the winding
            int v[faces[i].n_verts];
            GLfloat s[faces[i].n_verts];
            GLfloat t[faces[i].n_verts];

            //
            //NSLog(@"Normal pointing the wrong way for winding on face %d", i);
            //

            for (j = 0; j < faces[i].n_verts; j++)
            {
            	v[j] = faces[i].vertex[faces[i].n_verts - 1 - j];
            	s[j] = faces[i].s[faces[i].n_verts - 1 - j];
            	t[j] = faces[i].t[faces[i].n_verts - 1 - j];
            }
            for (j = 0; j < faces[i].n_verts; j++)
            {
            	faces[i].vertex[j] = v[j];
                faces[i].s[j] = s[j];
                faces[i].t[j] = t[j];
            }
        }
    }
}

- (void) calculateVertexNormals
{
	int i,j;
	float	triangle_area[n_faces];
	for (i = 0 ; i < n_faces; i++)
	{
		// calculate areas using Herons formula
		// in the form Area = sqrt(2*(a2*b2+b2*c2+c2*a2)-(a4+b4+c4))/4
		float	a2 = distance2( vertices[faces[i].vertex[0]], vertices[faces[i].vertex[1]]);
		float	b2 = distance2( vertices[faces[i].vertex[1]], vertices[faces[i].vertex[2]]);
		float	c2 = distance2( vertices[faces[i].vertex[2]], vertices[faces[i].vertex[0]]);
		triangle_area[i] = sqrt( 2.0 * (a2 * b2 + b2 * c2 + c2 * a2) - 0.25 * (a2 * a2 + b2 * b2 +c2 * c2));
	}
	for (i = 0; i < n_vertices; i++)
	{
		Vector normal_sum = make_vector( 0.0f, 0.0f, 0.0f);
		for (j = 0; j < n_faces; j++)
		{
			BOOL is_shared = ((faces[j].vertex[0] == i)||(faces[j].vertex[1] == i)||(faces[j].vertex[2] == i));
			if (is_shared)
			{
				float t = triangle_area[j]; // weight sum by area
				normal_sum.x += t * faces[j].normal.x;	normal_sum.y += t * faces[j].normal.y;	normal_sum.z += t * faces[j].normal.z;
			}
		}
		if (normal_sum.x||normal_sum.y||normal_sum.z)
			normal_sum = unit_vector(&normal_sum);
		else
			normal_sum.z = 1.0;
		vertex_normal[i] = normal_sum;
	}
}

- (void) setUpVertexArrays
{
	NSMutableDictionary*	texturesProcessed = [NSMutableDictionary dictionaryWithCapacity:MAX_TEXTURES_PER_ENTITY];

	int face, fi, vi, texi;

	// base model, flat or smooth shaded, all triangles
	int tri_index = 0;
	int uv_index = 0;
	int vertex_index = 0;
	entityData.texName = 0;

	texi = 1; // index of first texture

	for (face = 0; face < n_faces; face++)
	{
//		NSString* tex_string = faces[face].textureFile;
		NSString* tex_string = [NSString stringWithUTF8String: (char*)faces[face].textureFileStr255];
		if (![texturesProcessed objectForKey:tex_string])
		{
			// do this texture
			triangle_range[texi].location = tri_index;
//			texture_file[texi] = tex_string;
			strlcpy( (char*)texture_file[texi], (char*)faces[face].textureFileStr255, 256);
			texture_name[texi] = faces[face].texName;

			for (fi = 0; fi < n_faces; fi++)
			{
				Vector normal = make_vector( 0.0, 0.0, 1.0);
				int v;
				if (!is_smooth_shaded)
					normal = faces[fi].normal;
//				if ([faces[fi].textureFile isEqual:tex_string])
//				if ([[NSString stringWithUTF8String: faces[fi].textureFileStr255] isEqual:tex_string])
				if (strcmp( (char*)faces[fi].textureFileStr255, (char*)faces[face].textureFileStr255) == 0)
				{
					for (vi = 0; vi < 3; vi++)
					{
						v = faces[fi].vertex[vi];
						if (is_smooth_shaded)
							normal = vertex_normal[v];
						entityData.index_array[tri_index++] = vertex_index;
						entityData.normal_array[vertex_index] = normal;
						entityData.vertex_array[vertex_index++] = vertices[v];
						entityData.texture_uv_array[uv_index++] = faces[fi].s[vi];
						entityData.texture_uv_array[uv_index++] = faces[fi].t[vi];
					}
				}
			}
			triangle_range[texi].length = tri_index - triangle_range[texi].location;

//			NSLog(@"DEBUG processing %@ texture %@ texName %d triangles %d to %d",
//				basefile, texture_file[texi], texture_name[texi], triangle_range[texi].location,  triangle_range[texi].location + triangle_range[texi].length);

			//finally...
			[texturesProcessed setObject:tex_string forKey:tex_string];	// note this texture done
			texi++;
		}
	}
	entityData.n_triangles = tri_index;	// total number of triangle vertices
	triangle_range[0] = NSMakeRange( 0, tri_index);

	n_textures = texi - 1;
}





- (double) findCollisionRadius
{
    int i;
	double d_squared, result, length_longest_axis, length_shortest_axis;

	result = 0.0;
	if (n_vertices)
		bounding_box_reset_to_vector(&boundingBox,vertices[0]);
	else
		bounding_box_reset(&boundingBox);

    for (i = 0; i < n_vertices; i++)
    {
        d_squared = vertices[i].x*vertices[i].x + vertices[i].y*vertices[i].y + vertices[i].z*vertices[i].z;
        if (d_squared > result)
			result = d_squared;
		bounding_box_add_vector(&boundingBox,vertices[i]);
    }

	length_longest_axis = boundingBox.max.x - boundingBox.min.x;
	if (boundingBox.max.y - boundingBox.min.y > length_longest_axis)
		length_longest_axis = boundingBox.max.y - boundingBox.min.y;
	if (boundingBox.max.z - boundingBox.min.z > length_longest_axis)
		length_longest_axis = boundingBox.max.z - boundingBox.min.z;

	length_shortest_axis = boundingBox.max.x - boundingBox.min.x;
	if (boundingBox.max.y - boundingBox.min.y < length_shortest_axis)
		length_shortest_axis = boundingBox.max.y - boundingBox.min.y;
	if (boundingBox.max.z - boundingBox.min.z < length_shortest_axis)
		length_shortest_axis = boundingBox.max.z - boundingBox.min.z;

	d_squared = (length_longest_axis + length_shortest_axis) * (length_longest_axis + length_shortest_axis) * 0.25; // square of average length
	no_draw_distance = d_squared * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR;	// no longer based on the collision radius

	mass =	(boundingBox.max.x - boundingBox.min.x) * (boundingBox.max.y - boundingBox.min.y) * (boundingBox.max.z - boundingBox.min.z);

	return sqrt(result);
}


- (BoundingBox) findBoundingBoxRelativeTo:(Entity *)other InVectors:(Vector) _i :(Vector) _j :(Vector) _k
{
	NSLog(@"DEBUG ** DEPRECATED [Entity findBoundingBoxRelativeTo:(Entity *)other InVectors:(Vector) _i :(Vector) _j :(Vector) _k] CALLED **");

	Vector pv, rv;
	Vector  rpos = position;
	Vector  opv = (other)? other->position : rpos;
	rpos.x -= opv.x;	rpos.y -= opv.y;	rpos.z -= opv.z;
	rv.x = dot_product(_i,rpos);
	rv.y = dot_product(_j,rpos);
	rv.z = dot_product(_k,rpos);
	BoundingBox result;
	bounding_box_reset_to_vector(&result,rv);
	int i;
    for (i = 0; i < n_vertices; i++)
    {
		pv.x = rpos.x + vertices[i].x;
		pv.y = rpos.y + vertices[i].y;
		pv.z = rpos.z + vertices[i].z;
		rv.x = dot_product(_i,pv);
		rv.y = dot_product(_j,pv);
		rv.z = dot_product(_k,pv);
		bounding_box_add_vector(&result,rv);
    }
	return result;
}

- (BoundingBox) findBoundingBoxRelativeToPosition:(Vector)opv InVectors:(Vector) _i :(Vector) _j :(Vector) _k
{
//	NSLog(@"DEBUG ** DEPRECATED [Entity findBoundingBoxRelativeToPosition:(Vector)opv InVectors:(Vector) _i :(Vector) _j :(Vector) _k] CALLED **");

	Vector pv, rv;
	Vector  rpos = position;
	rpos.x -= opv.x;	rpos.y -= opv.y;	rpos.z -= opv.z;
	rv.x = dot_product(_i,rpos);
	rv.y = dot_product(_j,rpos);
	rv.z = dot_product(_k,rpos);
	BoundingBox result;
	bounding_box_reset_to_vector(&result,rv);
	int i;
    for (i = 0; i < n_vertices; i++)
    {
		pv.x = rpos.x + vertices[i].x;
		pv.y = rpos.y + vertices[i].y;
		pv.z = rpos.z + vertices[i].z;
		rv.x = dot_product(_i,pv);
		rv.y = dot_product(_j,pv);
		rv.z = dot_product(_k,pv);
		bounding_box_add_vector(&result,rv);
    }

	return result;
}

- (BOOL) checkCloseCollisionWith:(Entity *)other
{
	return YES;
}



- (void) takeEnergyDamage:(double) amount from:(Entity *) ent becauseOf:(Entity *) other
{
}

- (NSString *) toString
{
    // produce a file from the original data
    int i,j, r,g,b;
    NSString *result;
    NSString *boilerplate = @"# This is a file adapted from the model files for Java Elite\n# which in turn are based on the data released by Ian Bell\n# in the file b7051600.zip at\n# http://www.users.waitrose.com/~elitearc2/elite/archive/b7051600.zip\n#";
    result = [NSString stringWithFormat:@"%@\n# %@\n#\n\nNVERTS %d\nNFACES %d\n\nVERTEX\n", boilerplate, basefile, n_vertices, n_faces];
    for (i = 0; i < n_vertices; i++)
    {
        result = [NSString stringWithFormat:@"%@%f,\t%f,\t%f\n", result, vertices[i].x, vertices[i].y, vertices[i].z];
        if ((i % 5)==4)
            result = [NSString stringWithFormat:@"%@\n", result];
    }
    result = [NSString stringWithFormat:@"%@\nFACES\n", result];
    //
    //NSLog(result);
    //
    for (j = 0; j < n_faces; j++)
    {
        r = (int)(faces[j].red * 255.0);	g = (int)(faces[j].green * 255.0);	b = (int)(faces[j].blue * 255.0);
        result = [NSString stringWithFormat:@"%@%d, %d, %d,\t", result, r, g, b];
        result = [NSString stringWithFormat:@"%@%f, %f, %f,\t", result, faces[j].normal.x, faces[j].normal.y, faces[j].normal.z];
        result = [NSString stringWithFormat:@"%@%d,\t", result, faces[j].n_verts];
        for (i = 0; i < faces[j].n_verts; i++)
        {
            result = [NSString stringWithFormat:@"%@%d ", result, faces[j].vertex[i]];
        }
        result = [NSString stringWithFormat:@"%@\n", result];
    }
    if (universe)
    {
        result = [NSString stringWithFormat:@"%@\nTEXTURES\n", result];
        for (j = 0; j < n_faces; j++)
        {
//            NSSize	texSize = [[universe textureStore] getSizeOfTexture:faces[j].textureFile];
//            result = [NSString stringWithFormat:@"%@%@\t%d %d", result, faces[j].textureFile, (int)texSize.width, (int)texSize.height];
			NSString* texture = [NSString stringWithUTF8String: (char*)faces[j].textureFileStr255];
            NSSize	texSize = [[universe textureStore] getSizeOfTexture: texture];
            result = [NSString stringWithFormat:@"%@%@\t%d %d", result, texture, (int)texSize.width, (int)texSize.height];
            for (i = 0; i < faces[j].n_verts; i++)
            {
                int s = (int)(faces[j].s[i] * texSize.width);
                int t = (int)(faces[j].t[i] * texSize.height);
                result = [NSString stringWithFormat:@"%@\t%d %d", result, s, t];
            }
            result = [NSString stringWithFormat:@"%@\n", result];
        }
    }
    result = [NSString stringWithFormat:@"%@\nEND\n", result];

    return result;
}

- (void) fakeTexturesWithImageFile: (NSString *) textureFile andMaxSize:(NSSize) maxSize
{
    int i, j, k;
    Vector vec;
    int nf = 0;
    int		fi[MAX_FACES_PER_ENTITY];
    float	max_s, min_s, max_t, min_t, st_width, st_height;
    float	tolerance;
    Face	fa[MAX_FACES_PER_ENTITY];
    int		faces_to_match;
    BOOL	face_matched[MAX_FACES_PER_ENTITY];

    tolerance = 1.00;
    faces_to_match = n_faces;
    for (i = 0; i < n_faces; i++)
    {
	    face_matched[i] = NO;
    }
	while (faces_to_match > 0)
    {
        tolerance -= 0.05;

        // Top (+y) first
        vec.x = 0.0;	vec.y = 1.0;	vec.z = 0.0;
        // build list of faces that face in that direction...
        nf = 0;
        max_s = -999999.0; min_s = 999999.0;
        max_t = -999999.0; min_t = 999999.0;
        for (i = 0; i < n_faces; i++)
        {
            float s, t;
            float g = dot_product(vec, faces[i].normal) * sqrt(2.0);
            if ((g >= tolerance)&&(!face_matched[i]))
            {
                fi[nf++] = i;
                face_matched[i] = YES;
                faces_to_match--;
                for (j = 0; j < faces[i].n_verts; j++)
                {
                    s = vertices[faces[i].vertex[j]].x;
                    t = vertices[faces[i].vertex[j]].z;
                    max_s = (max_s > s) ? max_s:s ;	min_s = (min_s < s) ? min_s:s ;
                    max_t = (max_t > t) ? max_t:t ;	min_t = (min_t < t) ? min_t:t ;
                }
            }
        }
        //
        st_width = max_s - min_s;
        st_height = max_t - min_t;
        //
        //NSLog(@"TOP st_width %f st_height %f maxSize.height %f maxSize.width %f", st_width, st_height, maxSize.width, maxSize.height);
        //
        for (j = 0; j < nf; j++)
        {
            i = fi[j];
            //fa[i] = faces[i];
//            fa[i].textureFile = [NSString stringWithFormat:@"top_%@", textureFile];
//			strlcpy( (char*)fa[i].textureFileStr255, [fa[i].textureFile UTF8String], 256);
			strlcpy( (char*)fa[i].textureFileStr255, [[NSString stringWithFormat:@"top_%@", textureFile] UTF8String], 256);
            for (k = 0; k < faces[i].n_verts; k++)
            {
                float s, t;
                s = vertices[faces[i].vertex[k]].x;
                t = vertices[faces[i].vertex[k]].z;
                fa[i].s[k] = (s - min_s) * maxSize.width / st_width;
                fa[i].t[k] = (t - min_t) * maxSize.height / st_height;
				//
				// TESTING
				//
				fa[i].t[k] = maxSize.height - fa[i].t[k];	// REVERSE t locations
                //
                //NSLog(@"%f, %f", fa[i].s[k], fa[i].t[k]);
                //
            }
        }

        // Bottom (-y)
        vec.x = 0.0;	vec.y = -1.0;	vec.z = 0.0;
        // build list of faces that face in that direction...
        nf = 0;
        max_s = -999999.0; min_s = 999999.0;
        max_t = -999999.0; min_t = 999999.0;
        for (i = 0; i < n_faces; i++)
        {
            float s, t;
            float g = dot_product(vec, faces[i].normal) * sqrt(2.0);
            if ((g >= tolerance)&&(!face_matched[i]))
            {
                fi[nf++] = i;
                face_matched[i] = YES;
                faces_to_match--;
                for (j = 0; j < faces[i].n_verts; j++)
                {
                    s = -vertices[faces[i].vertex[j]].x;
                    t = -vertices[faces[i].vertex[j]].z;
                    max_s = (max_s > s) ? max_s:s ;	min_s = (min_s < s) ? min_s:s ;
                    max_t = (max_t > t) ? max_t:t ;	min_t = (min_t < t) ? min_t:t ;
                }
            }
        }
        st_width = max_s - min_s;
        st_height = max_t - min_t;
        for (j = 0; j < nf; j++)
        {
            i = fi[j];
            //fa[i] = faces[i];
//            fa[i].textureFile = [NSString stringWithFormat:@"bottom_%@", textureFile];
//			strlcpy( (char*)fa[i].textureFileStr255, [fa[i].textureFile UTF8String], 256);
			strlcpy( (char*)fa[i].textureFileStr255, [[NSString stringWithFormat:@"bottom_%@", textureFile] UTF8String], 256);
            for (k = 0; k < faces[i].n_verts; k++)
            {
                float s, t;
                s = -vertices[faces[i].vertex[k]].x;
                t = -vertices[faces[i].vertex[k]].z;
                fa[i].s[k] = (s - min_s) * maxSize.width / st_width;
                fa[i].t[k] = (t - min_t) * maxSize.height / st_height;
            }
        }

        // Right (+x)
        vec.x = 1.0;	vec.y = 0.0;	vec.z = 0.0;
        // build list of faces that face in that direction...
        nf = 0;
        max_s = -999999.0; min_s = 999999.0;
        max_t = -999999.0; min_t = 999999.0;
        for (i = 0; i < n_faces; i++)
        {
            float s, t;
            float g = dot_product(vec, faces[i].normal) * sqrt(2.0);
            if ((g >= tolerance)&&(!face_matched[i]))
            {
                fi[nf++] = i;
                face_matched[i] = YES;
                faces_to_match--;
                for (j = 0; j < faces[i].n_verts; j++)
                {
                    s = vertices[faces[i].vertex[j]].z;
                    t = vertices[faces[i].vertex[j]].y;
                    max_s = (max_s > s) ? max_s:s ;	min_s = (min_s < s) ? min_s:s ;
                    max_t = (max_t > t) ? max_t:t ;	min_t = (min_t < t) ? min_t:t ;
                }
            }
        }
        st_width = max_s - min_s;
        st_height = max_t - min_t;
        for (j = 0; j < nf; j++)
        {
            i = fi[j];
            //fa[i] = faces[i];
//            fa[i].textureFile = [NSString stringWithFormat:@"right_%@", textureFile];
//			strlcpy( (char*)fa[i].textureFileStr255, [fa[i].textureFile UTF8String], 256);
			strlcpy( (char*)fa[i].textureFileStr255, [[NSString stringWithFormat:@"right_%@", textureFile] UTF8String], 256);
            for (k = 0; k < faces[i].n_verts; k++)
            {
                float s, t;
                s = vertices[faces[i].vertex[k]].z;
                t = vertices[faces[i].vertex[k]].y;
                fa[i].s[k] = (s - min_s) * maxSize.width / st_width;
                fa[i].t[k] = (t - min_t) * maxSize.height / st_height;
            }
        }

        // Left (-x)
        vec.x = -1.0;	vec.y = 0.0;	vec.z = 0.0;
        // build list of faces that face in that direction...
        nf = 0;
        max_s = -999999.0; min_s = 999999.0;
        max_t = -999999.0; min_t = 999999.0;
        for (i = 0; i < n_faces; i++)
        {
            float s, t;
            float g = dot_product(vec, faces[i].normal) * sqrt(2.0);
            if ((g >= tolerance)&&(!face_matched[i]))
            {
                fi[nf++] = i;
                face_matched[i] = YES;
                faces_to_match--;
                for (j = 0; j < faces[i].n_verts; j++)
                {
                    s = -vertices[faces[i].vertex[j]].z;
                    t = -vertices[faces[i].vertex[j]].y;
                    max_s = (max_s > s) ? max_s:s ;	min_s = (min_s < s) ? min_s:s ;
                    max_t = (max_t > t) ? max_t:t ;	min_t = (min_t < t) ? min_t:t ;
                }
            }
        }
        st_width = max_s - min_s;
        st_height = max_t - min_t;
        for (j = 0; j < nf; j++)
        {
            i = fi[j];
            //fa[i] = faces[i];
//            fa[i].textureFile = [NSString stringWithFormat:@"left_%@", textureFile];
//			strlcpy( (char*)fa[i].textureFileStr255, [fa[i].textureFile UTF8String], 256);
			strlcpy( (char*)fa[i].textureFileStr255, [[NSString stringWithFormat:@"left_%@", textureFile] UTF8String], 256);
            for (k = 0; k < faces[i].n_verts; k++)
            {
                float s, t;
                s = -vertices[faces[i].vertex[k]].z;
                t = -vertices[faces[i].vertex[k]].y;
                fa[i].s[k] = (s - min_s) * maxSize.width / st_width;
                fa[i].t[k] = (t - min_t) * maxSize.height / st_height;
            }
        }

        // Front (+z)
        vec.x = 0.0;	vec.y = 0.0;	vec.z = 1.0;
        // build list of faces that face in that direction...
        nf = 0;
        max_s = -999999.0; min_s = 999999.0;
        max_t = -999999.0; min_t = 999999.0;
        for (i = 0; i < n_faces; i++)
        {
            float s, t;
            float g = dot_product(vec, faces[i].normal) * sqrt(2.0);
            if ((g >= tolerance)&&(!face_matched[i]))
            {
                fi[nf++] = i;
                face_matched[i] = YES;
                faces_to_match--;
                for (j = 0; j < faces[i].n_verts; j++)
                {
                    s = vertices[faces[i].vertex[j]].x;
                    t = vertices[faces[i].vertex[j]].y;
                    max_s = (max_s > s) ? max_s:s ;	min_s = (min_s < s) ? min_s:s ;
                    max_t = (max_t > t) ? max_t:t ;	min_t = (min_t < t) ? min_t:t ;
                }
            }
        }
        st_width = max_s - min_s;
        st_height = max_t - min_t;
        for (j = 0; j < nf; j++)
        {
            i = fi[j];
            //fa[i] = faces[i];
//            fa[i].textureFile = [NSString stringWithFormat:@"front_%@", textureFile];
//			strlcpy( (char*)fa[i].textureFileStr255, [fa[i].textureFile UTF8String], 256);
			strlcpy( (char*)fa[i].textureFileStr255, [[NSString stringWithFormat:@"front_%@", textureFile] UTF8String], 256);
            for (k = 0; k < faces[i].n_verts; k++)
            {
                float s, t;
                s = vertices[faces[i].vertex[k]].x;
                t = vertices[faces[i].vertex[k]].y;
                fa[i].s[k] = (s - min_s) * maxSize.width / st_width;
                fa[i].t[k] = (t - min_t) * maxSize.height / st_height;
            }
        }

        // Back (-z)
        vec.x = 0.0;	vec.y = 0.0;	vec.z = -1.0;
        // build list of faces that face in that direction...
        nf = 0;
        max_s = -999999.0; min_s = 999999.0;
        max_t = -999999.0; min_t = 999999.0;
        for (i = 0; i < n_faces; i++)
        {
            float s, t;
            float g = dot_product(vec, faces[i].normal) * sqrt(2.0);
            if ((g >= tolerance)&&(!face_matched[i]))
            {
                fi[nf++] = i;
                face_matched[i] = YES;
                faces_to_match--;
                for (j = 0; j < faces[i].n_verts; j++)
                {
                    s = -vertices[faces[i].vertex[j]].x;
                    t = -vertices[faces[i].vertex[j]].y;
                    max_s = (max_s > s) ? max_s:s ;	min_s = (min_s < s) ? min_s:s ;
                    max_t = (max_t > t) ? max_t:t ;	min_t = (min_t < t) ? min_t:t ;
                }
            }
        }
        st_width = max_s - min_s;
        st_height = max_t - min_t;
        for (j = 0; j < nf; j++)
        {
            i = fi[j];
            //fa[i] = faces[i];
//            fa[i].textureFile = [NSString stringWithFormat:@"back_%@", textureFile];
//			strlcpy( (char*)fa[i].textureFileStr255, [fa[i].textureFile UTF8String], 256);
			strlcpy( (char*)fa[i].textureFileStr255, [[NSString stringWithFormat:@"back_%@", textureFile] UTF8String], 256);
            for (k = 0; k < faces[i].n_verts; k++)
            {
                float s, t;
                s = -vertices[faces[i].vertex[k]].x;
                t = -vertices[faces[i].vertex[k]].y;
                fa[i].s[k] = (s - min_s) * maxSize.width / st_width;
                fa[i].t[k] = (t - min_t) * maxSize.height / st_height;
            }
        }
        //NSLog(@"%d / %d faces matched at tolerance: %f", n_faces - faces_to_match, n_faces, tolerance);
    }

    for (i = 0; i < n_faces; i++)
    {
        NSString *result;
//        faces[i].textureFile = [fa[i].textureFile retain];
		strlcpy( (char*)faces[i].textureFileStr255, (char*)fa[i].textureFileStr255, 256);
		faces[i].texName = 0;
        for (j = 0; j < faces[i].n_verts; j++)
        {
            //
            //NSLog(@"face[%d] %f, %f", i, fa[i].s[j], fa[i].t[j]);
            //
            faces[i].s[j] = fa[i].s[j] / maxSize.width;
            faces[i].t[j] = fa[i].t[j] / maxSize.height;
        }
//        result = [NSString stringWithFormat:@"%@\t%d %d", faces[i].textureFile, (int)maxSize.width, (int)maxSize.height];
        result = [NSString stringWithFormat:@"%s\t%d %d", faces[i].textureFileStr255, (int)maxSize.width, (int)maxSize.height];
        //NSLog(@"face[%d] : %@", i, result);
    }

}

// COMMON OGL STUFF

- (BOOL) OGL_InitVAR
{
	short			i;
	static char*	s;

	if (global_testForVAR)
	{
		global_testForVAR = NO;	// no need for further tests after this

		// see if we have supported hardware
		s = (char *)glGetString(GL_EXTENSIONS);	// get extensions list

		if (strstr(s, "GL_APPLE_vertex_array_range") == 0)
		{
			global_usingVAR &= NO;
			NSLog(@"Vertex Array Range optimisation - not supported");
			return NO;
		}
		else
		{
			NSLog(@"Vertex Array Range optimisation - supported");
			global_usingVAR |= YES;
		}
	}

	if (!global_usingVAR)
		return NO;
#ifdef GNUSTEP
   // TODO: Find out what these APPLE functions do
#else
	glGenVertexArraysAPPLE(NUM_VERTEX_ARRAY_RANGES, &gVertexArrayRangeObjects[0]);
#endif

	// INIT OUR DATA
	//
	// None of the VAR objects has been assigned to any data yet,
	// so here we just initialize our info.  We'll assign the VAR objects
	// to data later.
	//

	for (i = 0; i < NUM_VERTEX_ARRAY_RANGES; i++)
	{
		gVertexArrayRangeData[i].rangeSize		= 0;
		gVertexArrayRangeData[i].dataBlockPtr	= nil;
		gVertexArrayRangeData[i].forceUpdate	= true;
		gVertexArrayRangeData[i].activated		= false;
	}

	return YES;
}

- (void) OGL_AssignVARMemory:(long) size :(void *) data :(Byte) whichVAR
{
	if (whichVAR >= NUM_VERTEX_ARRAY_RANGES)
	{
		NSLog(@"VAR is out of range!");
		exit(-1);
	}

	gVertexArrayRangeData[whichVAR].rangeSize 		= size;
	gVertexArrayRangeData[whichVAR].dataBlockPtr 	= data;
	gVertexArrayRangeData[whichVAR].forceUpdate 	= true;
}

- (void) OGL_UpdateVAR
{
	long	size;
	Byte	i;

	for (i = 0; i < NUM_VERTEX_ARRAY_RANGES; i++)
	{
		// SEE IF THIS VAR IS USED

		size = gVertexArrayRangeData[i].rangeSize;
		if (size == 0)
			continue;


		// SEE IF VAR NEEDS UPDATING

		if (!gVertexArrayRangeData[i].forceUpdate)
			continue;

#ifdef GNUSTEP
      // TODO: find out what non-AAPL OpenGL stuff is equivalent
#else
		// BIND THIS VAR OBJECT SO WE CAN DO STUFF TO IT

		glBindVertexArrayAPPLE(gVertexArrayRangeObjects[i]);

		// SEE IF THIS IS THE FIRST TIME IN

		if (!gVertexArrayRangeData[i].activated)
		{
			glVertexArrayRangeAPPLE(size, gVertexArrayRangeData[i].dataBlockPtr);
			glVertexArrayParameteriAPPLE(GL_VERTEX_ARRAY_STORAGE_HINT_APPLE,GL_STORAGE_SHARED_APPLE);

					// you MUST call this flush to get the data primed!

			glFlushVertexArrayRangeAPPLE(size, gVertexArrayRangeData[i].dataBlockPtr);
			glEnableClientState(GL_VERTEX_ARRAY_RANGE_APPLE);
			gVertexArrayRangeData[i].activated = true;
		}

		// ALREADY ACTIVE, SO JUST UPDATING

		else
		{
			glFlushVertexArrayRangeAPPLE(size, gVertexArrayRangeData[i].dataBlockPtr);
		}
#endif

		gVertexArrayRangeData[i].forceUpdate = false;
	}
}

// log a list of current states
//
// we need to report on the material properties
GLfloat stored_mat_ambient[4];
GLfloat stored_mat_diffuse[4];
GLfloat stored_mat_emission[4];
GLfloat stored_mat_specular[4];
GLfloat stored_mat_shininess[1];
//
GLfloat stored_current_color[4];
//
GLint stored_gl_shade_model[1];
//
GLint stored_gl_texture_env_mode[1];
//
GLint stored_gl_cull_face_mode[1];
//
GLint stored_gl_front_face[1];
//
GLint stored_gl_blend_src[1];
GLint stored_gl_blend_dst[1];
//
GLenum stored_errCode;
//
void logGLState()
{
	// we need to report on the material properties
	GLfloat mat_ambient[4];
	GLfloat mat_diffuse[4];
	GLfloat mat_emission[4];
	GLfloat mat_specular[4];
	GLfloat mat_shininess[1];
	//
	GLfloat current_color[4];
	//
	GLint gl_shade_model[1];
	//
	GLint gl_texture_env_mode[1];
	NSString* tex_env_mode_string = nil;
	//
	GLint gl_cull_face_mode[1];
	NSString* cull_face_mode_string = nil;
	//
	GLint gl_front_face[1];
	NSString* front_face_string = nil;
	//
	GLint gl_blend_src[1];
	NSString* blend_src_string = nil;
	GLint gl_blend_dst[1];
	NSString* blend_dst_string = nil;
	//
	GLenum errCode;
	const GLubyte *errString;

	glGetMaterialfv( GL_FRONT, GL_AMBIENT, mat_ambient);
	glGetMaterialfv( GL_FRONT, GL_DIFFUSE, mat_diffuse);
	glGetMaterialfv( GL_FRONT, GL_EMISSION, mat_emission);
	glGetMaterialfv( GL_FRONT, GL_SPECULAR, mat_specular);
	glGetMaterialfv( GL_FRONT, GL_SHININESS, mat_shininess);
	//
	glGetFloatv( GL_CURRENT_COLOR, current_color);
	//
	glGetIntegerv( GL_SHADE_MODEL, gl_shade_model);
	//
	glGetIntegerv( GL_BLEND_SRC, gl_blend_src);
	switch (gl_blend_src[0])
	{
		case GL_ZERO:
			blend_src_string = @"GL_ZERO";
			break;
		case GL_ONE:
			blend_src_string = @"GL_ONE";
			break;
		case GL_DST_COLOR:
			blend_src_string = @"GL_DST_COLOR";
			break;
		case GL_SRC_COLOR:
			blend_src_string = @"GL_SRC_COLOR";
			break;
		case GL_ONE_MINUS_DST_COLOR:
			blend_src_string = @"GL_ONE_MINUS_DST_COLOR";
			break;
		case GL_ONE_MINUS_SRC_COLOR:
			blend_src_string = @"GL_ONE_MINUS_SRC_COLOR";
			break;
		case GL_SRC_ALPHA:
			blend_src_string = @"GL_SRC_ALPHA";
			break;
		case GL_DST_ALPHA:
			blend_src_string = @"GL_DST_ALPHA";
			break;
		case GL_ONE_MINUS_SRC_ALPHA:
			blend_src_string = @"GL_ONE_MINUS_SRC_ALPHA";
			break;
		case GL_ONE_MINUS_DST_ALPHA:
			blend_src_string = @"GL_ONE_MINUS_DST_ALPHA";
			break;
		case GL_SRC_ALPHA_SATURATE:
			blend_src_string = @"GL_SRC_ALPHA_SATURATE";
			break;
		default:
			break;
	}
	//
	glGetIntegerv( GL_BLEND_DST, gl_blend_dst);
	switch (gl_blend_dst[0])
	{
		case GL_ZERO:
			blend_dst_string = @"GL_ZERO";
			break;
		case GL_ONE:
			blend_dst_string = @"GL_ONE";
			break;
		case GL_DST_COLOR:
			blend_dst_string = @"GL_DST_COLOR";
			break;
		case GL_SRC_COLOR:
			blend_dst_string = @"GL_SRC_COLOR";
			break;
		case GL_ONE_MINUS_DST_COLOR:
			blend_dst_string = @"GL_ONE_MINUS_DST_COLOR";
			break;
		case GL_ONE_MINUS_SRC_COLOR:
			blend_dst_string = @"GL_ONE_MINUS_SRC_COLOR";
			break;
		case GL_SRC_ALPHA:
			blend_dst_string = @"GL_SRC_ALPHA";
			break;
		case GL_DST_ALPHA:
			blend_dst_string = @"GL_DST_ALPHA";
			break;
		case GL_ONE_MINUS_SRC_ALPHA:
			blend_dst_string = @"GL_ONE_MINUS_SRC_ALPHA";
			break;
		case GL_ONE_MINUS_DST_ALPHA:
			blend_dst_string = @"GL_ONE_MINUS_DST_ALPHA";
			break;
		case GL_SRC_ALPHA_SATURATE:
			blend_dst_string = @"GL_SRC_ALPHA_SATURATE";
			break;
		default:
			break;
	}
	//
	glGetIntegerv( GL_CULL_FACE_MODE, gl_cull_face_mode);
	switch (gl_cull_face_mode[0])
	{
		case GL_BACK:
			cull_face_mode_string = @"GL_BACK";
			break;
		case GL_FRONT:
			cull_face_mode_string = @"GL_FRONT";
			break;
		default:
			break;
	}
	//
	glGetIntegerv( GL_FRONT_FACE, gl_front_face);
	switch (gl_front_face[0])
	{
		case GL_CCW:
			front_face_string = @"GL_CCW";
			break;
		case GL_CW:
			front_face_string = @"GL_CW";
			break;
		default:
			break;
	}
	//
	glGetTexEnviv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, gl_texture_env_mode);
	switch (gl_texture_env_mode[0])
	{
		case GL_DECAL:
			tex_env_mode_string = @"GL_DECAL";
			break;
		case GL_REPLACE:
			tex_env_mode_string = @"GL_REPLACE";
			break;
		case GL_MODULATE:
			tex_env_mode_string = @"GL_MODULATE";
			break;
		case GL_BLEND:
			tex_env_mode_string = @"GL_BLEND";
			break;
		default:
			break;
	}
	//
	if ((errCode =glGetError()) != GL_NO_ERROR)
	{
		errString = gluErrorString(errCode);
		NSLog(@"OPENGL_DEBUG GL_ERROR (%d) %s", errCode, errString);
	}

	/*-- MATERIALS --*/
	if ((stored_mat_ambient[0] != mat_ambient[0])||(stored_mat_ambient[1] != mat_ambient[1])||(stored_mat_ambient[2] != mat_ambient[2])||(stored_mat_ambient[3] != mat_ambient[2]))
		NSLog(@"OPENGL_DEBUG GL_AMBIENT ( %.2ff, %.2ff, %.2ff, %.2ff)",
			mat_ambient[0], mat_ambient[1], mat_ambient[2], mat_ambient[3]);
	if ((stored_mat_diffuse[0] != mat_diffuse[0])||(stored_mat_diffuse[1] != mat_diffuse[1])||(stored_mat_diffuse[2] != mat_diffuse[2])||(stored_mat_diffuse[3] != mat_diffuse[2]))
		NSLog(@"OPENGL_DEBUG GL_DIFFUSE ( %.2ff, %.2ff, %.2ff, %.2ff)",
			mat_diffuse[0], mat_diffuse[1], mat_diffuse[2], mat_diffuse[3]);
	if ((stored_mat_emission[0] != mat_emission[0])||(stored_mat_emission[1] != mat_emission[1])||(stored_mat_emission[2] != mat_emission[2])||(stored_mat_emission[3] != mat_emission[2]))
		NSLog(@"OPENGL_DEBUG GL_EMISSION ( %.2ff, %.2ff, %.2ff, %.2ff)",
			mat_emission[0], mat_emission[1], mat_emission[2], mat_emission[3]);
	if ((stored_mat_specular[0] != mat_specular[0])||(stored_mat_specular[1] != mat_specular[1])||(stored_mat_specular[2] != mat_specular[2])||(stored_mat_specular[3] != mat_specular[2]))
		NSLog(@"OPENGL_DEBUG GL_SPECULAR ( %.2ff, %.2ff, %.2ff, %.2ff)",
			mat_specular[0], mat_specular[1], mat_specular[2], mat_specular[3]);
	if (stored_mat_shininess[0] != mat_shininess[0])
		NSLog(@"OPENGL_DEBUG GL_SHININESS ( %.2ff)", mat_shininess[0]);
	stored_mat_ambient[0] = mat_ambient[0];	stored_mat_ambient[1] = mat_ambient[1];	stored_mat_ambient[2] = mat_ambient[2];	stored_mat_ambient[3] = mat_ambient[3];
	stored_mat_diffuse[0] = mat_diffuse[0];	stored_mat_diffuse[1] = mat_diffuse[1];	stored_mat_diffuse[2] = mat_diffuse[2];	stored_mat_diffuse[3] = mat_diffuse[3];
	stored_mat_emission[0] = mat_emission[0];	stored_mat_emission[1] = mat_emission[1];	stored_mat_emission[2] = mat_emission[2];	stored_mat_emission[3] = mat_emission[3];
	stored_mat_specular[0] = mat_specular[0];	stored_mat_specular[1] = mat_specular[1];	stored_mat_specular[2] = mat_specular[2];	stored_mat_specular[3] = mat_specular[3];
	stored_mat_shininess[0] = mat_shininess[0];
	/*-- MATERIALS --*/

	//
	/*-- LIGHTS --*/
	if (glIsEnabled(GL_LIGHTING))
	{
		NSLog(@"OPENGL_DEBUG GL_LIGHTING :ENABLED:");
		if (glIsEnabled(GL_LIGHT0))
			NSLog(@"OPENGL_DEBUG GL_LIGHT0 :ENABLED:");
		if (glIsEnabled(GL_LIGHT1))
		{
			NSLog(@"OPENGL_DEBUG GL_LIGHT1 :ENABLED:");
			GLfloat light_ambient[4];
			GLfloat light_diffuse[4];
			GLfloat light_specular[4];
			glGetLightfv(GL_LIGHT1, GL_AMBIENT, light_ambient);
			glGetLightfv(GL_LIGHT1, GL_DIFFUSE, light_diffuse);
			glGetLightfv(GL_LIGHT1, GL_SPECULAR, light_specular);
			NSLog(@"OPENGL_DEBUG GL_LIGHT1 GL_AMBIENT ( %.2ff, %.2ff, %.2ff, %.2ff)",
				light_ambient[0], light_ambient[1], light_ambient[2], light_ambient[3]);
			NSLog(@"OPENGL_DEBUG GL_LIGHT1 GL_DIFFUSE ( %.2ff, %.2ff, %.2ff, %.2ff)",
				light_diffuse[0], light_diffuse[1], light_diffuse[2], light_diffuse[3]);
			NSLog(@"OPENGL_DEBUG GL_LIGHT1 GL_SPECULAR ( %.2ff, %.2ff, %.2ff, %.2ff)",
				light_specular[0], light_specular[1], light_specular[2], light_specular[3]);
		}
		if (glIsEnabled(GL_LIGHT2))
			NSLog(@"OPENGL_DEBUG GL_LIGHT2 :ENABLED:");
		if (glIsEnabled(GL_LIGHT3))
			NSLog(@"OPENGL_DEBUG GL_LIGHT3 :ENABLED:");
		if (glIsEnabled(GL_LIGHT4))
			NSLog(@"OPENGL_DEBUG GL_LIGHT4 :ENABLED:");
		if (glIsEnabled(GL_LIGHT5))
			NSLog(@"OPENGL_DEBUG GL_LIGHT5 :ENABLED:");
		if (glIsEnabled(GL_LIGHT6))
			NSLog(@"OPENGL_DEBUG GL_LIGHT6 :ENABLED:");
		if (glIsEnabled(GL_LIGHT7))
			NSLog(@"OPENGL_DEBUG GL_LIGHT7 :ENABLED:");
	}
	/*-- LIGHTS --*/

	NSLog(@"OPENGL_DEBUG GL_CURRENT_COLOR ( %.2ff, %.2ff, %.2ff, %.2ff)",
		current_color[0], current_color[1], current_color[2], current_color[3]);
	//
	NSLog(@"OPENGL_DEBUG GL_TEXTURE_ENV_MODE :%@:", tex_env_mode_string);
	//
	NSLog(@"OPENGL_DEBUG GL_SHADEMODEL :%@:",  (gl_shade_model[0] == GL_SMOOTH)? @"GL_SMOOTH": @"GL_FLAT");
	//
	if (glIsEnabled(GL_FOG))
		NSLog(@"OPENGL_DEBUG GL_FOG :ENABLED:");
	//
	if (glIsEnabled(GL_COLOR_MATERIAL))
		NSLog(@"OPENGL_DEBUG GL_COLOR_MATERIAL :ENABLED:");
	//
	if (glIsEnabled(GL_BLEND))
	{
		NSLog(@"OPENGL_DEBUG GL_BLEND :ENABLED:");
		NSLog(@"OPENGL_DEBUG GL_BLEND_FUNC (:%@:, :%@:)", blend_src_string, blend_dst_string);
	}
	//
	if (glIsEnabled(GL_CULL_FACE))
		NSLog(@"OPENGL_DEBUG GL_CULL_FACE :ENABLED:");
	//
	NSLog(@"OPENGL_DEBUG GL_CULL_FACE_MODE :%@:", cull_face_mode_string);
	//
	NSLog(@"OPENGL_DEBUG GL_FRONT_FACE :%@:", front_face_string);
}

// check for OpenGL errors, reporting them if where is not nil
//
BOOL checkGLErrors(NSString* where)
{
	GLenum errCode;
	const GLubyte *errString;

	if ((errCode =glGetError()) != GL_NO_ERROR)
	{
		errString = gluErrorString(errCode);
		if (where)
			NSLog(@"OPENGL_DEBUG GL_ERROR (%d) '%s' in: %@", errCode, errString, where);
		return YES;
	}
	return NO;
}

// keep track of various OpenGL states
//
void my_glEnable(GLenum gl_state)
{
	switch (gl_state)
	{
		case GL_TEXTURE_2D:
			if (mygl_texture_2d)
				return;
			mygl_texture_2d = YES;
			break;
		default:
			break;
	}
	glEnable(gl_state);
}
//
void my_glDisable(GLenum gl_state)
{
	switch (gl_state)
	{
		case GL_TEXTURE_2D:
			if (!mygl_texture_2d)
				return;
			mygl_texture_2d = NO;
			break;
		default:
			break;
	}
	glDisable(gl_state);
}

@end
