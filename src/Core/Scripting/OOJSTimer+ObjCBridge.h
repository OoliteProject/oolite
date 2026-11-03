/*

OOJSTimer+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-kdyh): the Objective-C OOJSTimer, the facade of a
cxx::OOJSTimer (OOJSTimer.h). Nothing outside OOJSTimer.mm names the class; a Timer's JS private
slot holds the C++ timer (OOJSPrivateObject.h), but Objective-C code may still send this facade the
JS glue selectors (-oo_jsValueInContext:, -cxx_oo_jsClassName), and the timer queue holds it. It is a
subclass of the OOScriptTimer facade with no ivars, which forwards through oo::ToCxx(self)
(amendment oo-up4b item 3); oo::ToObjC of a cxx::OOJSTimer picks it by name. Imported as the
last line of OOJSTimer.h; do not import it directly. Deleted by its deletion bead once the
timer queue holds C++ timers.


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

#ifndef OOJSTIMER_OBJCBRIDGE_H
#define OOJSTIMER_OBJCBRIDGE_H

@interface OOJSTimer : OOScriptTimer
@end

namespace oo {

// The timer's facade (an OOJSTimer): its live one, else a new one; autoreleased. nil for null.
::OOJSTimer* ToObjC(cxx::OOJSTimer* timer);

// The C++ timer behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOJSTimer* ToCxx(::OOJSTimer* timer);

} // namespace oo

#endif // OOJSTIMER_OBJCBRIDGE_H
