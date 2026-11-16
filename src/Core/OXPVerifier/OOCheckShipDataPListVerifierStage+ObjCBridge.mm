/*

OOCheckShipDataPListVerifierStage+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056 amendment oo-rmd7 item 1, bead oo-1v2w): the schema verifier's
delegate for the C++ ship data stage (see OOCheckShipDataPListVerifierStage+ObjCBridge.h).
Deleted with OOCheckShipDataPListVerifierStage+ObjCBridge.h.


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

#import "OOCheckShipDataPListVerifierStage.h"
#import "OOPListSchemaVerifier.h"

#if OO_OXP_VERIFIER_ENABLED

@implementation OOCheckShipDataPListVerifierStageSchemaDelegate

- (id)initWithStage:(OOCheckShipDataPListVerifierStage*)stage
{
    self = [super init];
    if (self != nil)
        _stage = stage;
    return self;
}

- (BOOL)verifier:(OOPListSchemaVerifier*)verifier
    withPropertyList:(const oo::PList&)rootPList
               named:(const std::string&)name
        testProperty:(const oo::PList&)subPList
              atPath:(const oo::PList&)keyPath
         againstType:(const oo::PList&)typeKey
               error:(std::optional<OOPListSchemaVerifierError>*)outError
{
    return _stage->verifierTestProperty(verifier, rootPList, name, subPList, keyPath, typeKey, outError);
}

- (BOOL)verifier:(OOPListSchemaVerifier*)verifier
     withPropertyList:(const oo::PList&)rootPList
                named:(const std::string&)name
    failedForProperty:(const oo::PList&)subPList
            withError:(const OOPListSchemaVerifierError&)error
         expectedType:(const oo::PList&)localSchema
{
    return _stage->verifierFailedForProperty(verifier, rootPList, name, subPList, error, localSchema);
}

@end

#endif // OO_OXP_VERIFIER_ENABLED
