/*

OOJSScript.h (QuickJS-ng proof of concept)

Minimal JavaScript script loader: enough to load a world script and call its
event handlers. The full OOJSScript (manifest properties, script caching,
OOScript subclassing) is ported in a later phase.

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

#import "OOJavaScriptEngine.h"

@interface OOJSScript : NSObject {
@private
    JSValue _jsSelf; // Owned; freed in -dealloc.
    NSString* _name;
    NSString* _version;
    NSString* _path;
}

// Returns nil (after logging) if the script cannot be loaded or its top level throws.
+ (id)scriptWithPath:(NSString*)path;
- (id)initWithPath:(NSString*)path;

+ (OOJSScript*)currentlyRunningScript;

- (NSString*)name;
- (NSString*)version;
- (NSString*)displayName;

- (JSValueConst)scriptObject;

/*	Call a method of the script object with the script as this, as
        -[OOJSScript callMethod:...] did. Returns NO if the method does not exist
        or throws. *outResult, if requested, is owned by the caller.
*/
- (BOOL)callMethodNamed:(NSString*)methodName
          withArguments:(JSValueConst*)argv
                  count:(int)argc
                 result:(JSValue*)outResult;

@end

void InitOOJSScript(JSContext* context, JSValueConst global);
