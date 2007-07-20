/*

OOModelVerifierStage.h

OOOXPVerifierStage which keeps track of models that are used and ensures they
are loadable.


Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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

#import "OOTextureVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

@interface OOModelVerifierStage: OOTextureHandlingStage
{
	NSMutableSet					*_usedModels;
}

// Returns name to be used in -dependents by other stages; also registers stage.
+ (NSString *)nameForReverseDependencyForVerifier:(OOOXPVerifier *)verifier;

/*	These can be called by other stages *before* the model stage runs.
	The context specifies where the model is used; something like
	"fooShip.dat" or "shipdata.plist materials dictionary for ship \"foo\"".
	It should make sense with "Model \"foo\" referenced in " in front of it.
*/
- (void) modelNamed:(NSString *)name usedInContext:(NSString *)context;

@end

#endif
