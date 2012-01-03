/*

EntityOOJavaScriptExtensions.h

JavaScript support methods for entities.

Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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


#import "Entity.h"
#import "OOJavaScriptEngine.h"


@interface Entity (OOJavaScriptExtensions)

- (BOOL) isVisibleToScripts;

- (NSString *) oo_jsClassName;

// Internal:
- (void) getJSClass:(JSClass **)outClass andPrototype:(JSObject **)outPrototype;
- (void) deleteJSSelf;

@end


@interface ShipEntity (OOJavaScriptExtensions)

// "Normal" subentities, excluding flashers and exhaust plumes.
- (NSArray *) subEntitiesForScript;

- (void) setTargetForScript:(ShipEntity *)target;

@end


@interface PlayerEntity (OOJavaScriptExtensions)

- (void) setJSSelf:(JSObject *)val context:(JSContext *)context;

@end
