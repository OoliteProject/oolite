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
#import "PlayerEntityScriptMethods.h"
#import "PlayerEntityLegacyScriptEngine.h"


@implementation Entity (ShaderBindings)

// Clock time.
- (GLfloat) clock
{
	return [PLAYER clockTime];
}


// System "flavour" numbers.
- (unsigned) pseudoFixedD100
{
	return [PLAYER systemPseudoRandom100];
}

- (unsigned) pseudoFixedD256
{
	return [PLAYER systemPseudoRandom256];
}


// System attributes.
- (unsigned) systemGovernment
{
	return [[PLAYER systemGovernment_number] unsignedIntValue];
}

- (unsigned) systemEconomy
{
	return [[PLAYER systemEconomy_number] unsignedIntValue];
}

- (unsigned) systemTechLevel
{
	return [[PLAYER systemTechLevel_number] unsignedIntValue];
}

- (unsigned) systemPopulation
{
	return [[PLAYER systemPopulation_number] unsignedIntValue];
}

- (unsigned) systemProductivity
{
	return [[PLAYER systemProductivity_number] unsignedIntValue];
}

@end
