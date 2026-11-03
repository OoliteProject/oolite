/*

OOJoystickProfile+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-fn2f): the Objective-C joystick axis profile facades over
cxx::OOJoystickAxisProfile and its two subclasses. Every method forwards to its C++ member;
copies come back through oo::ToObjC. Deleted with OOJoystickProfile+ObjCBridge.h.

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

#import "OOJoystickManager.h"
#import "OOJoystickProfile.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

// The facade class matching the C++ class, so isKindOfClass: answers as before. Most derived first.
Class FacadeClassFor(cxx::OOJoystickAxisProfile* profile)
{
    if (dynamic_cast<cxx::OOJoystickStandardAxisProfile*>(profile) != nullptr)
        return [OOJoystickStandardAxisProfile class];
    if (dynamic_cast<cxx::OOJoystickSplineAxisProfile*>(profile) != nullptr)
        return [OOJoystickSplineAxisProfile class];
    return [OOJoystickAxisProfile class];
}

} // namespace

@interface OOJoystickAxisProfile (OOObjCBridgePrivate)

// For oo::ToObjC, under the peer table's lock: stores the C++ object.
- (id)initWithCxxProfile:(cxx::OOJoystickAxisProfile*)profile;

// For -init: stores a new C++ object and records the facade as its peer (amendment oo-bhb9 item 3).
- (id)initWithNewCxxProfile:(const oo::Ref<cxx::OOJoystickAxisProfile>&)profile;

@end

@implementation OOJoystickAxisProfile

// Inside the @implementation for the private ivar.
OOJoystickAxisProfile* oo::ToObjC(cxx::OOJoystickAxisProfile* profile)
{
    return Peers().peerFor(profile, [profile] { return [[FacadeClassFor(profile) alloc] initWithCxxProfile:profile]; });
}

cxx::OOJoystickAxisProfile* oo::ToCxx(OOJoystickAxisProfile* profile)
{
    if (profile == nil)
        return nullptr;
    return profile->_cxxProfile.get();
}

- (id)initWithCxxProfile:(cxx::OOJoystickAxisProfile*)profile
{
    self = [super init];
    if (self != nil)
        _cxxProfile = oo::Ref<cxx::OOJoystickAxisProfile>(profile);
    return self;
}

- (id)initWithNewCxxProfile:(const oo::Ref<cxx::OOJoystickAxisProfile>&)profile
{
    self = [super init];
    if (self != nil) {
        _cxxProfile = profile;
        @autoreleasepool {
            Peers().peerFor(_cxxProfile.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

- (id)init
{
    return [self initWithNewCxxProfile:oo::makeRef<cxx::OOJoystickAxisProfile>()];
}

- (void)dealloc
{
    Peers().forget(_cxxProfile.get());
    [super dealloc];
}

- (id)copyWithZone:(OOZone*)zone
{
    return [oo::ToObjC(_cxxProfile->copy()) retain];
}

- (double)rawValue:(double)x
{
    return _cxxProfile->rawValue(x);
}
- (double)value:(double)x
{
    return _cxxProfile->value(x);
}
- (double)deadzone
{
    return _cxxProfile->deadzone();
}
- (void)setDeadzone:(double)newValue
{
    _cxxProfile->setDeadzone(newValue);
}

@end

OOJoystickStandardAxisProfile* oo::ToObjC(cxx::OOJoystickStandardAxisProfile* profile)
{
    return static_cast<OOJoystickStandardAxisProfile*>(oo::ToObjC(static_cast<cxx::OOJoystickAxisProfile*>(profile)));
}

cxx::OOJoystickStandardAxisProfile* oo::ToCxx(OOJoystickStandardAxisProfile* profile)
{
    return static_cast<cxx::OOJoystickStandardAxisProfile*>(oo::ToCxx(static_cast<OOJoystickAxisProfile*>(profile)));
}

@implementation OOJoystickStandardAxisProfile

- (id)init
{
    return [self initWithNewCxxProfile:oo::makeRef<cxx::OOJoystickStandardAxisProfile>()];
}

- (id)copyWithZone:(OOZone*)zone
{
    return [oo::ToObjC(oo::ToCxx(self)->copy()) retain];
}

- (void)setPower:(double)newValue
{
    oo::ToCxx(self)->setPower(newValue);
}
- (double)power
{
    return oo::ToCxx(self)->power();
}
- (void)setParameter:(double)newValue
{
    oo::ToCxx(self)->setParameter(newValue);
}
- (double)parameter
{
    return oo::ToCxx(self)->parameter();
}
- (double)rawValue:(double)x
{
    return oo::ToCxx(self)->rawValue(x);
}

@end

OOJoystickSplineAxisProfile* oo::ToObjC(cxx::OOJoystickSplineAxisProfile* profile)
{
    return static_cast<OOJoystickSplineAxisProfile*>(oo::ToObjC(static_cast<cxx::OOJoystickAxisProfile*>(profile)));
}

cxx::OOJoystickSplineAxisProfile* oo::ToCxx(OOJoystickSplineAxisProfile* profile)
{
    return static_cast<cxx::OOJoystickSplineAxisProfile*>(oo::ToCxx(static_cast<OOJoystickAxisProfile*>(profile)));
}

@implementation OOJoystickSplineAxisProfile

- (id)init
{
    return [self initWithNewCxxProfile:oo::makeRef<cxx::OOJoystickSplineAxisProfile>()];
}

- (void)dealloc
{
    [super dealloc];
    return;
}

- (id)copyWithZone:(OOZone*)zone
{
    return [oo::ToObjC(oo::ToCxx(self)->copy()) retain];
}

- (int)addControl:(NSPoint)point
{
    return oo::ToCxx(self)->addControl(point);
}
- (NSPoint)pointAtIndex:(NSInteger)index
{
    return oo::ToCxx(self)->pointAtIndex(index);
}
- (int)countPoints
{
    return oo::ToCxx(self)->countPoints();
}
- (void)removeControl:(NSInteger)index
{
    oo::ToCxx(self)->removeControl(index);
}
- (void)clearControlPoints
{
    oo::ToCxx(self)->clearControlPoints();
}
- (void)moveControl:(NSInteger)index point:(NSPoint)point
{
    oo::ToCxx(self)->moveControl(index, point);
}
- (double)rawValue:(double)x
{
    return oo::ToCxx(self)->rawValue(x);
}
- (double)gradient:(double)x
{
    return oo::ToCxx(self)->gradient(x);
}
- (std::vector<NSPoint>)controlPoints
{
    return oo::ToCxx(self)->controlPoints();
}

@end
