/*

OOJSEngineTimeManagement+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-cn4o): the Objective-C OOTimeProfile and
OOTimeProfileEntry facades; see OOJSEngineTimeManagement+ObjCBridge.h. Each method forwards in one
line to the C++ class.


Copyright (C) 2010-2013 Jens Ayton

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

#import "OOJSEngineTimeManagement.h"

#if OOJS_PROFILE

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& ProfilePeers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

oo::ObjCPeers& EntryPeers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOTimeProfile (OOObjCBridgePrivate)
- (id)initWithCxxProfile:(cxx::OOTimeProfile*)profile; // for oo::ToObjC, under the peer table's lock
@end

@interface OOTimeProfileEntry (OOObjCBridgePrivate)
- (id)initWithCxxEntry:(cxx::OOTimeProfileEntry*)entry; // for oo::ToObjC, under the peer table's lock
@end

@implementation OOTimeProfile

// Inside the @implementation for the private ivar.
::OOTimeProfile* oo::ToObjC(cxx::OOTimeProfile* profile)
{
    return ProfilePeers().peerFor(profile, [profile] { return [[::OOTimeProfile alloc] initWithCxxProfile:profile]; });
}

cxx::OOTimeProfile* oo::ToCxx(::OOTimeProfile* profile)
{
    if (profile == nil)
        return nullptr;
    return profile->_cxxProfile.get();
}

- (id)initWithCxxProfile:(cxx::OOTimeProfile*)profile
{
    self = [super init];
    if (self != nil)
        _cxxProfile = oo::Ref<cxx::OOTimeProfile>(profile);
    return self;
}

- (void)dealloc
{
    ProfilePeers().forget(_cxxProfile.get());
    [super dealloc];
}

- (std::optional<std::string>)cxx_description
{
    return _cxxProfile->description();
}
- (double)totalTime
{
    return _cxxProfile->totalTime();
}
- (double)javaScriptTime
{
    return _cxxProfile->javaScriptTime();
}
- (double)nativeTime
{
    return _cxxProfile->nativeTime();
}
- (double)extensionTime
{
    return _cxxProfile->extensionTime();
}
- (double)nonExtensionTime
{
    return _cxxProfile->nonExtensionTime();
}
- (double)profilerOverhead
{
    return _cxxProfile->profilerOverhead();
}
- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return _cxxProfile->oo_jsValueInContext(context);
}

- (std::vector<oo::ObjCRef<OOTimeProfileEntry*>>)profileEntries
{
    std::vector<oo::ObjCRef<OOTimeProfileEntry*>> result;
    for (const auto& entry : _cxxProfile->profileEntries())
        result.emplace_back(oo::ToObjC(entry.get()));
    return result;
}

@end

@implementation OOTimeProfileEntry

::OOTimeProfileEntry* oo::ToObjC(cxx::OOTimeProfileEntry* entry)
{
    return EntryPeers().peerFor(entry, [entry] { return [[::OOTimeProfileEntry alloc] initWithCxxEntry:entry]; });
}

cxx::OOTimeProfileEntry* oo::ToCxx(::OOTimeProfileEntry* entry)
{
    if (entry == nil)
        return nullptr;
    return entry->_cxxEntry.get();
}

- (id)initWithCxxEntry:(cxx::OOTimeProfileEntry*)entry
{
    self = [super init];
    if (self != nil)
        _cxxEntry = oo::Ref<cxx::OOTimeProfileEntry>(entry);
    return self;
}

- (void)dealloc
{
    EntryPeers().forget(_cxxEntry.get());
    [super dealloc];
}

- (std::optional<std::string>)cxx_description
{
    return _cxxEntry->description();
}
- (std::optional<std::string>)cxx_function
{
    return _cxxEntry->function();
}
- (NSUInteger)hitCount
{
    return _cxxEntry->hitCount();
}
- (double)totalTimeSum
{
    return _cxxEntry->totalTimeSum();
}
- (double)selfTimeSum
{
    return _cxxEntry->selfTimeSum();
}
- (double)totalTimeAverage
{
    return _cxxEntry->totalTimeAverage();
}
- (double)selfTimeAverage
{
    return _cxxEntry->selfTimeAverage();
}
- (double)totalTimeMax
{
    return _cxxEntry->totalTimeMax();
}
- (double)selfTimeMax
{
    return _cxxEntry->selfTimeMax();
}
- (BOOL)isJavaScriptFrame
{
    return _cxxEntry->isJavaScriptFrame();
}
- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return _cxxEntry->oo_jsValueInContext(context);
}

- (OOComparisonResult)compareByTotalTime:(OOTimeProfileEntry*)other
{
    return _cxxEntry->compareByTotalTime(oo::ToCxx(other));
}
- (OOComparisonResult)compareByTotalTimeReverse:(OOTimeProfileEntry*)other
{
    return _cxxEntry->compareByTotalTimeReverse(oo::ToCxx(other));
}
- (OOComparisonResult)compareBySelfTime:(OOTimeProfileEntry*)other
{
    return _cxxEntry->compareBySelfTime(oo::ToCxx(other));
}
- (OOComparisonResult)compareBySelfTimeReverse:(OOTimeProfileEntry*)other
{
    return _cxxEntry->compareBySelfTimeReverse(oo::ToCxx(other));
}

@end

#endif // OOJS_PROFILE
