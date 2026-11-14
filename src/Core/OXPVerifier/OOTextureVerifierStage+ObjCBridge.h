/*

OOTextureVerifierStage+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056 amendment oo-up4b items 2 and 4, bead oo-tuq8): the Objective-C
facade of the C++ intermediate class cxx::OOTextureHandlingStage (OOTextureVerifierStage.h), and
the verifier's -textureVerifierStage, for the stages not converted yet. Imported as the last line
of OOTextureVerifierStage.h; do not import it directly.

        OOTextureHandlingStage  the superclass of the Objective-C texture-handling stages (ship data,
                                model). Its -init makes their C++ part, an
                                oo::ObjCStage<cxx::OOTextureHandlingStage>, so -dependents, and
                                [super dependents], answer what cxx::OOTextureHandlingStage does.

-textureVerifierStage has no caller left; it answers the texture stage's facade (an
OOOXPVerifierStage: the stage is a global C++ class with no Objective-C class of its own).

Never add to this file; converted code does not message the facade. Deleted by its deletion bead
once the ship data and model stages are C++.


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

#ifndef OOTEXTUREVERIFIERSTAGE_OBJCBRIDGE_H
#define OOTEXTUREVERIFIERSTAGE_OBJCBRIDGE_H

#if OO_OXP_VERIFIER_ENABLED

// Convenience base class for stages that need to run before OOTextureHandlingStage.
@interface OOTextureHandlingStage : OOFileHandlingVerifierStage

@end

@interface OOOXPVerifier (OOTextureVerifierStage)

- (OOOXPVerifierStage*)textureVerifierStage; // was OOTextureVerifierStage *, now a C++ class

@end

#endif // OO_OXP_VERIFIER_ENABLED

#endif // OOTEXTUREVERIFIERSTAGE_OBJCBRIDGE_H
