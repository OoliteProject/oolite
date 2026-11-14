/*

OOJSSoundSource+ObjCBridge.mm

The Objective-C left over from OOJSSoundSource.mm (bead oo-cib0; proposed ADR-0056 amendments oo-
ppc and oo-ykoy): OOSoundSource (OOJavaScriptExtentions), the category through which the engine
asks a OOSoundSource for its JS side by selector. Its methods stay methods of OOSoundSource, each
forwarding in one line to the C++ function in OOJSSoundSource.mm that holds its old body, and its
@interface, which OOJSSoundSource.h declared, is here with them. Deleted when OOSoundSource
converts (oo-zoj3): the methods then become members of the C++ OOSoundSource that call the same
functions.

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

#import "OOJSSoundSource.h"
#import "OOSoundSource.h"

@implementation OOSoundSource (OOJavaScriptExtentions)

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return ::OOJSSoundSourceJSValueInContext(self, context);
}

- (std::optional<std::string>)cxx_oo_jsClassName
{
    return ::OOJSSoundSourceJSClassName();
}

@end
