/*

ScriptEngine.h

JavaScript support for Oolite
Copyright (C) 2007 David Taylor

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

#ifndef SCRIPTENGINE_H_SEEN
#define SCRIPTENGINE_H_SEEN

#import <Foundation/Foundation.h>
#import "Universe.h"
#import "PlayerEntity.h"
#import "PlayerEntityScripting.h"
#import <jsapi.h>

@interface ScriptEngine : NSObject
{
	JSRuntime *rt;
	JSContext *cx;
	JSObject *glob;
	JSBool builtins;
}

- (id) initWithUniverse: (Universe *) universe;
- (void) dealloc;

- (JSContext *) context;

@end

#endif
