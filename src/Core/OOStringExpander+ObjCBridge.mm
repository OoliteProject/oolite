/*

OOStringExpander+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendment oo-9ht.139 item 3): the string expander's sends to
Universe, PlayerEntity and ResourceManager, each verbatim behind one C++ function
(OOStringExpander+ObjCBridge.h), so that OOStringExpander.mm's converted functions have no
Objective-C. Deleted with the bridge's deletion bead, once those classes are C++.


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

#import "OOStringExpander+ObjCBridge.h"
// The imports OOStringExpander.mm made for these sends (tools/check-string-expander.sh stubs the same set).
#import "OOJavaScriptEngine.h"
#import "PlayerEntity.h"
#import "PlayerEntityScriptMethods.h"
#import "ResourceManager.h"
#import "Universe.h"

Random_Seed OOStringExpanderUniverseRandomSeedForCurrentSystem(void)
{
    auto* manager = [UNIVERSE systemManager]; // null: a zero seed, as a message to nil (auto: the expander harness stubs the class)
    return (manager != nullptr) ? manager->getRandomSeedForCurrentSystem() : Random_Seed { };
}

const oo::PList* OOStringExpanderUniverseDescriptions(void)
{
    return [UNIVERSE cxx_descriptions];
}

std::optional<std::string> OOStringExpanderUniverseGetSystemName(OOSystemID sysID)
{
    return [UNIVERSE cxx_getSystemName:sysID];
}

std::optional<std::string> OOStringExpanderUniverseGetSystemNameForGalaxy(OOSystemID sysID, OOGalaxyID galID)
{
    return [UNIVERSE cxx_getSystemName:sysID forGalaxy:galID];
}

OOSystemID OOStringExpanderPlayerSystemID(void)
{
    return (PLAYER != nullptr ? PLAYER->systemID() : 0);
}

bool OOStringExpanderPlayerRespondsToSelector(SEL selector)
{
    return [oo::ToObjC(PLAYER) respondsToSelector:selector]; // the root's facade answers the player's selectors (beads oo-9ht.177, oo-9ht.144)
}

std::optional<std::string> OOStringExpanderPlayerKeyBindingDescription2(const std::string& binding)
{
    return (PLAYER != nullptr ? PLAYER->keyBindingDescription2(binding) : std::optional<std::string>());
}

oo::PList OOStringExpanderPlayerMissionVariableForKey(const std::string& key)
{
    return (PLAYER != nullptr ? PLAYER->missionVariableForKey(key) : oo::PList());
}

oo::PList OOStringExpanderResourceManagerWhitelistDictionary(void)
{
    return [ResourceManager cxx_whitelistDictionary];
}
