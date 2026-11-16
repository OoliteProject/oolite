/*

OOJSGlobal+ObjCBridge.mm

The Objective-C left over from OOJSGlobal.mm (bead oo-3dj2; proposed ADR-0056 amendments oo-9ht.66
and oo-6ia4 item 6): OOJavaScriptEngine (OOMonitorSupportInternal), the category interface that
OOJSGlobal.mm declared to type its one send of -sendMonitorLogMessage:withMessageClass:inContext:
(the engine implements it in OOJavaScriptEngine.mm), moved here verbatim with that send, as
OOJSGlobalSendMonitorLogMessage(). Deleted when the engine converts (oo-k4nu) or declares the
method in its header: log() then calls the engine directly.

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

#import "OOJSGlobal.h"
#import "OOJavaScriptEngine.h"

#if OOJSENGINE_MONITOR_SUPPORT

@interface OOJavaScriptEngine (OOMonitorSupportInternal)

// Implemented in OOJavaScriptEngine.mm (types from bead oo-3rb.203).
- (void)sendMonitorLogMessage:(const std::optional<std::string>&)message
             withMessageClass:(const std::optional<std::string>&)messageClass
                    inContext:(JSContext*)context;

@end

#endif

#if OOJSENGINE_MONITOR_SUPPORT

void OOJSGlobalSendMonitorLogMessage(const std::optional<std::string>& message, const std::optional<std::string>& messageClass, JSContext* context)
{
    [[OOJavaScriptEngine sharedEngine] sendMonitorLogMessage:message
                                            withMessageClass:messageClass
                                                   inContext:context];
}

#endif
