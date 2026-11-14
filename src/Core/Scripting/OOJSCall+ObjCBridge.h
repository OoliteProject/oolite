/*

OOJSCall+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-81hy): the Objective-C that OOJSCallObjCObjectMethod()
(OOJSCall.mm) needs to read and call Objective-C methods by name, moved out of OOJSCall.mm
unchanged (amendment oo-rmd7 item 1): the template class whose methods' type encodings the call
matches a method's signature against (it exists to be read by the Objective-C runtime), and the
-boolValue/-intValue protocol a "_bool" method's object result is asked through. Imported as the
last line of OOJSCall.h; do not import it directly. Deleted by its deletion bead once no
Objective-C class is left to call by name.


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

#ifndef OOJSCALL_OBJCBRIDGE_H
#define OOJSCALL_OBJCBRIDGE_H

#ifdef OO_DEBUG_MONITOR_ENABLED

#import "OOFoundation.h"
#include "oofnd/PList.hpp"
#import "oofnd/objc/OOObject.h"

#include <string>

// -boolValue / -intValue as Foundation's number and string classes declared them (no Foundation
// header declares them since oo-qps.17).
@protocol OOJSCallScalarValues
- (BOOL)boolValue;
- (int)intValue;
@end

// Template class providing method type encodings for the signatures matched here.
@interface OOJSCallMethodSignatureTemplateClass : OOObject

- (void)voidVoidMethod;
- (void)voidStringMethod:(const std::string&)string;
- (oo::PList)pListStringMethod:(const std::string&)string;
- (oo::PList)pListVoidMethod;

@end

#endif // OO_DEBUG_MONITOR_ENABLED

#endif // OOJSCALL_OBJCBRIDGE_H
