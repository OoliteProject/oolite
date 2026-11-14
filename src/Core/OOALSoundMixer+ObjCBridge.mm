/*

OOALSoundMixer+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, the Audio module: amendment oo-2en): the Objective-C OOSoundMixer
facade (see OOALSoundMixer+ObjCBridge.h). Every method forwards to its C++ member. Deleted with
OOALSoundMixer+ObjCBridge.h.


OOALSound - OpenAL sound implementation for Oolite.
Copyright (C) 2006-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOALSoundMixer.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOSoundMixer (OOObjCBridgePrivate)

- (id)initWithCxxMixer:(cxx::OOSoundMixer*)mixer;

@end

@implementation OOSoundMixer

// Inside the @implementation for the private ivar.
OOSoundMixer* oo::ToObjC(cxx::OOSoundMixer* mixer)
{
    return Peers().peerFor(mixer, [mixer] { return [[OOSoundMixer alloc] initWithCxxMixer:mixer]; });
}

cxx::OOSoundMixer* oo::ToCxx(OOSoundMixer* mixer)
{
    if (mixer == nil)
        return nullptr;
    return mixer->_cxxMixer.get();
}

- (id)initWithCxxMixer:(cxx::OOSoundMixer*)mixer
{
    self = [super init];
    if (self != nil)
        _cxxMixer = oo::Ref<cxx::OOSoundMixer>(mixer);
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxMixer.get());
    [super dealloc];
}

// One facade for the life of the process, retained once and kept (amendment oo-r7m0 item 5); nil,
// and asked again next time, while there is no mixer.
+ (id)sharedMixer
{
    static OOSoundMixer* facade = nil;
    if (facade == nil)
        facade = [oo::ToObjC(cxx::OOSoundMixer::sharedMixer()) retain];
    return facade;
}

- (void)update
{
    _cxxMixer->update();
}

- (void)shutdown
{
    _cxxMixer->shutdown();
}

- (OOSoundChannel*)popChannel
{
    return _cxxMixer->popChannel();
}

- (void)pushChannel:(OOSoundChannel*)channel
{
    _cxxMixer->pushChannel(channel);
}

@end
