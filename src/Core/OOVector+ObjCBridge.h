/*

OOVector+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-86ek): the Objective-C OONativeVector, a facade over the
C++ cxx::OONativeVector (OOVector.h), for callers that are not converted yet. Its interface is the
one OOVector.h declared before the conversion, copied exactly (same selectors, same types), so
those callers compile and behave unchanged; each method forwards to its C++ member. Imported as
the last line of OOVector.h; do not import it directly.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  ----------------------------
        still Objective-C                      OONativeVector * (this facade)  nothing: messages as before
        converted (C++)                        oo::Ref<cxx::OONativeVector>, cxx::OONativeVector *
          handing a box to Objective-C                                          oo::ToObjC(box)
          taking one from Objective-C                                           oo::ToCxx(objcBox)

oo::ToObjC gives the box's one live facade (oo::ObjCPeers), so identity survives a round trip:
oo::ToObjC(oo::ToCxx(v)) == v. Never add to this file; converted code does not message the facade.
Deleted by its deletion bead once no file outside OOVector.* names the Objective-C OONativeVector.

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

#ifndef OOVECTOR_OBJCBRIDGE_H
#define OOVECTOR_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

/* For storing vectors in Objective-C collections */
@interface OONativeVector : OOObject {
@private
    oo::Ref<cxx::OONativeVector> _cxxVector;
}
- (id)initWithVector:(Vector)vect;
- (Vector)getVector;

@end

namespace oo {

// The box's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OONativeVector* ToObjC(cxx::OONativeVector* vector);
inline OONativeVector* ToObjC(const Ref<cxx::OONativeVector>& vector) { return ToObjC(vector.get()); }

// The C++ box behind a facade, borrowed (the facade retains it); null for nil.
cxx::OONativeVector* ToCxx(OONativeVector* vector);

} // namespace oo

#endif // OOVECTOR_OBJCBRIDGE_H
