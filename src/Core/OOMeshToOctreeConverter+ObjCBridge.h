/*

OOMeshToOctreeConverter+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-rsk8): the Objective-C OOMeshToOctreeConverter, a facade
over the C++ cxx::OOMeshToOctreeConverter (OOMeshToOctreeConverter.h), for its caller that is not
converted yet (OOMesh's -octree). Its interface is the one OOMeshToOctreeConverter.h declared
before the conversion, copied exactly (same selectors, same types), so that caller compiles and
behaves unchanged; each method forwards to its C++ member. Imported as the last line of
OOMeshToOctreeConverter.h; do not import it directly.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  ----------------------------
        still Objective-C                      OOMeshToOctreeConverter *       nothing: messages as before
        converted (C++)                        oo::Ref<cxx::OOMeshToOctreeConverter>
          handing a converter to Objective-C                                    oo::ToObjC(converter)
          taking one from Objective-C                                           oo::ToCxx(objcConverter)

oo::ToObjC gives the converter's one live facade (oo::ObjCPeers), so identity survives a round
trip. Never add to this file; converted code does not message the facade. Deleted by its deletion
bead once no file outside OOMeshToOctreeConverter.* names the Objective-C OOMeshToOctreeConverter.

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

#ifndef OOMESHTOOCTREECONVERTER_OBJCBRIDGE_H
#define OOMESHTOOCTREECONVERTER_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@interface OOMeshToOctreeConverter : OOObject {
@private
    oo::Ref<cxx::OOMeshToOctreeConverter> _cxxConverter;
}

- (id)initWithCapacity:(NSUInteger)capacity;
+ (instancetype)converterWithCapacity:(NSUInteger)capacity;

- (void)addTriangle:(Triangle)tri;

- (Octree*)findOctreeToDepth:(NSUInteger)depth;

@end

namespace oo {

// The converter's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OOMeshToOctreeConverter* ToObjC(cxx::OOMeshToOctreeConverter* converter);
inline OOMeshToOctreeConverter* ToObjC(const Ref<cxx::OOMeshToOctreeConverter>& converter) { return ToObjC(converter.get()); }

// The C++ converter behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOMeshToOctreeConverter* ToCxx(OOMeshToOctreeConverter* converter);

} // namespace oo

#endif // OOMESHTOOCTREECONVERTER_OBJCBRIDGE_H
