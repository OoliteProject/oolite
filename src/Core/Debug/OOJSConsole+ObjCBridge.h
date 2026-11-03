/*

OOJSConsole+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendments oo-vnts item 2 and oo-jy98): an entity's -inspect,
which only the Mac debug OXP's inspector adds (a category on Entity), behind a C++ function for
the console's inspectEntity() (OOJSConsole.mm). Imported by OOJSConsole.mm and
OOJSConsole+ObjCBridge.mm only. Deleted with OOJSConsole+ObjCBridge.mm.


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

#ifndef OOJSCONSOLE_OBJCBRIDGE_H
#define OOJSCONSOLE_OBJCBRIDGE_H

#ifdef OO_DEBUG_MONITOR_ENABLED

@class Entity;

// [entity inspect] if the entity answers -inspect; nothing otherwise (and for nil).
void OOJSConsoleInspect(Entity* entity);

#endif /* OO_DEBUG_MONITOR_ENABLED */

#endif // OOJSCONSOLE_OBJCBRIDGE_H
