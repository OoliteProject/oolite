/*

OOJSExhaustPlume+ObjCBridge.mm

The Objective-C left over from OOJSExhaustPlume.mm (bead oo-utlm; proposed ADR-0056 amendments oo-
ppc and oo-ykoy): OOExhaustPlumeEntity (OOJavaScriptExtensions), the category through which the
engine asks a OOExhaustPlumeEntity for its JS side by selector. Its methods stay methods of
OOExhaustPlumeEntity, each forwarding in one line to the C++ function in OOJSExhaustPlume.mm that
holds its old body, and its @interface, which OOJSExhaustPlume.h declared, is here with them.
Deleted when OOExhaustPlumeEntity converts (oo-y86f): the methods then become members of the C++
OOExhaustPlumeEntity that call the same functions.

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

#import "OOExhaustPlumeEntity.h"
#import "OOJSExhaustPlume.h"

@interface OOExhaustPlumeEntity (OOJavaScriptExtensions)

- (JSClassID)oo_jsClassID;
- (std::optional<std::string>)cxx_oo_jsClassName;
- (BOOL)isVisibleToScripts;

@end

@implementation OOExhaustPlumeEntity (OOJavaScriptExtensions)

- (JSClassID)oo_jsClassID
{
    return ::JSExhaustPlumeClassID();
}

- (std::optional<std::string>)cxx_oo_jsClassName
{
    return ::OOJSExhaustPlumeJSClassName();
}

- (BOOL)isVisibleToScripts
{
    return ::OOJSExhaustPlumeIsVisibleToScripts();
}

@end
