/*

OOMesh.m

A note on memory management:
The dynamically-sized buffers used by OOMesh (_vertex etc) are the byte arrays
of NSDatas, which are tracked using the _retainedObjects dictionary. This
simplifies the implementation of -dealloc, but more importantly, it means
bytes are refcounted. This means bytes read from the cache don't need to be
copied, we just need to retain the relevant NSData object (by sticking it in
_retainedObjects).

Since _retainedObjects is a dictionary its members can be replaced,
potentially allowing mutable meshes, although we have no use for this at
present.


Oolite
Copyright (C) 2004-2010 Giles C Williams and contributors

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

#import "OOMesh.h"
#import "Universe.h"
#import "Geometry.h"
#import "ResourceManager.h"
#import "Entity.h"		// for NO_DRAW_DISTANCE_FACTOR.
#import "Octree.h"
#import "OOMaterial.h"
#import "OOBasicMaterial.h"
#import "OOCollectionExtractors.h"
#import "OOOpenGLExtensionManager.h"
#import "OOGraphicsResetManager.h"
#import "OODebugGLDrawing.h"
#import "OOShaderMaterial.h"
#import "OOMacroOpenGL.h"


// If set, collision octree depth varies depending on the size of the mesh. This seems to cause collision handling glitches at present.
#define ADAPTIVE_OCTREE_DEPTH		1


enum
{
	kBaseOctreeDepth				= 5,	// 32x32x32
	kMaxOctreeDepth					= 7,	// 128x128x128
	kSmallOctreeDepth				= 4,	// 16x16x16
	kVerySmallOctreeDepth			= 3,	// 8x8x8
	kOctreeSizeThreshold			= 900,	// Size at which we start increasing octree depth
	kOctreeSmallSizeThreshold		= 50,
	kOctreeVerySmallSizeThreshold	= 15
};


typedef enum
{
	k_normalModePerFace,
	k_normalModeSmooth,
	k_normalModeExplicit
} OOMesh_normalMode;


static BOOL NormalsArePerVertex(OOMesh_normalMode mode)
{
	switch (mode)
	{
		case k_normalModePerFace:
			return NO;
			
		case k_normalModeSmooth:
		case k_normalModeExplicit:
			return YES;
	}
	
#ifndef NDEBUG
	[NSException raise:NSInvalidArgumentException format:@"Unexpected normal mode in %s", __FUNCTION__];
#endif
	return NO;
}


static NSString * const kOOLogMeshDataNotFound				= @"mesh.load.failed.fileNotFound";
static NSString * const kOOLogMeshTooManyVertices			= @"mesh.load.failed.tooManyVertices";
static NSString * const kOOLogMeshTooManyFaces				= @"mesh.load.failed.tooManyFaces";
static NSString * const kOOLogMeshTooManyMaterials			= @"mesh.load.failed.tooManyMaterials";


@interface OOMesh (Private) <NSMutableCopying, OOGraphicsResetClient>

- (id)initWithName:(NSString *)name
materialDictionary:(NSDictionary *)materialDict
 shadersDictionary:(NSDictionary *)shadersDict
			smooth:(BOOL)smooth
	  shaderMacros:(NSDictionary *)macros
shaderBindingTarget:(id<OOWeakReferenceSupport>)object;

- (void)setUpMaterialsWithMaterialsDictionary:(NSDictionary *)materialDict
							shadersDictionary:(NSDictionary *)shadersDict
								 shaderMacros:(NSDictionary *)macros
						  shaderBindingTarget:(id<OOWeakReferenceSupport>)target;

- (BOOL) loadData:(NSString *)filename;
- (void) checkNormalsAndAdjustWinding;
- (void) generateFaceTangents;
- (void) calculateVertexNormalsAndTangents;
- (void) calculateVertexTangents;

- (NSDictionary*) modelData;
- (BOOL) setModelFromModelData:(NSDictionary*) dict;

- (void) getNormal:(Vector *)outNormal andTangent:(Vector *)outTangent forVertex:(int) v_index inSmoothGroup:(OOMeshSmoothGroup)smoothGroup;

- (BOOL) setUpVertexArrays;

- (void) calculateBoundingVolumes;

- (void)rescaleByX:(GLfloat)scaleX y:(GLfloat)scaleY z:(GLfloat)scaleZ;

#ifndef NDEBUG
- (void)debugDrawNormals;
#endif

// Manage set of objects we need to hang on to, particularly NSDatas owning buffers.
- (void) setRetainedObject:(id)object forKey:(NSString *)key;
- (void *) allocateBytesWithSize:(size_t)size count:(OOUInteger)count key:(NSString *)key;

// Allocate all per-vertex/per-face buffers.
- (BOOL) allocateVertexBuffersWithCount:(OOUInteger)count;
- (BOOL) allocateFaceBuffersWithCount:(OOUInteger)count;
- (BOOL) allocateVertexArrayBuffersWithCount:(OOUInteger)count;

- (void) renameTexturesFrom:(NSString *)from to:(NSString *)to;

@end


@interface OOCacheManager (OOMesh)

+ (NSDictionary *)meshDataForName:(NSString *)inShipName;
+ (void)setMeshData:(NSDictionary *)inData forName:(NSString *)inShipName;

@end


@implementation OOMesh

+ (id)meshWithName:(NSString *)name
materialDictionary:(NSDictionary *)materialDict
 shadersDictionary:(NSDictionary *)shadersDict
			smooth:(BOOL)smooth
	  shaderMacros:(NSDictionary *)macros
shaderBindingTarget:(id<OOWeakReferenceSupport>)object
{
	return [[[self alloc] initWithName:name
					materialDictionary:materialDict
					 shadersDictionary:shadersDict
								smooth:smooth
						  shaderMacros:macros
				   shaderBindingTarget:object] autorelease];
}


+ (OOMaterial *)placeholderMaterial
{
	static OOBasicMaterial	*placeholderMaterial = nil;
	
	if (placeholderMaterial == nil)
	{
		placeholderMaterial = [[OOBasicMaterial alloc] initWithName:@"/placeholder/" configuration:[[ResourceManager materialDefaults] oo_dictionaryForKey:@"no-textures-material"]];
	}
	
	return placeholderMaterial;
}


- (id)init
{
	self = [super init];
	if (self == nil)  return nil;
	
	baseFile = @"No Model";
	
	return self;
}


- (void) dealloc
{
	unsigned				i;
	
	DESTROY(baseFile);
	DESTROY(octree);
	
	[self resetGraphicsState];
	
	for (i = 0; i != kOOMeshMaxMaterials; ++i)
	{
		DESTROY(materials[i]);
		DESTROY(materialKeys[i]);
	}
	
	[[OOGraphicsResetManager sharedManager] unregisterClient:self];
	
	DESTROY(_retainedObjects);
	
	[super dealloc];
}


static NSString *_normalModeDescription(OOMesh_normalMode mode)
{
	switch (mode)
	{
		case k_normalModePerFace:  return @"per-face";
		case k_normalModeSmooth:  return @"smooth";
		case k_normalModeExplicit:  return @"explicit";
	}
	
	return @"unknown";
}


- (NSString *)descriptionComponents
{
	return [NSString stringWithFormat:@"\"%@\", %u vertices, %u faces, radius: %g m normals: %@", [self modelName], [self vertexCount], [self faceCount], [self collisionRadius], _normalModeDescription(_normalMode)];
}


- (id)copyWithZone:(NSZone *)zone
{
	if (zone == [self zone])  return [self retain];	// OK because we're immutable seen from the outside
	else  return [self mutableCopyWithZone:zone];
}


- (NSString *) modelName
{
	return baseFile;
}


- (size_t)vertexCount
{
	return vertexCount;
}


- (size_t)faceCount
{
	return faceCount;
}


- (void)renderOpaqueParts
{
	if (EXPECT_NOT(baseFile == nil))
	{
		OOLog(kOOLogFileNotLoaded, @"***** ERROR: no baseFile for entity %@", self);
		return;
	}
	
	OO_ENTER_OPENGL();
	
	int			ti;
	
	OOGL(glPushAttrib(GL_ENABLE_BIT));
	
	OOGL(glShadeModel(GL_SMOOTH));
	
	OOGL(glDisableClientState(GL_COLOR_ARRAY));
	OOGL(glDisableClientState(GL_INDEX_ARRAY));
	OOGL(glDisableClientState(GL_EDGE_FLAG_ARRAY));
	
	OOGL(glEnableClientState(GL_VERTEX_ARRAY));
	OOGL(glEnableClientState(GL_NORMAL_ARRAY));
	OOGL(glEnableClientState(GL_TEXTURE_COORD_ARRAY));
	
	OOGL(glVertexPointer(3, GL_FLOAT, 0, _displayLists.vertexArray));
	OOGL(glNormalPointer(GL_FLOAT, 0, _displayLists.normalArray));
	OOGL(glTexCoordPointer(2, GL_FLOAT, 0, _displayLists.textureUVArray));
	if ([[OOOpenGLExtensionManager sharedManager] shadersSupported])
	{
		OOGL(glEnableVertexAttribArrayARB(kTangentAttributeIndex));
		OOGL(glVertexAttribPointerARB(kTangentAttributeIndex, 3, GL_FLOAT, GL_FALSE, 0, _displayLists.tangentArray));
	}
	
	OOGL(glDisable(GL_BLEND));
	OOGL(glEnable(GL_TEXTURE_2D));
	
	NS_DURING
		if (!listsReady)
		{
			OOGL(displayList0 = glGenLists(materialCount));
			
			// Ensure all textures are loaded
			for (ti = 0; ti < materialCount; ti++)
			{
				[materials[ti] ensureFinishedLoading];
			}
		}
		
		for (ti = 0; ti < materialCount; ti++)
		{
			[materials[ti] apply];
#if 0
			if (listsReady)
			{
				OOGL(glCallList(displayList0 + ti));
			}
			else
			{
				OOGL(glNewList(displayList0 + ti, GL_COMPILE_AND_EXECUTE));
				OOGL(glDrawArrays(GL_TRIANGLES, triangle_range[ti].location, triangle_range[ti].length));
				OOGL(glEndList());
			}
#else
			OOGL(glDrawArrays(GL_TRIANGLES, triangle_range[ti].location, triangle_range[ti].length));
#endif
		}
		
		listsReady = YES;
		brokenInRender = NO;
	NS_HANDLER
		if (!brokenInRender)
		{
			OOLog(kOOLogException, @"***** %s for %@ encountered exception: %@ : %@ *****", __FUNCTION__, self, [localException name], [localException reason]);
			brokenInRender = YES;
		}
		if ([[localException name] hasPrefix:@"Oolite"])  [UNIVERSE handleOoliteException:localException];	// handle these ourself
		else  [localException raise];	// pass these on
	NS_ENDHANDLER
	
	OOGL(glDisableClientState(GL_VERTEX_ARRAY));
	OOGL(glDisableClientState(GL_NORMAL_ARRAY));
	OOGL(glDisableClientState(GL_TEXTURE_COORD_ARRAY));
	
#ifndef NDEBUG
	if (gDebugFlags & DEBUG_DRAW_NORMALS)  [self debugDrawNormals];
#endif
	
	if ([[OOOpenGLExtensionManager sharedManager] shadersSupported])
	{
		OOGL(glDisableVertexAttribArrayARB(kTangentAttributeIndex));
	}
	
	[OOMaterial applyNone];
	CheckOpenGLErrors(@"OOMesh after drawing %@", self);
	
#ifndef NDEBUG
	if (gDebugFlags & DEBUG_OCTREE_DRAW)  [[self octree] drawOctree];
#endif
	
	OOGL(glPopAttrib());
}


- (BOOL)hasOpaqueParts
{
	return YES;
}

- (GLfloat)collisionRadius
{
	return collisionRadius;
}


- (GLfloat)maxDrawDistance
{
	return maxDrawDistance;
}


- (Geometry *)geometry
{
	Geometry *result = [[Geometry alloc] initWithCapacity:faceCount];
	int i;
	for (i = 0; i < faceCount; i++)
	{
		Triangle tri;
		tri.v[0] = _vertices[_faces[i].vertex[0]];
		tri.v[1] = _vertices[_faces[i].vertex[1]];
		tri.v[2] = _vertices[_faces[i].vertex[2]];
		[result addTriangle:tri];
	}
	return [result autorelease];
}


#if ADAPTIVE_OCTREE_DEPTH
- (unsigned) octreeDepth
{
	float				threshold = kOctreeSizeThreshold;
	unsigned			result = kBaseOctreeDepth;
	GLfloat				xs, ys, zs, t, size;
	
	bounding_box_get_dimensions(boundingBox, &xs, &ys, &zs);
	// Shuffle dimensions around so zs is smallest
	if (xs < zs)  { t = zs; zs = xs; xs = t; }
	if (ys < zs)  { t = zs; zs = ys; ys = t; }
	size = (xs + ys) / 2.0f;	// Use average of two largest
	
	if (size < kOctreeVerySmallSizeThreshold)  result = kVerySmallOctreeDepth;
	else if (size < kOctreeSmallSizeThreshold)  result = kSmallOctreeDepth;
	else while (result < kMaxOctreeDepth)
	{
		if (size < threshold) break;
		threshold *= 2.0f;
		result++;
	}
	
	OOLog(@"mesh.load.octree.size", @"Selected octree depth %u for size %g for %@", result, size, baseFile);
	return result;
}
#else
- (unsigned) octreeDepth
{
	return kBaseOctreeDepth;
}
#endif


- (Octree *)octree
{
	if (octree == nil)
	{
		octree = [OOCacheManager octreeForModel:baseFile];
		if (octree == nil)
		{
			octree = [[self geometry] findOctreeToDepth:[self octreeDepth]];
			[OOCacheManager setOctree:octree forModel:baseFile];
		}
		[octree retain];
	}
	
	return octree;
}


- (BoundingBox) findBoundingBoxRelativeToPosition:(Vector)opv
											basis:(Vector)ri :(Vector)rj :(Vector)rk
									 selfPosition:(Vector)position
										selfBasis:(Vector)si :(Vector)sj :(Vector)sk
{
	BoundingBox	result;
	Vector		pv, rv;
	int			i;
	
	// FIXME: rewrite with matrices
	Vector rpos = vector_subtract(position, opv);	// model origin relative to opv
	
	rv.x = dot_product(ri,rpos);
	rv.y = dot_product(rj,rpos);
	rv.z = dot_product(rk,rpos);	// model origin rel to opv in ijk
	
	if (EXPECT_NOT(vertexCount < 1))
	{
		bounding_box_reset_to_vector(&result, rv);
	}
	else
	{
		pv.x = rpos.x + si.x * _vertices[0].x + sj.x * _vertices[0].y + sk.x * _vertices[0].z;
		pv.y = rpos.y + si.y * _vertices[0].x + sj.y * _vertices[0].y + sk.y * _vertices[0].z;
		pv.z = rpos.z + si.z * _vertices[0].x + sj.z * _vertices[0].y + sk.z * _vertices[0].z;	// _vertices[0] position rel to opv
		rv.x = dot_product(ri, pv);
		rv.y = dot_product(rj, pv);
		rv.z = dot_product(rk, pv);	// _vertices[0] position rel to opv in ijk
		bounding_box_reset_to_vector(&result, rv);
	}
	for (i = 1; i < vertexCount; i++)
	{
		pv.x = rpos.x + si.x * _vertices[i].x + sj.x * _vertices[i].y + sk.x * _vertices[i].z;
		pv.y = rpos.y + si.y * _vertices[i].x + sj.y * _vertices[i].y + sk.y * _vertices[i].z;
		pv.z = rpos.z + si.z * _vertices[i].x + sj.z * _vertices[i].y + sk.z * _vertices[i].z;
		rv.x = dot_product(ri, pv);
		rv.y = dot_product(rj, pv);
		rv.z = dot_product(rk, pv);
		bounding_box_add_vector(&result, rv);
	}

	return result;
}


- (BoundingBox)findSubentityBoundingBoxWithPosition:(Vector)position rotMatrix:(OOMatrix)rotMatrix
{
	// HACK! Should work out what the various bounding box things do and make it neat and consistent.
	BoundingBox		result;
	Vector			v;
	int				i;
	
	v = vector_add(position, OOVectorMultiplyMatrix(_vertices[0], rotMatrix));
	bounding_box_reset_to_vector(&result,v);
	
	for (i = 1; i < vertexCount; i++)
	{
		v = vector_add(position, OOVectorMultiplyMatrix(_vertices[i], rotMatrix));
		bounding_box_add_vector(&result,v);
	}
	
	return result;
}


- (OOMesh *)meshRescaledBy:(GLfloat)scaleFactor
{
	return [self meshRescaledByX:scaleFactor y:scaleFactor z:scaleFactor];
}


- (OOMesh *)meshRescaledByX:(GLfloat)scaleX y:(GLfloat)scaleY z:(GLfloat)scaleZ
{
	id					result = nil;
		
	result = [self mutableCopy];
	[result rescaleByX:scaleX y:scaleY z:scaleZ];
	return [result autorelease];
}


- (void)setBindingTarget:(id<OOWeakReferenceSupport>)target
{
	unsigned				i;
	
	for (i = 0; i != kOOMeshMaxMaterials; ++i)
	{
		[materials[i] setBindingTarget:target];
	}
}


#ifndef NDEBUG
- (void)dumpSelfState
{
	[super dumpSelfState];
	
	if (baseFile != nil)  OOLog(@"dumpState.mesh", @"Model file: %@", baseFile);
	OOLog(@"dumpState.mesh", @"Vertex count: %u, face count: %u", vertexCount, faceCount);
	OOLog(@"dumpState.mesh", @"Normals: %@", _normalModeDescription(_normalMode));
}
#endif


/*	This method exists purely to suppress Clang static analyzer warnings that
	these ivars are unused (but may be used by categories, which they are).
	FIXME: there must be a feature macro we can use to avoid actually building
	this into the app, but I can't find it in docs.
*/
- (BOOL) suppressClangStuff
{
	return _normals && _tangents && _faces && boundingBox.min.x;
}

@end


@implementation OOMesh (Private)

- (id)initWithName:(NSString *)name
materialDictionary:(NSDictionary *)materialDict
 shadersDictionary:(NSDictionary *)shadersDict
			smooth:(BOOL)smooth
	  shaderMacros:(NSDictionary *)macros
shaderBindingTarget:(id<OOWeakReferenceSupport>)target
{
	self = [super init];
	if (self == nil)  return nil;
	
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	_normalMode = smooth ? k_normalModeSmooth : k_normalModePerFace;
	
	if ([self loadData:name])
	{
		[self checkNormalsAndAdjustWinding];
		[self calculateBoundingVolumes];
		baseFile = [name copy];
		[self setUpMaterialsWithMaterialsDictionary:materialDict shadersDictionary:shadersDict shaderMacros:macros shaderBindingTarget:target];
		[[OOGraphicsResetManager sharedManager] registerClient:self];
	}
	else
	{
		[self release];
		self = nil;
	}
	
	[pool release];
	return self;
}


- (void)setUpMaterialsWithMaterialsDictionary:(NSDictionary *)materialDict
							shadersDictionary:(NSDictionary *)shadersDict
								 shaderMacros:(NSDictionary *)macros
						  shaderBindingTarget:(id<OOWeakReferenceSupport>)target
{
	OOMeshMaterialCount		i;
	OOMaterial				*material = nil;
	
	if (materialCount != 0)
	{
		for (i = 0; i != materialCount; ++i)
		{
			if (![materialKeys[i] isEqualToString:@"_oo_placeholder_material"])
			{
				material = [OOMaterial materialWithName:materialKeys[i]
										  forModelNamed:baseFile
									 materialDictionary:materialDict
									  shadersDictionary:shadersDict
												 macros:macros
										  bindingTarget:target
										forSmoothedMesh:NormalsArePerVertex(_normalMode)];
			}
			else
			{
				material = nil;
			}
			
			if (material != nil)
			{
				materials[i] = [material retain];
			}
			else
			{
				materials[i] = [[OOMesh placeholderMaterial] retain];
			}
		}
	}
}


- (id)mutableCopyWithZone:(NSZone *)zone
{
	OOMesh				*result = nil;
	OOMeshMaterialCount	i;
	
	result = (OOMesh *)NSCopyObject(self, 0, zone);
	
	if (result != nil)
	{
		[result->baseFile retain];
		[result->octree retain];
		[result->_retainedObjects retain];
		
		for (i = 0; i != kOOMeshMaxMaterials; ++i)
		{
			[result->materialKeys[i] retain];
			[result->materials[i] retain];
		}
		
		// Reset unsharable GL state
		result->listsReady = NO;
		
		[[OOGraphicsResetManager sharedManager] registerClient:result];
	}
	
	return result;
}


- (void) resetGraphicsState
{
	if (listsReady)
	{
		OO_ENTER_OPENGL();
		
		OOGL(glDeleteLists(displayList0, materialCount));
		listsReady = NO;
	}
}


- (NSDictionary *)modelData
{
	NSNumber			*vertCnt = nil,
						*faceCnt = nil;
	NSData				*vertData = nil,
						*normData = nil,
						*tanData = nil,
						*faceData = nil;
	NSArray				*mtlKeys = nil;
	NSNumber			*normMode = nil;
	
	// Prepare cache data elements.
	vertCnt = [NSNumber numberWithUnsignedInt:vertexCount];
	faceCnt = [NSNumber numberWithUnsignedInt:faceCount];
	
#if 0
	vertData = [NSData dataWithBytes:_vertices length:sizeof *_vertices * vertexCount];
	normData = [NSData dataWithBytes:_normals length:sizeof *_normals * vertexCount];
	tanData = [NSData dataWithBytes:_tangents length:sizeof *_tangents * vertexCount];
	faceData = [NSData dataWithBytes:_faces length:sizeof *_faces * faceCount];
#else
	vertData = [_retainedObjects objectForKey:@"vertices"];
	normData = [_retainedObjects objectForKey:@"normals"];
	tanData = [_retainedObjects objectForKey:@"tangents"];
	faceData = [_retainedObjects objectForKey:@"faces"];
#endif
	
	if (materialCount != 0)
	{
		mtlKeys = [NSArray arrayWithObjects:materialKeys count:materialCount];
	}
	else
	{
		mtlKeys = [NSArray array];
	}
	normMode = [NSNumber numberWithUnsignedChar:_normalMode];
	
	// Ensure we have all the required data elements.
	if (vertCnt == nil ||
		faceCnt == nil ||
		vertData == nil ||
		normData == nil ||
		tanData == nil ||
		faceData == nil ||
		mtlKeys == nil ||
		normMode == nil)
	{
		return nil;
	}
	
	// All OK; stick 'em in a dictionary.
	return [NSDictionary dictionaryWithObjectsAndKeys:
						vertCnt, @"vertex count",
						vertData, @"vertex data",
						normData, @"normal data",
						tanData, @"tangent data",
						faceCnt, @"face count",
						faceData, @"face data",
						mtlKeys, @"material keys",
						normMode, @"normal mode",
						nil];
}


- (BOOL)setModelFromModelData:(NSDictionary *)dict
{
	NSData				*vertData = nil,
						*normData = nil,
						*tanData = nil,
						*faceData = nil;
	NSArray				*mtlKeys = nil;
	NSString			*key = nil;
	unsigned			i;
	
	if (dict == nil || ![dict isKindOfClass:[NSDictionary class]])  return NO;
	
	vertexCount = [dict oo_unsignedIntForKey:@"vertex count"];
	faceCount = [dict oo_unsignedIntForKey:@"face count"];
	
	if (vertexCount == 0 || faceCount == 0)  return NO;
	
	// Read data elements from dictionary.
	vertData = [dict oo_dataForKey:@"vertex data"];
	normData = [dict oo_dataForKey:@"normal data"];
	tanData = [dict oo_dataForKey:@"tangent data"];
	faceData = [dict oo_dataForKey:@"face data"];
	
	mtlKeys = [dict oo_arrayForKey:@"material keys"];
	_normalMode = [dict oo_unsignedCharForKey:@"normal mode"];
	
	// Ensure we have all the required data elements.
	if (vertData == nil ||
		normData == nil ||
		tanData == nil ||
		faceData == nil ||
		mtlKeys == nil)
	{
		return NO;
	}
	
	// Ensure data objects are of correct size.
	if ([vertData length] != sizeof *_vertices * vertexCount)  return NO;
	if ([normData length] != sizeof *_normals * vertexCount)  return NO;
	if ([tanData length] != sizeof *_tangents * vertexCount)  return NO;
	if ([faceData length] != sizeof *_faces * faceCount)  return NO;
	
	// Retain data.
	_vertices = (Vector *)[vertData bytes];
	[self setRetainedObject:vertData forKey:@"vertices"];
	_normals = (Vector *)[normData bytes];
	[self setRetainedObject:normData forKey:@"normals"];
	_tangents = (Vector *)[tanData bytes];
	[self setRetainedObject:tanData forKey:@"tangents"];
	_faces = (OOMeshFace *)[faceData bytes];
	[self setRetainedObject:faceData forKey:@"faces"];
	
	// Copy material keys.
	materialCount = [mtlKeys count];
	for (i = 0; i != materialCount; ++i)
	{
		key = [mtlKeys oo_stringAtIndex:i];
		if (key != nil)  materialKeys[i] = [key retain];
		else  return NO;
	}
	
	return YES;
}


- (BOOL)loadData:(NSString *)filename
{
	NSScanner			*scanner;
	NSDictionary		*cacheData = nil;
	NSString			*data = nil;
	NSMutableArray		*lines;
	BOOL				failFlag = NO;
	NSString			*failString = @"***** ";
	unsigned			i, j;
	NSMutableDictionary	*texFileName2Idx = nil;
	
	BOOL using_preloaded = NO;
	
	cacheData = [OOCacheManager meshDataForName:filename];
	if (cacheData != nil)
	{
		if ([self setModelFromModelData:cacheData]) using_preloaded = YES;
	}
	
	if (!using_preloaded)
	{
		NSCharacterSet	*whitespaceCharSet = [NSCharacterSet whitespaceCharacterSet];
		NSCharacterSet	*whitespaceAndNewlineCharSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
#if OOLITE_LEOPARD
		NSCharacterSet	*newlineCharSet = [NSCharacterSet newlineCharacterSet];
#else
		NSMutableCharacterSet *newlineCharSet = [[whitespaceAndNewlineCharSet mutableCopy] autorelease];
		[newlineCharSet formIntersectionWithCharacterSet:[whitespaceCharSet invertedSet]];
#endif
		
		texFileName2Idx = [NSMutableDictionary dictionary];
		
		data = [ResourceManager stringFromFilesNamed:filename inFolder:@"Models" cache:NO];
		if (data == nil)
		{
			// Model not found
			OOLog(kOOLogMeshDataNotFound, @"***** ERROR: could not find %@", filename);
			return NO;
		}

		// strip out comments and commas between values
		//
		lines = [NSMutableArray arrayWithArray:[data componentsSeparatedByString:@"\n"]];
		for (i = 0; i < [lines count]; i++)
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
		
		if (![self allocateVertexBuffersWithCount:vertexCount])
		{
			OOLog(kOOLogAllocationFailure, @"***** ERROR: failed to allocate memory for model %@ (%u vertices).", filename, vertexCount);
			return NO;
		}
		
		// get number of faces
		if ([scanner scanString:@"NFACES" intoString:NULL])
		{
			int n_f;
			if ([scanner scanInt:&n_f])
			{
				faceCount = n_f;
			}
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
		
		if (![self allocateFaceBuffersWithCount:faceCount])
		{
			OOLog(kOOLogAllocationFailure, @"***** ERROR: failed to allocate memory for model %@ (%u vertices, %u faces).", filename, vertexCount, faceCount);
			return NO;
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
					if (![scanner scanFloat:&x])  failFlag = YES;
					if (![scanner scanFloat:&y])  failFlag = YES;
					if (![scanner scanFloat:&z])  failFlag = YES;
					if (!failFlag)
					{
						_vertices[j] = make_vector(x, y, z);
					}
					else
					{
						failString = [NSString stringWithFormat:@"%@Failed to read a value for vertex[%d] in %@\n", failString, j, @"VERTEX"];
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
					if (![scanner scanInt:&r])  failFlag = YES;
					if (![scanner scanInt:&g])  failFlag = YES;
					if (![scanner scanInt:&b])  failFlag = YES;
					if (!failFlag)
					{
						_faces[j].smoothGroup = r;
					}
					else
					{
						failString = [NSString stringWithFormat:@"%@Failed to read a color for face[%d] in FACES\n", failString, j];
					}

					// normal
					if (![scanner scanFloat:&nx])  failFlag = YES;
					if (![scanner scanFloat:&ny])  failFlag = YES;
					if (![scanner scanFloat:&nz])  failFlag = YES;
					if (!failFlag)
					{
						_faces[j].normal = vector_normal(make_vector(nx, ny, nz));
					}
					else
					{
						failString = [NSString stringWithFormat:@"%@Failed to read a normal for face[%d] in FACES\n", failString, j];
					}

					// vertices
					if ([scanner scanInt:&n_v])
					{
						_faces[j].n_verts = n_v;
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
						for (i = 0; (int)i < n_v; i++)
						{
							if ([scanner scanInt:&vi])
							{
								_faces[j].vertex[i] = vi;
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

		// Get textures data.
		if ([scanner scanString:@"TEXTURES" intoString:NULL])
		{
			for (j = 0; j < faceCount; j++)
			{
				NSString	*materialKey;
				float	max_x, max_y;
				float	s, t;
				if (!failFlag)
				{
					// materialKey
					//
					[scanner scanCharactersFromSet:whitespaceAndNewlineCharSet intoString:NULL];
					if (![scanner scanUpToCharactersFromSet:whitespaceCharSet intoString:&materialKey])
					{
						failFlag = YES;
						failString = [NSString stringWithFormat:@"%@Failed to read texture filename for face[%d] in TEXTURES\n", failString, j];
					}
					else
					{
						NSNumber *index = [texFileName2Idx objectForKey:materialKey];
						if (index != nil)
						{
							_faces[j].materialIndex = [index unsignedIntValue];
						}
						else
						{
							if (materialCount == kOOMeshMaxMaterials)
							{
								OOLog(kOOLogMeshTooManyMaterials, @"***** ERROR: model %@ has too many materials (maximum is %d)", filename, kOOMeshMaxMaterials);
								return NO;
							}
							_faces[j].materialIndex = materialCount;
							materialKeys[materialCount] = [materialKey retain];
							index = [NSNumber numberWithUnsignedInt:materialCount];
							[texFileName2Idx setObject:index forKey:materialKey];
							++materialCount;
						}
					}

					// texture size
					//
				   if (!failFlag)
					{
						if (![scanner scanFloat:&max_x])  failFlag = YES;
						if (![scanner scanFloat:&max_y])  failFlag = YES;
						if (failFlag)
							failString = [NSString stringWithFormat:@"%@Failed to read texture size for max_x and max_y in face[%d] in TEXTURES\n", failString, j];
					}

					// vertices
					//
					if (!failFlag)
					{
						for (i = 0; i < _faces[j].n_verts; i++)
						{
							if (![scanner scanFloat:&s])  failFlag = YES;
							if (![scanner scanFloat:&t])  failFlag = YES;
							if (!failFlag)
							{
								_faces[j].s[i] = s / max_x;
								_faces[j].t[i] = t / max_y;
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
			failString = [failString stringByAppendingString:@"Failed to find TEXTURES data (will use placeholder material)\n"];
			materialKeys[0] = @"_oo_placeholder_material";
			materialCount = 1;
			
			for (j = 0; j < faceCount; j++)
			{
				_faces[j].materialIndex = 0;
			}
		}
		
		if ([scanner scanString:@"NAMES" intoString:NULL])
		{
			unsigned int count;
			if (![scanner scanInt:(int *)&count])
			{	
				failFlag = YES;
				failString = [failString stringByAppendingString:@"Expected count after NAMES\n"];
			}
			else
			{
				for (j = 0; j < count; j++)
				{
					NSString *name = nil;
					[scanner scanCharactersFromSet:whitespaceAndNewlineCharSet intoString:NULL];
					if (![scanner scanUpToCharactersFromSet:newlineCharSet intoString:&name])
					{
						failFlag = YES;
						failString = [failString stringByAppendingString:@"Expected file name\n"];
					}
					else
					{
						[self renameTexturesFrom:[NSString stringWithFormat:@"%u", j] to:name];
					}
				}
			}
		}
		
		BOOL explicitTangents = NO;
		
		// Get explicit normals.
		if ([scanner scanString:@"NORMALS" intoString:NULL])
		{
			_normalMode = k_normalModeExplicit;
			
			for (j = 0; j < vertexCount; j++)
			{
				float x, y, z;
				if (!failFlag)
				{
					if (![scanner scanFloat:&x])  failFlag = YES;
					if (![scanner scanFloat:&y])  failFlag = YES;
					if (![scanner scanFloat:&z])  failFlag = YES;
					if (!failFlag)
					{
						_normals[j] = vector_normal(make_vector(x, y, z));
					}
					else
					{
						failString = [NSString stringWithFormat:@"%@Failed to read a value for vertex[%d] in %@\n", failString, j, @"NORMALS"];
					}
				}
			}
			
			// Get explicit tangents (only together with vertices).
			if ([scanner scanString:@"TANGENTS" intoString:NULL])
			{
				_normalMode = k_normalModeExplicit;
				
				for (j = 0; j < vertexCount; j++)
				{
					float x, y, z;
					if (!failFlag)
					{
						if (![scanner scanFloat:&x])  failFlag = YES;
						if (![scanner scanFloat:&y])  failFlag = YES;
						if (![scanner scanFloat:&z])  failFlag = YES;
						if (!failFlag)
						{
							_tangents[j] = vector_normal(make_vector(x, y, z));
						}
						else
						{
							failString = [NSString stringWithFormat:@"%@Failed to read a value for vertex[%d] in %@\n", failString, j, @"TANGENTS"];
						}
					}
				}
			}
		}
		
		[self checkNormalsAndAdjustWinding];
		if (!explicitTangents)  [self generateFaceTangents];
		
		// check for smooth shading and recalculate normals
		if (_normalMode == k_normalModeSmooth)  [self calculateVertexNormalsAndTangents];
		else if (NormalsArePerVertex(_normalMode) && !explicitTangents)  [self calculateVertexTangents];
		
		// save the resulting data for possible reuse
		[OOCacheManager setMeshData:[self modelData] forName:filename];
		
		if (failFlag)
		{
			OOLog(@"mesh.error", @"%@ ..... from %@ %@", failString, filename, (using_preloaded)? @"(from preloaded data)" :@"(from file)");
		}
	}
	
	[self calculateBoundingVolumes];
	
	// set up vertex arrays for drawing
	if (![self setUpVertexArrays])  return NO;
	
	return YES;
}


// FIXME: this isn't working, we're getting smoothed models with inside-out winding. --Ahruman
- (void) checkNormalsAndAdjustWinding
{
	Vector		calculatedNormal;
	int			i, j;
	for (i = 0; i < faceCount; i++)
	{
		Vector v0, v1, v2, norm;
		v0 = _vertices[_faces[i].vertex[0]];
		v1 = _vertices[_faces[i].vertex[1]];
		v2 = _vertices[_faces[i].vertex[2]];
		
		if (_normalMode != k_normalModeExplicit)
		{
			norm = _faces[i].normal;
		}
		else
		{
			/*	Face normal may not exist and is irrelevant anyway; use sum of
				vertex normals. NB: does not need to be normalized since we're
				only doing sign checks.
			*/
			norm = kZeroVector;
			for (j = 0; j < _faces[i].n_verts; j++)
			{
				norm = vector_add(norm, _normals[_faces[i].vertex[j]]);
			}
		}

		calculatedNormal = normal_to_surface(v2, v1, v0);
		if (vector_equal(norm, kZeroVector))
		{
			norm = vector_flip(calculatedNormal);
			_faces[i].normal = norm;
		}
		if (norm.x*calculatedNormal.x < 0 || norm.y*calculatedNormal.y < 0 || norm.z*calculatedNormal.z < 0)
		{
			// normal lies in the WRONG direction!
			// reverse the winding
			int			v[_faces[i].n_verts];
			GLfloat		s[_faces[i].n_verts];
			GLfloat		t[_faces[i].n_verts];
			
			for (j = 0; j < _faces[i].n_verts; j++)
			{
				v[j] = _faces[i].vertex[_faces[i].n_verts - 1 - j];
				s[j] = _faces[i].s[_faces[i].n_verts - 1 - j];
				t[j] = _faces[i].t[_faces[i].n_verts - 1 - j];
			}
			for (j = 0; j < _faces[i].n_verts; j++)
			{
				_faces[i].vertex[j] = v[j];
				_faces[i].s[j] = s[j];
				_faces[i].t[j] = t[j];
			}
		}
	}
}


- (void) generateFaceTangents
{
	int i;
	for (i = 0; i < faceCount; i++)
	{
		OOMeshFace *face = _faces + i;
		
		/*	Generate tangents, i.e. vectors that run in the direction of the s
			texture coordinate. Based on code I found in a forum somewhere and
			then lost track of. Sorry to whomever I should be crediting.
			-- Ahruman 2008-11-23
		*/
		Vector vAB = vector_subtract(_vertices[face->vertex[1]], _vertices[face->vertex[0]]);
		Vector vAC = vector_subtract(_vertices[face->vertex[2]], _vertices[face->vertex[0]]);
		Vector nA = face->normal;
		
		// projAB = aB - (nA . vAB) * nA
		Vector vProjAB = vector_subtract(vAB, vector_multiply_scalar(nA, dot_product(nA, vAB)));
		Vector vProjAC = vector_subtract(vAC, vector_multiply_scalar(nA, dot_product(nA, vAC)));
		
		// delta s/t
		GLfloat dsAB = face->s[1] - face->s[0];
		GLfloat dsAC = face->s[2] - face->s[0];
		GLfloat dtAB = face->t[1] - face->t[0];
		GLfloat dtAC = face->t[2] - face->t[0];
		
		if (dsAC * dtAB > dsAB * dtAC)
		{
			dsAB = -dsAB;
			dsAC = -dsAC;
		}
		
		Vector tangent = vector_subtract(vector_multiply_scalar(vProjAB, dsAC), vector_multiply_scalar(vProjAC, dsAB));
		face->tangent = cross_product(nA, tangent);	// Rotate 90 degrees. Done this way because I'm too lazy to grok the code above.
	}
}


static float FaceArea(GLint *vertIndices, Vector *vertices)
{
	// calculate areas using Heron's formula
	// in the form Area = sqrt(2*(a2*b2+b2*c2+c2*a2)-(a4+b4+c4))/4
	float	a2 = distance2(vertices[vertIndices[0]], vertices[vertIndices[1]]);
	float	b2 = distance2(vertices[vertIndices[1]], vertices[vertIndices[2]]);
	float	c2 = distance2(vertices[vertIndices[2]], vertices[vertIndices[0]]);
	return sqrtf(2.0 * (a2 * b2 + b2 * c2 + c2 * a2) - 0.25 * (a2 * a2 + b2 * b2 +c2 * c2));
}


- (void) calculateVertexNormalsAndTangents
{
	int i,j;
	float	triangle_area[faceCount];
	for (i = 0 ; i < faceCount; i++)
	{
		triangle_area[i] = FaceArea(_faces[i].vertex, _vertices);
	}
	for (i = 0; i < vertexCount; i++)
	{
		Vector normal_sum = kZeroVector;
		Vector tangent_sum = kZeroVector;
		
		for (j = 0; j < faceCount; j++)
		{
			BOOL is_shared = ((_faces[j].vertex[0] == i)||(_faces[j].vertex[1] == i)||(_faces[j].vertex[2] == i));
			if (is_shared)
			{
				float t = triangle_area[j]; // weight sum by area
				normal_sum = vector_add(normal_sum, vector_multiply_scalar(_faces[j].normal, t));
				tangent_sum = vector_add(tangent_sum, vector_multiply_scalar(_faces[j].tangent, t));
			}
		}
		
		normal_sum = vector_normal_or_fallback(normal_sum, kBasisZVector);
		tangent_sum = vector_normal_or_fallback(tangent_sum, kBasisXVector);
		
		_normals[i] = normal_sum;
		_tangents[i] = tangent_sum;
	}
}


- (void) calculateVertexTangents
{
	int i,j;
	float	triangle_area[faceCount];
	for (i = 0 ; i < faceCount; i++)
	{
		triangle_area[i] = FaceArea(_faces[i].vertex, _vertices);
	}
	for (i = 0; i < vertexCount; i++)
	{
		Vector tangent_sum = kZeroVector;
		
		for (j = 0; j < faceCount; j++)
		{
			BOOL is_shared = ((_faces[j].vertex[0] == i)||(_faces[j].vertex[1] == i)||(_faces[j].vertex[2] == i));
			if (is_shared)
			{
				float t = triangle_area[j]; // weight sum by area
				tangent_sum = vector_add(tangent_sum, vector_multiply_scalar(_faces[j].tangent, t));
			}
		}
		
		tangent_sum = vector_normal_or_fallback(tangent_sum, kBasisXVector);
		
		_tangents[i] = tangent_sum;
	}
}


- (void) getNormal:(Vector *)outNormal andTangent:(Vector *)outTangent forVertex:(int) v_index inSmoothGroup:(OOMeshSmoothGroup)smoothGroup
{
	assert(outNormal != NULL && outTangent != NULL);
	
	int j;
	Vector normal_sum = kZeroVector;
	Vector tangent_sum = kZeroVector;
	for (j = 0; j < faceCount; j++)
	{
		if (_faces[j].smoothGroup == smoothGroup)
		{
			if ((_faces[j].vertex[0] == v_index)||(_faces[j].vertex[1] == v_index)||(_faces[j].vertex[2] == v_index))
			{
				float area = FaceArea(_faces[j].vertex, _vertices);
				normal_sum = vector_add(normal_sum, vector_multiply_scalar(_faces[j].normal, area));
				tangent_sum = vector_add(tangent_sum, vector_multiply_scalar(_faces[j].tangent, area));
			}
		}
	}
	
	*outNormal = vector_normal_or_fallback(normal_sum, kBasisZVector);
	*outTangent = vector_normal_or_fallback(tangent_sum, kBasisXVector);
}


- (BOOL) setUpVertexArrays
{
	int fi, vi, mi;
	
	if (![self allocateVertexArrayBuffersWithCount:faceCount])  return NO;
	
	// if smoothed, find any vertices that are between faces of different
	// smoothing groups and mark them as being on an edge and therefore NOT
	// smooth shaded
	BOOL is_edge_vertex[vertexCount];
	GLfloat smoothGroup[vertexCount];
	for (vi = 0; vi < vertexCount; vi++)
	{
		is_edge_vertex[vi] = NO;
		smoothGroup[vi] = -1;
	}
	if (_normalMode == k_normalModeSmooth)
	{
		for (fi = 0; fi < faceCount; fi++)
		{
			GLfloat rv = _faces[fi].smoothGroup;
			int i;
			for (i = 0; i < 3; i++)
			{
				vi = _faces[fi].vertex[i];
				if (smoothGroup[vi] < 0.0)	// unassigned
					smoothGroup[vi] = rv;
				else if (smoothGroup[vi] != rv)	// a different colour
					is_edge_vertex[vi] = YES;
			}
		}
	}


	// base model, flat or smooth shaded, all triangles
	int tri_index = 0;
	int uv_index = 0;
	int vertex_index = 0;
	
	// Iterate over material names
	for (mi = 0; mi != materialCount; ++mi)
	{
		triangle_range[mi].location = tri_index;
		
		for (fi = 0; fi < faceCount; fi++)
		{
			Vector normal, tangent;
			
			if (_faces[fi].materialIndex == mi)
			{
				for (vi = 0; vi < 3; vi++)
				{
					int v = _faces[fi].vertex[vi];
					if (NormalsArePerVertex(_normalMode))
					{
						if (is_edge_vertex[v])
						{
							[self getNormal:&normal	andTangent:&tangent forVertex:v inSmoothGroup:_faces[fi].smoothGroup];
						}
						else
						{
							normal = _normals[v];
							tangent = _tangents[v];
						}
					}
					else
					{
						normal = _faces[fi].normal;
						tangent = _faces[fi].tangent;
					}
					
					// FIXME: avoid redundant vertices so index array is actually useful.
					_displayLists.indexArray[tri_index++] = vertex_index;
					_displayLists.normalArray[vertex_index] = normal;
					_displayLists.tangentArray[vertex_index] = tangent;
					_displayLists.vertexArray[vertex_index++] = _vertices[v];
					_displayLists.textureUVArray[uv_index++] = _faces[fi].s[vi];
					_displayLists.textureUVArray[uv_index++] = _faces[fi].t[vi];
				}
			}
		}
		triangle_range[mi].length = tri_index - triangle_range[mi].location;
	}
	
	_displayLists.count = tri_index;	// total number of triangle vertices
	return YES;
}


- (void) calculateBoundingVolumes
{
	int i;
	double d_squared, length_longest_axis, length_shortest_axis;
	GLfloat result;
	
	result = 0.0f;
	if (vertexCount)  bounding_box_reset_to_vector(&boundingBox, _vertices[0]);
	else  bounding_box_reset(&boundingBox);

	for (i = 0; i < vertexCount; i++)
	{
		d_squared = magnitude2(_vertices[i]);
		if (d_squared > result)  result = d_squared;
		bounding_box_add_vector(&boundingBox, _vertices[i]);
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
	maxDrawDistance = d_squared * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR;	// no longer based on the collision radius
	
	collisionRadius = sqrt(result);
}


- (void)rescaleByX:(GLfloat)scaleX y:(GLfloat)scaleY z:(GLfloat)scaleZ
{
	
	OOMeshVertexCount	i;
	BOOL				isotropic;
	Vector				*vertex = NULL, *normal = NULL;
	
	isotropic = (scaleX == scaleY && scaleY == scaleZ);
	
	for (i = 0; i != vertexCount; ++i)
	{
		vertex = &_vertices[i];
		
		vertex->x *= scaleX;
		vertex->y *= scaleY;
		vertex->z *= scaleZ;
		
		if (!isotropic)
		{
			normal = &_normals[i];
			// For efficiency freaks: let's assume some sort of adaptive branch prediction.
			normal->x *= scaleX;
			normal->y *= scaleY;
			normal->z *= scaleZ;
			*normal = vector_normal(*normal);
		}
	}
	
	[self calculateBoundingVolumes];
	[octree release];
	octree = nil;
}


- (BoundingBox)boundingBox
{
	return boundingBox;
}


#ifndef NDEBUG
- (void)debugDrawNormals
{
	GLuint				i;
	Vector				v, n, t, b;
	float				length, blend;
	GLfloat				color[3];
	OODebugWFState		state;
	
	OO_ENTER_OPENGL();
	
	state = OODebugBeginWireframe(NO);
	
	// Draw
	OOGLBEGIN(GL_LINES);
	for (i = 0; i < _displayLists.count; ++i)
	{
		v = _displayLists.vertexArray[i];
		n = _displayLists.normalArray[i];
		t = _displayLists.tangentArray[i];
		b = true_cross_product(n, t);
		
		// Draw normal
		length = magnitude2(n);
		blend = fabsf(length - 1) * 5.0;
		color[0] = MIN(blend, 1.0f);
		color[1] = 1.0f - color[0];
		color[2] = color[1];
		glColor3fv(color);
		
		glVertex3f(v.x, v.y, v.z);
		scale_vector(&n, 5.0f);
		n = vector_add(n, v);
		glVertex3f(n.x, n.y, n.z);
		
		// Draw tangent
		glColor3f(1.0f, 1.0f, 0.0f);
		t = vector_add(v, vector_multiply_scalar(t, 3.0f));
		glVertex3f(v.x, v.y, v.z);
		glVertex3f(t.x, t.y, t.z);
		
		// Draw binormal
		glColor3f(0.0f, 1.0f, 0.0f);
		b = vector_add(v, vector_multiply_scalar(b, 3.0f));
		glVertex3f(v.x, v.y, v.z);
		glVertex3f(b.x, b.y, b.z);
	}
	OOGLEND();
	
	OODebugEndWireframe(state);
}
#endif


- (void) setRetainedObject:(id)object forKey:(NSString *)key
{
	assert(key != nil);
	
	if (object != nil)
	{
		if (_retainedObjects == nil)  _retainedObjects = [[NSMutableDictionary alloc] init];
		[_retainedObjects setObject:object forKey:key];
	}
}


static void Scribble(void *bytes, size_t size)
{
	#if OOLITE_BIG_ENDIAN
	enum { kScribble = 0xFEEDFACE };
	#else
	enum { kScribble = 0xCEFAEDFE };
	#endif
	
	size /= sizeof (uint32_t);
	uint32_t *mem = bytes;
	while (size--)  *mem++ = kScribble;
}


- (void *) allocateBytesWithSize:(size_t)size count:(OOUInteger)count key:(NSString *)key
{
	size *= count;
	void *bytes = malloc(size);
	if (bytes != NULL)
	{
		Scribble(bytes, size);
		NSData *holder = [NSData dataWithBytesNoCopy:bytes length:size freeWhenDone:YES];
		[self setRetainedObject:holder forKey:key];
	}
	return bytes;
}


- (BOOL) allocateVertexBuffersWithCount:(OOUInteger)count
{
	_vertices = [self allocateBytesWithSize:sizeof *_vertices count:vertexCount key:@"vertices"];
	_normals = [self allocateBytesWithSize:sizeof *_normals count:vertexCount key:@"normals"];
	_tangents = [self allocateBytesWithSize:sizeof *_tangents count:vertexCount key:@"tangents"];
	
	return	_vertices != NULL &&
			_normals != NULL &&
			_tangents != NULL;
}


- (BOOL) allocateFaceBuffersWithCount:(OOUInteger)count
{
	_faces = [self allocateBytesWithSize:sizeof *_faces count:faceCount key:@"faces"];
	return	_faces != NULL;
}


- (BOOL) allocateVertexArrayBuffersWithCount:(OOUInteger)count
{
	_displayLists.indexArray = [self allocateBytesWithSize:sizeof *_displayLists.indexArray count:count * 3 key:@"indexArray"];
	_displayLists.textureUVArray = [self allocateBytesWithSize:sizeof *_displayLists.textureUVArray count:count * 6 key:@"textureUVArray"];
	_displayLists.vertexArray = [self allocateBytesWithSize:sizeof *_displayLists.vertexArray count:count * 3 key:@"vertexArray"];
	_displayLists.normalArray = [self allocateBytesWithSize:sizeof *_displayLists.normalArray count:count * 3 key:@"normalArray"];
	_displayLists.tangentArray = [self allocateBytesWithSize:sizeof *_displayLists.tangentArray count:count * 3 key:@"tangentArray"];
	
	return	_faces != NULL &&
			_displayLists.indexArray != NULL &&
			_displayLists.textureUVArray != NULL &&
			_displayLists.vertexArray != NULL &&
			_displayLists.normalArray != NULL &&
			_displayLists.tangentArray != NULL;
}


- (void) renameTexturesFrom:(NSString *)from to:(NSString *)to
{
	/*	IMPORTANT: this has to be called before setUpMaterials..., so it can
		only be used during loading.
	*/
	OOMeshMaterialCount i;
	for (i = 0; i != materialCount; i++)
	{
		if ([materialKeys[i] isEqualToString:from])
		{
			[materialKeys[i] release];
			materialKeys[i] = [to copy];
		}
	}
}

@end


static NSString * const kOOCacheMeshes = @"OOMesh";

@implementation OOCacheManager (OOMesh)

+ (NSDictionary *)meshDataForName:(NSString *)inShipName
{
	return [[self sharedCache] objectForKey:inShipName inCache:kOOCacheMeshes];
}


+ (void)setMeshData:(NSDictionary *)inData forName:(NSString *)inShipName
{
	if (inData != nil && inShipName != nil)
	{
		[[self sharedCache] setObject:inData forKey:inShipName inCache:kOOCacheMeshes];
	}
}

@end


static NSString * const kOOCacheOctrees = @"octrees";

@implementation OOCacheManager (Octree)

+ (Octree *)octreeForModel:(NSString *)inKey
{
	NSDictionary		*dict = nil;
	Octree				*result = nil;
	
	dict = [[self sharedCache] objectForKey:inKey inCache:kOOCacheOctrees];
	if (dict != nil)
	{
		result = [[Octree alloc] initWithDictionary:dict];
		[result autorelease];
	}
	
	return result;
}


+ (void)setOctree:(Octree *)inOctree forModel:(NSString *)inKey
{
	if (inOctree != nil && inKey != nil)
	{
		[[self sharedCache] setObject:[inOctree dict] forKey:inKey inCache:kOOCacheOctrees];
	}
}

@end
