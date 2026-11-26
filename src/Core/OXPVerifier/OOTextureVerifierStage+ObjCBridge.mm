/*

OOTextureVerifierStage+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056 amendment oo-up4b items 2 and 4, bead oo-tuq8): the Objective-C
facade OOTextureHandlingStage and the verifier's -textureVerifierStage (see
OOTextureVerifierStage+ObjCBridge.h). Deleted with OOTextureVerifierStage+ObjCBridge.h.


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

#import "OOOXPVerifierStageInternal.h"
#import "OOTextureVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

@implementation OOTextureHandlingStage

// An Objective-C texture-handling stage ([[X alloc] init] of a subclass): its C++ part derives from
// cxx::OOTextureHandlingStage, so what the subclass does not override answers as that class does.
- (id)init
{
    return [super initWithCxxStage:oo::makeRef<oo::ObjCStage<cxx::OOTextureHandlingStage>>(self).get()];
}

@end

@implementation OOOXPVerifier (OOTextureVerifierStage)

- (OOOXPVerifierStage*)textureVerifierStage
{
    return [self cxx_stageWithName:OOTextureVerifierStage::nameForReverseDependencyForVerifier(self)];
}

@end

#endif // OO_OXP_VERIFIER_ENABLED
