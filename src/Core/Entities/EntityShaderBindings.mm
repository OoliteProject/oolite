/*

EntityShaderBindings.m

Extra methods exposed for shader bindings.

C++20 since bead oo-aeev (proposed ADR-0056, amendment oo-9fwb): the category Entity
(ShaderBindings) is members of cxx::Entity (Entity.h), defined here. The shader uniforms bind them
through the entities' member table; the category's forwarders
(EntityShaderBindings+ObjCBridge.mm) went with bead oo-9ht.127.


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

#import "Entity.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import "PlayerEntityScriptMethods.h"

// -unsignedIntValue of the number a system-data query returned (nil: 0).
static unsigned UnsignedIntValueOf(const oo::PList& value)
{
    return value.isNumber() ? static_cast<unsigned>(value.int64Value()) : 0;
}

namespace cxx {

// Clock time.
GLfloat Entity::clock()
{
    return (PLAYER != nullptr ? PLAYER->clockTime() : 0.0);
}

// System "flavour" numbers.
unsigned Entity::pseudoFixedD100()
{
    return (PLAYER != nullptr ? PLAYER->systemPseudoRandom100() : unsigned { });
}

unsigned Entity::pseudoFixedD256()
{
    return (PLAYER != nullptr ? PLAYER->systemPseudoRandom256() : unsigned { });
}

// System attributes.
unsigned Entity::systemGovernment()
{
    return UnsignedIntValueOf((PLAYER != nullptr ? PLAYER->systemGovernment_number() : oo::PList()));
}

unsigned Entity::systemEconomy()
{
    return UnsignedIntValueOf((PLAYER != nullptr ? PLAYER->systemEconomy_number() : oo::PList()));
}

unsigned Entity::systemTechLevel()
{
    return UnsignedIntValueOf((PLAYER != nullptr ? PLAYER->systemTechLevel_number() : oo::PList()));
}

unsigned Entity::systemPopulation()
{
    return UnsignedIntValueOf((PLAYER != nullptr ? PLAYER->systemPopulation_number() : oo::PList()));
}

unsigned Entity::systemProductivity()
{
    return UnsignedIntValueOf((PLAYER != nullptr ? PLAYER->systemProductivity_number() : oo::PList()));
}

} // namespace cxx
