/*

OOJSTimer+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-kdyh): the Objective-C OOJSTimer facade; see
OOJSTimer+ObjCBridge.h. It answers the engine's JS glue selectors for a cxx::OOJSTimer; the rest
(the timer's own selectors, -cxx_descriptionComponents, -timerFired) is the OOScriptTimer
facade's, which calls the C++ virtual members.


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

#import "OOJSTimer.h"
#import "OOJavaScriptEngine.h"

::OOJSTimer* oo::ToObjC(cxx::OOJSTimer* timer)
{
    return static_cast<::OOJSTimer*>(oo::ToObjC(static_cast<cxx::OOScriptTimer*>(timer)));
}

cxx::OOJSTimer* oo::ToCxx(::OOJSTimer* timer)
{
    return static_cast<cxx::OOJSTimer*>(oo::ToCxx(static_cast<::OOScriptTimer*>(timer)));
}

@implementation OOJSTimer

- (std::optional<std::string>)cxx_oo_jsClassName
{
    return oo::ToCxx(self)->oo_jsClassName();
}
- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return oo::ToCxx(self)->oo_jsValueInContext(context);
}

@end
