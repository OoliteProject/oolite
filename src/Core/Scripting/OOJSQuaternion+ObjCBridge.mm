/*

OOJSQuaternion+ObjCBridge.mm

The Objective-C left over from OOJSQuaternion.mm (bead oo-hwae, converted the way bead oo-ppc
converted OOJSVector; proposed ADR-0056 amendment oo-ppc): PlayerEntity (JSQuaternionStatistics),
a debug-build category on a class that is still Objective-C. The debug console calls its methods
by selector name (PS.callObjC("reportJSQuaternionStatistics")), so they stay methods of
PlayerEntity, each forwarding in one line to the C++ function that holds its old body. Deleted
when PlayerEntity converts (bead oo-9ht.15, with OOJSVector's): the two methods then become
members of the C++ PlayerEntity that call the same functions, reached by callObjC's name table.

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

#import "OOJSQuaternion.h"
#import "PlayerEntity.h"

#if OO_DEBUG

@implementation PlayerEntity (JSQuaternionStatistics)

// :setM quatStats PS.callObjC("reportJSQuaternionStatistics")
// :quatStats

- (oo::PList)reportJSQuaternionStatistics // called by name from JavaScript (callObjC): the ADR-0055 item 5 signature
{
    return ::reportJSQuaternionStatistics();
}

- (void)clearJSQuaternionStatistics
{
    ::clearJSQuaternionStatistics();
}

@end

#endif
