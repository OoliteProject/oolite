/*

OOFlasherEntity.h

Flashing light attached to ships.


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

#import "OOLightParticleEntity.h"
#import "ShipEntity.h"

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

@class OOColor;

/*	Foundation sweep (proposed ADR-0043, bead oo-5lu6): +flasherWithDictionary: is unique and takes
        the subentity configuration as an oo::PList; -initWithDictionary: is shared and keeps id.
        Foundation declares -initWithDictionary: too, so its typed form is the twin
        -cxx_initWithDictionary: (bead oo-3rb.292.1).
*/

@interface OOFlasherEntity : OOLightParticleEntity <OOSubEntity> {
@private
    float _frequency;
    float _phase;
    float _wave;
    float _brightfraction;
    std::vector<oo::ObjCRef<OOColor*>> _colors;
    NSUInteger _activeColor;

    OOTimeDelta _time;

    BOOL _active;
    BOOL _justSwitched;
}

+ (instancetype)flasherWithDictionary:(const oo::PList&)dictionary;
- (id)initWithDictionary:(id)dictionary; // shared selector (Foundation declares -initWithDictionary: too): -cxx_initWithDictionary: with an Objective-C dictionary
- (id)cxx_initWithDictionary:(const oo::PList&)dictionary OO_RETURNS_RETAINED;

- (BOOL)isActive;
- (void)setActive:(BOOL)active;

- (OOColor*)color;
// setColor is defined by superclass

- (float)frequency;
- (void)setFrequency:(float)frequency;

- (float)phase;
- (void)setPhase:(float)phase;

- (float)fraction;
- (void)setFraction:(float)fraction;

@end

@interface Entity (OOFlasherEntityExtensions)

- (BOOL)isFlasher;

@end
