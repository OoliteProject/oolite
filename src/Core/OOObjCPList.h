/*

OOObjCPList.h

Objective-C objects inside an oo::PList (proposed ADR-0055 item 2, bead oo-qps.33): the
PList::Object node that carried a live Objective-C object through plist data (oo::PListObject,
oo::ObjectIn, oo::PListFromObjects, oo::ObjCRefsIn, ObjCPListForeign) was deleted by bead oo-4aq6a.5:
no game object is an Objective-C object, so no node held one (an entity's node is
oo::EntityPListForeign, every other node's payload a C++ oo::PListForeign). This header stays as a
forwarding header so its includers need no change; it includes what they had from it.

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

#include "OODescription.h"

// extern "C++" as OODescription.h is: a header may be reached from inside an extern "C" block.
extern "C++" {

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

} // extern "C++"

#endif // OOOBJCPLIST_H
