/*

OOStellarBody.h

Protocol shared by suns and planets (which used to be the same class).


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

#include "OOFoundation.h"
#include "OOMaths.h"
#include "OOTypes.h"
#include "oofnd/objc/OOObject.h"

typedef enum {
    STELLAR_TYPE_SUN,
    STELLAR_TYPE_NORMAL_PLANET, // Terrestrial planet with atmosphere and oceans
    STELLAR_TYPE_MOON, // Rocky/airless planet
    STELLAR_TYPE_MINIATURE // Display proxy for a "normal" planet
} OOStellarBodyType;

#define ATMOSPHERE_DEPTH 500.0
#define PLANET_MINIATURE_FACTOR 0.00185
#define MAX_SUBDIVIDE 6

/*	The radius and planet type of a stellar body: the sun and the
        planet are asked directly; any other body by
        selector. Null answers 0. Defined in OOSunEntity.mm.
*/
class Entity;
double OOStellarBodyRadius(Entity* body); // of the C++ entity
OOStellarBodyType OOStellarBodyPlanetType(Entity* body); // the same
