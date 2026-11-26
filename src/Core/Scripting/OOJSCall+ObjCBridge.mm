/*

OOJSCall+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-81hy): the template class of OOJSCall+ObjCBridge.h,
moved unchanged from OOJSCall.mm.


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

#ifdef OO_DEBUG_MONITOR_ENABLED

#import "OOJSCall.h"

@implementation OOJSCallMethodSignatureTemplateClass : OOObject

- (void)voidVoidMethod
{
}

- (void)voidStringMethod:(const std::string&)string
{
}

- (oo::PList)pListStringMethod:(const std::string&)string
{
    return oo::PList();
}

- (oo::PList)pListVoidMethod
{
    return oo::PList();
}

@end

#endif // OO_DEBUG_MONITOR_ENABLED
