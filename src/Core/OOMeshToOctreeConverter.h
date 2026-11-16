/*

OOMeshToOctreeConverter.h

Class to manage the construction of octrees from triangle soups.


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

#ifndef OOMESHTOOCTREECONVERTER_H
#define OOMESHTOOCTREECONVERTER_H

#include "OOFoundation.h"
#include "OOMaths.h"
#include "Octree.h"
#include "oofnd/objc/OOObject.h"

#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

class ShipEntity; // C++ since bead oo-9ht.144

enum {
    kOOMeshToOctreeConverterSmallDataCapacity = 16
};

// (declared inside the Objective-C class's ivar block before bead oo-rsk8, which put it at file scope)
struct OOMeshToOctreeConverterInternalData {
    Triangle* triangles;
    uint32_t count;
    uint32_t capacity;
    uint32_t pendingCapacity;
    Triangle smallData[kOOMeshToOctreeConverterSmallDataCapacity];
};

class OOMeshToOctreeConverter : public oo::RefCounted {
public:
    explicit OOMeshToOctreeConverter(NSUInteger capacity); // -initWithCapacity:
    static oo::Ref<OOMeshToOctreeConverter> converterWithCapacity(NSUInteger capacity);
    ~OOMeshToOctreeConverter() override;

    void addTriangle(Triangle tri);

    oo::Ref<Octree> findOctreeToDepth(NSUInteger depth);

    // What "%@" prints between the braces of <OOMeshToOctreeConverter 0x...>{...} (OODescription.h).
    std::optional<std::string> descriptionComponents() const;

private:
    struct OOMeshToOctreeConverterInternalData _data = { };
};

#endif // OOMESHTOOCTREECONVERTER_H
