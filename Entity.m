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
#import "Universe.h"
#import "TextureStore.h"
#import "ResourceManager.h"

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

- (id) init
{    
    self = [super init];
    //
    quaternion_set_identity(&q_rotation);
    quaternion_into_gl_matrix(q_rotation, rotMatrix);
    //
	position = make_vector( 0.0, 0.0, 0.0);
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
	collidingEntities = [[NSMutableArray alloc] initWithCapacity:16];   // alloc automatically retains
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
	//
    return self;
}

- (void) dealloc
{
    if (universe)	[universe release];
    if (basefile)	[basefile release];
	if (collidingEntities)	[collidingEntities release];
	[super dealloc];
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
    if (univ)
    {
        if (universe)	[universe release];
        universe = [univ retain];
    }
	else
	{
        if (universe)	[universe release];
        universe = nil;
    }
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
	if (universe)
	{
		if ([universe entityForUniversalID:owner_id] == ent)	// check to make sure it's kosher
			owner = owner_id;
		else
			owner = NO_TARGET;
	}
	else
	{
		owner = owner_id;	// if the universe hasn't been initialised yet, trust the sender
	}
}

- (Entity *) owner
{
	return [universe entityForUniversalID:owner];
}

- (void) setModel:(NSString *) modelName
{    
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
	if (is_smooth_shaded)
		[self calculateVertexNormals];
	// set the collision radius
	//
	collision_radius = [self findCollisionRadius];
	//NSLog(@"Entity with model '%@' collision radius set to %f",modelName, collision_radius);
	//
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
	quaternion_rotate_about_z( &q_rotation, -roll);
	quaternion_rotate_about_x( &q_rotation, -climb);
	
    quaternion_normalise(&q_rotation);
    quaternion_into_gl_matrix(q_rotation, rotMatrix);
}

- (void) applyRoll:(GLfloat) roll climb:(GLfloat) climb andYaw:(GLfloat) yaw
{
	quaternion_rotate_about_z( &q_rotation, -roll);
	quaternion_rotate_about_x( &q_rotation, -climb);
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

- (Vector) getPosition
{
    return position;
}

- (Vector) getViewpointPosition
{
    return position;
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
    // roll out each face and vertex in turn
    //
//    int fi,vi;
    int ti;
    GLfloat mat_ambient[] = { 1.0, 1.0, 1.0, 1.0 };
    GLfloat mat_no[] =		{ 0.0, 0.0, 0.0, 1.0 };
	if (is_smooth_shaded)
		glShadeModel(GL_SMOOTH);
	else
		glShadeModel(GL_FLAT);	
	
    //
    if (!translucent)
	{
		if (basefile)
		{
			// calls moved here because they are unsupported in display lists
			//
			glDisableClientState(GL_COLOR_ARRAY);
			glDisableClientState(GL_INDEX_ARRAY);
			glDisableClientState(GL_EDGE_FLAG_ARRAY);
			glDisableClientState(GL_TEXTURE_COORD_ARRAY);
			//
			glEnableClientState(GL_NORMAL_ARRAY);
			glEnableClientState(GL_VERTEX_ARRAY);
			glEnableClientState(GL_TEXTURE_COORD_ARRAY);
			//
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
				//
				for (ti = 1; ti <= n_textures; ti++)
				{
					glBindTexture(GL_TEXTURE_2D, texture_name[ti]);
					glDrawArrays( GL_TRIANGLES, triangle_range[ti].location, triangle_range[ti].length);
				}
				//					
				glDisable(GL_TEXTURE_2D);
				
			}
			else
			{
				if (displayListName != 0)
					glCallList(displayListName);
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
			NSBeep();
		}
	}
	glShadeModel(GL_SMOOTH);
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
	if (status != STATUS_ACTIVE)
	{
		if ((![universe reducedDetail])||(status == STATUS_EFFECT))	// don't draw passive subentities except exhausts in reduced detail mode.
		{
			glPushMatrix();

			// position and orientation is relative to owner
			
			//NSLog(@"DEBUG drawing passive subentity at %.3f, %.3f, %.3f", position.x, position.y, position.z);
			
			glTranslated( position.x, position.y, position.z);
			glMultMatrixf(rotMatrix);
			
			[self drawEntity:immediate :translucent];
				
			glPopMatrix();

//			NSLog(@"drawn static entity : %@", basefile);


		}
	}
	else
	{
		Vector abspos = position;  // STATUS_ACTIVE means it is in control of it's own orientation
		Entity*		father = my_owner;
		GLfloat*	r_mat = [father rotationMatrix];
		while (father)
		{
			mult_vector_gl_matrix(&abspos, r_mat);
			Vector pos = father->position;
			abspos.x += pos.x;	abspos.y += pos.y;	abspos.z += pos.z;
			father = [father owner];
			r_mat = [father rotationMatrix];
		}
		glPopMatrix();  // one down
		glPushMatrix();
				// position and orientation is absolute
		glTranslated( abspos.x, abspos.y, abspos.z);
		
		glMultMatrixf(rotMatrix);
		
		[self drawEntity:immediate :translucent];
		
//		NSLog(@"drawn active entity : %@", basefile);

	}
}

- (void) initialiseTextures
{
    // roll out each face and tetxure in turn
    //
    int fi,ti ;
    //
    for (fi = 0; fi < n_faces; fi++)
    {        
        // texture
        if ((faces[fi].texName == 0)&&(faces[fi].textureFile))
        {
            // load texture into Universe texturestore
//            NSLog(@"Off to load %@",faces[fi].textureFile);
            if (universe)
            {
                faces[fi].texName = [[universe textureStore] getTextureNameFor:faces[fi].textureFile];
            }
        }
    }
	
	for (ti = 1; ti <= n_textures; ti++)
	{
		if (!texture_name[ti])
		{
			texture_name[ti] = [[universe textureStore] getTextureNameFor:texture_file[ti]];
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
		track_index = (track_index + 1 ) & 0xff;
//		if (isPlayer)
//			NSLog(@"Saving frame %d %.2f", track_index, track_time);
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
		double f1 = 1 - f0;
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
	return result;
}

- (void) loadData:(NSString *) filename
{
    NSScanner		*scanner;
    NSString		*data = nil;
    NSMutableArray	*lines;
    BOOL			failFlag = NO;
    NSString		*failString = @"***** ";
    int	i, j;
    
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
	
	// failsafe in case the stored data fails
	if (data == nil)
	{
		data = [ResourceManager stringFromFilesNamed:filename inFolder:@"Models"];
		using_preloaded = NO;
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
    //[scanner scanCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:nil];
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
    
	NSMutableDictionary* facesForTexture = [NSMutableDictionary dictionaryWithCapacity:MAX_TEXTURES_PER_ENTITY];
	
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
                    faces[j].textureFile = [texfile retain];
					
					// create/extend a list of faces for this texture
					NSMutableArray* facesForThisTexture;
					if ([facesForTexture objectForKey:texfile])
						facesForThisTexture = (NSMutableArray*)[facesForTexture objectForKey:texfile];
					else
						facesForThisTexture = [NSMutableArray arrayWithCapacity:32];
					[facesForThisTexture addObject:[NSNumber numberWithInt:j]];
					[facesForTexture setObject:facesForThisTexture forKey:texfile];
					
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
                            
                            //NSLog(@" st %f %f", faces[j].s[i], faces[j].t[i]);
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
	
//	NSLog(@"Loading data for %@: facesForTexture:\n%@", filename, [facesForTexture description]);
	
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
	
	// set the collision radius
	//
	collision_radius = [self findCollisionRadius];
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
	int i,j,k;
	for (i = 0; i < n_vertices; i++)
	{
		int shared_faces = 0;
		Vector normal_sum;
		normal_sum.x = 0.0;	normal_sum.y = 0.0;	normal_sum.z = 0.0;
		for (j = 0; j < n_faces; j++)
		{
			BOOL is_shared = NO;
			for (k = 0; (k < faces[j].n_verts)&&(!is_shared); k++)
				is_shared = (faces[j].vertex[k] == i);
			if (is_shared)
			{
				normal_sum.x += faces[j].normal.x;	normal_sum.y += faces[j].normal.y;	normal_sum.z += faces[j].normal.z;
				shared_faces++;
			}
		}
		normal_sum = unit_vector(&normal_sum);
		vertex_normal[i].x = normal_sum.x;
		vertex_normal[i].y = normal_sum.y;
		vertex_normal[i].z = normal_sum.z;
	}
}

- (void) setUpVertexArrays
{
	NSMutableDictionary*	texturesProcessed = [NSMutableDictionary dictionaryWithCapacity:MAX_TEXTURES_PER_ENTITY];

	int face, fi, vi, texi;
	
	// base model, flat shaded, all triangles
	int tri_index = 0;
	int uv_index = 0; // not used
	int vertex_index = 0;
	int normal_index = 0;
	entityData.textureFile = nil;
	entityData.texName = 0;
	
	texi = 1; // index of first texture
	
	for (face = 0; face < n_faces; face++)
	{
		NSString* tex_string = faces[face].textureFile;
		if (![texturesProcessed objectForKey:tex_string])
		{
			// do this texture
			triangle_range[texi].location = tri_index;
			texture_file[texi] = tex_string;
			texture_name[texi] = faces[face].texName;
			
			for (fi = 0; fi < n_faces; fi++)
			{
				Vector normal;
				int v;
				if (!is_smooth_shaded)
					normal = faces[fi].normal;
				if ([faces[fi].textureFile isEqual:tex_string])
				{
					for (vi = 0; vi < 3; vi++)
					{
						v = faces[fi].vertex[vi];
						if (is_smooth_shaded)
							normal = vertex_normal[v];
						entityData.index_array[tri_index++] = vertex_index;
						entityData.vertex_array[vertex_index++] = vertices[v];
						entityData.normal_array[normal_index++] = normal;
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
	bounding_box_reset(&boundingBox);
	
    for (i = 0; i < n_vertices; i++)
    {
        d_squared = vertices[i].x*vertices[i].x + vertices[i].y*vertices[i].y + vertices[i].z*vertices[i].z;
        if (d_squared > result)
			result = d_squared;
		bounding_box_add_vector(&boundingBox,vertices[i]);
    }
	
	length_longest_axis = boundingBox.max_x - boundingBox.min_x;
	if (boundingBox.max_y - boundingBox.min_y > length_longest_axis)
		length_longest_axis = boundingBox.max_y - boundingBox.min_y;
	if (boundingBox.max_z - boundingBox.min_z > length_longest_axis)
		length_longest_axis = boundingBox.max_z - boundingBox.min_z;
	
	length_shortest_axis = boundingBox.max_x - boundingBox.min_x;
	if (boundingBox.max_y - boundingBox.min_y < length_shortest_axis)
		length_shortest_axis = boundingBox.max_y - boundingBox.min_y;
	if (boundingBox.max_z - boundingBox.min_z < length_shortest_axis)
		length_shortest_axis = boundingBox.max_z - boundingBox.min_z;
	
	d_squared = (length_longest_axis + length_shortest_axis) * (length_longest_axis + length_shortest_axis) * 0.25; // square of average length
	no_draw_distance = d_squared * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR;	// no longer based on the collision radius
	
	mass =	(boundingBox.max_x - boundingBox.min_x) * (boundingBox.max_y - boundingBox.min_y) * (boundingBox.max_z - boundingBox.min_z);
	
//	NSLog(@"%@ has mass %.3f", basefile, mass);
	
	return sqrt(result);
}


- (BoundingBox) findBoundingBoxRelativeTo:(Entity *)other InVectors:(Vector) _i :(Vector) _j :(Vector) _k
{
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
            NSSize	texSize = [[universe textureStore] getSizeOfTexture:faces[j].textureFile];
            result = [NSString stringWithFormat:@"%@%@\t%d %d", result, faces[j].textureFile, (int)texSize.width, (int)texSize.height];
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
            fa[i].textureFile = [NSString stringWithFormat:@"top_%@", textureFile];
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
            fa[i].textureFile = [NSString stringWithFormat:@"bottom_%@", textureFile];
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
            fa[i].textureFile = [NSString stringWithFormat:@"right_%@", textureFile];
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
            fa[i].textureFile = [NSString stringWithFormat:@"left_%@", textureFile];
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
            fa[i].textureFile = [NSString stringWithFormat:@"front_%@", textureFile];
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
            fa[i].textureFile = [NSString stringWithFormat:@"back_%@", textureFile];
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
        faces[i].textureFile = [fa[i].textureFile retain];
		faces[i].texName = 0;
        for (j = 0; j < faces[i].n_verts; j++)
        {
            //
            //NSLog(@"face[%d] %f, %f", i, fa[i].s[j], fa[i].t[j]);
            //
            faces[i].s[j] = fa[i].s[j] / maxSize.width;
            faces[i].t[j] = fa[i].t[j] / maxSize.height;
        }
        result = [NSString stringWithFormat:@"%@\t%d %d", faces[i].textureFile, (int)maxSize.width, (int)maxSize.height];
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
				
		if (strstr(s, "GL_APPLE_vertex_array_range") == NULL)
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

@end
