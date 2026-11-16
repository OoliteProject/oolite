/*

OOStringExpander+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendment oo-9ht.139 item 3): the string expander's sends to
classes that are still Objective-C (Universe, PlayerEntity, ResourceManager), one C++ function per
distinct send, for OOStringExpander.mm's converted functions (slice 1 of
docs/phases/3-slices/OOStringExpander.md, bead oo-6060). Imported by OOStringExpander.mm and
OOStringExpander+ObjCBridge.mm only. Each function goes when the class it messages converts
(its bead calls the member directly); the files go with the deletion bead.


Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the impllied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#ifndef OOSTRINGEXPANDER_OBJCBRIDGE_H
#define OOSTRINGEXPANDER_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "OOMaths.h"
#import "OOTypes.h"

#include "oofnd/PList.hpp"
#include "oofnd/objc/OORuntime.h"

#include <optional>
#include <string>

// [[UNIVERSE systemManager] getRandomSeedForCurrentSystem]
Random_Seed OOStringExpanderUniverseRandomSeedForCurrentSystem(void);

// [UNIVERSE cxx_descriptions]
const oo::PList* OOStringExpanderUniverseDescriptions(void);

// [UNIVERSE cxx_getSystemName:sysID]
std::optional<std::string> OOStringExpanderUniverseGetSystemName(OOSystemID sysID);

// [UNIVERSE cxx_getSystemName:sysID forGalaxy:galID]
std::optional<std::string> OOStringExpanderUniverseGetSystemNameForGalaxy(OOSystemID sysID, OOGalaxyID galID);

// [PLAYER systemID]
OOSystemID OOStringExpanderPlayerSystemID(void);

// [PLAYER respondsToSelector:selector]
bool OOStringExpanderPlayerRespondsToSelector(SEL selector);

// [PLAYER cxx_keyBindingDescription2:binding]
std::optional<std::string> OOStringExpanderPlayerKeyBindingDescription2(const std::string& binding);

// [PLAYER cxx_missionVariableForKey:key]
oo::PList OOStringExpanderPlayerMissionVariableForKey(const std::string& key);

// [ResourceManager cxx_whitelistDictionary]
oo::PList OOStringExpanderResourceManagerWhitelistDictionary(void);

#endif // OOSTRINGEXPANDER_OBJCBRIDGE_H
