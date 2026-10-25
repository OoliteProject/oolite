/*

OOExhaustPlumeEntity.h


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

#pragma once

#include "ShipEntity.h"
#include "OOTexture.h"

#include "oofnd/StdLib.hpp"

typedef struct
{
	double					timeframe;		// universal time for this frame
	HPVector					position;
	Quaternion				orientation;
	Vector					k;				// direction vectors
} Frame;


enum
{
	kExhaustFrameCount = 16
};


/*	C++ only since bead oo-9ht.110 deleted its Objective-C façade (proposed ADR-0056 amendments
	oo-9ht.12 and oo-9ht.107): the ships make it with exhaustForShip() and hand it to Objective-C
	with oo::NewEntityFacade, which wraps it in the root's façade. The engine's JS questions reach it
	through the root's virtual members, an owner's OOSubEntity messages through
	cxx::OOSubEntityInterface, and the graphics reset manager through a C++ client in
	OOExhaustPlumeEntity.mm.
*/
class OOExhaustPlumeEntity : public Entity, public cxx::OOSubEntityInterface
{
public:
	// definition: the exhaust's tokens (x y z scale_x scale_y scale_z), read as -oo_floatAtIndex: read them.
	// A new plume, initialised; null for no tokens. oo::NewEntityFacade hands it to Objective-C.
	static oo::Ref<OOExhaustPlumeEntity> exhaustForShip(::ShipEntity *ship, const std::vector<std::string> &definition, float scale);
	// -initForShip:withDefinition:andScale:'s body, run once right after construction (amendment
	// oo-vl43 item 2): false where the initialiser answered nil.
	bool initForShip(::ShipEntity *ship, const std::vector<std::string> &definition, float scale);

	void resetPlume();

	Vector scale();
	void setScale(Vector scale);

	OOTexture *texture();

	static void setUpTexture();
	static OOTexture *plumeTexture();
	// What the graphics reset client (OOExhaustPlumeEntity.mm) runs.
	static void resetGraphicsState();

	// OOSubEntity.
	void rescaleBy(GLfloat factor) override;
	void rescaleBy(GLfloat factor, bool writeToCache) override;
	void drawSubEntityImmediate(bool immediate, bool translucent) override;

	// Entity (OOExhaustPlume)'s answer; callers ask dynamic_cast<OOExhaustPlumeEntity *>.
	bool isExhaust();

	// Entity (OOJavaScriptExtensions): the binding's bodies (OOJSExhaustPlume.h).
	void getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype) override;
	std::optional<std::string> jsClassName() override;
	bool isVisibleToScripts() override;

	double findCollisionRadius() override;
	void update(OOTimeDelta delta_t) override;

private:
	void saveToLastFrame();
	Frame frameAtTime(double t_frame, Frame frame_zero);	// t_frame is relative to now ie. -0.5 = half a second ago.

	Vector			_exhaustScale = {};
	OOHPScalar			_vertices[34 * 3] = {};
	GLfloat			_glVertices[34 * 3] = {};
	GLfloat			_exhaustBaseColors[34 * 4] = {};
	Frame			_track[kExhaustFrameCount] = {};
	OOTimeAbsolute	_trackTime = {};
	uint8_t			_nextFrame = {};
};
