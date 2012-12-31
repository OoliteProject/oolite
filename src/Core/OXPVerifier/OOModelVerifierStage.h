/*

OOModelVerifierStage.h

OOOXPVerifierStage which keeps track of models that are used and ensures they
are loadable.


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

#import "OOTextureVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

@interface OOModelVerifierStage: OOTextureHandlingStage
{
@private
	NSMutableSet					*_modelsToCheck;
}

// Returns name to be used in -dependents by other stages; also registers stage.
+ (NSString *)nameForReverseDependencyForVerifier:(OOOXPVerifier *)verifier;

/*	This can be called by other stages *before* the model stage runs.
	returns YES if the model is found, NO if it is not. Caller is responsible
	for complaining if it is not.
*/
- (BOOL)modelNamed:(NSString *)name
	  usedForEntry:(NSString *)entryName
			inFile:(NSString *)fileName
	 withMaterials:(NSDictionary *)materials
		andShaders:(NSDictionary *)shaders;

@end


@interface OOOXPVerifier(OOModelVerifierStage)

- (OOModelVerifierStage *)modelVerifierStage;

@end

#endif
