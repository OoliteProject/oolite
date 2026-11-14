/*

OORoleSet+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-bhb9): the Objective-C OORoleSet facade over
cxx::OORoleSet. Every method forwards to its C++ member: results that were role sets come back
through oo::ToObjC. Deleted with OORoleSet+ObjCBridge.h.


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

#import "OORoleSet.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OORoleSet (OOObjCBridgePrivate)

- (id)initWithCxxRoleSet:(cxx::OORoleSet*)roleSet;
- (id)initWithNewCxxRoleSet:(oo::Ref<cxx::OORoleSet>)roleSet;

@end

@implementation OORoleSet

// Inside the @implementation for the private ivar.
OORoleSet* oo::ToObjC(cxx::OORoleSet* roleSet)
{
    return Peers().peerFor(roleSet, [roleSet] { return [[OORoleSet alloc] initWithCxxRoleSet:roleSet]; });
}

cxx::OORoleSet* oo::ToCxx(OORoleSet* roleSet)
{
    if (roleSet == nil)
        return nullptr;
    return roleSet->_cxxRoleSet.get();
}

// The facade oo::ToObjC makes (under the peer table's lock: it only stores the ivar).
- (id)initWithCxxRoleSet:(cxx::OORoleSet*)roleSet
{
    self = [super init];
    if (self != nil)
        _cxxRoleSet = oo::Ref<cxx::OORoleSet>(roleSet);
    return self;
}

// The facade alloc/init makes: adopts its new C++ set and records itself as the set's peer. nil
// (and self released) for a null set, as the initialisers failed on no roles.
- (id)initWithNewCxxRoleSet:(oo::Ref<cxx::OORoleSet>)roleSet
{
    if (roleSet.get() == nullptr) {
        [self release];
        return nil;
    }

    self = [super init];
    if (self != nil) {
        _cxxRoleSet = std::move(roleSet);
        @autoreleasepool {
            Peers().peerFor(_cxxRoleSet.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxRoleSet.get());
    [super dealloc];
}

+ (instancetype)roleSetWithString:(const std::string&)roleString
{
    return oo::ToObjC(cxx::OORoleSet::roleSetWithString(roleString));
}

+ (instancetype)roleSetWithRole:(const std::string&)role probability:(float)probability
{
    return oo::ToObjC(cxx::OORoleSet::roleSetWithRole(role, probability));
}

- (id)initWithRoleString:(const std::string&)roleString
{
    return [self initWithNewCxxRoleSet:cxx::OORoleSet::roleSetWithString(roleString)];
}

- (id)initWithRole:(const std::string&)role probability:(float)probability
{
    return [self initWithNewCxxRoleSet:cxx::OORoleSet::roleSetWithRole(role, probability)];
}

- (std::optional<std::string>)cxx_descriptionComponents
{
    return _cxxRoleSet->descriptionComponents();
}

- (BOOL)isEqual:(id)other
{
    if ([other isKindOfClass:[OORoleSet class]])
        return _cxxRoleSet->isEqual(oo::ToCxx((OORoleSet*)other));
    else
        return NO;
}

- (NSUInteger)hash
{
    return _cxxRoleSet->hash();
}

- (id)copyWithZone:(OOZone*)zone
{
    // Note: since object is immutable, a copy is no different from the original.
    return [self retain];
}

- (std::optional<std::string>)roleString
{
    return _cxxRoleSet->roleString();
}
- (BOOL)hasRole:(const std::string&)role
{
    return _cxxRoleSet->hasRole(role);
}
- (float)probabilityForRole:(const std::string&)role
{
    return _cxxRoleSet->probabilityForRole(role);
}
- (std::vector<std::string>)roles
{
    return _cxxRoleSet->roles();
}
- (std::vector<std::string>)sortedRoles
{
    return _cxxRoleSet->sortedRoles();
}
- (std::optional<std::map<std::string, float>>)rolesAndProbabilities
{
    return _cxxRoleSet->rolesAndProbabilities();
}
- (std::optional<std::string>)anyRole
{
    return _cxxRoleSet->anyRole();
}

- (id)roleSetWithAddedRole:(const std::string&)role probability:(float)probability
{
    return oo::ToObjC(_cxxRoleSet->roleSetWithAddedRole(role, probability));
}

- (id)roleSetWithAddedRoleIfNotSet:(const std::string&)role probability:(float)probability
{
    return oo::ToObjC(_cxxRoleSet->roleSetWithAddedRoleIfNotSet(role, probability));
}

- (id)roleSetWithRemovedRole:(const std::string&)role
{
    return oo::ToObjC(_cxxRoleSet->roleSetWithRemovedRole(role));
}

@end
