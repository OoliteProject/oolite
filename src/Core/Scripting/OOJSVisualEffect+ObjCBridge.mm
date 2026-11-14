/*

OOJSVisualEffect+ObjCBridge.mm

The Objective-C left over from OOJSVisualEffect.mm (bead oo-s1wq; proposed ADR-0056 amendments oo-
ppc and oo-ykoy): OOVisualEffectEntity (OOJavaScriptExtensions), the category through which the
engine asks a OOVisualEffectEntity for its JS side by selector. Its methods stay methods of
OOVisualEffectEntity, each forwarding in one line to the C++ function in OOJSVisualEffect.mm that
holds its old body, and its @interface, which OOJSVisualEffect.h declared, is here with them.
Deleted when OOVisualEffectEntity converts (oo-xjga): the methods then become members of the C++
OOVisualEffectEntity that call the same functions.

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

#import "OOJSVisualEffect.h"
#import "OOVisualEffectEntity.h"

@interface OOVisualEffectEntity (OOJavaScriptExtensions)

- (JSClassID)oo_jsClassID;
- (std::optional<std::string>)cxx_oo_jsClassName;
- (BOOL)isVisibleToScripts;
- (std::vector<oo::ObjCRef<Entity*>>)subEntitiesForScript; // empty before the first subentity; JS nil via visualEffectSubEntityEnumerator

@end

@implementation OOVisualEffectEntity (OOJavaScriptExtensions)

- (JSClassID)oo_jsClassID
{
    return ::JSVisualEffectClassID();
}

- (std::optional<std::string>)cxx_oo_jsClassName
{
    return ::OOJSVisualEffectJSClassName();
}

- (BOOL)isVisibleToScripts
{
    return ::OOJSVisualEffectIsVisibleToScripts();
}

- (std::vector<oo::ObjCRef<Entity*>>)subEntitiesForScript
{
    return ::OOJSVisualEffectSubEntitiesForScript(self);
}

@end
