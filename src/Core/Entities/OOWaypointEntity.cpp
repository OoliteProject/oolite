/*

OOWaypointEntity.m

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

#include "OOWaypointEntity.h"
#include "Entity.h"
#include "OOStringExpander.h"
#include "Universe.h"
#include "PlayerEntity.h"
#include "OOPolygonSprite.h"
#include "HeadUpDisplay.h"
#include "OOOpenGL.h"
#include "OOMacroOpenGL.h"
#include "OOPListGameTypes.h"
#include "OOJSWaypoint.h"

#include "oofnd/PListGet.hpp"
#include "oofnd/String.hpp"

#define OOWAYPOINT_KEY_POSITION		"position"
#define OOWAYPOINT_KEY_ORIENTATION	"orientation"
#define OOWAYPOINT_KEY_SIZE			"size"
#define OOWAYPOINT_KEY_CODE			"beaconCode"
#define OOWAYPOINT_KEY_LABEL		"beaconLabel"


oo::Ref<OOWaypointEntity> OOWaypointEntity::waypointWithDictionary(const oo::PList &info)
{
	const oo::Ref<OOWaypointEntity> waypoint = oo::makeRef<OOWaypointEntity>();
	waypoint->initWithDictionary(info);
	return waypoint;
}

void OOWaypointEntity::initWithDictionary(const oo::PList &info)
{
	// self = [super init]: the constructor ran Entity's -init body.

	// A nil dictionary read zero-filled values and nil strings (messaging nil), not the defaults.
	oriented = YES;
	position = info ? OOHPVectorFromPList(info.find(OOWAYPOINT_KEY_POSITION), kZeroHPVector) : kZeroHPVector;
	Quaternion q = info ? OOQuaternionFromPList(info.find(OOWAYPOINT_KEY_ORIENTATION), kIdentityQuaternion) : (Quaternion){ 0, 0, 0, 0 };
	setOrientation(q);
	setSize(info.get<oo::NonNegative<float>>(OOWAYPOINT_KEY_SIZE, 1000.0));
	setBeaconCode(info ? std::optional<std::string>(info.get<std::string>(OOWAYPOINT_KEY_CODE, "W")) : std::nullopt);
	setBeaconLabel(info ? std::optional<std::string>(info.get<std::string>(OOWAYPOINT_KEY_LABEL, "Waypoint")) : std::nullopt);
	
	setStatus(STATUS_EFFECT);
	setScanClass(CLASS_NO_DRAW);
}


// override
void OOWaypointEntity::setOrientation(Quaternion q)
{
	if (quaternion_equal(q,kZeroQuaternion)) {
		q = kIdentityQuaternion;
		oriented = NO;
	} else {
		oriented = YES;
	}
	Entity::setOrientation(q);
}


bool OOWaypointEntity::getOriented()
{
	return oriented;
}


OOScalar OOWaypointEntity::size()
{
	return _size;
}


void OOWaypointEntity::setSize(OOScalar newSize)
{
	if (newSize > 0)
	{
		_size = newSize;
		no_draw_distance = newSize * newSize * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR * 2;
	}
}



bool OOWaypointEntity::isEffect()
{
	return YES;
}


bool OOWaypointEntity::isWaypoint()
{
	return YES;
}


void OOWaypointEntity::drawImmediate(bool /*immediate*/, bool translucent)
{
	if (!translucent || no_draw_distance < cam_zero_distance)
	{
		return;
	}

	if (!(PLAYER != nullptr ? PLAYER->hasEquipmentItemProviding("EQ_ADVANCED_COMPASS") : false))
	{
		return;
	}

	int8_t i,j,k;

	GLfloat a = 0.75;
	if ((PLAYER != nullptr ? PLAYER->getCompassTargetEntity() : nullptr) != this)
	{
		a *= 0.25;
	}
	if (cam_zero_distance > _size * _size)
	{
		// dim out as gets further away; 2-D HUD display more
		// important at long range
		a -=  0.004f*(sqrtf(cam_zero_distance) / _size);
	}
	if (a < 0.01f)
	{
		return;
	}

	GLfloat s0 = _size;
	GLfloat s1 = _size * 0.75f;

	OO_ENTER_OPENGL();
	OOSetOpenGLState(OPENGL_STATE_TRANSLUCENT_PASS);
	OOGL(glEnable(GL_BLEND));
	GLScaledLineWidth(1.0);

	OOGL(glColor4f(0.0, 0.0, 1.0, a));
	OOGLBEGIN(GL_LINES);
	for (i = -1; i <= 1; i+=2)
	{
		for (j = -1; j <= 1; j+=2)
		{
			for (k = -1; k <= 1; k+=2)
			{
				glVertex3f(i*s0,j*s0,k*s1);	glVertex3f(i*s0,j*s1,k*s0);
				glVertex3f(i*s0,j*s1,k*s0);	glVertex3f(i*s1,j*s0,k*s0);
				glVertex3f(i*s1,j*s0,k*s0);	glVertex3f(i*s0,j*s0,k*s1);
			}
		}
	}
	if (oriented)
	{
		while (s1 > 20.0f)
		{
			glVertex3f(-20.0,0,-s1-20.0f);	glVertex3f(0,0,-s1);
			glVertex3f(20.0,0,-s1-20.0f);	glVertex3f(0,0,-s1);
			glVertex3f(-20.0,0,s1-20.0f);	glVertex3f(0,0,s1);
			glVertex3f(20.0,0,s1-20.0f);	glVertex3f(0,0,s1);
			s1 *= 0.5;
		}
	}
	OOGLEND();

	OOGL(glDisable(GL_BLEND));
	OOVerifyOpenGLState();
}


/* beacons */

OOComparisonResult OOWaypointEntity::compareBeaconCodeWith(Entity *other)
{
	return (OOComparisonResult)oo::str::caseInsensitiveCompare(beaconCode().value_or(""), oo::BeaconCode(other).value_or(""));
}


std::optional<std::string> OOWaypointEntity::beaconCode()
{
	return _beaconCode;
}


// bcode: optional string; empty is treated as none. The Foundation version compared the new string with the
// old by pointer, so any new string (every string this class hands out is new) replaced it.
void OOWaypointEntity::setBeaconCode(const std::optional<std::string> &bcode)
{
	std::optional<std::string> code = bcode;
	if (code.has_value() && code->empty())  code.reset();

	if (code.has_value() || _beaconCode.has_value())
	{
		_beaconCode = code;

		_beaconDrawable = nullptr;
	}
	// if not blanking code and label is currently blank, default label to code
	if (code.has_value() && (!_beaconLabel.has_value() || _beaconLabel->empty()))
	{
		setBeaconLabel(code);
	}

}


std::optional<std::string> OOWaypointEntity::beaconLabel()
{
	return _beaconLabel;
}


void OOWaypointEntity::setBeaconLabel(const std::optional<std::string> &blabel)
{
	std::optional<std::string> label = blabel;
	if (label.has_value() && label->empty())  label.reset();

	if (label.has_value() || _beaconLabel.has_value())
	{
		_beaconLabel = label.has_value() ? cxx_OOExpand(*label) : std::nullopt;
	}
}


bool OOWaypointEntity::isBeacon()
{
	return beaconCode().has_value();
}


OOHUDBeaconIcon *OOWaypointEntity::beaconDrawable()
{
	if (_beaconDrawable == nullptr)
	{
		const std::u16string	beaconCode = oo::utf8ToUtf16(_beaconCode.value_or(std::string()));
		NSUInteger	length = beaconCode.size();	// -length: UTF-16 units

		if (length > 1)
		{
			const oo::PList *iconEntry = UNIVERSE->descriptions()->find(*_beaconCode);
			const oo::PList iconData = (iconEntry != nullptr) ? *iconEntry : oo::PList();
			if (iconData.isArray())  _beaconDrawable = OOPolygonSprite::initWithDataArray(iconData, 0.5, *_beaconCode);	// null where it answered nil
		}

		if (_beaconDrawable == nullptr)
		{
			if (length > 0)  _beaconDrawable = oo::makeRef<OOHUDBeaconCodeIcon>(oo::utf16ToUtf8(beaconCode.substr(0, 1)));	// -substringToIndex:1
			else  _beaconDrawable = oo::makeRef<OOHUDBeaconCodeIcon>(std::string());
		}
	}
	
	return _beaconDrawable.get();
}


Entity *OOWaypointEntity::prevBeacon()
{
	return oo::LiveEntity(_prevBeacon);
}


Entity *OOWaypointEntity::nextBeacon()
{
	return oo::LiveEntity(_nextBeacon);
}


void OOWaypointEntity::setPrevBeacon(Entity *beaconShip)
{
	if (beaconShip != prevBeacon())
	{
		_prevBeacon = oo::WeakRef<Entity>(beaconShip);
	}
}


void OOWaypointEntity::setNextBeacon(Entity *beaconShip)
{
	if (beaconShip != nextBeacon())
	{
		_nextBeacon = oo::WeakRef<Entity>(beaconShip);
	}
}


bool OOWaypointEntity::isJammingScanning() 
{
	return NO;
}

// The binding's category, which the facade forwarded (bead oo-9ht.50) until bead oo-9ht.108.
void OOWaypointEntity::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)	{ ::OOJSWaypointGetJSClass(outClass, outPrototype); }
std::optional<std::string> OOWaypointEntity::jsClassName()										{ return ::OOJSWaypointJSClassName(); }
bool OOWaypointEntity::isVisibleToScripts()														{ return ::OOJSWaypointIsVisibleToScripts(); }
