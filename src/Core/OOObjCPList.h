/*

OOObjCPList.h

Objective-C objects inside an oo::PList (proposed ADR-0055 item 2, bead oo-qps.33): the
PList::Object node that carries a live object through plist data (proposed ADR-0043 Amendment 2),
and arrays of such nodes. Foundation-free: it names nothing from gnustep-base, and survives
oo-qps.18. Objective-C++ only.

        what                                            here
        ----------------------------------------------  ---------------------------------------------
        an object as a PList::Object node               oo::PListObject(object)             (nil -> null PList)
        the object inside a PList::Object node          oo::ObjectIn(plist)                 (nil for any other node)
        refs -> an array of Object nodes                oo::PListFromObjects(refs)          (nil elements skipped)
        the Object nodes of an array -> refs            oo::ObjCRefsIn<OOFoo *>(plist)      (other elements skipped)

An Object node retains its object, compares by the node's identity, and describes itself as "%@" described
the object (oo::DescriptionOf, OODescription.h). PListFromObjects is the PList form of an array of
objects: its elements are Object nodes in the vector's order, so converting it back to a
Foundation array gives the array of the same objects in the same order. ObjCRefsIn is its inverse:
the caller names the element type it knows the array holds (as a cast would); nothing is checked.
Anything but an array gives an empty vector.

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

#ifndef OOOBJCPLIST_H
#define OOOBJCPLIST_H

#import "OODescription.h"

// extern "C++" as OODescription.h is: a header may be reached from inside an extern "C" block.
extern "C++" {

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

namespace oo {

    // A PList::Object node's payload: an Objective-C object, retained (Amendment 2 carrier). Not final:
    // an entity's node is a subclass that also answers its C++ part (oo::EntityPListForeign).
    class ObjCPListForeign : public PListForeign {
    public:
        explicit ObjCPListForeign(id object)
            : object_(object)
        {
        }
        id object() const noexcept { return object_.get(); }
        std::string className() const override { return class_getName(object_getClass(object_.get())); }
        std::string description() const override { return DescriptionOf(object_.get()); }

    private:
        ObjCRef<id> object_;
    };

    inline PList PListObject(id object)
    {
        if (object == nil)
            return PList();
        return PList(PList::Object(makeRef<ObjCPListForeign>(object)));
    }

    // The object a PList::Object node holds; nil for any other node.
    inline id ObjectIn(const PList& plist)
    {
        if (const PList::Object* node = plist.getIf<PList::Object>()) {
            if (const auto* foreign = dynamic_cast<const ObjCPListForeign*>(node->get()))
                return foreign->object();
        }
        return nil;
    }

    // An array of Object nodes, one per non-nil element, in order.
    template <class T>
    PList PListFromObjects(const std::vector<ObjCRef<T>>& objects)
    {
        PList::Array result;
        result.reserve(objects.size());
        for (const auto& object : objects) {
            if (object)
                result.push_back(PListObject(object.get()));
        }
        return PList(std::move(result));
    }

    // The objects of an array's Object nodes, retained, in order; other elements are skipped.
    template <class T>
    std::vector<ObjCRef<T>> ObjCRefsIn(const PList& plist)
    {
        std::vector<ObjCRef<T>> result;
        if (const PList::Array* array = plist.getIf<PList::Array>()) {
            for (const PList& element : *array) {
                id object = ObjectIn(element);
                if (object != nil)
                    result.emplace_back(static_cast<T>(object));
            }
        }
        return result;
    }

} // namespace oo

} // extern "C++"

#endif // OOOBJCPLIST_H
