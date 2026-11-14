/*

OOOXPVerifier+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-tsa4): the Objective-C OOOXPVerifier facade (see
OOOXPVerifier+ObjCBridge.h). Every method forwards to its C++ member in one line; the facade is
kept once per verifier through oo::ObjCPeers, and its -dealloc forgets it.
Deleted with OOOXPVerifier+ObjCBridge.h.


Copyright (C) 2007-2013 Jens Ayton and contributors

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

#import "OOOXPVerifier.h"

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

@implementation OOOXPVerifier

// Inside the @implementation for the private ivar.
OOOXPVerifier* oo::ToObjC(cxx::OOOXPVerifier* verifier)
{
    if (verifier == nullptr)
        return nil;
    return Peers().peerFor(verifier, [verifier] { return [[OOOXPVerifier alloc] initWithCxxVerifier:verifier]; });
}

cxx::OOOXPVerifier* oo::ToCxx(OOOXPVerifier* verifier)
{
    if (verifier == nil)
        return nullptr;
    return verifier->_cxxVerifier.get();
}

- (id)initWithCxxVerifier:(cxx::OOOXPVerifier*)verifier
{
    self = [super init];
    if (self != nil)
        _cxxVerifier = oo::Ref<cxx::OOOXPVerifier>(verifier);
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxVerifier.get());
    [super dealloc];
}

+ (BOOL)runVerificationIfRequested
{
    return cxx::OOOXPVerifier::runVerificationIfRequested();
}
- (void)registerStage:(OOOXPVerifierStage*)stage
{
    _cxxVerifier->registerStage(stage);
}
- (std::optional<std::string>)cxx_oxpPath
{
    return _cxxVerifier->oxpPath();
}
- (std::optional<std::string>)cxx_oxpDisplayName
{
    return _cxxVerifier->oxpDisplayName();
}
- (OOOXPVerifierStage*)cxx_stageWithName:(const std::string&)name
{
    return _cxxVerifier->stageWithName(name);
}
- (oo::PList)configurationValueForKey:(const std::string&)key
{
    return _cxxVerifier->configurationValueForKey(key);
}
- (oo::PList)cxx_configurationArrayForKey:(const std::string&)key
{
    return _cxxVerifier->configurationArrayForKey(key);
}
- (oo::PList)cxx_configurationDictionaryForKey:(const std::string&)key
{
    return _cxxVerifier->configurationDictionaryForKey(key);
}
- (std::optional<std::string>)cxx_configurationStringForKey:(const std::string&)key
{
    return _cxxVerifier->configurationStringForKey(key);
}
- (std::optional<std::vector<std::string>>)cxx_configurationSetForKey:(const std::string&)key
{
    return _cxxVerifier->configurationSetForKey(key);
}

@end

#endif // OO_OXP_VERIFIER_ENABLED
