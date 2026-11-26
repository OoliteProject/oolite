/*

EntityOOJavaScriptExtensions+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendments oo-ppc and oo-ykoy): the categories' @interfaces that
EntityOOJavaScriptExtensions.h declared, copied exactly, for the engine, the bindings and the
entities that send their selectors (isVisibleToScripts, oo_jsClassID, deleteJSSelf,
subEntitiesForScript, setTargetForScript:, and PlayerEntity's setJSSelf:context:, which
OOJSPlayerShip.mm implements). Imported as the last line of EntityOOJavaScriptExtensions.h; do not
import it directly. Deleted by its deletion bead once Entity, ShipEntity and PlayerEntity are C++.

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

#ifndef ENTITYOOJAVASCRIPTEXTENSIONS_OBJCBRIDGE_H
#define ENTITYOOJAVASCRIPTEXTENSIONS_OBJCBRIDGE_H

@interface Entity (OOJavaScriptExtensions)

- (BOOL)isVisibleToScripts;

- (std::optional<std::string>)cxx_oo_jsClassName;

// Internal:
// The JS class of the entity's wrapper object; subclasses override this.
- (JSClassID)oo_jsClassID;
- (void)deleteJSSelf;

@end

@interface ShipEntity (OOJavaScriptExtensions)

// "Normal" subentities, excluding flashers and exhaust plumes.
- (std::vector<oo::ObjCRef<Entity*>>)subEntitiesForScript;

- (void)setTargetForScript:(ShipEntity*)target;

@end

@interface PlayerEntity (OOJavaScriptExtensions)

// The player's wrapper is created by OOJSPlayerShip; the entity keeps its own reference to val.
- (void)setJSSelf:(JSValueConst)val context:(JSContext*)context;

@end

#endif // ENTITYOOJAVASCRIPTEXTENSIONS_OBJCBRIDGE_H
