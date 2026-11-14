/*

OOCheckShipDataPListVerifierStage+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056 amendment oo-rmd7 item 1, bead oo-1v2w): the schema verifier's
delegate for the C++ OOCheckShipDataPListVerifierStage. OOPListSchemaVerifier is Objective-C and
messages its delegate through the informal protocol OOPListSchemaVerifierDelegate (a category on
OOObject), so the delegate is an Objective-C object: this helper, which the stage makes in run()
and which forwards both delegate methods to the stage's members. Imported as the last line of
OOCheckShipDataPListVerifierStage.h; do not import it directly. Deleted by its deletion bead once
OOPListSchemaVerifier is C++, when the stage becomes the delegate again.


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

#ifndef OOCHECKSHIPDATAPLISTVERIFIERSTAGE_OBJCBRIDGE_H
#define OOCHECKSHIPDATAPLISTVERIFIERSTAGE_OBJCBRIDGE_H

#if OO_OXP_VERIFIER_ENABLED

@interface OOCheckShipDataPListVerifierStageSchemaDelegate : OOObject {
@private
    OOCheckShipDataPListVerifierStage* _stage; // Not retained: the stage retains this helper.
}

- (id)initWithStage:(OOCheckShipDataPListVerifierStage*)stage;

@end

#endif // OO_OXP_VERIFIER_ENABLED

#endif // OOCHECKSHIPDATAPLISTVERIFIERSTAGE_OBJCBRIDGE_H
