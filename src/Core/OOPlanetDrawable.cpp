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

#include "OOStellarBody.h"


#include "OOPlanetDrawable.h"
#include "OOPlanetData.h"
#include "OOSingleTextureMaterial.h"
#include "OOTexture.h"	// allTextures() destroys oo::Ref<OOTexture>s (bead oo-9ht.99)
#include "OOOpenGL.h"
#include "OOMacroOpenGL.h"
#include "Universe.h"
#include "MyOpenGLView.h"
#include "oofnd/Log.hpp"

#ifndef NDEBUG
#include "Entity.h"
#include "OODebugGLDrawing.h"
#include "OODebugFlags.h"
#endif


#define LOD_GRANULARITY		((float)(kOOPlanetDataLevels - 1))
#define LOD_FACTOR			(1.0 / 4.0)



oo::Ref<OOPlanetDrawable> OOPlanetDrawable::planetWithTextureName(const std::string &textureName, float radius)
{
	oo::Ref<OOPlanetDrawable> result = oo::makeRef<OOPlanetDrawable>();
	result->setTextureName(textureName);
	result->setRadius(radius);

	return result;
}


oo::Ref<OOPlanetDrawable> OOPlanetDrawable::atmosphereWithRadius(float radius)
{
	oo::Ref<OOPlanetDrawable> result = initAsAtmosphere();
	result->setRadius(radius);

	return result;
}


OOPlanetDrawable::OOPlanetDrawable()
{
	{	// [super init] could not fail (amendment oo-lh0x item 3).
		_radius = 1.0f;
		recalculateTransform();
		setLevelOfDetail(0.5f);
	}
}


oo::Ref<OOPlanetDrawable> OOPlanetDrawable::initAsAtmosphere()
{
	oo::Ref<OOPlanetDrawable> self = oo::makeRef<OOPlanetDrawable>();
	{	// -init could not fail.
		self->_isAtmosphere = true;
	}

	return self;
}


// -dealloc's DESTROY(_material) is the member's destructor.


oo::Ref<OOPlanetDrawable> OOPlanetDrawable::copy()
{
	oo::Ref<OOPlanetDrawable> copy = oo::makeRef<OOPlanetDrawable>();	// [[[self class] allocWithZone:zone] init]: the class has no subclass
	copy->setMaterial(material());
	copy->_isAtmosphere = _isAtmosphere;
	copy->_radius = _radius;
	copy->_transform = _transform;
	copy->_lod = _lod;

	return copy;
}


OOMaterial *OOPlanetDrawable::material()
{
	return _material.get();
}


void OOPlanetDrawable::setMaterial(OOMaterial *material)
{
	OOMaterialAutorelease(std::move(_material));	// [_material autorelease]
	_material = oo::Ref<OOMaterial>(material);
}


std::optional<std::string> OOPlanetDrawable::textureName()
{
	OOMaterial *material = _material.get();
	return material != nullptr ? material->name() : std::nullopt;
}


void OOPlanetDrawable::setTextureName(const std::string &textureName)
{
	if (this->textureName() != textureName)
	{
		// {diffuse_map={repeat_s=yes;cube_map=yes};}, as the old-style property list parsed.
		const oo::PList spec(oo::PList::Dict{
			{ "diffuse_map", oo::PList(oo::PList::Dict{ { "repeat_s", oo::PList("yes") }, { "cube_map", oo::PList("yes") } }) } });
		// [_material release], then [[OOSingleTextureMaterial alloc] initWithName:configuration:]:
		// the factory's material (null for none).
		_material = OOSingleTextureMaterial::materialWithName(textureName, spec);
	}
}


float OOPlanetDrawable::radius()
{
	return _radius;
}


void OOPlanetDrawable::setRadius(float radius)
{
	_radius = fabsf(radius);
	recalculateTransform();
}


float OOPlanetDrawable::levelOfDetail()
{
	return (float)_lod / LOD_GRANULARITY;
}


void OOPlanetDrawable::setLevelOfDetail(float lod)
{
	_lod = roundf(OOClamp_0_1_f(lod) * LOD_GRANULARITY);
}


void OOPlanetDrawable::calculateLevelOfDetailForViewDistance(float distance)
{
	BOOL simple = (UNIVERSE != nullptr ? UNIVERSE->reducedDetail() : false);
	float	drawFactor = (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getViewSize() : NSSize{}).width / (simple ? 100.0 : 40.0);
	float	drawRatio2 = drawFactor * _radius / sqrtf(distance); // proportional to size on screen in pixels
	
	float lod = sqrtf(drawRatio2 * LOD_FACTOR);
	if (simple)
	{
		lod -= 0.5f / LOD_GRANULARITY;	// Make LOD transitions earlier.
		lod = OOClamp_0_max_f(lod, (LOD_GRANULARITY - 1) / LOD_GRANULARITY);	// Don't use highest LOD.
	}
	setLevelOfDetail(lod);
}


void OOPlanetDrawable::renderOpaqueParts()
{
	assert(_lod < kOOPlanetDataLevels);

	OOSetOpenGLState(OPENGL_STATE_OPAQUE);
	
	renderCommonParts();

	OOVerifyOpenGLState();

}


void OOPlanetDrawable::renderTranslucentParts()
{
	assert(_lod < kOOPlanetDataLevels);

	// yes, opaque - necessary changes made later
	OOSetOpenGLState(OPENGL_STATE_OPAQUE);
	
	renderCommonParts();

	OOVerifyOpenGLState();

}


void OOPlanetDrawable::renderTranslucentPartsOnOpaquePass()
{
	assert(_lod < kOOPlanetDataLevels);
	
	OO_ENTER_OPENGL();

	// yes, opaque - necessary changes made later
	OOSetOpenGLState(OPENGL_STATE_OPAQUE);
	
	OOGL(glDisable(GL_DEPTH_TEST));
	renderCommonParts();
	OOGL(glEnable(GL_DEPTH_TEST));

	OOVerifyOpenGLState();

}


void OOPlanetDrawable::renderCommonParts()
{
	const OOPlanetDataLevel *data = &kPlanetData[_lod];
	OOMaterial *material = _material.get();	// messages to nil did nothing and answered NO
	
	OO_ENTER_OPENGL();
	
	OOGL(glPushAttrib(GL_ENABLE_BIT | GL_DEPTH_BUFFER_BIT));
	OOGL(glShadeModel(GL_SMOOTH));
	
	if (_isAtmosphere)
	{
		OOGL(glEnable(GL_BLEND));
		OOGL(glDepthMask(GL_FALSE));
	}
	else
	{
		OOGL(glDisable(GL_BLEND));
	}
	
	// Scale the ball.
	OOGLPushModelView();
	OOGLMultModelView(_transform);
	
	if (material != nullptr)  material->apply();
	
	OOGL(glEnable(GL_LIGHTING));
	OOGL(glEnable(GL_TEXTURE_2D));

#if OO_TEXTURE_CUBE_MAP
	if (material != nullptr && material->wantsNormalsAsTextureCoordinates())
	{
		OOGL(glDisable(GL_TEXTURE_2D));
		OOGL(glEnable(GL_TEXTURE_CUBE_MAP));
	}
#endif
	
	OOGL(glDisableClientState(GL_COLOR_ARRAY));
	
	OOGL(glEnableClientState(GL_TEXTURE_COORD_ARRAY));
	
	OOGL(glVertexPointer(3, GL_FLOAT, 0, kOOPlanetVertices));
	if (material != nullptr && material->wantsNormalsAsTextureCoordinates())
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
	if ((UNIVERSE != nullptr ? UNIVERSE->getWireframeGraphics() : false))
	{
		OODebugDrawBasisAtOrigin(1.5);
	}
#endif

#if OO_TEXTURE_CUBE_MAP
	if (material != nullptr && material->wantsNormalsAsTextureCoordinates())
	{
		OOGL(glEnable(GL_TEXTURE_2D));
		OOGL(glDisable(GL_TEXTURE_CUBE_MAP));
	}
#endif

	
	OOGLPopModelView();
#ifndef NDEBUG
	if (gDebugFlags & DEBUG_DRAW_NORMALS)  debugDrawNormals();
#endif
	
	OOMaterial::applyNone();
	OOGL(glPopAttrib());
	
	OOGL(glDisableClientState(GL_TEXTURE_COORD_ARRAY));
	
}


bool OOPlanetDrawable::hasOpaqueParts()
{
	return !_isAtmosphere;
}


bool OOPlanetDrawable::hasTranslucentParts()
{
	return _isAtmosphere;
}


GLfloat OOPlanetDrawable::collisionRadius()
{
	return _radius;
}


GLfloat OOPlanetDrawable::maxDrawDistance()
{
	// FIXME
	return INFINITY;
}


BoundingBox OOPlanetDrawable::boundingBox()
{
	return (BoundingBox){{ -_radius, -_radius, -_radius }, { _radius, _radius, _radius }};
}


void OOPlanetDrawable::setBindingTarget(Entity *target)
{
	if (OOMaterial *material = _material.get())  material->setBindingTarget(target);
}


void OOPlanetDrawable::dumpSelfState()
{
	OODrawable::dumpSelfState();
	OO_LOG("dumpState.planetDrawable", "radius: {:g}", radius());
	OO_LOG("dumpState.planetDrawable", "LOD: {:g}", levelOfDetail());
}


void OOPlanetDrawable::recalculateTransform()
{
	_transform = OOMatrixForScaleUniform(_radius);
}


#ifndef NDEBUG

void OOPlanetDrawable::debugDrawNormals()
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


std::vector<oo::Ref<OOTexture>> OOPlanetDrawable::allTextures()
{
	OOMaterial *material = this->material();
	return material != nullptr ? material->allTextures() : std::vector<oo::Ref<OOTexture>>();
}

#endif

