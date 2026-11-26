/*

OOAIStateMachineVerifierStage.h

OOOXPVerifierStage which validates AI plists.


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

#import "OOFileScannerVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#include "oofnd/StdLib.hpp"

/*	Foundation sweep (proposed ADR-0043, bead oo-bfgm): the whitelist and the used AI names are
        sorted std::vectors of strings (sets). +nameForReverseDependencyForVerifier: is a shared
        selector (the other stages declare it) and keeps an Objective-C string result.
*/
@interface OOAIStateMachineVerifierStage : OOFileHandlingVerifierStage {
@private
    std::vector<std::string> _whitelist; // sorted, no duplicates
    std::vector<std::string> _usedAIs; // sorted, no duplicates
}

// Returns name to be used in -dependents by other stages.
+ (id)nameForReverseDependencyForVerifier:(OOOXPVerifier*)verifier; // shared selector (proposed ADR-0043)

// The caller only reports an AI it has a name for (it tested the name against nil).
- (void)stateMachineNamed:(const std::string&)name usedByShip:(const std::string&)shipName;

@end

#endif
