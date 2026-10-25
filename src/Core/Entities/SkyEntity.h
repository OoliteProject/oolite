/*

SkyEntity.h

Entity subclass implementing the game backdrop of stars and nebulae.

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

#include "OOEntityWithDrawable.h"

#include "oofnd/StdLib.hpp"
#include "oofnd/PList.hpp"


/*	C++ only since bead oo-9ht.109 deleted its Objective-C facade (ADR-0056 amendments oo-9ht.23 and
	oo-9ht.106): the universe makes it with oo::makeRef<SkyEntity>(), hands it to Objective-C with
	oo::NewEntityFacade (its object is the root's facade, OOEntityWithDrawable's until bead oo-9ht.40) and finds it by dynamic_cast.
*/
class SkyEntity : public OOEntityWithDrawable
{
public:
	/*	-initWithColors::andSystemInfo:'s body after [super init] (the constructor ran Entity's), run
		on a new sky once its object is made (the facade ran it until bead oo-9ht.109).
	*/
	void initWithColors(OOColor *col1, OOColor *col2, const oo::PList &systemInfo);
	bool changeProperty(const std::string &key, const oo::PList &dict);

	OOColor *getSkyColor();		// -skyColor (amendment oo-862e item 1: the ivar keeps the name)

	void update(OOTimeDelta delta_t) override;
	bool isSky() override;
	bool isVisible() override;
	bool canCollide() override;
	GLfloat cameraRangeFront() override;
	GLfloat cameraRangeBack() override;
	void drawImmediate(bool immediate, bool translucent) override;

#ifndef NDEBUG
	std::optional<std::string> descriptionForObjDump() override;
#endif

private:
	bool readColor1(oo::Ref<OOColor> *ioColor1, oo::Ref<OOColor> *ioColor2, oo::Ref<OOColor> *ioColor3, oo::Ref<OOColor> *ioColor4, const oo::PList &dictionary);

	oo::Ref<OOColor>		skyColor;
};
