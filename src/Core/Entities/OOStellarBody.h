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

#import "OOFoundation.h"
#import "OOMaths.h"
#import "OOTypes.h"
#import "oofnd/objc/OOObject.h"

typedef enum {
    STELLAR_TYPE_SUN,
    STELLAR_TYPE_NORMAL_PLANET, // Terrestrial planet with atmosphere and oceans
    STELLAR_TYPE_MOON, // Rocky/airless planet
    STELLAR_TYPE_MINIATURE // Display proxy for a "normal" planet
} OOStellarBodyType;

#define ATMOSPHERE_DEPTH 500.0
#define PLANET_MINIATURE_FACTOR 0.00185
#define MAX_SUBDIVIDE 6

@protocol OOStellarBody <OOObject> // (and the weak-reference protocol until the root facade went: nothing adopts it)

- (double)radius;
- (OOStellarBodyType)planetType;

- (std::optional<std::string>)cxx_name; // nullopt: unnamed (bead oo-3rb.289.12)
- (void)cxx_setName:(const std::optional<std::string>&)name;

@end

/*	-radius and -planetType of a stellar body's Objective-C object: the sun and the
        planet, C++ since their facades were deleted, are asked directly
        (their object is the root Entity's facade, which does not answer them); any other body by
        selector, as before. Nil answers 0, as the message to nil did. Defined in OOSunEntity.mm.
*/
class Entity;
double OOStellarBodyRadius(Entity* body); // of the C++ entity (the object overloads went with the facade)
OOStellarBodyType OOStellarBodyPlanetType(Entity* body); // the same
