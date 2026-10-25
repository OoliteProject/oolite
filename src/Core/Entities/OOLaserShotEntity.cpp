/*

OOLaserShotEntity.m


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

#include "OOLaserShotEntity.h"
#include "Universe.h"
#include "ShipEntity.h"
#include "OOMacroOpenGL.h"

#include "OOTexture.h"
#include "OOGraphicsResetManager.h"

#include "MyOpenGLView.h"

#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"


#define kLaserDuration		(0.09)	// seconds

// Default colour
#define kLaserRed			(1.0f)
#define kLaserGreen			(0.0f)
#define kLaserBlue			(0.0f)

// Brightness - set to 1.0 for legacy laser appearance
#define kLaserBrightness	(5.0f)

// Constant alpha
#define kLaserAlpha			(0.45f / kLaserBrightness)

#define kLaserCoreWidth		(0.4f)
#define kLaserFlareWidth		(1.8f)
#define kLaserHalfWidth		(3.6f)

static OOTexture *sShotTexture = nil;
static OOTexture *sShotTexture2 = nil;


namespace {

// The shot textures' graphics reset client, which the facade class was until bead oo-9ht.78
// (ADR-0056 amendment oo-jpd8 item 3): registered once, with the textures, and never destroyed.
class ShotTextureResetClient : public OOGraphicsResetClient
{
public:
	void resetGraphicsState() override  { OOLaserShotEntity::resetGraphicsState(); }
};

}	// namespace


void OOLaserShotEntity::initLaserFromShip(::ShipEntity *srcEntity, OOWeaponFacing direction, Vector offset)
{
	// [super init] could not fail: the constructor ran Entity's -init body.

	::ShipEntity			*ship = oo::ToShip((srcEntity != nullptr ? srcEntity->rootShipEntity() : (Entity *)nullptr));
	Vector				middle = OOBoundingBoxCenter((srcEntity != nullptr ? srcEntity->getBoundingBox() : BoundingBox{}));

	OOCParameterAssert((srcEntity != nullptr ? srcEntity->getIsShip() : false) && (ship != nullptr ? ship->getIsShip() : false));

	setStatus(STATUS_EFFECT);

	if (ship == srcEntity)
	{
		// main laser offset
		setPosition(HPvector_add((ship != nullptr ? ship->getPosition() : HPVector{}), vectorToHPVector(OOVectorMultiplyMatrix(offset, (ship != nullptr ? ship->drawRotationMatrix() : OOMatrix{})))));
	}
	else
	{
		// subentity laser
		setPosition((srcEntity != nullptr ? srcEntity->absolutePositionForSubentityOffset(vectorToHPVector(middle)) : HPVector{}));
	}

	Quaternion q = kIdentityQuaternion;
	Vector q_up = vector_up_from_quaternion(q);
	Quaternion q0 = (ship != nullptr ? ship->normalOrientation() : Quaternion{});
	velocity = vector_multiply_scalar(vector_forward_from_quaternion(q0), (ship != nullptr ? ship->getFlightSpeed() : 0.0f));

	switch (direction)
	{
		case WEAPON_FACING_NONE:
		case WEAPON_FACING_FORWARD:
			break;

		case WEAPON_FACING_AFT:
			quaternion_rotate_about_axis(&q, q_up, M_PI);
			break;

		case WEAPON_FACING_PORT:
			quaternion_rotate_about_axis(&q, q_up, M_PI/2.0);
			break;

		case WEAPON_FACING_STARBOARD:
			quaternion_rotate_about_axis(&q, q_up, -M_PI/2.0);
			break;
	}

	setOrientation(quaternion_multiply(q,q0));
	setOwner(ship);
	setRange((srcEntity != nullptr ? srcEntity->getWeaponRange() : 0.0f));
	_lifetime = kLaserDuration;

	_color[0] = kLaserRed/3.0;
	_color[1] = kLaserGreen/3.0;
	_color[2] = kLaserBlue/3.0;
	_color[3] = kLaserAlpha;

	_offset = (ship == srcEntity) ? offset : middle;
	_relOrientation = q;
}


oo::Ref<OOLaserShotEntity> OOLaserShotEntity::laserFromShip(::ShipEntity *ship, OOWeaponFacing direction, Vector offset)
{
	const oo::Ref<OOLaserShotEntity> shot = oo::makeRef<OOLaserShotEntity>();
	shot->initLaserFromShip(ship, direction, offset);
	return shot;
}


// -dealloc set the colour to nil (zeroing it) on the way out; nothing read it after.


std::optional<std::string> OOLaserShotEntity::descriptionComponents() const
{
	// The getter read this ivar.
	return oo::str::format("ttl: %.3fs - %s orientation %s", _lifetime, Entity::descriptionComponents().value_or("(null)").c_str(), QuaternionDescription(orientation).c_str());
}


void OOLaserShotEntity::setColor(OOColor *color)
{
	// Messages to a nil colour answered 0.
	_color[0] = kLaserBrightness * (color != nullptr ? color->redComponent() : 0.0f)/3.0;
	_color[1] = kLaserBrightness * (color != nullptr ? color->greenComponent() : 0.0f)/3.0;
	_color[2] = kLaserBrightness * (color != nullptr ? color->blueComponent() : 0.0f)/3.0;
	// Ignore alpha; _color[3] is constant.
}


void OOLaserShotEntity::setRange(GLfloat range)
{
	_range = range;
	setCollisionRadius(range);
}


void OOLaserShotEntity::update(OOTimeDelta delta_t)
{
	Entity::update(delta_t);
	_lifetime -= delta_t;
	::ShipEntity		*ship = oo::ToShip(owner());

	if ((ship != nullptr ? ship->getIsPlayer() : false))
	{
		/*
			Reposition this shot accurately. This overrides integration over
			velocity in Entity::update(), which is considered sufficient for
			NPC ships.
		*/
		setPosition(HPvector_add((ship != nullptr ? ship->getPosition() : HPVector{}), vectorToHPVector(OOVectorMultiplyMatrix(_offset, (ship != nullptr ? ship->drawRotationMatrix() : OOMatrix{})))));
		setOrientation(quaternion_multiply(_relOrientation, (ship != nullptr ? ship->normalOrientation() : Quaternion{})));
	}

	if (_lifetime < 0)
	{
		if (UNIVERSE != nullptr)  UNIVERSE->removeEntity(this);
	}
}


static const GLfloat kLaserVertices[] = 
{
	 1.0f, 0.0f, 0.0f,
	 1.0f, 0.0f, 1.0f,
	 -1.0f, 0.0f, 1.0f,
	 -1.0f, 0.0f, 0.0f,
	
	 0.0f,  1.0f, 0.0f,
	 0.0f,  1.0f, 1.0f,
	 0.0f, -1.0f, 1.0f,
	 0.0f, -1.0f, 0.0f,
};


void OOLaserShotEntity::drawImmediate(bool /*immediate*/, bool translucent)
{
	if (!translucent || (UNIVERSE != nullptr ? UNIVERSE->breakPatternHide() : false))  return;

	OO_ENTER_OPENGL();
	OOSetOpenGLState(OPENGL_STATE_ADDITIVE_BLENDING);
	

	/*	FIXME: spread damage across the lifetime of the shot,
		hurting whatever is hit in a given frame.
		-- Ahruman 2011-01-31
	*/
	OOGL(glEnableClientState(GL_TEXTURE_COORD_ARRAY));
	OOGL(glEnable(GL_TEXTURE_2D));
	OOGLPushModelView();
	
	OOGLScaleModelView(make_vector(kLaserHalfWidth, kLaserHalfWidth, _range));
	if (OOTexture *shot = texture1())  shot->apply();	// a message to nil did nothing
	GLfloat s = sinf((UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0));
	GLfloat phase = s*(_range/200.0f);
	GLfloat phase2 = (1.0f+s)*(_range/200.0f);
	GLfloat phase3 = -s*(_range/500.0f);
	GLfloat phase4 = -(1.0f+s)*(_range/500.0f);

	GLfloat laserTexCoords[] = 
		{
			0.0f, phase,	0.0f, phase2,	1.0f, phase2,	1.0f, phase,

			0.0f, phase,	0.0f, phase2,	1.0f, phase2,	1.0f, phase
		};
	GLfloat laserTexCoords2[] = 
		{
			0.0f, phase3,	0.0f, phase4,	1.0f, phase4,	1.0f, phase3,

			0.0f, phase3,	0.0f, phase4,	1.0f, phase4,	1.0f, phase3
		};
	
	OOGL(glColor4fv(_color));
	glVertexPointer(3, GL_FLOAT, 0, kLaserVertices);
	glTexCoordPointer(2, GL_FLOAT, 0, laserTexCoords2);
	glDrawArrays(GL_QUADS, 0, 8);
	
	OOGLScaleModelView(make_vector(kLaserCoreWidth / kLaserHalfWidth, kLaserCoreWidth / kLaserHalfWidth, 1.0));
	OOGL(glColor4f(kLaserBrightness,kLaserBrightness,kLaserBrightness,0.9));
	glDrawArrays(GL_QUADS, 0, 8);

	if (OOTexture *shot = texture2())  shot->apply();	// a message to nil did nothing
	OOGLScaleModelView(make_vector(kLaserFlareWidth / kLaserCoreWidth, kLaserFlareWidth / kLaserCoreWidth, 1.0));
	OOGL(glColor4f(_color[0],_color[1],_color[2],0.9));
	glTexCoordPointer(2, GL_FLOAT, 0, laserTexCoords);
	glDrawArrays(GL_QUADS, 0, 8);
	
	OOGLPopModelView();
	OOGL(glDisableClientState(GL_TEXTURE_COORD_ARRAY));
	OOGL(glDisable(GL_TEXTURE_2D));
	
	OOVerifyOpenGLState();
	cxx_OOCheckOpenGLErrors([&]() -> std::string { return "OOLaserShotEntity after drawing " + oo::EntityDescription(this); });
}


bool OOLaserShotEntity::isEffect()
{
	return YES;
}


bool OOLaserShotEntity::canCollide()
{
	return NO;
}

OOTexture *OOLaserShotEntity::texture1()
{
	return OOLaserShotEntity::outerTexture();
}


OOTexture *OOLaserShotEntity::texture2()
{
	return OOLaserShotEntity::innerTexture();
}


void OOLaserShotEntity::setUpTexture()
{
	if (sShotTexture == nil)
	{
		sShotTexture = OOTexture::textureWithName("oolite-laser-blur.png", "Textures", kOOTextureMinFilterMipMap | kOOTextureMagFilterLinear | kOOTextureAlphaMask | kOOTextureRepeatT, kOOTextureDefaultAnisotropy / 2.0, 0.0).leakRef();
		OOGraphicsResetManager::sharedManager()->registerCxxClient(new ShotTextureResetClient);

		sShotTexture2 = OOTexture::textureWithName("oolite-laser-blur2.png", "Textures", kOOTextureMinFilterMipMap | kOOTextureMagFilterLinear | kOOTextureAlphaMask | kOOTextureRepeatT, kOOTextureDefaultAnisotropy / 2.0, 0.0).leakRef();
	}
}


OOTexture *OOLaserShotEntity::innerTexture()
{
	if (sShotTexture2 == nil)  setUpTexture();
	return sShotTexture2;
}


OOTexture *OOLaserShotEntity::outerTexture()
{
	if (sShotTexture == nil)  setUpTexture();
	return sShotTexture;
}


void OOLaserShotEntity::resetGraphicsState()
{
	oo::release(sShotTexture);
	sShotTexture = nullptr;
	oo::release(sShotTexture2);
	sShotTexture2 = nullptr;
}

