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
Copyright (C) 2004-2012 Giles C Williams and contributors

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
#import "OOMaterialConvenienceCreators.h"
#import "OOBasicMaterial.h"
#import "OOCollectionExtractors.h"
#import "OOOpenGLExtensionManager.h"
#import "OOGraphicsResetManager.h"
#import "OODebugGLDrawing.h"
#import "OOShaderMaterial.h"
#import "OOMacroOpenGL.h"
#import "OOProfilingStopwatch.h"
#import "OODebugFlags.h"
#import "NSObjectOOExtensions.h"

#import "OOJavaScriptEngine.h"


// If set, collision octree depth varies depending on the size of the mesh.
#define ADAPTIVE_OCTREE_DEPTH		1

// If set, cachable memory is scribbled with FEEDFACE to identify junk in cache.
#define SCRIBBLE					0


enum
{
	kBaseOctreeDepth				= 5,	// 32x32x32
//	kMaxOctreeDepth declared in Octree.h.
	kSmallOctreeDepth				= 4,	// 16x16x16
	kVerySmallOctreeDepth			= 3,	// 8x8x8
	kOctreeSizeThreshold			= 900,	// Size at which we start increasing octree depth
	kOctreeSmallSizeThreshold		= 50,
	kOctreeVerySmallSizeThreshold	= 15
};


typedef enum
{
	kNormalModePerFace,
	kNormalModeSmooth,
	kNormalModeExplicit
} OOMeshNormalMode;


static NSString * const kOOLogMeshDataNotFound				= @"mesh.load.failed.fileNotFound";
static NSString * const kOOLogMeshTooManyVertices			= @"mesh.load.failed.tooManyVertices";
static NSString * const kOOLogMeshTooManyFaces				= @"mesh.load.failed.tooManyFaces";
static NSString * const kOOLogMeshTooManyMaterials			= @"mesh.load.failed.tooManyMaterials";


#if OOMESH_PROFILE
#define PROFILE(tag)  do { _stopwatchLastTime = Profile(tag, _stopwatch, _stopwatchLastTime); } while (0)
static OOTimeDelta Profile(NSString *tag, OOProfilingStopwatch *stopwatch, OOTimeDelta lastTime)
{
	OOTimeDelta now = [stopwatch currentTime];
	OOLog(@"mesh.profile", @"Mesh profile: stage %@, %g seconds (delta %g)", tag, now, now - lastTime);
	return now;
}
#else
#define PROFILE(tag)  do {} while (0)
#endif


/*	VertexFaceRef
	List of indices of faces used by a given vertex.
	Always access using the provided functions.
	
	NOTE: VFRAddFace may use autoreleased memory. All accesses to a given VFR
	must be inside the same autorelease pool.
*/
enum
{
#if OOLITE_64_BIT
	kVertexFaceDefInternalCount	= 11	// sizeof (VertexFaceRef) = 32
#else
	kVertexFaceDefInternalCount	= 5		// sizeof (VertexFaceRef) = 16
#endif
};

typedef struct VertexFaceRef
{
	uint16_t			internCount;
	uint16_t			internFaces[kVertexFaceDefInternalCount];
	NSMutableArray		*extra;
} VertexFaceRef;


static void VFRAddFace(VertexFaceRef *vfr, NSUInteger index);
static NSUInteger VFRGetCount(VertexFaceRef *vfr);
static NSUInteger VFRGetFaceAtIndex(VertexFaceRef *vfr, NSUInteger index);


@interface OOMesh (Private) <NSMutableCopying, OOGraphicsResetClient>

- (id)initWithName:(NSString *)name
		  cacheKey:(NSString *)cacheKey
materialDictionary:(NSDictionary *)materialDict
 shadersDictionary:(NSDictionary *)shadersDict
			smooth:(BOOL)smooth
	  shaderMacros:(NSDictionary *)macros
shaderBindingTarget:(id<OOWeakReferenceSupport>)object;

- (BOOL) loadData:(NSString *)filename;
- (void) checkNormalsAndAdjustWinding;
- (void) generateFaceTangents;
- (void) calculateVertexNormalsAndTangentsWithFaceRefs:(VertexFaceRef *)faceRefs;
- (void) calculateVertexTangentsWithFaceRefs:(VertexFaceRef *)faceRefs;

- (void) deleteDisplayLists;

- (NSDictionary*) modelData;
- (BOOL) setModelFromModelData:(NSDictionary*) dict name:(NSString *)fileName;

- (void) getNormal:(Vector *)outNormal andTangent:(Vector *)outTangent forVertex:(OOMeshVertexCount)v_index inSmoothGroup:(OOMeshSmoothGroup)smoothGroup;

- (BOOL) setUpVertexArrays;

- (void) calculateBoundingVolumes;

- (void) rescaleByFactor:(GLfloat)factor;

#ifndef NDEBUG
- (void)debugDrawNormals;
#endif

// Manage set of objects we need to hang on to, particularly NSDatas owning buffers.
- (void) setRetainedObject:(id)object forKey:(NSString *)key;
- (void *) allocateBytesWithSize:(size_t)size count:(NSUInteger)count key:(NSString *)key;

// Allocate all per-vertex/per-face buffers.
- (BOOL) allocateVertexBuffersWithCount:(NSUInteger)count;
- (BOOL) allocateNormalBuffersWithCount:(NSUInteger)count;
- (BOOL) allocateFaceBuffersWithCount:(NSUInteger)count;
- (BOOL) allocateVertexArrayBuffersWithCount:(NSUInteger)count;

- (void) renameTexturesFrom:(NSString *)from to:(NSString *)to;

@end


@interface OOCacheManager (OOMesh)

+ (NSDictionary *)meshDataForName:(NSString *)inShipName;
+ (void)setMeshData:(NSDictionary *)inData forName:(NSString *)inShipName;

@end


static BOOL IsLegacyNormalMode(OOMeshNormalMode mode)
{
	/*	True for modes that predate the "normal mode" concept, i.e. per-face
		and smooth. These modes require automatic winding correction.
	*/
	switch (mode)
	{
		case kNormalModePerFace:
		case kNormalModeSmooth:
			return YES;
			
		case kNormalModeExplicit:
			return NO;
	}
	
#ifndef NDEBUG
	[NSException raise:NSInvalidArgumentException format:@"Unexpected normal mode in %s", __PRETTY_FUNCTION__];
#endif
	return NO;	
}


static BOOL IsPerVertexNormalMode(OOMeshNormalMode mode)
{
	/*	True for modes that have per-vertex normals, i.e. not per-face mode.
	*/
	switch (mode)
	{
		case kNormalModePerFace:
			return NO;
			
		case kNormalModeSmooth:
		case kNormalModeExplicit:
			return YES;
	}
	
#ifndef NDEBUG
	[NSException raise:NSInvalidArgumentException format:@"Unexpected normal mode in %s", __PRETTY_FUNCTION__];
#endif
	return NO;
}


@implementation OOMesh

+ (instancetype) meshWithName:(NSString *)name
					 cacheKey:(NSString *)cacheKey
		   materialDictionary:(NSDictionary *)materialDict
			shadersDictionary:(NSDictionary *)shadersDict
					   smooth:(BOOL)smooth
				 shaderMacros:(NSDictionary *)macros
		  shaderBindingTarget:(id<OOWeakReferenceSupport>)object
{
	return [[[self alloc] initWithName:name
							  cacheKey:cacheKey
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
#if OO_MULTITEXTURE
	_textureUnitCount = NSNotFound;
#endif

	_lastPosition = kZeroVector;
	_lastRotMatrix = kZeroMatrix; // not identity
	_lastBoundingBox = kZeroBoundingBox;

	return self;
}


- (void) dealloc
{
	unsigned				i;
	
	DESTROY(baseFile);
	DESTROY(octree);
	
	[self deleteDisplayLists];
	
	for (i = 0; i != kOOMeshMaxMaterials; ++i)
	{
		DESTROY(materials[i]);
		DESTROY(materialKeys[i]);
	}
	
	[[OOGraphicsResetManager sharedManager] unregisterClient:self];
	
	DESTROY(_retainedObjects);
	
	DESTROY(_materialDict);
	DESTROY(_shadersDict);
	DESTROY(_cacheKey);
	DESTROY(_shaderMacros);
	DESTROY(_shaderBindingTarget);
	
#if OOMESH_PROFILE
	DESTROY(_stopwatch);
#endif
	
	[super dealloc];
}


static NSString *NormalModeDescription(OOMeshNormalMode mode)
{
	switch (mode)
	{
		case kNormalModePerFace:  return @"per-face";
		case kNormalModeSmooth:  return @"smooth";
		case kNormalModeExplicit:  return @"explicit";
	}
	
	return @"unknown";
}


- (NSString *)descriptionComponents
{
	return [NSString stringWithFormat:@"\"%@\", %zu vertices, %zu faces, radius: %g m normals: %@", [self modelName], [self vertexCount], [self faceCount], [self collisionRadius], NormalModeDescription(_normalMode)];
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
	OO_ENTER_OPENGL();
	
	OOGL(glPushAttrib(GL_ENABLE_BIT));
	
	OOGL(glShadeModel(GL_SMOOTH));
	
	OOGL(glDisableClientState(GL_COLOR_ARRAY));
	OOGL(glDisableClientState(GL_EDGE_FLAG_ARRAY));
	
	OOGL(glEnableClientState(GL_VERTEX_ARRAY));
	OOGL(glEnableClientState(GL_NORMAL_ARRAY));
	
	OOGL(glVertexPointer(3, GL_FLOAT, 0, _displayLists.vertexArray));
	OOGL(glNormalPointer(GL_FLOAT, 0, _displayLists.normalArray));
	
#if OO_SHADERS
	if ([[OOOpenGLExtensionManager sharedManager] shadersSupported])
	{
		OOGL(glEnableVertexAttribArrayARB(kTangentAttributeIndex));
		OOGL(glVertexAttribPointerARB(kTangentAttributeIndex, 3, GL_FLOAT, GL_FALSE, 0, _displayLists.tangentArray));
	}
#endif
	
	OOGL(glDisable(GL_BLEND));
	
	BOOL usingNormalsAsTexCoords = NO;
	OOMeshMaterialIndex ti;
	
	/*	FIXME: really, really horrible hack to set up texture coordinates for
		each texture unit. Very messy and still fails to handle some possibly-
		basic stuff, like switching usingNormalsAsTexCoords per texture unit.
		The right way to do this is probably to move attribute setup into the
		material model.
		-- Ahruman 2010-04-12
	*/
#if OO_MULTITEXTURE
	if (_textureUnitCount == NSNotFound)
	{
		_textureUnitCount = 0;
		for (ti = 0; ti < materialCount; ti++)
		{
			NSUInteger count = [materials[ti] countOfTextureUnitsWithBaseCoordinates];
			if (_textureUnitCount < count)  _textureUnitCount = count;
		}
	}
	
	NSUInteger unit;
	if (_textureUnitCount <= 1)
	{
		OOGL(glEnableClientState(GL_TEXTURE_COORD_ARRAY));
	}
	else
	{
		/*	It should not be possible to have multiple texture units if
			texture combiners are not available.
		*/
		NSAssert2([[OOOpenGLExtensionManager sharedManager] textureCombinersSupported], @"Mesh %@ uses %lu texture units, but multitexturing is not available.", [self shortDescription], _textureUnitCount);
		
		for (unit = 0; unit < _textureUnitCount; unit++)
		{
			OOGL(glClientActiveTextureARB(GL_TEXTURE0_ARB + unit));
			OOGL(glEnableClientState(GL_TEXTURE_COORD_ARRAY));
		}
	}
#else
	OOGL(glEnableClientState(GL_TEXTURE_COORD_ARRAY));
#endif
	
	@try
	{
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
			BOOL wantsNormalsAsTextureCoordinates = [materials[ti] wantsNormalsAsTextureCoordinates];
			if (ti == 0 || wantsNormalsAsTextureCoordinates != usingNormalsAsTexCoords)
			{
					// FIXME: enabling/disabling texturing should be handled by the material.
#if OO_MULTITEXTURE
				for (unit = 0; unit < _textureUnitCount; unit++)
				{
					if (_textureUnitCount > 1)
					{
						OOGL(glClientActiveTextureARB(GL_TEXTURE0_ARB + unit));
						OOGL(glActiveTextureARB(GL_TEXTURE0_ARB + unit));
					}
#endif
					if (!wantsNormalsAsTextureCoordinates)
					{
						OOGL(glDisable(GL_TEXTURE_CUBE_MAP));
						OOGL(glTexCoordPointer(2, GL_FLOAT, 0, _displayLists.textureUVArray));
						OOGL(glEnable(GL_TEXTURE_2D));
					}
					else
					{
						OOGL(glDisable(GL_TEXTURE_2D));
						OOGL(glTexCoordPointer(3, GL_FLOAT, 0, _displayLists.vertexArray));
						OOGL(glEnable(GL_TEXTURE_CUBE_MAP));
					}
#if OO_MULTITEXTURE
				}
#endif
				usingNormalsAsTexCoords = wantsNormalsAsTextureCoordinates;
			}
			
			[materials[ti] apply];
			OOGL(glDrawArrays(GL_TRIANGLES, triangle_range[ti].location, triangle_range[ti].length));
		}
		
		listsReady = YES;
		brokenInRender = NO;
	}
	@catch (NSException *exception)
	{
		if (!brokenInRender)
		{
			OOLog(kOOLogException, @"***** %s for %@ encountered exception: %@ : %@ *****", __PRETTY_FUNCTION__, self, [exception name], [exception reason]);
			brokenInRender = YES;
		}
		if ([[exception name] hasPrefix:@"Oolite"])  [UNIVERSE handleOoliteException:exception];	// handle these ourself
		else  @throw exception;	// pass these on
	}
	
	OOGL(glDisableClientState(GL_VERTEX_ARRAY));
	OOGL(glDisableClientState(GL_NORMAL_ARRAY));
	OOGL(glDisableClientState(GL_TEXTURE_COORD_ARRAY));
	
#if OO_SHADERS
	if ([[OOOpenGLExtensionManager sharedManager] shadersSupported])
	{
		OOGL(glDisableVertexAttribArrayARB(kTangentAttributeIndex));
	}
#endif
	
	[OOMaterial applyNone];
	CheckOpenGLErrors(@"OOMesh after drawing %@", self);
	
#ifndef NDEBUG
	if (gDebugFlags & DEBUG_DRAW_NORMALS)  [self debugDrawNormals];
	if (gDebugFlags & DEBUG_OCTREE_DRAW)  [[self octree] drawOctree];
#endif
	
#if OO_MULTITEXTURE
	if (_textureUnitCount <= 1)
	{
		OOGL(glDisableClientState(GL_TEXTURE_COORD_ARRAY));
	}
	else
	{
		for (unit = 0; unit < _textureUnitCount; unit++)
		{
			OOGL(glClientActiveTextureARB(GL_TEXTURE0_ARB + unit));
			OOGL(glDisableClientState(GL_TEXTURE_COORD_ARRAY));
		}
		
		OOGL(glClientActiveTextureARB(GL_TEXTURE0_ARB));
		OOGL(glActiveTextureARB(GL_TEXTURE0_ARB));
	}
#else
	OOGL(glDisableClientState(GL_TEXTURE_COORD_ARRAY));
#endif
	
	OOGL(glPopAttrib());
}


- (void) rebindMaterials
{
	OOMeshMaterialCount		i;
	OOMaterial				*material = nil;
	
	if (materialCount != 0)
	{
		for (i = 0; i != materialCount; ++i)
		{
			OOMaterial *oldMaterial = materials[i];
			
			if (![materialKeys[i] isEqualToString:@"_oo_placeholder_material"])
			{
				material = [OOMaterial materialWithName:materialKeys[i]
											   cacheKey:_cacheKey
									 materialDictionary:_materialDict
									  shadersDictionary:_shadersDict
												 macros:_shaderMacros
										  bindingTarget:[_shaderBindingTarget weakRefUnderlyingObject]	// Windows DEP fix.
										forSmoothedMesh:IsPerVertexNormalMode(_normalMode)];
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
			
			/*	Release is deferred to here to ensure we don't end up releasing
				a texture that's not in the recent-cache and then reloading it.
			*/
			[oldMaterial release];
		}
	}
}


- (NSDictionary *) materials
{
	return _materialDict;
}


- (NSDictionary *) shaders
{
	return _shadersDict;
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
	OOMeshFaceCount i;
	for (i = 0; i < faceCount; i++)
	{
		// Somewhat surprisingly, this method doesn't even show up in profiles. -- Ahruman 2012-09-22
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
		octree = [[OOCacheManager octreeForModel:baseFile] retain];
		if (octree == nil)
		{
			NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
			
			octree = [[self geometry] findOctreeToDepth:[self octreeDepth]];
			[octree retain];
			[OOCacheManager setOctree:octree forModel:baseFile];
			
			[pool release];
		}
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
	
	OOMeshVertexCount i;
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
	// FIXME: this is a bottleneck.
// Try to fix bottleneck by caching for common case where subentity
// pos+rot is constant from frame to frame. - CIM

	if (vector_equal(position,_lastPosition) && OOMatrixEqual(rotMatrix,_lastRotMatrix))
	{
		return _lastBoundingBox;
	}

	BoundingBox		result;
	Vector			v;
	
	v = vector_add(position, OOVectorMultiplyMatrix(_vertices[0], rotMatrix));
	bounding_box_reset_to_vector(&result,v);
	
	OOMeshVertexCount i;
	for (i = 1; i < vertexCount; i++)
	{
		v = vector_add(position, OOVectorMultiplyMatrix(_vertices[i], rotMatrix));
		bounding_box_add_vector(&result,v);
	}
	
	_lastBoundingBox = result;
	_lastPosition = position;
	_lastRotMatrix = rotMatrix;

	return result;
}


- (OOMesh *)meshRescaledBy:(GLfloat)scaleFactor
{
	OOMesh *result = [self mutableCopy];
	[result copyVertexArray];
	[result rescaleByFactor:scaleFactor];
	return [result autorelease];
}


// create copies of the vertex arrays for safe scaling
- (void) copyVertexArray
{
	NSData *prevData = [_retainedObjects objectForKey:@"vertices"];
	NSData *vertData = [[NSData alloc] initWithData:prevData];
	[self setRetainedObject:vertData forKey:@"vertices"];
	_vertices = (Vector *)[vertData bytes];
	[vertData release];

	NSData *prevVArray = [_retainedObjects objectForKey:@"vertexArray"];
	NSData *vertArray = [[NSData alloc] initWithData:prevVArray];
	[self setRetainedObject:vertArray forKey:@"vertexArray"];
	_displayLists.vertexArray = (Vector *)[vertArray bytes];
	[vertArray release];
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
	OOLog(@"dumpState.mesh", @"Normals: %@", NormalModeDescription(_normalMode));
}
#endif


#ifndef NDEBUG
- (NSSet *) allTextures
{
	NSMutableSet *result = [NSMutableSet set];
	OOMeshMaterialCount i;
	for (i = 0; i != materialCount; i++)
	{
		[result unionSet:[materials[i] allTextures]];
	}
	
	return result;
}


- (size_t) totalSize
{
	size_t result = [super totalSize];
	if (_vertices != NULL)  result += sizeof *_vertices * vertexCount;
	if (_normals != NULL)  result += sizeof *_normals * vertexCount;
	if (_tangents != NULL)  result += sizeof *_tangents * vertexCount;
	if (_faces != NULL)  result += sizeof *_faces * faceCount;
	
	result += _displayLists.count * (sizeof (GLint) + sizeof (GLfloat) + sizeof (Vector) * 3);
	
	OOMeshMaterialCount i;
	for (i = 0; i != materialCount; i++)
	{
		result += [materials[i] oo_objectSize];
	}
	
	result += [octree totalSize];
	return result;
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
		  cacheKey:(NSString *)cacheKey
materialDictionary:(NSDictionary *)materialDict
 shadersDictionary:(NSDictionary *)shadersDict
			smooth:(BOOL)smooth
	  shaderMacros:(NSDictionary *)macros
shaderBindingTarget:(id<OOWeakReferenceSupport>)target
{
	OOJS_PROFILE_ENTER
	
	self = [super init];
	if (self == nil)  return nil;
	
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
 	_normalMode = smooth ? kNormalModeSmooth : kNormalModePerFace;
	
#if OOMESH_PROFILE
	_stopwatch = [[OOProfilingStopwatch alloc] init];
#endif
	
	if ([self loadData:name])
	{
		[self calculateBoundingVolumes];
		PROFILE(@"finished calculateBoundingVolumes (again\?\?)");
		
		baseFile = [name copy];
		
		/*	New in r3033: save the material-defining parameters here so we
			can rebind the materials at any time.
			-- Ahruman 2010-02-17
		*/
		_materialDict = [materialDict copy];
		_shadersDict = [shadersDict copy];
		_cacheKey = [cacheKey copy];
		_shaderMacros = [macros copy];
		_shaderBindingTarget = [target weakRetain];
		
		[self rebindMaterials];
		PROFILE(@"finished material setup");
		
		[[OOGraphicsResetManager sharedManager] registerClient:self];
	}
	else
	{
		[self release];
		self = nil;
	}
#if OOMESH_PROFILE
	DESTROY(_stopwatch);
#endif
#if OO_MULTITEXTURE
	_textureUnitCount = NSNotFound;
#endif
	
	[pool release];
	return self;
	
	OOJS_PROFILE_EXIT
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
		[result->_materialDict retain];
		[result->_shadersDict retain];
		[result->_cacheKey retain];
		[result->_shaderMacros retain];
		[result->_shaderBindingTarget retain];
		
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


- (void) deleteDisplayLists
{
	if (listsReady)
	{
		OO_ENTER_OPENGL();
		
		OOGL(glDeleteLists(displayList0, materialCount));
		listsReady = NO;
	}
}


- (void) resetGraphicsState
{
	[self deleteDisplayLists];
	[self rebindMaterials];
	_textureUnitCount = NSNotFound;
}


- (NSDictionary *)modelData
{
	OOJS_PROFILE_ENTER
	
	NSNumber			*vertCnt = nil,
						*faceCnt = nil;
	NSData				*vertData = nil,
						*normData = nil,
						*tanData = nil,
						*faceData = nil;
	NSArray				*mtlKeys = nil;
	NSNumber			*normMode = nil;
	
	BOOL includeNormals = IsPerVertexNormalMode(_normalMode);
	
	// Prepare cache data elements.
	vertCnt = [NSNumber numberWithUnsignedInt:vertexCount];
	faceCnt = [NSNumber numberWithUnsignedInt:faceCount];
	
	vertData = [_retainedObjects objectForKey:@"vertices"];
	faceData = [_retainedObjects objectForKey:@"faces"];
	if (includeNormals)
	{
		normData = [_retainedObjects objectForKey:@"normals"];
		tanData = [_retainedObjects objectForKey:@"tangents"];
	}
	
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
		faceData == nil ||
		mtlKeys == nil ||
		normMode == nil)
	{
		return nil;
	}
	
	if (includeNormals)
	{
		if (normData == nil || tanData == nil)  return nil;
	}
	
	// All OK; stick 'em in a dictionary.
	return [NSDictionary dictionaryWithObjectsAndKeys:
						vertCnt, @"vertex count",
						vertData, @"vertex data",
						faceCnt, @"face count",
						faceData, @"face data",
						mtlKeys, @"material keys",
						normMode, @"normal mode",
						/*	NOTE: order matters. Since normData and tanData
							are last, if they're nil the dictionary will be
							built without them, which is desired behaviour.
						*/
						normData, @"normal data",
						tanData, @"tangent data",
						nil];
	
	OOJS_PROFILE_EXIT
}


- (BOOL)setModelFromModelData:(NSDictionary *)dict name:(NSString *)fileName
{
	OOJS_PROFILE_ENTER
	
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
	faceData = [dict oo_dataForKey:@"face data"];
	
	mtlKeys = [dict oo_arrayForKey:@"material keys"];
	_normalMode = [dict oo_unsignedCharForKey:@"normal mode"];
	BOOL includeNormals = IsPerVertexNormalMode(_normalMode);
	
	// Ensure we have all the required data elements.
	if (vertData == nil ||
		faceData == nil ||
		mtlKeys == nil)
	{
		OOLog(@"mesh.load.error.badCacheData", @"Ignoring bad cache data for mesh \"%@\".", fileName);
		return NO;
	}
	
	if (includeNormals)
	{
		normData = [dict oo_dataForKey:@"normal data"];
		tanData = [dict oo_dataForKey:@"tangent data"];
		if (normData == nil || tanData == nil)
		{
			OOLog(@"mesh.load.error.badCacheData", @"Ignoring bad normal/tangent cache data for mesh \"%@\".", fileName);
			return NO;
		}
	}
	
	// Ensure data objects are of correct size.
	if ([vertData length] != sizeof *_vertices * vertexCount)  return NO;
	if ([faceData length] != sizeof *_faces * faceCount)  return NO;
	if (includeNormals)
	{
		if ([normData length] != sizeof *_normals * vertexCount)  return NO;
		if ([tanData length] != sizeof *_tangents * vertexCount)  return NO;
	}
	
	// Retain data.
	_vertices = (Vector *)[vertData bytes];
	[self setRetainedObject:vertData forKey:@"vertices"];
	_faces = (OOMeshFace *)[faceData bytes];
	[self setRetainedObject:faceData forKey:@"faces"];
	if (includeNormals)
	{
		_normals = (Vector *)[normData bytes];
		[self setRetainedObject:normData forKey:@"normals"];
		_tangents = (Vector *)[tanData bytes];
		[self setRetainedObject:tanData forKey:@"tangents"];
	}
	else
	{
		_normals = NULL;
		_tangents = NULL;
	}
	
	// Copy material keys.
	materialCount = [mtlKeys count];
	for (i = 0; i != materialCount; ++i)
	{
		key = [mtlKeys oo_stringAtIndex:i];
		if (key != nil)  materialKeys[i] = [key copy];
		else
		{
			OOLog(@"mesh.load.error.badCacheData", @"Ignoring bad cache data for mesh \"%@\".", fileName);
			return NO;
		}
	}
	
	return YES;
	
	OOJS_PROFILE_EXIT
}


- (BOOL)loadData:(NSString *)filename
{
	OOJS_PROFILE_ENTER
	
	NSScanner			*scanner;
	NSDictionary		*cacheData = nil;
	BOOL				failFlag = NO;
	NSString			*failString = @"***** ";
	unsigned			i, j;
	NSMutableDictionary	*texFileName2Idx = nil;
	NSString			*cacheKey = nil;
	BOOL				using_preloaded = NO;
	
	cacheKey = [NSString stringWithFormat:@"%@:%u", filename, _normalMode];
	cacheData = [OOCacheManager meshDataForName:cacheKey];
	if (cacheData != nil)
	{
		if ([self setModelFromModelData:cacheData name:filename])
		{
			using_preloaded = YES;
			PROFILE(@"loaded from cache");
			OOLog(@"mesh.load.cached", @"Retrieved mesh \"%@\" from cache.", filename);
		}
	}
	
	if (!using_preloaded)
	{
		OOLog(@"mesh.load.uncached", @"Mesh \"%@\" is not in cache, loading.", filename);
		
		NSCharacterSet	*whitespaceCharSet = [NSCharacterSet whitespaceCharacterSet];
		NSCharacterSet	*whitespaceAndNewlineCharSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
#if OOLITE_MAC_OS_X
		NSCharacterSet	*newlineCharSet = [NSCharacterSet newlineCharacterSet];
#else
		static NSCharacterSet *newlineCharSet = nil;
		if (newlineCharSet == nil)
		{
			NSMutableCharacterSet *temp = [[whitespaceAndNewlineCharSet mutableCopy] autorelease];
			[temp formIntersectionWithCharacterSet:[whitespaceCharSet invertedSet]];
			newlineCharSet = [temp copy];
		}
#endif
		
		texFileName2Idx = [NSMutableDictionary dictionary];
		
		{
			NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
			NSString *data = [ResourceManager stringFromFilesNamed:filename inFolder:@"Models" cache:NO];
			if (data == nil)
			{
				// Model not found
				OOLog(kOOLogMeshDataNotFound, @"***** ERROR: could not find %@", filename);
				return NO;
			}
			
			// strip out comments and commas between values
			NSMutableArray *lines = [NSMutableArray arrayWithArray:[data componentsSeparatedByString:@"\n"]];
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
			
			[scanner retain];
			[pool release];
			[scanner autorelease];
		}
		
		PROFILE(@"finished preprocessing");

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
		
		// Allocate face->vertex table.
		size_t faceRefSize = sizeof (VertexFaceRef) * vertexCount;
		VertexFaceRef *faceRefs = calloc(1, faceRefSize);
		if (faceRefs != NULL)
		{
			// use an NSData to effectively autorelease it.
			NSData *faceRefHolder = [NSData dataWithBytesNoCopy:faceRefs length:faceRefSize freeWhenDone:YES];
			if (faceRefHolder == nil)
			{
				free(faceRefs);
				faceRefs = NULL;
			}
		}
		
		if (faceRefs == NULL || ![self allocateFaceBuffersWithCount:faceCount])
		{
			OOLog(kOOLogAllocationFailure, @"***** ERROR: failed to allocate memory for model %@ (%u vertices, %u faces).", filename, vertexCount, faceCount);
			return NO;
		}
		
		// get vertex data
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
						if (n_v < 3)
						{
							failFlag = YES;
							failString = [NSString stringWithFormat:@"%@Face[%u] has fewer than three vertices.\n", failString, j];
						}
						else if (n_v > 3)
						{
							OOLogWARN(@"mesh.load.warning.nonTriangular", @"Face[%u] of %@ has %u vertices specified. Only the first three will be used.", j, baseFile, n_v);
							n_v = 3;
						}
					}
					else
					{
						failFlag = YES;
						failString = [NSString stringWithFormat:@"%@Failed to read number of vertices for face[%d] in FACES\n", failString, j];
					}
					
					if (!failFlag)
					{
						int vi;
						for (i = 0; (int)i < n_v; i++)
						{
							if ([scanner scanInt:&vi])
							{
								_faces[j].vertex[i] = vi;
								if (faceRefs != NULL)  VFRAddFace(&faceRefs[vi], j);
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
						for (i = 0; i < 3; i++)
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
			_normalMode = kNormalModeExplicit;
			if (![self allocateNormalBuffersWithCount:vertexCount])
			{
				OOLog(kOOLogAllocationFailure, @"***** ERROR: failed to allocate memory for model %@ (%u vertices).", filename, vertexCount);
				return NO;
			}
			
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
		
		PROFILE(@"finished parsing");
		
		if (IsLegacyNormalMode(_normalMode))
		{
			[self checkNormalsAndAdjustWinding];
			PROFILE(@"finished checkNormalsAndAdjustWinding");
		}
		if (!explicitTangents)
		{
			[self generateFaceTangents];
			PROFILE(@"finished generateFaceTangents");
		}
		
		// check for smooth shading and recalculate normals
		if (_normalMode == kNormalModeSmooth)
		{
			if (![self allocateNormalBuffersWithCount:vertexCount])
			{
				OOLog(kOOLogAllocationFailure, @"***** ERROR: failed to allocate memory for model %@ (%u vertices).", filename, vertexCount);
				return NO;
			}
			[self calculateVertexNormalsAndTangentsWithFaceRefs:faceRefs];
			PROFILE(@"finished calculateVertexNormalsAndTangents");
			
		}
		else if (IsPerVertexNormalMode(_normalMode) && !explicitTangents)
		{
			[self calculateVertexTangentsWithFaceRefs:faceRefs];
			PROFILE(@"finished calculateVertexTangents");
		}
		
		// save the resulting data for possible reuse
		[OOCacheManager setMeshData:[self modelData] forName:cacheKey];
		PROFILE(@"saved to cache");
		
		if (failFlag)
		{
			OOLog(@"mesh.error", @"%@ ..... from %@ %@", failString, filename, (using_preloaded)? @"(from preloaded data)" :@"(from file)");
		}
	}
	
	[self calculateBoundingVolumes];
	PROFILE(@"finished calculateBoundingVolumes");
	
	// set up vertex arrays for drawing
	if (![self setUpVertexArrays])  return NO;
	PROFILE(@"finished setUpVertexArrays");
	
	return YES;
	
	OOJS_PROFILE_EXIT
}


- (void) checkNormalsAndAdjustWinding
{
	OOJS_PROFILE_ENTER
	
	Vector				calculatedNormal;
	OOMeshFaceCount		i;
	
	NSParameterAssert(_normalMode != kNormalModeExplicit);
	
	for (i = 0; i < faceCount; i++)
	{
		Vector v0, v1, v2, norm;
		v0 = _vertices[_faces[i].vertex[0]];
		v1 = _vertices[_faces[i].vertex[1]];
		v2 = _vertices[_faces[i].vertex[2]];
		norm = _faces[i].normal;
		
		calculatedNormal = normal_to_surface(v2, v1, v0);
		if (vector_equal(norm, kZeroVector))
		{
			norm = vector_flip(calculatedNormal);
			_faces[i].normal = norm;
		}
		
		/*	FIXME: for 2.0, either require explicit normals for every model
			or change to: if (dot_product(norm, calculatedNormal) < 0.0f)
			-- Ahruman 2010-01-23
		*/
		if (norm.x * calculatedNormal.x < 0 || norm.y * calculatedNormal.y < 0 || norm.z * calculatedNormal.z < 0)
		{
			// normal lies in the WRONG direction!
			// reverse the winding
			int v0 = _faces[i].vertex[0];
			_faces[i].vertex[0] = _faces[i].vertex[2];
			_faces[i].vertex[2] = v0;
			
			GLfloat f0 = _faces[i].s[0];
			_faces[i].s[0] = _faces[i].s[2];
			_faces[i].s[2] = f0;
			
			f0 = _faces[i].t[0];
			_faces[i].t[0] = _faces[i].t[2];
			_faces[i].t[2] = f0;
		}
	}
	
	OOJS_PROFILE_EXIT_VOID
}


- (void) generateFaceTangents
{
	OOJS_PROFILE_ENTER
	
	OOMeshFaceCount	i;
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
	
	OOJS_PROFILE_EXIT_VOID
}


static float FaceArea(GLuint *vertIndices, Vector *vertices)
{
	/*	Calculate areas using Heron's formula.	*/
	float	a2 = distance2(vertices[vertIndices[0]], vertices[vertIndices[1]]);
	float	b2 = distance2(vertices[vertIndices[1]], vertices[vertIndices[2]]);
	float	c2 = distance2(vertices[vertIndices[2]], vertices[vertIndices[0]]);
	return sqrt((2.0f * (a2 * b2 + b2 * c2 + c2 * a2) - (a2 * a2 + b2 * b2 +c2 * c2)) * 0.0625f);
}


- (void) calculateVertexNormalsAndTangentsWithFaceRefs:(VertexFaceRef *)faceRefs
{
	OOJS_PROFILE_ENTER
	
	NSParameterAssert(faceRefs != NULL);
	
	NSUInteger	i,j;
	float		triangle_area[faceCount];
	
	NSAssert1(_normals != NULL && _tangents != NULL, @"Normal/tangent buffers not allocated in %s", __PRETTY_FUNCTION__);
	
	for (i = 0 ; i < faceCount; i++)
	{
		triangle_area[i] = FaceArea(_faces[i].vertex, _vertices);
	}
	for (i = 0; i < vertexCount; i++)
	{
		Vector normal_sum = kZeroVector;
		Vector tangent_sum = kZeroVector;
		
		VertexFaceRef *vfr = &faceRefs[i];
		NSUInteger fIter, fCount = VFRGetCount(vfr);
		for (fIter = 0; fIter < fCount; fIter++)
		{
			j = VFRGetFaceAtIndex(vfr, fIter);
			
			float t = triangle_area[j]; // weight sum by area
			normal_sum = vector_add(normal_sum, vector_multiply_scalar(_faces[j].normal, t));
			tangent_sum = vector_add(tangent_sum, vector_multiply_scalar(_faces[j].tangent, t));
		}
		
		normal_sum = vector_normal_or_fallback(normal_sum, kBasisZVector);
		tangent_sum = vector_normal_or_fallback(tangent_sum, kBasisXVector);
		
		_normals[i] = normal_sum;
		_tangents[i] = tangent_sum;
	}
	
	OOJS_PROFILE_EXIT_VOID
}


static float FaceAreaCorrect(GLuint *vertIndices, Vector *vertices)
{
	/*	Calculate area of triangle.
		The magnitude of the cross product of two vectors is the area of
		the parallelogram they span. The area of a triangle is half the
		area of a parallelogram sharing two of its sides.
		Since we only use the area of the triangle as a weight factor,
		constant terms are irrelevant, so we don't bother halving the
		value.
	*/
	Vector AB = vector_subtract(vertices[vertIndices[1]], vertices[vertIndices[0]]);
	Vector AC = vector_subtract(vertices[vertIndices[2]], vertices[vertIndices[0]]);
	return magnitude(true_cross_product(AB, AC));
}


- (void) calculateVertexTangentsWithFaceRefs:(VertexFaceRef *)faceRefs
{
	OOJS_PROFILE_ENTER
	
	NSParameterAssert(faceRefs != NULL);
	
	/*	This is conceptually broken.
		At the moment, it's calculating one tangent per "input" vertex. It should
		be calculating one tangent per "real" vertex, where a "real" vertex is
		defined as a combination of position, normal, material and texture
		coordinates.
		Currently, we don't have a format with unique "real" vertices.
		This basically means explicit-normal models without explicit tangents
		can't usefully be normal mapped.
		I don't intend to do anything about this pre-MSNR, although it might be
		possible to fix it by moving tangent generation to the same stage as
		smooth-grouped normal generation.
		-- Ahruman 2010-05-22
	*/
	NSUInteger	i,j;
	float	triangle_area[faceCount];
	for (i = 0 ; i < faceCount; i++)
	{
		triangle_area[i] = FaceAreaCorrect(_faces[i].vertex, _vertices);
	}
	for (i = 0; i < vertexCount; i++)
	{
		Vector tangent_sum = kZeroVector;
		
		VertexFaceRef *vfr = &faceRefs[i];
		NSUInteger fIter, fCount = VFRGetCount(vfr);
		for (fIter = 0; fIter < fCount; fIter++)
		{
			j = VFRGetFaceAtIndex(vfr, fIter);
			
			float t = triangle_area[j]; // weight sum by area
			tangent_sum = vector_add(tangent_sum, vector_multiply_scalar(_faces[j].tangent, t));
		}
		
		tangent_sum = vector_normal_or_fallback(tangent_sum, kBasisXVector);
		
		_tangents[i] = tangent_sum;
	}
	
	OOJS_PROFILE_EXIT_VOID
}


- (void) getNormal:(Vector *)outNormal andTangent:(Vector *)outTangent forVertex:(OOMeshVertexCount)v_index inSmoothGroup:(OOMeshSmoothGroup)smoothGroup
{
	OOJS_PROFILE_ENTER
	
	assert(outNormal != NULL && outTangent != NULL);
	
	NSUInteger j;
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
	
	OOJS_PROFILE_EXIT_VOID
}


- (BOOL) setUpVertexArrays
{
	OOJS_PROFILE_ENTER
	
	NSUInteger	fi, vi, mi;
	
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
	if (_normalMode == kNormalModeSmooth)
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
					if (IsPerVertexNormalMode(_normalMode))
					{
						if (is_edge_vertex[v])
						{
							[self getNormal:&normal	andTangent:&tangent forVertex:v inSmoothGroup:_faces[fi].smoothGroup];
						}
						else
						{
							NSAssert1(_normals != NULL && _tangents != NULL, @"Normal/tangent buffers not allocated in %s", __PRETTY_FUNCTION__);
							
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
	
	OOJS_PROFILE_EXIT
}


- (void) calculateBoundingVolumes
{
	OOJS_PROFILE_ENTER
	
	OOMeshVertexCount	i;
	double				d_squared, length_longest_axis, length_shortest_axis;
	GLfloat				result;
	
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
	
	OOJS_PROFILE_EXIT_VOID
}


- (void) rescaleByFactor:(GLfloat)factor
{
	// Rescale base vertices used for geometry calculations.
	OOMeshVertexCount	i;
	Vector				*vertex = NULL;
	
	for (i = 0; i < vertexCount; i++)
	{
		vertex = &_vertices[i];
		*vertex = vector_multiply_scalar(*vertex, factor);
	}
	
	// Rescale actual display vertices.
	for (i = 0; i < _displayLists.count; i++)
	{
		vertex = &_displayLists.vertexArray[i];
		*vertex = vector_multiply_scalar(*vertex, factor);
	}
	
	[self calculateBoundingVolumes];
	DESTROY(octree);
	DESTROY(baseFile);	// Avoid octree cache.
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
		blend = fabs(length - 1) * 5.0;
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
		
		// Draw bitangent
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


#if SCRIBBLE
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
#else
#define Scribble(bytes, size) do {} while (0)
#endif


- (void *) allocateBytesWithSize:(size_t)size count:(NSUInteger)count key:(NSString *)key
{
	if (count == 0) { count=1; }
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


- (BOOL) allocateVertexBuffersWithCount:(NSUInteger)count
{
	_vertices = [self allocateBytesWithSize:sizeof *_vertices count:vertexCount key:@"vertices"];
	return _vertices != NULL;
}


- (BOOL) allocateNormalBuffersWithCount:(NSUInteger)count
{
	_normals = [self allocateBytesWithSize:sizeof *_normals count:vertexCount key:@"normals"];
	_tangents = [self allocateBytesWithSize:sizeof *_tangents count:vertexCount key:@"tangents"];
	return _normals != NULL && _tangents != NULL;
}


- (BOOL) allocateFaceBuffersWithCount:(NSUInteger)count
{
	_faces = [self allocateBytesWithSize:sizeof *_faces count:faceCount key:@"faces"];
	return	_faces != NULL;
}


- (BOOL) allocateVertexArrayBuffersWithCount:(NSUInteger)count
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
	
	if (inKey == nil)  return nil;
	
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
		[[self sharedCache] setObject:[inOctree dictionaryRepresentation] forKey:inKey inCache:kOOCacheOctrees];
	}
}


static void VFRAddFace(VertexFaceRef *vfr, NSUInteger index)
{
	NSCParameterAssert(vfr != NULL);
	
	if (index < UINT16_MAX && vfr->internCount < kVertexFaceDefInternalCount)
	{
		vfr->internFaces[vfr->internCount++] = index;
	}
	else
	{
		if (vfr->extra == nil)  vfr->extra = [NSMutableArray array];
		[vfr->extra addObject:[NSNumber numberWithInteger:index]];
	}
}


static NSUInteger VFRGetCount(VertexFaceRef *vfr)
{
	NSCParameterAssert(vfr != NULL);
	
	return vfr->internCount + [vfr->extra count];
}


static NSUInteger VFRGetFaceAtIndex(VertexFaceRef *vfr, NSUInteger index)
{
	NSCParameterAssert(vfr != NULL && index < VFRGetCount(vfr));
	
	if (index < vfr->internCount)  return vfr->internFaces[index];
	else  return [vfr->extra oo_unsignedIntegerAtIndex:index - vfr->internCount];
}

@end
