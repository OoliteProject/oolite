/*

EntityShaderBindings.m

Extra methods exposed for shader bindings.


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

@implementation Entity (ShaderBindings)

// Clock time.
- (GLfloat)clock
{
    return [PLAYER clockTime];
}

// System "flavour" numbers.
- (unsigned)pseudoFixedD100
{
    return [PLAYER systemPseudoRandom100];
}

- (unsigned)pseudoFixedD256
{
    return [PLAYER systemPseudoRandom256];
}

// System attributes.
- (unsigned)systemGovernment
{
    return UnsignedIntValueOf([PLAYER systemGovernment_number]);
}

- (unsigned)systemEconomy
{
    return UnsignedIntValueOf([PLAYER systemEconomy_number]);
}

- (unsigned)systemTechLevel
{
    return UnsignedIntValueOf([PLAYER systemTechLevel_number]);
}

- (unsigned)systemPopulation
{
    return UnsignedIntValueOf([PLAYER systemPopulation_number]);
}

- (unsigned)systemProductivity
{
    return UnsignedIntValueOf([PLAYER systemProductivity_number]);
}

@end
