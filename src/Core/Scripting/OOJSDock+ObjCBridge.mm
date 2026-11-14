/*

OOJSDock+ObjCBridge.mm

The Objective-C left over from OOJSDock.mm (bead oo-zbx3; proposed ADR-0056 amendments oo-ppc and
oo-ykoy): DockEntity (OOJavaScriptExtensions), the category through which the engine asks a
DockEntity for its JS side by selector. Its methods stay methods of DockEntity, each forwarding in
one line to the C++ function in OOJSDock.mm that holds its old body, and its @interface, which
OOJSDock.h declared, is here with them. Deleted when DockEntity converts (oo-ao2d): the methods
then become members of the C++ DockEntity that call the same functions.

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

#import "DockEntity.h"
#import "OOJSDock.h"

@implementation DockEntity (OOJavaScriptExtensions)

- (JSClassID)oo_jsClassID
{
    return ::JSDockClassID();
}

- (std::optional<std::string>)cxx_oo_jsClassName
{
    return ::OOJSDockJSClassName();
}

@end
