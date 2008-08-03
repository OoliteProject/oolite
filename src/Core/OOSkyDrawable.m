/*

OOSkyDrawable.m

Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2007 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOSkyDrawable.h"
#import "ResourceManager.h"
#import "OOTexture.h"
#import "GameController.h"
#import "OOColor.h"
#import "OOProbabilisticTextureManager.h"
#import "OOGraphicsResetManager.h"
#import "Universe.h"
#import "OOMacroOpenGL.h"


#define SKY_ELEMENT_SCALE_FACTOR		(BILLBOARD_DEPTH / 500.0f)
#define NEBULA_SHUFFLE_FACTOR			0.005f

BOOL		gSkyWireframe = NO;


/*	Min and max coords are 0 and 1 normally, but the default
	sky-render-inset-coords can be used to modify them slightly as an attempted
	work-around for artefacts on buggy S3/Via renderers.
*/
static float sMinTexCoord = 0.0f, sMaxTexCoord = 1.0f;
static BOOL sInited = NO;


/*	Struct used to describe quads initially. This form is optimized for
	reasoning about.
*/
typedef struct OOSkyQuadDesc
{
	Vector				corners[4];
	OOColor				*color;
	OOTexture			*texture;
} OOSkyQuadDesc;


enum
{
	kSkyQuadSetPositionEntriesPerVertex		= 3,
	kSkyQuadSetTexCoordEntriesPerVertex		= 2,
	kSkyQuadSetColorEntriesPerVertex		= 4
};


/*	Class containing a set of quads with the same texture. This form is
	optimized for rendering.
*/
@interface OOSkyQuadSet: NSObject
{
	OOTexture				*_texture;
	unsigned				_count;
	GLfloat					*_positions;	// 3 entries per vertex, 12 per quad
	GLfloat					*_texCoords;	// 2 entries per vertex, 8 per quad
	GLfloat					*_colors;		// 4 entries per vertex, 16 per quad
}

+ (void)addQuads:(OOSkyQuadDesc *)quads count:(unsigned)count toArray:(NSMutableArray *)ioArray;

- (id)initWithQuadsWithTexture:(OOTexture *)texture inArray:(OOSkyQuadDesc *)array count:(unsigned)totalCount;

- (void)render;

@end


/*	Textures are global because there is always a sky, but the sky isn't
	replaced very often, so the textures are likely to fall out of the cache.
*/
static OOProbabilisticTextureManager	*sStarTextures;
static OOProbabilisticTextureManager	*sNebulaTextures;


static OOColor *SaturatedColorInRange(OOColor *color1, OOColor *color2);


@interface OOSkyDrawable (OOPrivate) <OOGraphicsResetClient>

- (void)setUpStarsWithColor1:(OOColor *)color1 color2:(OOColor *)color2;
- (void)setUpNebulaeWithColor1:(OOColor *)color1
						color2:(OOColor *)color2
				 clusterFactor:(float)nebulaClusterFactor
						 alpha:(float)nebulaAlpha
						 scale:(float)nebulaScale;
						

- (void)loadStarTextures;
- (void)loadNebulaTextures;

- (void)addQuads:(OOSkyQuadDesc *)quads count:(unsigned)count;

- (void)ensureTexturesLoaded;

@end


@implementation OOSkyDrawable

- (id)initWithColor1:(OOColor *)color1
			  Color2:(OOColor *)color2
		   starCount:(unsigned)starCount
		 nebulaCount:(unsigned)nebulaCount
	   clusterFactor:(float)nebulaClusterFactor
			   alpha:(float)nebulaAlpha
			   scale:(float)nebulaScale
{
	NSAutoreleasePool		*pool = nil;
	
	if (!sInited)
	{
		sInited = YES;
		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"sky-render-inset-coords"])
		{
			sMinTexCoord += 1.0f/128.0f;
			sMaxTexCoord -= 1.0f/128.0f;
		}
	}
	
	self = [super init];
	if (self == nil)  return nil;
	
	_starCount = starCount;
	_nebulaCount = nebulaCount;
	
	pool = [[NSAutoreleasePool alloc] init];
	[self setUpStarsWithColor1:color1 color2:color2];
	
	if (![UNIVERSE reducedDetail])
	{
		[self setUpNebulaeWithColor1:color1
							  color2:color2
					   clusterFactor:nebulaClusterFactor
							   alpha:nebulaAlpha
							   scale:nebulaScale];
	}
	[pool release];
	
	[[OOGraphicsResetManager sharedManager] registerClient:self];
	
	return self;
}


- (void)dealloc
{
	OO_ENTER_OPENGL();
	
	[_quadSets release];
	[[OOGraphicsResetManager sharedManager] unregisterClient:self];
	if (_displayListName != 0)  glDeleteLists(_displayListName, 1);
	
	[super dealloc];
}


- (void)renderOpaqueParts
{
	// While technically translucent, the sky doesn't need to be depth-sorted
	// since it'll be behind everything else anyway.
	
	OO_ENTER_OPENGL();
	
	glDisable(GL_LIGHTING);
	glDisable(GL_DEPTH_TEST);	// don't read the depth buffer
	glDepthMask(GL_FALSE);		// don't write to depth buffer
	glDisable(GL_CULL_FACE);
	glDisable(GL_FOG);
	
	if (_displayListName != 0)
	{
		glCallList(_displayListName);
	}
	else
	{
		// Set up display list
		[self ensureTexturesLoaded];
		_displayListName = glGenLists(1);
		glNewList(_displayListName, GL_COMPILE);
		
		glEnable(GL_TEXTURE_2D);
		glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
		glBlendFunc(GL_ONE, GL_ONE);	// Pure additive blending, ignoring alpha
		
		glDisableClientState(GL_INDEX_ARRAY);
		glDisableClientState(GL_NORMAL_ARRAY);
		glDisableClientState(GL_EDGE_FLAG_ARRAY);
		glEnableClientState(GL_VERTEX_ARRAY);
		glEnableClientState(GL_TEXTURE_COORD_ARRAY);
		glEnableClientState(GL_COLOR_ARRAY);
		
		[_quadSets makeObjectsPerformSelector:@selector(render)];
		
		glDisable(GL_TEXTURE_2D);
		glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);	// Basic alpha blending
		
		glEndList();
	}
	
	// Restore state
	glEnable(GL_CULL_FACE);
	glEnable(GL_DEPTH_TEST);	// read the depth buffer
	glDepthMask(GL_TRUE);		// restore write to depth buffer
	glEnable(GL_LIGHTING);
}


- (BOOL)hasOpaqueParts
{
	return YES;
}


- (GLfloat)maxDrawDistance
{
	return INFINITY;
}

@end


@implementation OOSkyDrawable (OOPrivate)

- (void)setUpStarsWithColor1:(OOColor *)color1 color2:(OOColor *)color2
{
	OOSkyQuadDesc		*quads = NULL, *currQuad = NULL;
	unsigned			i;
	Quaternion			q;
	Vector				vi, vj, vk;
	float				size;
	Vector				middle, offset;
	
	[self loadStarTextures];
	
	quads = malloc(sizeof *quads * _starCount);
	if (quads == NULL)  return;
	
	currQuad = quads;
	for (i = 0; i != _starCount; ++i)
	{
		// Select colour and texture.
		currQuad->color = [color1 blendedColorWithFraction:randf() ofColor:color2];
		currQuad->texture = [sStarTextures selectTexture];	// Not retained, since sStarTextures is never released.
		
		// Select a direction and rotation.
		q = OORandomQuaternion();
		basis_vectors_from_quaternion(q, &vi, &vj, &vk);
		
		// Select scale; calculate centre position and offset to first corner.
		size = (1 + (ranrot_rand() % 6)) * SKY_ELEMENT_SCALE_FACTOR;
		middle = vector_multiply_scalar(vk, BILLBOARD_DEPTH);
		offset = vector_multiply_scalar(vector_add(vi, vj), 0.5f * size);
		
		// Scale the "side" vectors.
		Vector vj2 = vector_multiply_scalar(vj, size);
		Vector vi2 = vector_multiply_scalar(vi, size);
		
		// Set up corners.
		currQuad->corners[0] = vector_subtract(middle, offset);
		currQuad->corners[1] = vector_add(currQuad->corners[0], vj2);
		currQuad->corners[2] = vector_add(currQuad->corners[1], vi2);
		currQuad->corners[3] = vector_add(currQuad->corners[0], vi2);
		
		++currQuad;
	}
	
	[self addQuads:quads count:_starCount];
	free(quads);
}


- (void)setUpNebulaeWithColor1:(OOColor *)color1
						color2:(OOColor *)color2
				 clusterFactor:(float)nebulaClusterFactor
						 alpha:(float)nebulaAlpha
						 scale:(float)nebulaScale
{
	OOSkyQuadDesc		*quads = NULL, *currQuad = NULL;
	unsigned			i, actualCount = 0, clusters = 0;
	OOColor				*color;
	Quaternion			q;
	Vector				vi, vj, vk;
	double				size, r2;
	Vector				middle, offset;
	int					r1;
	
	[self loadNebulaTextures];
	
	quads = malloc(sizeof *quads * _nebulaCount);
	if (quads == NULL)  return;
	
	currQuad = quads;
	for (i = 0; i < _nebulaCount; ++i)
	{
		color = SaturatedColorInRange(color1, color2);
		
		// Select a direction and rotation.
		q = OORandomQuaternion();
		
		// Create a cluster of nebula quads.
		while ((i < _nebulaCount) && (randf() < nebulaClusterFactor))
		{
			// Select size.
			r1 = 1 + (ranrot_rand() & 15);
			size = nebulaScale * r1 * SKY_ELEMENT_SCALE_FACTOR;
			
			// Select colour and texture. Smaller nebula quads are dimmer.
			currQuad->color = [color colorWithBrightnessFactor:nebulaAlpha * (0.5f + (float)r1 / 32.0f)];
			currQuad->texture = [sNebulaTextures selectTexture];	// Not retained, since sStarTextures is never released.
			
			// Calculate centre position and offset to first corner.
			basis_vectors_from_quaternion(q, &vi, &vj, &vk);
			middle = vector_multiply_scalar(vk, BILLBOARD_DEPTH);
			offset = vector_multiply_scalar(vector_add(vi, vj), 0.5f * size);
			
			// Rotate vi and vj by a random angle
			r2 = randf() * M_PI * 2.0;
			quaternion_rotate_about_axis(&q, vk, r2);
			vi = vector_right_from_quaternion(q);
			vj = vector_up_from_quaternion(q);
			
			#if 1
			// Scale the "side" vectors.
			vj = vector_multiply_scalar(vj, size);
			vi = vector_multiply_scalar(vi, size);
			
			// Set up corners.
			currQuad->corners[0] = vector_subtract(middle, offset);
			currQuad->corners[1] = vector_add(currQuad->corners[0], vj);
			currQuad->corners[2] = vector_add(currQuad->corners[1], vi);
			currQuad->corners[3] = vector_add(currQuad->corners[0], vi);
			#else
			// Set up corners.
			vj = vector_multiply_scalar(vj, size);
			Vector vi2 = vector_multiply_scalar(vi, size);
			currQuad->corners[0] = vector_subtract(middle, offset);
			currQuad->corners[1] = vector_add(currQuad->corners[0], vj);
			currQuad->corners[2] = vector_add(currQuad->corners[1], vi2);
			currQuad->corners[3] = vector_add(currQuad->corners[0], vi2);
			#endif
			
			// Shuffle direction quat around a bit to spread the cluster out.
			size = NEBULA_SHUFFLE_FACTOR / (nebulaScale * SKY_ELEMENT_SCALE_FACTOR);
			q.x += size * (randf() - 0.5);
			q.y += size * (randf() - 0.5);
			q.z += size * (randf() - 0.5);
			q.w += size * (randf() - 0.5);
			quaternion_normalize(&q);
			
			++i;
			++currQuad;
			++actualCount;
		}
		++clusters;
	}
	
	/*	The above code generates less than _nebulaCount quads, because i is
		incremented once in the outer loop as well as in the inner loop. To
		keep skies looking the same, we leave the bug in and fill in the
		actual generated count here.
	*/
	_nebulaCount = actualCount;
	
	[self addQuads:quads count:_nebulaCount];
	free(quads);
}


- (void)addQuads:(OOSkyQuadDesc *)quads count:(unsigned)count
{
	if (_quadSets == nil)  _quadSets = [[NSMutableArray alloc] init];
	
	[OOSkyQuadSet addQuads:quads count:count toArray:_quadSets];
}


- (void)loadStarTextures
{
	if (sStarTextures == nil)
	{
		sStarTextures = [[OOProbabilisticTextureManager alloc]
							initWithPListName:@"startextures.plist"
									  options:kOOTextureDefaultOptions
								   anisotropy:0.0f
									  lodBias:-0.6f];
		if (sStarTextures == nil)
		{
			[NSException raise:OOLITE_EXCEPTION_DATA_NOT_FOUND format:@"No star textures could be loaded."];
		}
	}
	
	[sStarTextures setSeed:RANROTGetFullSeed()];
	
}


- (void)loadNebulaTextures
{
	if (sNebulaTextures == nil)
	{
		sNebulaTextures = [[OOProbabilisticTextureManager alloc]
							initWithPListName:@"nebulatextures.plist"
									  options:kOOTextureDefaultOptions
								   anisotropy:0.0f
									  lodBias:0.0f];
		if (sNebulaTextures == nil)
		{
			[NSException raise:OOLITE_EXCEPTION_DATA_NOT_FOUND format:@"No nebula textures could be loaded."];
		}
	}
	
	[sNebulaTextures setSeed:RANROTGetFullSeed()];
	
}


- (void)ensureTexturesLoaded
{
	[sStarTextures ensureTexturesLoaded];
	[sNebulaTextures ensureTexturesLoaded];
}


- (void)resetGraphicsState
{
	OO_ENTER_OPENGL();
	
	if (_displayListName != 0)
	{
		glDeleteLists(_displayListName, 1);
		_displayListName = 0;
	}
}

@end


@implementation OOSkyQuadSet

+ (void)addQuads:(OOSkyQuadDesc *)quads count:(unsigned)count toArray:(NSMutableArray *)ioArray
{
	NSMutableSet			*seenTextures = nil;
	OOTexture				*texture = nil;
	OOSkyQuadSet			*quadSet = nil;
	unsigned				i;
	
	// Iterate over all quads.
	seenTextures = [NSMutableSet set];
	for (i = 0; i != count; ++i)
	{
		texture = quads[i].texture;
		
		// If we haven't seen this quad's texture before...
		if (![seenTextures containsObject:texture])
		{
			[seenTextures addObject:texture];
			
			// ...create a quad set for this texture.
			quadSet = [[self alloc] initWithQuadsWithTexture:texture
													 inArray:quads
													   count:count];
			if (quadSet != nil)
			{
				[ioArray addObject:quadSet];
				[quadSet release];
			}
		}
	}
}


- (id)initWithQuadsWithTexture:(OOTexture *)texture inArray:(OOSkyQuadDesc *)array count:(unsigned)totalCount
{
	BOOL					OK = YES;
	unsigned				i, j, vertexCount;
	GLfloat					*pos;
	GLfloat					*tc;
	GLfloat					*col;
	GLfloat					r, g, b;
	size_t					posSize, tcSize, colSize;
	unsigned				count = 0;
	
	self = [super init];
	if (self == nil)  OK = NO;
	
	if (OK)
	{
		// Count the quads in the array using this texture.
		for (i = 0; i != totalCount; ++i)
		{
			if (array[i].texture == texture)  ++_count;
		}
		if (_count == 0)  OK = NO;
	}
	
	if (OK)
	{
		// Allocate arrays.
		vertexCount = _count * 4;
		posSize = sizeof *_positions * vertexCount * kSkyQuadSetPositionEntriesPerVertex;
		tcSize = sizeof *_texCoords * vertexCount * kSkyQuadSetTexCoordEntriesPerVertex;
		colSize = sizeof *_colors * vertexCount * kSkyQuadSetColorEntriesPerVertex;
		
		_positions = malloc(posSize);
		_texCoords = malloc(tcSize);
		_colors = malloc(colSize);
		
		if (_positions == NULL || _texCoords == NULL || _colors == NULL)  OK = NO;
		
		pos = _positions;
		tc = _texCoords;
		col = _colors;
	}
	
	if (OK)
	{
		// Find the matching quads again, and convert them to renderable representation.
		for (i = 0; i != totalCount; ++i)
		{
			if (array[i].texture == texture)
			{
				r = [array[i].color redComponent];
				g = [array[i].color greenComponent];
				b = [array[i].color blueComponent];
				
				// Loop over vertices
				for (j = 0; j != 4; ++j)
				{
					*pos++ = array[i].corners[j].x;
					*pos++ = array[i].corners[j].y;
					*pos++ = array[i].corners[j].z;
					
					// Colour is the same for each vertex
					*col++ = r;
					*col++ = g;
					*col++ = b;
					*col++ = 1.0f;	// Alpha is unused but needs to be there
				}
				
				// Texture co-ordinates are the same for each quad.
				*tc++ = sMinTexCoord;
				*tc++ = sMinTexCoord;
				
				*tc++ = sMaxTexCoord;
				*tc++ = sMinTexCoord;
				
				*tc++ = sMaxTexCoord;
				*tc++ = sMaxTexCoord;
				
				*tc++ = sMinTexCoord;
				*tc++ = sMaxTexCoord;
				
				count++;
			}
		}
		
		_texture = [texture retain];
		OOLog(@"sky.setup", @"Generated quadset with %u quads for texture %@", count, _texture);
	}
	
	if (!OK)
	{
		[self release];
		self = nil;
	}
	
	return self;
}


- (void)dealloc
{
	[_texture release];
	
	if (_positions != NULL)  free(_positions);
	if (_texCoords != NULL)  free(_texCoords);
	if (_colors != NULL)  free(_colors);
	
	[super dealloc];
}


- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p>{%u quads, texture: %@}", [self class], self, _count, _texture];
}


- (void)render
{
	OO_ENTER_OPENGL();
	
	[_texture apply];
	
	glVertexPointer(kSkyQuadSetPositionEntriesPerVertex, GL_FLOAT, 0, _positions);
	glTexCoordPointer(kSkyQuadSetTexCoordEntriesPerVertex, GL_FLOAT, 0, _texCoords);
	glColorPointer(kSkyQuadSetColorEntriesPerVertex, GL_FLOAT, 0, _colors);
	
	glDrawArrays(GL_QUADS, 0, 4 * _count);
}

@end


static OOColor *SaturatedColorInRange(OOColor *color1, OOColor *color2)
{
	OOColor				*color = nil;
	OOCGFloat			hue, saturation, brightness, alpha;
	
	color = [color1 blendedColorWithFraction:randf() ofColor:color2];
	[color getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha];
	
	saturation = 0.5 * saturation + 0.5;	// move saturation up a notch!
	
	/*	NOTE: this changes the hue, because getHue:... produces hue values
		in [0, 360], but colorWithCalibratedHue:... takes hue values in
		[0, 1].
	*/
	return [OOColor colorWithCalibratedHue:hue saturation:saturation brightness:brightness alpha:alpha];
}
