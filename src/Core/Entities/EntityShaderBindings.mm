/*

EntityShaderBindings.m

Extra methods exposed for shader bindings.

C++20 since bead oo-aeev (proposed ADR-0056, amendment oo-9fwb): the category Entity
(ShaderBindings) is members of cxx::Entity (Entity.h), defined here. The shader uniforms find the
methods by selector on the entity's Objective-C object, so the category's forwarders stay in
EntityShaderBindings+ObjCBridge.mm until the uniforms bind C++ members.


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
    return [PLAYER clockTime];
}

// System "flavour" numbers.
unsigned Entity::pseudoFixedD100()
{
    return [PLAYER systemPseudoRandom100];
}

unsigned Entity::pseudoFixedD256()
{
    return [PLAYER systemPseudoRandom256];
}

// System attributes.
unsigned Entity::systemGovernment()
{
    return UnsignedIntValueOf([PLAYER systemGovernment_number]);
}

unsigned Entity::systemEconomy()
{
    return UnsignedIntValueOf([PLAYER systemEconomy_number]);
}

unsigned Entity::systemTechLevel()
{
    return UnsignedIntValueOf([PLAYER systemTechLevel_number]);
}

unsigned Entity::systemPopulation()
{
    return UnsignedIntValueOf([PLAYER systemPopulation_number]);
}

unsigned Entity::systemProductivity()
{
    return UnsignedIntValueOf([PLAYER systemProductivity_number]);
}

} // namespace cxx
