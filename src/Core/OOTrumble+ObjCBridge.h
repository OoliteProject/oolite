/*

OOTrumble+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-862e): the Objective-C OOTrumble, a facade over the C++
cxx::OOTrumble (OOTrumble.h), for callers that are not converted yet: PlayerEntity makes, keeps,
updates, saves and removes its trumbles through it, and HeadUpDisplay draws them. Its interface is
the one OOTrumble.h declared before the conversion, copied exactly (same selectors, same types), so
those callers compile and behave unchanged; each method forwards to its C++ member. Imported as the
last line of OOTrumble.h; do not import it directly.

oo::ToObjC gives the trumble's one live facade (oo::ObjCPeers), so identity survives a round trip:
the player's trumble array and the trumble's own -addTrumble:/-removeTrumble: messages name the same
object. Never add to this file; converted code does not message the facade. Deleted by its deletion
bead once no file outside OOTrumble.* names the Objective-C OOTrumble.

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

#ifndef OOTRUMBLE_OBJCBRIDGE_H
#define OOTRUMBLE_OBJCBRIDGE_H

#import "oofnd/objc/OOObject.h"

@interface OOTrumble : OOObject {
@private
    oo::Ref<cxx::OOTrumble> _cxxTrumble;
}

- (id)initForPlayer:(PlayerEntity*)p1;
- (id)initForPlayer:(PlayerEntity*)p1 digram:(const std::string&)digramString;

- (void)setupForPlayer:(PlayerEntity*)p1 digram:(const std::string&)digramString;

- (void)spawnFrom:(OOTrumble*)parentTrumble;

- (void)calcGrowthRate;

- (uint16_t*)digram;
- (NSPoint)position;
- (NSPoint)movement;
- (GLfloat)rotation;
- (GLfloat)size;
- (GLfloat)hunger;
- (GLfloat)discomfort;

// AI methods here
- (void)actionIdle;
- (void)actionBlink;
- (void)actionSnarl;
- (void)actionProot;
- (void)actionShudder;
- (void)actionStoned;
- (void)actionPop;
- (void)actionSleep;
- (void)actionSpawn;

- (void)randomizeMotionX;
- (void)randomizeMotionY;

- (void)drawTrumble:(double)z;
- (void)updateTrumble:(double)delta_t;

- (void)updateIdle:(double)delta_t;
- (void)updateBlink:(double)delta_t;
- (void)updateSnarl:(double)delta_t;
- (void)updateProot:(double)delta_t;
- (void)updateShudder:(double)delta_t;
- (void)updateStoned:(double)delta_t;
- (void)updatePop:(double)delta_t;
- (void)updateSleep:(double)delta_t;
- (void)updateSpawn:(double)delta_t;

- (oo::PList)dictionary; // the savegame record: a dictionary
- (void)setFromDictionary:(const oo::PList&)dict;

@end

namespace oo {

// The trumble's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OOTrumble* ToObjC(cxx::OOTrumble* trumble);
inline OOTrumble* ToObjC(const Ref<cxx::OOTrumble>& trumble) { return ToObjC(trumble.get()); }

// The C++ trumble behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOTrumble* ToCxx(OOTrumble* trumble);

} // namespace oo

#endif // OOTRUMBLE_OBJCBRIDGE_H
