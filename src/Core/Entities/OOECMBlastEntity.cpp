/*

OOECMBlastEntity.m

C++20 since bead oo-ryhi (see OOECMBlastEntity.h). The bodies are the Objective-C ones: a message
to self is a member call, the universe is handed the C++ entity (bead oo-9ht.39.26) and the scripts the entity's Objective-C
object, oo::ToObjC(this). The ship stays its Objective-C object (amendment oo-bj8 item 4).

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

#include "OOECMBlastEntity.h"
#include "Universe.h"
#include "ShipEntity.h"
#include "OOEntityFilterPredicate.h"
#include "OOJavaScriptEngine.h"


// NOTE: these values are documented for scripting, be careful about changing them.
#define ECM_EFFECT_DURATION		2.0
#define ECM_PULSE_COUNT			4
#define ECM_PULSE_INTERVAL		(ECM_EFFECT_DURATION / (double)ECM_PULSE_COUNT)

#define ECM_DEBUG_DRAW			0


#if ECM_DEBUG_DRAW
#include "OODebugGLDrawing.h"
#endif


// The part of -initFromShip: that could not fail. Virtual members are called as the base's own
// during construction (amendment oo-bj8 item 6).
OOECMBlastEntity::OOECMBlastEntity(ShipEntity *ship)
{
	_blastsRemaining = ECM_PULSE_COUNT;
	_nextBlast = ECM_PULSE_INTERVAL;
	_ship = oo::WeakRef<Entity>(ship);
	
	Entity::setPosition((ship != nullptr ? ship->getPosition() : HPVector{}));
	
	Entity::setStatus(STATUS_EFFECT);
	setScanClass(CLASS_NO_DRAW);
}


oo::Ref<OOECMBlastEntity> OOECMBlastEntity::initFromShip(ShipEntity *ship)
{
	if (ship == nil)
	{
		return nullptr;
	}
	return oo::adopt(new OOECMBlastEntity(ship));
}


void OOECMBlastEntity::update(OOTimeDelta delta_t)
{
	_nextBlast -= delta_t;
	ShipEntity		*ship = oo::ToShip(_ship.get());
	BOOL 			validShip = (ship != nil) && ((ship != nullptr ? ship->status() : OOEntityStatus{}) != STATUS_DEAD);
	
	if (_nextBlast <= 0.0 && validShip)
	{
		// Do ECM stuff.
		double radius = OOClamp_0_1_d((double)(ECM_PULSE_COUNT - _blastsRemaining + 1) * 1.0 / (double)ECM_PULSE_COUNT);
		radius *= SCANNER_MAX_RANGE;
		_blastsRemaining--;
		
		const std::vector<oo::EntityHold> targets = (UNIVERSE != nullptr ? UNIVERSE->findEntitiesMatchingPredicate(IsShipPredicate, NULL, radius, this) : std::vector<oo::EntityHold>());
		NSUInteger i, count = targets.size();
		if (count > 0)
		{
			ooscript::Context context = OOJSAcquireContext();
			ooscript::Value ecmPulsesRemaining = ooscript::int32Value(_blastsRemaining);
			ooscript::Value whomVal = OOJSValueFromCxxObject(context, ship);
			
			for (i = 0; i < count; i++)
			{
				ShipEntity *target = oo::ToShip(targets[i].get());
				ShipScriptEvent(context, target, "shipHitByECM", ecmPulsesRemaining, whomVal);
				if (target != nullptr)  target->reactToAIMessage("ECM", std::nullopt);
				if (target != nullptr)  target->noticeECM();
			}
			
			OOJSRelinquishContext(context);
		}
		_nextBlast += ECM_PULSE_INTERVAL;
	}
	
	if (_blastsRemaining == 0 || !validShip)  { if (UNIVERSE != nullptr)  UNIVERSE->removeEntity(this); }
}


void OOECMBlastEntity::drawImmediate(bool /*immediate*/, bool /*translucent*/)
{
#if ECM_DEBUG_DRAW && OO_DEBUG
	OODebugDrawPoint(kZeroVector, OOColor::cyanColor().get());
#endif
	// Else do nothing, we're invisible!
}


bool OOECMBlastEntity::isECMBlast()
{
	return true;
}
