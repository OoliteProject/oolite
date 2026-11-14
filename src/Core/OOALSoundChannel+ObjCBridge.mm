/*

OOALSoundChannel+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, the Audio module: amendment oo-2en): the Objective-C
OOSoundChannel facade (see OOALSoundChannel+ObjCBridge.h). Every method forwards to its C++
member. Deleted with OOALSoundChannel+ObjCBridge.h.


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

#import "OOALSound.h"
#import "OOALSoundChannel.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOSoundChannel (OOObjCBridgePrivate)

- (id)initWithCxxChannel:(cxx::OOSoundChannel*)channel;

@end

@implementation OOSoundChannel

// Inside the @implementation for the private ivar.
OOSoundChannel* oo::ToObjC(cxx::OOSoundChannel* channel)
{
    return Peers().peerFor(channel, [channel] { return [[OOSoundChannel alloc] initWithCxxChannel:channel]; });
}

cxx::OOSoundChannel* oo::ToCxx(OOSoundChannel* channel)
{
    if (channel == nil)
        return nullptr;
    return channel->_cxxChannel.get();
}

// The facade oo::ToObjC makes (under the peer table's lock: it only stores the ivar).
- (id)initWithCxxChannel:(cxx::OOSoundChannel*)channel
{
    self = [super init];
    if (self != nil)
        _cxxChannel = oo::Ref<cxx::OOSoundChannel>(channel);
    return self;
}

// [[OOSoundChannel alloc] init]: a new channel, whose facade (and peer) this is; nil (and self
// released) when OpenAL would not make its source, as before.
- (id)init
{
    oo::Ref<cxx::OOSoundChannel> channel = oo::makeRef<cxx::OOSoundChannel>();
    if (!channel->init()) {
        [self release];
        return nil;
    }

    self = [super init];
    if (self != nil) {
        _cxxChannel = std::move(channel);
        @autoreleasepool {
            Peers().peerFor(_cxxChannel.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

// -dealloc's [self hasStopped] (make sure buffers are dequeued and deleted), which tells the
// delegate of this object; the C++ destructor deletes the source.
- (void)dealloc
{
    if (_cxxChannel)
        _cxxChannel->hasStopped(self);
    Peers().forget(_cxxChannel.get());
    [super dealloc];
}

- (void)update
{
    _cxxChannel->update();
}

- (void)setDelegate:(id)delegate
{
    _cxxChannel->setDelegate(delegate);
}

- (OOSoundChannel*)next
{
    return oo::ToObjC(_cxxChannel->next());
}

- (void)setNext:(OOSoundChannel*)next
{
    _cxxChannel->setNext(oo::ToCxx(next));
}

- (void)setPosition:(Vector)vector
{
    _cxxChannel->setPosition(vector);
}

- (void)setGain:(float)gain
{
    _cxxChannel->setGain(gain);
}

- (BOOL)playSound:(OOSound*)sound looped:(BOOL)loop
{
    return _cxxChannel->playSound(sound, loop);
}

- (void)stop
{
    _cxxChannel->stop();
}

- (OOSound*)sound
{
    return _cxxChannel->sound();
}

@end
