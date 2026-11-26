/*

OORegExpMatcher+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-ct7c): the Objective-C OORegExpMatcher facade over
cxx::OORegExpMatcher. Every method forwards to its C++ member; the matcher +regExpMatcher gives
comes back through oo::ToObjC. Deleted with OORegExpMatcher+ObjCBridge.h.


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

#import "OORegExpMatcher.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OORegExpMatcher (OOObjCBridgePrivate)

- (id)initWithCxxMatcher:(cxx::OORegExpMatcher*)matcher;

@end

@implementation OORegExpMatcher

// Inside the @implementation for the private ivar.
OORegExpMatcher* oo::ToObjC(cxx::OORegExpMatcher* matcher)
{
    return Peers().peerFor(matcher, [matcher] { return [[OORegExpMatcher alloc] initWithCxxMatcher:matcher]; });
}

cxx::OORegExpMatcher* oo::ToCxx(OORegExpMatcher* matcher)
{
    if (matcher == nil)
        return nullptr;
    return matcher->_cxxMatcher.get();
}

- (id)initWithCxxMatcher:(cxx::OORegExpMatcher*)matcher
{
    self = [super init];
    if (self != nil)
        _cxxMatcher = oo::Ref<cxx::OORegExpMatcher>(matcher);
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxMatcher.get());
    [super dealloc];
}

+ (instancetype)regExpMatcher
{
    return oo::ToObjC(cxx::OORegExpMatcher::regExpMatcher());
}

- (BOOL)string:(const std::string&)string matchesExpression:(const std::string&)regExp
{
    return _cxxMatcher->string(string, regExp);
}

- (BOOL)string:(const std::string&)string matchesExpression:(const std::string&)regExp flags:(NSUInteger)flags
{
    return _cxxMatcher->string(string, regExp, flags);
}

@end
