/*

OOJSConsole+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendments oo-vnts item 2 and oo-jy98): an entity's -inspect,
an Objective-C selector only the Mac debug OXP's inspector adds, with the category that declares
it and the respondsToSelector: test, behind OOJSConsoleInspect() (OOJSConsole+ObjCBridge.h).
Deleted when Entity converts and the inspector with it.


Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#ifdef OO_DEBUG_MONITOR_ENABLED

#import "Entity.h"
#import "OOFoundation.h"
#import "OOJSConsole+ObjCBridge.h"

@interface Entity (OODebugInspector)

// Method added by inspector in Debug OXP under OS X only.
- (void)inspect;

@end

void OOJSConsoleInspect(Entity* entity)
{
    if ([entity respondsToSelector:@selector(inspect)]) {
        [entity inspect];
    }
}

#endif /* OO_DEBUG_MONITOR_ENABLED */
