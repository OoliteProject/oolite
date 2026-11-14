/*

EntityShaderBindings+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendment oo-9fwb): the category Entity (ShaderBindings), whose
methods the shader uniforms find by selector on an entity's Objective-C object (the names and
types are whitelisted in shader-uniform-bindings.plist). Each method forwards to its member of
cxx::Entity (EntityShaderBindings.mm). Deleted with the Entity facade (its deletion bead), when
the uniforms bind C++ members.


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

@implementation Entity (ShaderBindings)

// Clock time.
- (GLfloat)clock
{
    return _cxxEntity->clock();
}

// System "flavour" numbers.
- (unsigned)pseudoFixedD100
{
    return _cxxEntity->pseudoFixedD100();
}
- (unsigned)pseudoFixedD256
{
    return _cxxEntity->pseudoFixedD256();
}

// System attributes.
- (unsigned)systemGovernment
{
    return _cxxEntity->systemGovernment();
}
- (unsigned)systemEconomy
{
    return _cxxEntity->systemEconomy();
}
- (unsigned)systemTechLevel
{
    return _cxxEntity->systemTechLevel();
}
- (unsigned)systemPopulation
{
    return _cxxEntity->systemPopulation();
}
- (unsigned)systemProductivity
{
    return _cxxEntity->systemProductivity();
}

@end
