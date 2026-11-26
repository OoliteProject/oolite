/*

OOPListSchemaVerifier+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-pni4): the Objective-C OOPListSchemaVerifier facade. Every
method forwards to cxx::OOPListSchemaVerifier in one line. See OOPListSchemaVerifier+ObjCBridge.h.

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

#import "OOPListSchemaVerifier.h"

#if OO_OXP_VERIFIER_ENABLED

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOPListSchemaVerifier (OOObjCBridgePrivate)

- (id)initWithCxxVerifier:(cxx::OOPListSchemaVerifier*)verifier;

@end

@implementation OOPListSchemaVerifier

// Inside the @implementation for the private ivar.
OOPListSchemaVerifier* oo::ToObjC(cxx::OOPListSchemaVerifier* verifier)
{
    return Peers().peerFor(verifier, [verifier] { return [[OOPListSchemaVerifier alloc] initWithCxxVerifier:verifier]; });
}

cxx::OOPListSchemaVerifier* oo::ToCxx(OOPListSchemaVerifier* verifier)
{
    if (verifier == nil)
        return nullptr;
    return verifier->_cxxVerifier.get();
}

+ (instancetype)verifierWithSchema:(const oo::PList&)schema
{
    return oo::ToObjC(cxx::OOPListSchemaVerifier::verifierWithSchema(schema));
}

- (id)initWithSchema:(const oo::PList&)schema
{
    oo::Ref<cxx::OOPListSchemaVerifier> verifier = cxx::OOPListSchemaVerifier::initWithSchema(schema);
    if (verifier.get() == nullptr) {
        [self release];
        return nil;
    }

    self = [super init];
    if (self == nil)
        return nil;

    _cxxVerifier = std::move(verifier);
    @autoreleasepool {
        Peers().peerFor(_cxxVerifier.get(), [self] { return [self retain]; });
    }
    return self;
}

- (id)initWithCxxVerifier:(cxx::OOPListSchemaVerifier*)verifier
{
    self = [super init];
    if (self != nil)
        _cxxVerifier = oo::Ref<cxx::OOPListSchemaVerifier>(verifier);
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxVerifier.get());
    [super dealloc];
}

- (void)setDelegate:(id)delegate
{
    _cxxVerifier->setDelegate(delegate);
}

- (id)delegate
{
    return _cxxVerifier->delegate();
}

- (BOOL)verifyPropertyList:(const oo::PList&)plist named:(const std::string&)name
{
    return _cxxVerifier->verifyPropertyList(plist, name);
}

+ (std::optional<std::string>)descriptionForKeyPath:(const oo::PList&)keyPath
{
    return cxx::OOPListSchemaVerifier::descriptionForKeyPath(keyPath);
}

@end

#endif // OO_OXP_VERIFIER_ENABLED
