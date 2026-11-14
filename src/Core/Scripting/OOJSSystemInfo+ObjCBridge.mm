/*

OOJSSystemInfo+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-6ia4): the Objective-C OOSystemInfo facade, declared in
OOJSSystemInfo+ObjCBridge.h. Each method forwards to its cxx::OOSystemInfo member. Deleted with
OOJSSystemInfo+ObjCBridge.h.


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

#import "OOJSSystemInfo.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOSystemInfo (OOObjCBridgePrivate)
- (id)initWithCxxInfo:(cxx::OOSystemInfo*)info; // for oo::ToObjC, under the peer table's lock
- (id)initWithNewCxxInfo:(oo::Ref<cxx::OOSystemInfo>)info; // for the initialiser: adopts it, nil for null
@end

@implementation OOSystemInfo

// Inside the @implementation for the private ivar.
::OOSystemInfo* oo::ToObjC(cxx::OOSystemInfo* info)
{
    return Peers().peerFor(info, [info] { return [[::OOSystemInfo alloc] initWithCxxInfo:info]; });
}

cxx::OOSystemInfo* oo::ToCxx(::OOSystemInfo* info)
{
    if (info == nil)
        return nullptr;
    return info->_cxxInfo.get();
}

- (id)initWithCxxInfo:(cxx::OOSystemInfo*)info
{
    self = [super init];
    if (self != nil)
        _cxxInfo = oo::Ref<cxx::OOSystemInfo>(info);
    return self;
}

- (id)initWithNewCxxInfo:(oo::Ref<cxx::OOSystemInfo>)info
{
    if (info.get() == nullptr) {
        [self release];
        return nil;
    }

    self = [super init];
    if (self != nil) {
        _cxxInfo = std::move(info);
        @autoreleasepool {
            Peers().peerFor(_cxxInfo.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxInfo.get());
    [super dealloc];
}

- (id)init
{
    [self release];
    return nil;
}

- (id)initWithGalaxy:(OOGalaxyID)galaxy system:(OOSystemID)system
{
    return [self initWithNewCxxInfo:cxx::OOSystemInfo::initWithGalaxy(galaxy, system)];
}

- (std::optional<std::string>)cxx_descriptionComponents
{
    return _cxxInfo->descriptionComponents();
}
- (std::optional<std::string>)cxx_shortDescriptionComponents
{
    return _cxxInfo->shortDescriptionComponents();
}
- (std::optional<std::string>)cxx_oo_jsClassName
{
    return _cxxInfo->oo_jsClassName();
}
- (oo::PList)cxx_valueForKey:(const std::optional<std::string>&)key
{
    return _cxxInfo->valueForKey(key);
}
- (void)cxx_setValue:(const oo::PList&)value forKey:(const std::string&)key
{
    _cxxInfo->setValue(value, key);
}
- (std::vector<std::string>)cxx_allKeys
{
    return _cxxInfo->allKeys();
}
- (void)setNullAssigned:(BOOL)flag forKey:(const std::string&)key
{
    _cxxInfo->setNullAssigned(flag, key);
}
- (BOOL)isNullAssignedForKey:(const std::string&)key
{
    return _cxxInfo->isNullAssignedForKey(key);
}
- (OOGalaxyID)galaxy
{
    return _cxxInfo->galaxy();
}
- (OOSystemID)system
{
    return _cxxInfo->system();
}
- (NSPoint)coordinates
{
    return _cxxInfo->coordinates();
}
- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return _cxxInfo->oo_jsValueInContext(context);
}

- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    if ([other isKindOfClass:[OOSystemInfo class]])
        return _cxxInfo->isEqual(oo::ToCxx((OOSystemInfo*)other));
    return NO;
}

- (NSUInteger)hash
{
    return _cxxInfo->hash();
}

@end
