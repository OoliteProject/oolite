/*

OOModelVerifierStage+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056 amendment oo-up4b item 4, bead oo-5zby): the verifier's
-modelVerifierStage, a category of the Objective-C OOOXPVerifier, which the ship data stage calls
to find the model stage. It answers the model stage's facade (an OOOXPVerifierStage: the stage is
a global C++ class with no Objective-C class of its own). Imported as the last line of
OOModelVerifierStage.h; do not import it directly. Deleted by its deletion bead once the verifier
is C++ (oo-tsa4), which finds the stage itself.


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

#ifndef OOMODELVERIFIERSTAGE_OBJCBRIDGE_H
#define OOMODELVERIFIERSTAGE_OBJCBRIDGE_H

#if OO_OXP_VERIFIER_ENABLED

@interface OOOXPVerifier (OOModelVerifierStage)

- (OOOXPVerifierStage*)modelVerifierStage; // was OOModelVerifierStage *, now a C++ class

@end

#endif // OO_OXP_VERIFIER_ENABLED

#endif // OOMODELVERIFIERSTAGE_OBJCBRIDGE_H
