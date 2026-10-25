/*

OOEntityWithDrawable.h

Abstract intermediate class for entities which use an OODrawable to render.

C++20 since bead oo-bj8, with Entity the Entities pattern seam (proposed ADR-0056, amendment
oo-bj8). The global C++ class since bead oo-9ht.40 deleted its Objective-C facade
(OOEntityWithDrawable+ObjCBridge): the object of a ship, a sky or a visual effect is the root's
facade (ADR-0056 amendment oo-9ht.40).

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

#include "Entity.h"

#include "OODrawable.h"	// the drawable is held by oo::Ref (a complete type wherever the entity is destroyed)


class OOEntityWithDrawable : public Entity
{
public:
	OODrawable *getDrawable();	// borrowed
	void setDrawable(OODrawable *drawable);

	double findCollisionRadius() override;
	void drawImmediate(bool immediate, bool translucent) override;

#ifndef NDEBUG
	std::vector<oo::Ref<OOTexture>> allTextures() override;
#endif

private:
	// The drawable, held (an Objective-C object until bead oo-hahfg: every drawable is C++).
	oo::Ref<OODrawable>			drawable;
};
