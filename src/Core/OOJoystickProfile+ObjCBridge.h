/*

OOJoystickProfile+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-fn2f): the Objective-C joystick axis profiles, facades
over the C++ cxx::OOJoystickAxisProfile hierarchy (OOJoystickProfile.h), for the callers that are
not converted yet (OOJoystickManager, PlayerEntityStickProfile). Their interfaces are the ones
OOJoystickProfile.h declared before the conversion, copied exactly (same classes, superclasses,
selectors and types; the ivars are the root's one C++ reference), so those callers compile and
behave unchanged: they still alloc/init the subclasses, test them with isKindOfClass: and copy
them. Imported as the last line of OOJoystickProfile.h; do not import it directly.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  ----------------------------
        still Objective-C                      OOJoystick...AxisProfile *      nothing: messages as before
        converted (C++)                        oo::Ref<cxx::OOJoystick...AxisProfile>
          handing a profile to Objective-C                                      oo::ToObjC(profile)
          taking one from Objective-C                                           oo::ToCxx(objcProfile)

The root facade holds the C++ object; the two subclass facades add no ivars and forward through
oo::ToCxx(self) (amendment oo-up4b item 3). oo::ToObjC gives a profile's one live facade
(oo::ObjCPeers), of the facade class that matches its C++ class, so identity and isKindOfClass:
survive a round trip. [[X alloc] init] on a facade class makes a new C++ X. Never add to this
file; converted code does not message the facades. Deleted by its deletion bead once no file
outside OOJoystickProfile.* names the Objective-C classes.

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

#ifndef OOJOYSTICKPROFILE_OBJCBRIDGE_H
#define OOJOYSTICKPROFILE_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@interface OOJoystickAxisProfile : OOObject <OOCopying> {
@private
    oo::Ref<cxx::OOJoystickAxisProfile> _cxxProfile;
}

- (id)init;
- (id)copyWithZone:(OOZone*)zone;
- (double)rawValue:(double)x;
- (double)value:(double)x;
- (double)deadzone;
- (void)setDeadzone:(double)newValue;

@end

@interface OOJoystickStandardAxisProfile : OOJoystickAxisProfile

- (id)init;
- (id)copyWithZone:(OOZone*)zone;
- (void)setPower:(double)newValue;
- (double)power;
- (void)setParameter:(double)newValue;
- (double)parameter;
- (double)rawValue:(double)x;

@end

@interface OOJoystickSplineAxisProfile : OOJoystickAxisProfile

- (id)init;
- (void)dealloc;
- (id)copyWithZone:(OOZone*)zone;
- (int)addControl:(NSPoint)point;
- (NSPoint)pointAtIndex:(NSInteger)index;
- (int)countPoints;
- (void)removeControl:(NSInteger)index;
- (void)clearControlPoints;
- (void)moveControl:(NSInteger)index point:(NSPoint)point;
- (double)rawValue:(double)x;
- (double)gradient:(double)x;
- (std::vector<NSPoint>)controlPoints;

@end

namespace oo {

// A profile's Objective-C facade, of the class matching its C++ class: its live one, else a new
// one; autoreleased. nil for null.
OOJoystickAxisProfile* ToObjC(cxx::OOJoystickAxisProfile* profile);
inline OOJoystickAxisProfile* ToObjC(const Ref<cxx::OOJoystickAxisProfile>& profile) { return ToObjC(profile.get()); }
OOJoystickStandardAxisProfile* ToObjC(cxx::OOJoystickStandardAxisProfile* profile);
OOJoystickSplineAxisProfile* ToObjC(cxx::OOJoystickSplineAxisProfile* profile);

// The C++ profile behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOJoystickAxisProfile* ToCxx(OOJoystickAxisProfile* profile);
cxx::OOJoystickStandardAxisProfile* ToCxx(OOJoystickStandardAxisProfile* profile);
cxx::OOJoystickSplineAxisProfile* ToCxx(OOJoystickSplineAxisProfile* profile);

} // namespace oo

#endif // OOJOYSTICKPROFILE_OBJCBRIDGE_H
