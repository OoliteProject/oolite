/*

OOJSPlanet+ObjCBridge.mm

The Objective-C left over from OOJSPlanet.mm (bead oo-7ixd; proposed ADR-0056 amendments oo-ppc and
oo-ykoy): OOPlanetEntity (OOJavaScriptExtensions), the category through which the engine asks a
OOPlanetEntity for its JS side by selector. Its methods stay methods of OOPlanetEntity, each
forwarding in one line to the C++ function in OOJSPlanet.mm that holds its old body. Deleted when
OOPlanetEntity converts (oo-mp0d): the methods then become members of the C++ OOPlanetEntity that
call the same functions.

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

#import "OOJSPlanet.h"
#import "OOPlanetEntity.h"

@implementation OOPlanetEntity (OOJavaScriptExtensions)

- (BOOL)isVisibleToScripts
{
    return ::OOJSPlanetIsVisibleToScripts(self);
}

- (JSClassID)oo_jsClassID
{
    return ::JSPlanetClassID();
}

- (std::optional<std::string>)cxx_oo_jsClassName
{
    return ::OOJSPlanetJSClassName(self);
}

@end
