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

@interface OOAIStateMachineVerifierStage: OOFileHandlingVerifierStage
{
@private
	NSSet					*_whitelist;
	NSMutableSet			*_usedAIs;
}

// Returns name to be used in -dependents by other stages.
+ (NSString *) nameForReverseDependencyForVerifier:(OOOXPVerifier *)verifier;

- (void) stateMachineNamed:(NSString *)name usedByShip:(NSString *)shipName;

@end

#endif
