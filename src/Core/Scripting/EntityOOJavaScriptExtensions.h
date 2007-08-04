/*

EntityOOJavaScriptExtensions.h

JavaScript support methods for Entity.

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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

- (BOOL)isVisibleToScripts;

- (NSString *)jsClassName;

- (BOOL)isShip;
- (BOOL)isStation;
- (BOOL)isSubEntity;
- (BOOL)isPlayer;
- (BOOL)isPlanet;

// Internal:
- (void)getJSClass:(JSClass **)outClass andPrototype:(JSObject **)outPrototype;

@end


@interface ShipEntity (OOJavaScriptExtensions)

// "Normal" subentities, excluding flashers and exhaust plumes.
- (NSArray *)subEntitiesForScript;

- (NSArray *)escorts;

- (void)setTargetForScript:(ShipEntity *)target;

@end
