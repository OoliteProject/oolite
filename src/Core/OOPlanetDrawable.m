/*
 
 OOPlanetDrawable.m
 
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
#if NEW_PLANETS


#import "OOPlanetDrawable.h"
#import "OOPlanetData.h"
#import "OOSingleTextureMaterial.h"
#import "OOOpenGL.h"
#import "OOMacroOpenGL.h"
#import "Universe.h"
#import "MyOpenGLView.h"

#ifndef NDEBUG
#import "Entity.h"
#import "OODebugGLDrawing.h"
#import "OODebugFlags.h"
#endif


#define LOD_GRANULARITY		((float)(kOOPlanetDataLevels - 1))
#define LOD_FACTOR			(1.0 / 4.0)


@interface OOPlanetDrawable (Private)

- (void) recalculateTransform;

- (void) debugDrawNormals;

@end


@implementation OOPlanetDrawable

+ (instancetype) planetWithTextureName:(NSString *)textureName radius:(float)radius
{
	OOPlanetDrawable *result = [[[self alloc] init] autorelease];
	[result setTextureName:textureName];
	[result setRadius:radius];
	
	return result;
}


+ (instancetype) atmosphereWithRadius:(float)radius
{
	OOPlanetDrawable *result = [[[self alloc] initAsAtmosphere] autorelease];
	[result setRadius:radius];
	
	return result;
}


- (id) init
{
	if ((self = [super init]))
	{
		_radius = 1.0f;
		[self recalculateTransform];
		[self setLevelOfDetail:0.5f];
	}
	
	return self;
}


- (id) initAsAtmosphere
{
	if ((self = [self init]))
	{
		_isAtmosphere = YES;
	}
	
	return self;
}


- (void) dealloc
{
	DESTROY(_material);
	
	[super dealloc];
}


- (id) copyWithZone:(NSZone *)zone
{
	OOPlanetDrawable *copy = [[[self class] allocWithZone:zone] init];
	[copy setMaterial:[self material]];
	copy->_isAtmosphere = _isAtmosphere;
	copy->_radius = _radius;
	copy->_transform = _transform;
	copy->_lod = _lod;
	
	return copy;
}


- (OOMaterial *) material
{
	return _material;
}


- (void) setMaterial:(OOMaterial *)material
{
	[_material autorelease];
	_material = [material retain];
}


- (NSString *) textureName
{
	return [_material name];
}


- (void) setTextureName:(NSString *)textureName
{
	if (![textureName isEqual:[self textureName]])
	{
		[_material release];
		NSDictionary *spec = [@"{diffuse_map={repeat_s=yes;cube_map=yes};}" propertyList];
		_material = [[OOSingleTextureMaterial alloc] initWithName:textureName configuration:spec];
	}
}


- (float) radius
{
	return _radius;
}


- (void) setRadius:(float)radius
{
	_radius = fabs(radius);
	[self recalculateTransform];
}


- (float) levelOfDetail
{
	return (float)_lod / LOD_GRANULARITY;
}


- (void) setLevelOfDetail:(float)lod
{
	_lod = round(OOClamp_0_1_f(lod) * LOD_GRANULARITY);
}


- (void) calculateLevelOfDetailForViewDistance:(float)distance
{
	float	drawFactor = [[UNIVERSE gameView] viewSize].width / 100.0f;
	float	drawRatio2 = drawFactor * _radius / sqrt(distance); // proportional to size on screen in pixels
	
	float lod = sqrt(drawRatio2 * LOD_FACTOR);
	if ([UNIVERSE reducedDetail])
	{
		lod -= 0.5f / LOD_GRANULARITY;	// Make LOD transitions earlier.
		lod = OOClamp_0_max_f(lod, (LOD_GRANULARITY - 1) / LOD_GRANULARITY);	// Don't use highest LOD.
	}
	[self setLevelOfDetail:lod];
}


- (void) renderOpaqueParts
{
	assert(_lod < kOOPlanetDataLevels);
	
	const OOPlanetDataLevel *data = &kPlanetData[_lod];
	
	OO_ENTER_OPENGL();
	
	OOSetOpenGLState(OPENGL_STATE_OPAQUE);
	
	OOGL(glPushAttrib(GL_ENABLE_BIT | GL_DEPTH_BUFFER_BIT));
	OOGL(glShadeModel(GL_SMOOTH));
	
	if (_isAtmosphere)
	{
		OOGL(glEnable(GL_BLEND));
		OOGL(glDisable(GL_DEPTH_TEST));
		OOGL(glDepthMask(GL_FALSE));
	}
	else
	{
		OOGL(glDisable(GL_BLEND));
	}
	
	[_material apply];
	
	// Scale the ball.
	OOGL(glPushMatrix());
	GLMultOOMatrix(_transform);
	
	OOGL(glEnable(GL_LIGHTING));
	OOGL(glEnable(GL_TEXTURE_2D));

#if OO_TEXTURE_CUBE_MAP
	if ([_material wantsNormalsAsTextureCoordinates])
	{
		OOGL(glDisable(GL_TEXTURE_2D));
		OOGL(glEnable(GL_TEXTURE_CUBE_MAP));
	}
#endif
	
	OOGL(glDisableClientState(GL_COLOR_ARRAY));
	
	OOGL(glEnableClientState(GL_TEXTURE_COORD_ARRAY));
	
	OOGL(glVertexPointer(3, GL_FLOAT, 0, kOOPlanetVertices));
	if ([_material wantsNormalsAsTextureCoordinates])
	{
		OOGL(glTexCoordPointer(3, GL_FLOAT, 0, kOOPlanetVertices));
	}
	else
	{
		OOGL(glTexCoordPointer(2, GL_FLOAT, 0, kOOPlanetTexCoords));
	}
	
	// FIXME: instead of GL_RESCALE_NORMAL, consider copying and transforming the vertex array for each planet.
	OOGL(glEnable(GL_RESCALE_NORMAL));
	OOGL(glNormalPointer(GL_FLOAT, 0, kOOPlanetVertices));
	
	OOGL(glDrawElements(GL_TRIANGLES, data->faceCount*3, data->type, data->indices));
	
#ifndef NDEBUG
	if ([UNIVERSE wireframeGraphics])
	{
		OODebugDrawBasisAtOrigin(1.5);
	}
#endif

#if OO_TEXTURE_CUBE_MAP
	if ([_material wantsNormalsAsTextureCoordinates])
	{
		OOGL(glEnable(GL_TEXTURE_2D));
		OOGL(glDisable(GL_TEXTURE_CUBE_MAP));
	}
#endif

	
	OOGL(glPopMatrix());
#ifndef NDEBUG
	if (gDebugFlags & DEBUG_DRAW_NORMALS)  [self debugDrawNormals];
#endif
	
	[OOMaterial applyNone];
	OOGL(glPopAttrib());
	
	OOGL(glDisableClientState(GL_TEXTURE_COORD_ARRAY));
	
	OOVerifyOpenGLState();
}


- (void) renderTranslucentParts
{
	[self renderOpaqueParts];
}


- (BOOL) hasOpaqueParts
{
	return !_isAtmosphere;
}


- (BOOL) hasTranslucentParts
{
	return _isAtmosphere;
}


- (GLfloat) collisionRadius
{
	return _radius;
}


- (GLfloat) maxDrawDistance
{
	// FIXME
	return INFINITY;
}


- (BoundingBox) boundingBox
{
	return (BoundingBox){{ -_radius, -_radius, -_radius }, { _radius, _radius, _radius }};
}


- (void) setBindingTarget:(id<OOWeakReferenceSupport>)target
{
	[_material setBindingTarget:target];
}


- (void) dumpSelfState
{
	[super dumpSelfState];
	OOLog(@"dumpState.planetDrawable", @"radius: %g", [self radius]);
	OOLog(@"dumpState.planetDrawable", @"LOD: %g", [self levelOfDetail]);
}


- (void) recalculateTransform
{
	_transform = OOMatrixForScaleUniform(_radius);
}


#ifndef NDEBUG

- (void) debugDrawNormals
{
	OODebugWFState		state;
	
	OO_ENTER_OPENGL();
	
	state = OODebugBeginWireframe(NO);
	
	const OOPlanetDataLevel *data = &kPlanetData[_lod];
	unsigned i;
	
	OOGLBEGIN(GL_LINES);
	for (i = 0; i < data->vertexCount; i++)
	{
		/*	Fun sphere facts: the normalized coordinates of a point on a sphere at the origin
			is equal to the object-space normal of the surface at that point.
			Furthermore, we can construct the binormal (a vector pointing westward along the
			surface) as the cross product of the normal with the Y axis. (This produces
			singularities at the pole, but there have to be singularities according to the
			Hairy Ball Theorem.) The tangent (a vector north along the surface) is then the
			inverse of the cross product of the normal and binormal.
			
			(This comment courtesy of the in-development planet shader.)
		*/
		Vector v = make_vector(kOOPlanetVertices[i * 3], kOOPlanetVertices[i * 3 + 1], kOOPlanetVertices[i * 3 + 2]);
		Vector n = v;
		v = OOVectorMultiplyMatrix(v, _transform);
		
		glColor3f(0.0f, 1.0f, 1.0f);
		GLVertexOOVector(v);
		GLVertexOOVector(vector_add(v, vector_multiply_scalar(n, _radius * 0.05)));
		
		Vector b = cross_product(n, kBasisYVector);
		Vector t = vector_flip(true_cross_product(n, b));
		
		glColor3f(1.0f, 1.0f, 0.0f);
		GLVertexOOVector(v);
		GLVertexOOVector(vector_add(v, vector_multiply_scalar(t, _radius * 0.03)));
		
		glColor3f(0.0f, 1.0f, 0.0f);
		GLVertexOOVector(v);
		GLVertexOOVector(vector_add(v, vector_multiply_scalar(b, _radius * 0.03)));
	}
	OOGLEND();
	
	OODebugEndWireframe(state);
}


- (NSSet *) allTextures
{
	return [[self material] allTextures];
}

#endif

@end

#endif	/* NEW_PLANETS */
