/*

OOLightParticleEntity.m


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

#include "OOLightParticleEntity.h"
#include "Universe.h"
#include "PlayerEntity.h"
#include "OOTexture.h"
#include "OOColor.h"
#include "OOFunctionAttributes.h"
#include "OOMacroOpenGL.h"
#include "OOGraphicsResetManager.h"
#include "MyOpenGLView.h"


#define PARTICLE_DISTANCE_SCALE_LOW		12.0
#define PARTICLE_DISTANCE_SCALE_HIGH	36.0


static OOTexture *sBlobTexture = nil;


namespace {

// The texture's graphics reset client, which the facade class was until bead oo-9ht.23 (ADR-0056
// amendment oo-jpd8 item 3, as OOLaserShotEntity's): registered once, with the texture, and never
// destroyed.
class BlobTextureResetClient : public OOGraphicsResetClient
{
public:
	void resetGraphicsState() override  { OOLightParticleEntity::resetGraphicsState(); }
};

}	// namespace


void OOLightParticleEntity::initWithDiameter(float diameter)
{
	// [super init] could not fail: the constructor ran Entity's -init body.
	{
		_diameter = diameter;
		no_draw_distance = pow(diameter / 2.0, M_SQRT2) * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR;
		no_draw_distance *= (UNIVERSE != nullptr ? UNIVERSE->reducedDetail() : false) ? PARTICLE_DISTANCE_SCALE_LOW : PARTICLE_DISTANCE_SCALE_HIGH;
		
		_colorComponents[0] = 1.0f;
		_colorComponents[1] = 1.0f;
		_colorComponents[2] = 1.0f;
		_colorComponents[3] = 1.0f;
		
		setScanClass(CLASS_NO_DRAW);
		setStatus(STATUS_EFFECT);
	}
}


float OOLightParticleEntity::diameter()
{
	return _diameter;
}


void OOLightParticleEntity::setDiameter(float diameter)
{
	_diameter = diameter;
}


void OOLightParticleEntity::setColor(OOColor *color)
{
	// A message to a nil colour did nothing.
	if (color != nullptr)  color->getRed(&_colorComponents[0], &_colorComponents[1], &_colorComponents[2], &_colorComponents[3]);
}


void OOLightParticleEntity::setColor(OOColor *color, GLfloat alpha)
{
	setColor(color);
	_colorComponents[3] = alpha;
}


void OOLightParticleEntity::drawSubEntityImmediate(bool immediate, bool translucent)
{
	if (!translucent)  return;
	
	/*	TODO: someone will inevitably build a ship so big that individual
		zero_distances are necessary for flashers, if they haven't already.
		-- Ahruman 2009-09-20
	*/
	Entity *ownerPart = oo::LiveOwner(this);	// -owner's C++ entity (bead oo-zwnvp)
	cam_zero_distance = ownerPart != nullptr ? ownerPart->camZeroDistance() : 0;	// a message to nil answered 0
	if (no_draw_distance <= cam_zero_distance)  return;
	
	Entity *father = ownerPart;
	Entity *last = nullptr;
	HPVector abspos = position;

	while (father != nullptr && father != last)	// && father != (Entity *)NO_TARGET, which is nil: NO_TARGET is 0
	{
		OOMatrix rM = father->drawRotationMatrix();
		abspos = HPvector_add(OOHPVectorMultiplyMatrix(abspos, rM), father->getPosition());
		last = father;
		
		if (!oo::EntityIsSubEntity(father))  break;
		father = oo::LiveOwner(father);	// [father owner]
	}

	OOMatrix temp_matrix = OOGLPopModelView();
	OOGLPushModelView();

	/* Flashers are drawn using the absolute view matrix */
	OOGLLoadModelView((UNIVERSE != nullptr ? UNIVERSE->getViewMatrix() : OOMatrix{}));
	/* ...modified by the aggregate translation calculated above */
	OOGLTranslateModelView(HPVectorToVector(HPvector_subtract(abspos,(PLAYER != nullptr ? PLAYER->viewpointPosition() : HPVector{}))));	// move to camera-relative position	
	drawImmediate(immediate, translucent);

	OOGLLoadModelView(temp_matrix);
}


void OOLightParticleEntity::drawImmediate(bool /*immediate*/, bool translucent)
{
	if (!translucent) return;
	if ((UNIVERSE != nullptr ? UNIVERSE->breakPatternHide() : false) && !getIsImmuneToBreakPatternHide())
	{
		Entity *father = oo::LiveOwner(this);	// -owner's C++ entity (bead oo-zwnvp)
		while (father != nullptr)	// && father != (Entity *)NO_TARGET, which is nil: NO_TARGET is 0
		{
			if (!oo::EntityIsSubEntity(father))  break;
			father = oo::LiveOwner(father);	// [father owner]
		}
		if (!(father != nullptr && father->getIsImmuneToBreakPatternHide()))	// nil answered NO
		{
			return;
		}
	}
	if (no_draw_distance <= cam_zero_distance)  return;
	
	OO_ENTER_OPENGL();
	OOSetOpenGLState(OPENGL_STATE_ADDITIVE_BLENDING);
	
	OOGL(glPushAttrib(GL_COLOR_BUFFER_BIT | GL_ENABLE_BIT));
	OOGL(glEnable(GL_BLEND));
	OOGL(glBlendFunc(GL_SRC_ALPHA, GL_ONE));
	
	OOGL(glEnable(GL_TEXTURE_2D));
	OOGL(glDepthMask(GL_FALSE));
	
	GLfloat distanceAttenuation = cam_zero_distance / no_draw_distance;
	distanceAttenuation = 1.0 - distanceAttenuation;
	GLfloat components[4] = { _colorComponents[0], _colorComponents[1], _colorComponents[2], _colorComponents[3] * distanceAttenuation };
	OOGL(glColor4fv(components));
	
	OOGL(glTexEnvfv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_COLOR, components));
	OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_BLEND));
	
	OOViewID viewDir = (UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{});
	if (viewDir != VIEW_GUI_DISPLAY)  OOGLMultModelView((PLAYER != nullptr ? PLAYER->drawRotationMatrix() : OOMatrix{}));
	if (OOTexture *blob = texture())  blob->apply();	// a message to nil did nothing
	
	/*	NOTE: nominal diameter is actual radius, because of the black border
		in the texture. However, the offset along the view axis is not
		affected by the border and needs to be scaled.
		-- Ahruman 2009-12-20
	*/
	float viewOffset = _diameter * 0.5f;
	
	OOGLBEGIN(GL_QUADS);
	switch (viewDir)
	{
		case VIEW_FORWARD:
		case VIEW_GUI_DISPLAY:
			glTexCoord2f(0.0, 1.0);
			glVertex3f(-_diameter, -_diameter, -viewOffset);
			
			glTexCoord2f(1.0, 1.0);
			glVertex3f(_diameter, -_diameter, -viewOffset);
			
			glTexCoord2f(1.0, 0.0);
			glVertex3f(_diameter, _diameter, -viewOffset);
			
			glTexCoord2f(0.0, 0.0);
			glVertex3f(-_diameter, _diameter, -viewOffset);
			break;
			
		case VIEW_AFT:
			glTexCoord2f(0.0, 1.0);
			glVertex3f(_diameter, -_diameter, viewOffset);
			
			glTexCoord2f(1.0, 1.0);
			glVertex3f(-_diameter, -_diameter, viewOffset);
			
			glTexCoord2f(1.0, 0.0);
			glVertex3f(-_diameter, _diameter, viewOffset);
			
			glTexCoord2f(0.0, 0.0);
			glVertex3f(_diameter, _diameter, viewOffset);
			break;
			
		case VIEW_STARBOARD:
			glTexCoord2f(0.0, 1.0);
			glVertex3f(-viewOffset, -_diameter, _diameter);
			
			glTexCoord2f(1.0, 1.0);
			glVertex3f(-viewOffset, -_diameter, -_diameter);
			
			glTexCoord2f(1.0, 0.0);
			glVertex3f(-viewOffset, _diameter, -_diameter);
			
			glTexCoord2f(0.0, 0.0);
			glVertex3f(-viewOffset, _diameter, _diameter);
			break;
			
		case VIEW_PORT:
			glTexCoord2f(0.0, 1.0);
			glVertex3f(viewOffset, -_diameter, -_diameter);
			
			glTexCoord2f(1.0, 1.0);
			glVertex3f(viewOffset, -_diameter, _diameter);
			
			glTexCoord2f(1.0, 0.0);
			glVertex3f(viewOffset, _diameter, _diameter);
			
			glTexCoord2f(0.0, 0.0);
			glVertex3f(viewOffset, _diameter, -_diameter);
			break;
			
		case VIEW_CUSTOM:
			{
				::PlayerEntity *player = PLAYER;
				Vector vi = (player != nullptr ? player->getCustomViewRightVector() : Vector{});		vi.x *= _diameter;	vi.y *= _diameter;	vi.z *= _diameter;
				Vector vj = (player != nullptr ? player->getCustomViewUpVector() : Vector{});		vj.x *= _diameter;	vj.y *= _diameter;	vj.z *= _diameter;
				Vector vk = (player != nullptr ? player->getCustomViewForwardVector() : Vector{});	vk.x *= viewOffset;	vk.y *= viewOffset;	vk.z *= viewOffset;
				glTexCoord2f(0.0, 1.0);
				glVertex3f(-vi.x -vj.x -vk.x, -vi.y -vj.y -vk.y, -vi.z -vj.z -vk.z);
				glTexCoord2f(1.0, 1.0);
				glVertex3f(+vi.x -vj.x -vk.x, +vi.y -vj.y -vk.y, +vi.z -vj.z -vk.z);
				glTexCoord2f(1.0, 0.0);
				glVertex3f(+vi.x +vj.x -vk.x, +vi.y +vj.y -vk.y, +vi.z +vj.z -vk.z);
				glTexCoord2f(0.0, 0.0);
				glVertex3f(-vi.x +vj.x -vk.x, -vi.y +vj.y -vk.y, -vi.z +vj.z -vk.z);
			}
			break;
			
		default:
			glTexCoord2f(0.0, 1.0);
			glVertex3f(-_diameter, -_diameter, -_diameter);
			
			glTexCoord2f(1.0, 1.0);
			glVertex3f(_diameter, -_diameter, -_diameter);
			
			glTexCoord2f(1.0, 0.0);
			glVertex3f(_diameter, _diameter, -_diameter);
			
			glTexCoord2f(0.0, 0.0);
			glVertex3f(-_diameter, _diameter, -_diameter);
			break;
	}
	OOGLEND();
	
	OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE));
	OOGL(glPopAttrib());
	
	OOVerifyOpenGLState();
}


OOTexture *OOLightParticleEntity::texture()
{
	return OOLightParticleEntity::defaultParticleTexture();
}


void OOLightParticleEntity::setUpTexture()
{
	if (sBlobTexture == nil)
	{
		sBlobTexture = OOTexture::textureWithName("oolite-particle-blur.png", "Textures", kOOTextureMinFilterMipMap | kOOTextureMagFilterLinear | kOOTextureAlphaMask, kOOTextureDefaultAnisotropy / 2.0, 0.0).leakRef();
		OOGraphicsResetManager::sharedManager()->registerCxxClient(new BlobTextureResetClient);
	}
}


OOTexture *OOLightParticleEntity::defaultParticleTexture()
{
	if (sBlobTexture == nil)  setUpTexture();
	return sBlobTexture;
}


void OOLightParticleEntity::resetGraphicsState()
{
	oo::release(sBlobTexture);
	sBlobTexture = nullptr;
}


bool OOLightParticleEntity::isEffect()
{
	return YES;
}


bool OOLightParticleEntity::canCollide()
{
	return NO;
}



#ifndef NDEBUG
std::vector<oo::Ref<OOTexture>> OOLightParticleEntity::allTextures()
{
	std::vector<oo::Ref<OOTexture>> result;
	result.emplace_back(texture());
	return result;
}
#endif

