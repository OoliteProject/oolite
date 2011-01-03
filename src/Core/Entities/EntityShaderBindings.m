/*

EntityShaderBindings.m

Extra methods exposed for shader bindings.


Oolite
Copyright (C) 2004-2011 Giles C Williams and contributors

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
	return [[PlayerEntity sharedPlayer] clockTime];
}


// System "flavour" numbers.
- (unsigned) pseudoFixedD100
{
	return [[PlayerEntity sharedPlayer] systemPseudoRandom100];
}

- (unsigned) pseudoFixedD256
{
	return [[PlayerEntity sharedPlayer] systemPseudoRandom256];
}


// System attributes.
- (unsigned) systemGovernment
{
	return [[[PlayerEntity sharedPlayer] systemGovernment_number] unsignedIntValue];
}

- (unsigned) systemEconomy
{
	return [[[PlayerEntity sharedPlayer] systemEconomy_number] unsignedIntValue];
}

- (unsigned) systemTechLevel
{
	return [[[PlayerEntity sharedPlayer] systemTechLevel_number] unsignedIntValue];
}

- (unsigned) systemPopulation
{
	return [[[PlayerEntity sharedPlayer] systemPopulation_number] unsignedIntValue];
}

- (unsigned) systemProductivity
{
	return [[[PlayerEntity sharedPlayer] systemProductivity_number] unsignedIntValue];
}

@end
