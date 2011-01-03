/*

OOSelfDrawingEntity.m

Oolite
Copyright (C) 2004-2011 Giles C Williams and contributors

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
#import "Universe.h"
#import "Geometry.h"
#import "ResourceManager.h"
#import "OOOpenGLExtensionManager.h"
#import "OOGraphicsResetManager.h"

#if !OOLITE_MAC_OS_X
#define NEED_STRLCPY
#endif

#import "bsd_string.h"


static NSString * const kOOLogEntityDataNotFound			= @"entity.loadMesh.failed.fileNotFound";
static NSString * const kOOLogEntityTooManyVertices			= @"entity.loadMesh.failed.tooManyVertices";
static NSString * const kOOLogEntityTooManyFaces			= @"entity.loadMesh.failed.tooManyFaces";


@interface OOSelfDrawingEntity (Private) <OOGraphicsResetClient>

- (void)loadData:(NSString *)filename;
- (void)checkNormalsAndAdjustWinding;
- (void)calculateVertexNormals;

- (NSDictionary *)modelData;
- (BOOL)setModelFromModelData:(NSDictionary*) dict;

- (Vector)normalForVertex:(int)v_index withSharedRedValue:(GLfloat)red_value;

- (void)fakeTexturesWithImageFile: (NSString *) textureFile andMaxSize:(NSSize) maxSize;

- (void)setUpVertexArrays;

@end


@interface OOCacheManager (OSSelfDrawingEntity)

+ (NSDictionary *)entityDataForName:(NSString *)inShipName;
+ (void)setEntityData:(NSDictionary *)inData forName:(NSString *)inShipName;

@end


@implementation OOSelfDrawingEntity

- (id)init
{
	self = [super init];
	if (self == nil)  return nil;
	
	basefile = @"No Model";
	[[OOGraphicsResetManager sharedManager] registerClient:self];
	
	return self;
}


- (void) dealloc
{
	[basefile release];
	[[OOGraphicsResetManager sharedManager] unregisterClient:self];
	if (displayListName != 0)  OOGL(glDeleteLists(displayListName, 1));
	
	[super dealloc];
}


- (void) setModelName:(NSString *)modelName
{
	NSAutoreleasePool* mypool = [[NSAutoreleasePool alloc] init];
	
	[basefile autorelease];
	basefile = [modelName retain];
	
	OOGL(glDeleteLists(displayListName,1));
	displayListName = 0;
	
	NS_DURING
		[self loadData:basefile];
	NS_HANDLER
		if ([[localException name] isEqual: OOLITE_EXCEPTION_DATA_NOT_FOUND])
		{
			OOLog(kOOLogFileNotFound, @"***** Oolite Data Not Found Exception : '%@' in %s *****", [localException reason], __PRETTY_FUNCTION__);
		}
		[localException retain];
		[mypool release];
		[localException autorelease];
		[localException raise];
	NS_ENDHANDLER

	[self checkNormalsAndAdjustWinding];
	
	// set the collision radius
	collision_radius = [self findCollisionRadius];
	
	[mypool release];
}


- (NSString *) modelName
{
	return basefile;
}


- (BOOL) isSmoothShaded
{
	return isSmoothShaded;
}


- (void) setSmoothShaded:(BOOL) value
{
	isSmoothShaded = value;
}


- (Geometry*) geometry
{
	Geometry* result = [(Geometry *)[Geometry alloc] initWithCapacity: faceCount];
	OOMeshFaceCount i;
	for (i = 0; i < faceCount; i++)
	{
		Triangle tri;
		tri.v[0] = vertices[faces[i].vertex[0]];
		tri.v[1] = vertices[faces[i].vertex[1]];
		tri.v[2] = vertices[faces[i].vertex[2]];
		[result addTriangle: tri];
	}
	return [result autorelease];
}


- (void) drawSubEntity:(BOOL) immediate :(BOOL) translucent
{
	Entity* my_owner = [self owner];
	if (my_owner)
	{
		// this test provides an opportunity to do simple LoD culling
		//
		zero_distance = [my_owner zeroDistance];
		if (zero_distance > no_draw_distance)
		{
			return; // TOO FAR AWAY
		}
	}
	if ([self status] == STATUS_ACTIVE)
	{
		Vector		abspos = position;  // STATUS_ACTIVE means it is in control of it's own orientation
		Entity		*last = nil;
		Entity		*father = my_owner;
		OOMatrix	r_mat;
		
		while ((father)&&(father != last))
		{
			r_mat = [father drawRotationMatrix];
			abspos = vector_add(OOVectorMultiplyMatrix(abspos, r_mat), [father position]);
			
			last = father;
			father = [father owner];
		}
		OOGL(glPopMatrix());  // one down
		OOGL(glPushMatrix());
				// position and orientation is absolute
		GLTranslateOOVector(abspos);
		GLMultOOMatrix(rotMatrix);
		
		[self drawEntity:immediate :translucent];
	}
	else
	{
		OOGL(glPushMatrix());
		
		GLTranslateOOVector(position);
		GLMultOOMatrix(rotMatrix);
		
		[self drawEntity:immediate :translucent];
		
		OOGL(glPopMatrix());
	}
}


- (void) generateDisplayList
{
	OOGL(displayListName = glGenLists(1));
	if (displayListName != 0)
	{
		OOGL(glNewList(displayListName, GL_COMPILE));
		[self drawEntity:YES:NO];	//	immediate YES	translucent NO
		OOGL(glEndList());
	}
}

@end


@implementation OOSelfDrawingEntity (Private)

- (NSDictionary*)modelData
{
	NSMutableDictionary*	mdict = [NSMutableDictionary dictionaryWithCapacity:8];
	[mdict setObject:[NSNumber numberWithInt: vertexCount]	forKey:@"vertexCount"];
	[mdict setObject:[NSData dataWithBytes: vertices		length: sizeof(Vector)*vertexCount]	forKey:@"vertices"];
	[mdict setObject:[NSData dataWithBytes: vertex_normal	length: sizeof(Vector)*vertexCount]	forKey:@"normals"];
	[mdict setObject:[NSNumber numberWithInt: faceCount] forKey:@"faceCount"];
	[mdict setObject:[NSData dataWithBytes: faces			length: sizeof(Face)*faceCount]		forKey:@"faces"];
	return [NSDictionary dictionaryWithDictionary:mdict];
}


- (BOOL)setModelFromModelData:(NSDictionary*) dict
{
	vertexCount = [[dict objectForKey:@"vertexCount"] intValue];
	faceCount = [[dict objectForKey:@"faceCount"] intValue];
	NSData* vdata = (NSData*)[dict objectForKey:@"vertices"];
	NSData* ndata = (NSData*)[dict objectForKey:@"normals"];
	NSData* fdata = (NSData*)[dict objectForKey:@"faces"];
	if ((vdata) && (ndata) && (fdata))
	{
		Vector* vbytes = (Vector*)[vdata bytes];
		Vector* nbytes = (Vector*)[ndata bytes];
		Face* fbytes = (Face*)[fdata bytes];
		OOUInteger i;
		for (i = 0; i < vertexCount; i++)
		{
			vertices[i] = vbytes[i];
			vertex_normal[i] = nbytes[i];
		}
		for (i = 0; i < faceCount; i++)
		{
			faces[i] = fbytes[i];
		}
		return YES;
	}
	else
	{
		return NO;
	}
}


- (void)resetGraphicsState
{
	if (displayListName != 0)
	{
		OOGL(glDeleteLists(displayListName, 1));
		displayListName = 0;
	}
}


- (void)loadData:(NSString *) filename
{
	NSScanner			*scanner;
	NSDictionary		*cacheData = nil;
	NSString			*data = nil;
	NSMutableArray		*lines;
	BOOL				failFlag = NO;
	NSString			*failString = @"***** ";
	unsigned			i, j;

	BOOL using_preloaded = NO;
	
	// TODO: rejigger this to look for the file and check modification date.
	cacheData = [OOCacheManager entityDataForName:filename];
	if (cacheData != nil)
	{
		if ([self setModelFromModelData:cacheData]) using_preloaded = YES;
	}
	
	if (!using_preloaded)
	{
		data = [ResourceManager stringFromFilesNamed:filename inFolder:@"Models"];
		if (data == nil)
		{
			// Model not found
			OOLog(kOOLogEntityDataNotFound, @"***** ERROR: could not find '%@'.", filename);
			[NSException raise:OOLITE_EXCEPTION_DATA_NOT_FOUND format:@"No data for model called '%@' could be found in %@.", filename, [ResourceManager paths]];
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

		scanner = [NSScanner scannerWithString:data];

		// get number of vertices
		//
		[scanner setScanLocation:0];	//reset
		if ([scanner scanString:@"NVERTS" intoString:NULL])
		{
			int n_v;
			if ([scanner scanInt:&n_v])
				vertexCount = n_v;
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

		if (vertexCount > MAX_VERTICES_PER_ENTITY)
		{
			//2 error lines for just one error?
			OOLog(kOOLogEntityTooManyVertices, @"***** ERROR: model %@ has too many vertices (model has %d, maximum is %d).", filename, vertexCount, MAX_VERTICES_PER_ENTITY);
			failFlag = YES;
			// ERROR model file not found
			[NSException raise:@"OoliteException"
						format:@"***** ERROR: model %@ has too many vertices (model has %d, maximum is %d).", filename, vertexCount, MAX_VERTICES_PER_ENTITY];
		}

		// get number of faces
		//
		//[scanner setScanLocation:0];	//reset
		if ([scanner scanString:@"NFACES" intoString:NULL])
		{
			int n_f;
			if ([scanner scanInt:&n_f])
				faceCount = n_f;
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

		if (faceCount > MAX_FACES_PER_ENTITY)
		{
			//2 error lines for just one error?
			OOLog(kOOLogEntityTooManyFaces, @"***** ERROR: model %@ has too many faces (model has %d, maximum is %d).", filename, faceCount, MAX_FACES_PER_ENTITY);
			failFlag = YES;
			// ERROR model file not found
			[NSException raise:@"OoliteException"
						format:@"***** ERROR: model %@ has too many faces (model has %d, maximum is %d).", filename, faceCount, MAX_FACES_PER_ENTITY];
		}

		// get vertex data
		//
		//[scanner setScanLocation:0];	//reset
		if ([scanner scanString:@"VERTEX" intoString:NULL])
		{
			for (j = 0; j < vertexCount; j++)
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
		if ([scanner scanString:@"FACES" intoString:NULL])
		{
			for (j = 0; j < faceCount; j++)
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
						faces[j].red = r / 255.0;
						faces[j].green = g / 255.0;
						faces[j].blue = b / 255.0;
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
						faces[j].normal.x = nx;
						faces[j].normal.y = ny;
						faces[j].normal.z = nz;
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
						for (i = 0; i < faces[j].n_verts; i++)
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
		if ([scanner scanString:@"TEXTURES" intoString:NULL])
		{
			for (j = 0; j < faceCount; j++)
			{
				NSString	*texfile;
				float	max_x, max_y;
				float	s, t;
				if (!failFlag)
				{
					// texfile
					//
					[scanner scanCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:NULL];
					if (![scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&texfile])
					{
						failFlag = YES;
						failString = [NSString stringWithFormat:@"%@Failed to read texture filename for face[%d] in TEXTURES\n", failString, j];
					}
					else
					{
						strlcpy(faces[j].textureFileName, [texfile UTF8String], 256);
					}
					faces[j].textureName = 0;

					// texture size
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
								faces[j].s[i] = s / max_x;
								faces[j].t[i] = t / max_y;
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
		[self checkNormalsAndAdjustWinding];

		if ((failFlag)&&([failString rangeOfString:@"TEXTURES"].location != NSNotFound))
		{
			[self fakeTexturesWithImageFile:@"metal.png" andMaxSize:NSMakeSize(256.0,256.0)];
		}

		if (failFlag)
			OOLog(@"selfDrawingEntity.load.failed", @"%@ ..... from %@ %@", failString, filename, (using_preloaded)? @"(from preloaded data)" : @"(from file)");

		// check for smooth shading and recalculate normals
		if (isSmoothShaded)  [self calculateVertexNormals];

		// save the resulting data for possible reuse
		[OOCacheManager setEntityData:[self modelData] forName:filename];
	}
	
	// set the collision radius
	collision_radius = [self findCollisionRadius];

	// set up vertex arrays for drawing
	[self setUpVertexArrays];
}


// FIXME: this isn't working, we're getting smoothed models with inside-out winding. --Ahruman
- (void) checkNormalsAndAdjustWinding
{
	Vector		calculatedNormal;
	unsigned	i, j;
	
	for (i = 0; i < faceCount; i++)
	{
		Vector v0, v1, v2, norm;
		v0 = vertices[faces[i].vertex[0]];
		v1 = vertices[faces[i].vertex[1]];
		v2 = vertices[faces[i].vertex[2]];
		norm = faces[i].normal;
		calculatedNormal = normal_to_surface (v2, v1, v0);
		if (vector_equal(norm, kZeroVector))
		{
			faces[i].normal = normal_to_surface (v0, v1, v2);
			norm = normal_to_surface (v0, v1, v2);
		}
		if (norm.x*calculatedNormal.x < 0 || norm.y*calculatedNormal.y < 0 || norm.z*calculatedNormal.z < 0)
		{
			// normal lies in the WRONG direction!
			// reverse the winding
			int			v[faces[i].n_verts];
			GLfloat		s[faces[i].n_verts];
			GLfloat		t[faces[i].n_verts];

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
	unsigned i,j;
	float	triangle_area[faceCount];
	for (i = 0 ; i < faceCount; i++)
	{
		// calculate areas using Herons formula
		// in the form Area = sqrt(2*(a2*b2+b2*c2+c2*a2)-(a4+b4+c4))/4
		float	a2 = distance2( vertices[faces[i].vertex[0]], vertices[faces[i].vertex[1]]);
		float	b2 = distance2( vertices[faces[i].vertex[1]], vertices[faces[i].vertex[2]]);
		float	c2 = distance2( vertices[faces[i].vertex[2]], vertices[faces[i].vertex[0]]);
		triangle_area[i] = sqrt( 2.0 * (a2 * b2 + b2 * c2 + c2 * a2) - 0.25 * (a2 * a2 + b2 * b2 +c2 * c2));
	}
	for (i = 0; i < vertexCount; i++)
	{
		Vector normal_sum = kZeroVector;
		for (j = 0; j < faceCount; j++)
		{
			BOOL is_shared = (((unsigned)faces[j].vertex[0] == i)||((unsigned)faces[j].vertex[1] == i)||((unsigned)faces[j].vertex[2] == i));
			if (is_shared)
			{
				float t = triangle_area[j]; // weight sum by area
				normal_sum.x += t * faces[j].normal.x;	normal_sum.y += t * faces[j].normal.y;	normal_sum.z += t * faces[j].normal.z;
			}
		}
		if (normal_sum.x||normal_sum.y||normal_sum.z)
			normal_sum = vector_normal(normal_sum);
		else
			normal_sum.z = 1.0;
		vertex_normal[i] = normal_sum;
	}
}


- (Vector) normalForVertex:(int) v_index withSharedRedValue:(GLfloat) red_value
{
	OOMeshFaceCount j;
	Vector normal_sum = kZeroVector;
	for (j = 0; j < faceCount; j++)
	{
		if (faces[j].red == red_value)
		{
			if ((faces[j].vertex[0] == v_index)||(faces[j].vertex[1] == v_index)||(faces[j].vertex[2] == v_index))
			{
				float	a2 = distance2( vertices[faces[j].vertex[0]], vertices[faces[j].vertex[1]]);
				float	b2 = distance2( vertices[faces[j].vertex[1]], vertices[faces[j].vertex[2]]);
				float	c2 = distance2( vertices[faces[j].vertex[2]], vertices[faces[j].vertex[0]]);
				float	t = sqrt( 2.0 * (a2 * b2 + b2 * c2 + c2 * a2) - 0.25 * (a2 * a2 + b2 * b2 +c2 * c2));
				normal_sum.x += t * faces[j].normal.x;	normal_sum.y += t * faces[j].normal.y;	normal_sum.z += t * faces[j].normal.z;
			}
		}
	}
	if (normal_sum.x||normal_sum.y||normal_sum.z)
		normal_sum = vector_normal(normal_sum);
	else
		normal_sum.z = 1.0;
	return normal_sum;
}


- (void) setUpVertexArrays
{
	NSMutableDictionary*	texturesProcessed = [NSMutableDictionary dictionaryWithCapacity:MAX_TEXTURES_PER_ENTITY];

	unsigned face, fi, vi, texi;

	// if isSmoothShaded find any vertices that are between faces of two different colour (by red value)
	// and mark them as being on an edge and therefore NOT smooth shaded
	BOOL is_edge_vertex[vertexCount];
	GLfloat red_value[vertexCount];
	for (vi = 0; vi < vertexCount; vi++)
	{
		is_edge_vertex[vi] = NO;
		red_value[vi] = -1;
	}
	if (isSmoothShaded)
	{
		for (fi = 0; fi < faceCount; fi++)
		{
			GLfloat rv = faces[fi].red;
			int i;
			for (i = 0; i < 3; i++)
			{
				vi = faces[fi].vertex[i];
				if (red_value[vi] < 0.0)	// unassigned
					red_value[vi] = rv;
				else if (red_value[vi] != rv)	// a different colour
					is_edge_vertex[vi] = YES;
			}
		}
	}


	// base model, flat or smooth shaded, all triangles
	int tri_index = 0;
	int uv_index = 0;
	int vertex_index = 0;

	texi = 1; // index of first texture

	for (face = 0; face < faceCount; face++)
	{
		NSString* tex_string = [NSString stringWithUTF8String:faces[face].textureFileName];
		if (![texturesProcessed objectForKey:tex_string])
		{
			// do this texture
			triangle_range[texi].location = tri_index;
			strlcpy(textureFileName[texi], faces[face].textureFileName, 256);
			textureNames[texi] = faces[face].textureName;

			for (fi = 0; fi < faceCount; fi++)
			{
				int v;
				
				Vector normal;
				
				if (strcmp(faces[fi].textureFileName, faces[face].textureFileName) == 0)
				{
					for (vi = 0; vi < 3; vi++)
					{
						v = faces[fi].vertex[vi];
						if (isSmoothShaded)
						{
							if (is_edge_vertex[v])
								normal = [self normalForVertex: v withSharedRedValue: faces[fi].red];
							else
								normal = vertex_normal[v];
						}
						else
							normal = faces[fi].normal;
						entityData.index_array[tri_index++] = vertex_index;
						entityData.normal_array[vertex_index] = normal;
						entityData.vertex_array[vertex_index++] = vertices[v];
						entityData.texture_uv_array[uv_index++] = faces[fi].s[vi];
						entityData.texture_uv_array[uv_index++] = faces[fi].t[vi];
					}
				}
			}
			triangle_range[texi].length = tri_index - triangle_range[texi].location;

			//finally...
			[texturesProcessed setObject:tex_string forKey:tex_string];	// note this texture done
			texi++;
		}
	}
	entityData.n_triangles = tri_index;	// total number of triangle vertices
	triangle_range[0] = NSMakeRange( 0, tri_index);

	textureCount = texi - 1;
}


- (double) findCollisionRadius
{
	OOMeshVertexCount i;
	double d_squared, result, length_longest_axis, length_shortest_axis;

	result = 0.0;
	if (vertexCount)
		bounding_box_reset_to_vector(&boundingBox,vertices[0]);
	else
		bounding_box_reset(&boundingBox);

	for (i = 0; i < vertexCount; i++)
	{
		d_squared = magnitude2(vertices[i]);
		if (d_squared > result)
		{
			result = d_squared;
		}
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


- (void) fakeTexturesWithImageFile: (NSString *) textureFile andMaxSize:(NSSize) maxSize
{
	unsigned	i, j, k;
	Vector		vec;
	unsigned	nf = 0;
	unsigned	fi[MAX_FACES_PER_ENTITY];
	float		max_s, min_s, max_t, min_t, st_width, st_height;
	float		tolerance;
	Face		fa[MAX_FACES_PER_ENTITY];
	unsigned	faces_to_match;
	BOOL		face_matched[MAX_FACES_PER_ENTITY];

	tolerance = 1.00;
	faces_to_match = faceCount;
	for (i = 0; i < faceCount; i++)
	{
		face_matched[i] = NO;
	}
	while (faces_to_match > 0)
	{
		tolerance -= 0.05;

		// Top (+y) first
		vec = kBasisYVector;
		// build list of faces that face in that direction...
		nf = 0;
		max_s = -999999.0; min_s = 999999.0;
		max_t = -999999.0; min_t = 999999.0;
		for (i = 0; i < faceCount; i++)
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
		
		st_width = max_s - min_s;
		st_height = max_t - min_t;
		
		for (j = 0; j < nf; j++)
		{
			i = fi[j];
			
			strlcpy(fa[i].textureFileName, [[NSString stringWithFormat:@"top_%@", textureFile] UTF8String], 256);
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
			}
		}

		// Bottom (-y)
		vec = vector_flip(kBasisYVector);
		// build list of faces that face in that direction...
		nf = 0;
		max_s = -999999.0; min_s = 999999.0;
		max_t = -999999.0; min_t = 999999.0;
		for (i = 0; i < faceCount; i++)
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
			strlcpy(fa[i].textureFileName, [[NSString stringWithFormat:@"bottom_%@", textureFile] UTF8String], 256);
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
		vec = kBasisXVector;
		// build list of faces that face in that direction...
		nf = 0;
		max_s = -999999.0; min_s = 999999.0;
		max_t = -999999.0; min_t = 999999.0;
		for (i = 0; i < faceCount; i++)
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
			strlcpy(fa[i].textureFileName, [[NSString stringWithFormat:@"right_%@", textureFile] UTF8String], 256);
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
		vec = vector_flip(kBasisXVector);
		// build list of faces that face in that direction...
		nf = 0;
		max_s = -999999.0; min_s = 999999.0;
		max_t = -999999.0; min_t = 999999.0;
		for (i = 0; i < faceCount; i++)
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
			strlcpy(fa[i].textureFileName, [[NSString stringWithFormat:@"left_%@", textureFile] UTF8String], 256);
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
		vec = kBasisZVector;
		// build list of faces that face in that direction...
		nf = 0;
		max_s = -999999.0; min_s = 999999.0;
		max_t = -999999.0; min_t = 999999.0;
		for (i = 0; i < faceCount; i++)
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
			strlcpy(fa[i].textureFileName, [[NSString stringWithFormat:@"front_%@", textureFile] UTF8String], 256);
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
		vec = vector_flip(kBasisZVector);
		// build list of faces that face in that direction...
		nf = 0;
		max_s = -999999.0; min_s = 999999.0;
		max_t = -999999.0; min_t = 999999.0;
		for (i = 0; i < faceCount; i++)
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
			strlcpy(fa[i].textureFileName, [[NSString stringWithFormat:@"back_%@", textureFile] UTF8String], 256);
			for (k = 0; k < faces[i].n_verts; k++)
			{
				float s, t;
				s = -vertices[faces[i].vertex[k]].x;
				t = -vertices[faces[i].vertex[k]].y;
				fa[i].s[k] = (s - min_s) * maxSize.width / st_width;
				fa[i].t[k] = (t - min_t) * maxSize.height / st_height;
			}
		}
	}

	for (i = 0; i < faceCount; i++)
	{
		strlcpy(faces[i].textureFileName, fa[i].textureFileName, 256);
		faces[i].textureName = 0;
		for (j = 0; j < faces[i].n_verts; j++)
		{
			faces[i].s[j] = fa[i].s[j] / maxSize.width;
			faces[i].t[j] = fa[i].t[j] / maxSize.height;
		}
	}
}


#ifndef NDEBUG
- (void)dumpSelfState
{
	NSMutableArray		*flags = nil;
	NSString			*flagsString = nil;
	
	[super dumpSelfState];
	
	if (basefile != nil)  OOLog(@"dumpState.selfDrawingEntity", @"Model file: %@", basefile);
	
	flags = [NSMutableArray array];
	#define ADD_FLAG_IF_SET(x)		if (x) { [flags addObject:@#x]; }
	ADD_FLAG_IF_SET(isSmoothShaded);
	flagsString = [flags count] ? [flags componentsJoinedByString:@", "] : (NSString *)@"none";
	OOLog(@"dumpState.selfDrawingEntity", @"Flags: %@", flagsString);
}
#endif

@end


static NSString * const kOOCacheMeshes = @"OOSelfDrawingEntity-mesh";

@implementation OOCacheManager (OSSelfDrawingEntity)

+ (NSDictionary *)entityDataForName:(NSString *)inShipName
{
	return [[self sharedCache] objectForKey:inShipName inCache:kOOCacheMeshes];
}


+ (void)setEntityData:(NSDictionary *)inData forName:(NSString *)inShipName
{
	if (inData != nil && inShipName != nil)
	{
		[[self sharedCache] setObject:inData forKey:inShipName inCache:kOOCacheMeshes];
	}
}

@end
