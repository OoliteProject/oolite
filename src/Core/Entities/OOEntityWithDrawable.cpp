/*

OOEntityWithDrawable.m

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

#include "OOEntityWithDrawable.h"
#include "OODrawable.h"
#include "OOTexture.h"	// allTextures() destroys oo::Ref<OOTexture>s (bead oo-9ht.99)
#include "Universe.h"
#include "ShipEntity.h"
#include "OOVisualEffectEntity.h"



// -dealloc released the drawable; the member does, when the Objective-C object releases its C++
// part at the end of its -dealloc.


OODrawable *OOEntityWithDrawable::getDrawable()
{
	return drawable.get();
}


void OOEntityWithDrawable::setDrawable(OODrawable *inDrawable)
{
	if (inDrawable != drawable.get())
	{
		OODrawableAutorelease(std::move(drawable));	// [drawable autorelease]: the old one lives until the pool drains
		drawable = oo::Ref<OODrawable>(inDrawable);
		// Messages to a nil drawable did nothing and answered 0.
		OODrawable *cxxDrawable = drawable.get();
		if (cxxDrawable != nullptr)  cxxDrawable->setBindingTarget(this);	// the C++ entity (bead oo-9ht.39.6)

		collision_radius = cxxDrawable != nullptr ? cxxDrawable->collisionRadius() : 0.0f;
		no_draw_distance = cxxDrawable != nullptr ? cxxDrawable->maxDrawDistance() : 0.0f;
		boundingBox = cxxDrawable != nullptr ? cxxDrawable->boundingBox() : kZeroBoundingBox;
	}
}


double OOEntityWithDrawable::findCollisionRadius()
{
	OODrawable *cxxDrawable = drawable.get();
	return cxxDrawable != nullptr ? cxxDrawable->collisionRadius() : 0.0f;
}


void OOEntityWithDrawable::drawImmediate(bool /*immediate*/, bool translucent)
{
	if (no_draw_distance < cam_zero_distance)
	{
		// Don't draw.
		return;
	}

	if (no_draw_distance != INFINITY && !getIsImmuneToBreakPatternHide())
	{
		// (always draw sky, always draw break patterns)
		if (!getIsSubEntity())
		{
			GLfloat clipradius = collision_radius;
			if (getIsShip())
			{
				clipradius = frustumRadius();	// [oo::ToShip(self) frustumRadius]
			}
			else if (getIsVisualEffect())
			{
				clipradius = frustumRadius();	// [(OOVisualEffectEntity *)self frustumRadius]
			}
			// don't bother with frustum culling within/near collision radius, as
			// potential for problems with floating point inaccuracy causing
			// unwanted disappearance maybe fix
			// http://aegidian.org/bb/viewtopic.php?f=3&t=13619 - CIM
			if (cam_zero_distance > (clipradius+1000)*(clipradius+1000))
			{
				if (!(UNIVERSE != nullptr ? UNIVERSE->viewFrustumIntersectsSphereAt(cameraRelativePosition, clipradius) : false))
				{
					return;
				}
			}
		}
		else // is subentity
		{
			// don't bother with frustum culling within 1km, as above - CIM
			if (cam_zero_distance > (collision_radius+1000)*(collision_radius+1000))
			{
				// check correct sub-entity position
				if (!(UNIVERSE != nullptr ? UNIVERSE->viewFrustumIntersectsSphereAt(cameraRelativePosition, collisionRadius()) : false))
				{
					return;
				}
			}
		}
	}

	if ((UNIVERSE != nullptr ? UNIVERSE->getWireframeGraphics() : false))  OOGLWireframeModeOn();

	OODrawable *cxxDrawable = drawable.get();
	if (cxxDrawable != nullptr)
	{
		if (translucent)  cxxDrawable->renderTranslucentParts();
		else  cxxDrawable->renderOpaqueParts();
	}

	if ((UNIVERSE != nullptr ? UNIVERSE->getWireframeGraphics() : false))  OOGLWireframeModeOff();
}


#ifndef NDEBUG
std::vector<oo::Ref<OOTexture>> OOEntityWithDrawable::allTextures()
{
	OODrawable *cxxDrawable = getDrawable();
	return cxxDrawable != nullptr ? cxxDrawable->allTextures() : std::vector<oo::Ref<OOTexture>>();
}
#endif

