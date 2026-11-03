/*

OODebugSupport+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendment oo-vnts): the debug plug-in controller's
-setUpDebugger, an Objective-C selector the controller may not implement, behind two functions
(OODebugSupport+ObjCBridge.mm) for OODebugSupport.mm. Imported by those two files only. Deleted
with OODebugSupport+ObjCBridge.mm.


Copyright (C) 2007-2013 Jens Ayton

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

#ifndef OODEBUGSUPPORT_OBJCBRIDGE_H
#define OODEBUGSUPPORT_OBJCBRIDGE_H

#ifdef OO_DEBUG_MONITOR_ENABLED

#import "OODebuggerInterface.h"
#import "OOFoundation.h"

// Whether the controller answers -setUpDebugger (false for nil).
bool OODebugPlugInControllerCanSetUpDebugger(id controller);

// The controller's -setUpDebugger.
id<OODebuggerInterface> OODebugPlugInControllerSetUpDebugger(id controller);

#endif /* OO_DEBUG_MONITOR_ENABLED */

#endif // OODEBUGSUPPORT_OBJCBRIDGE_H
