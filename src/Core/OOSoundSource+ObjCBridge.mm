/*

OOSoundSource+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, the Audio module: amendment oo-2en): the Objective-C OOSoundSource
facade (see OOSoundSource+ObjCBridge.h). Every method forwards to its C++ member. Deleted with
OOSoundSource+ObjCBridge.h.


Copyright (C) 2006-2013 Jens Ayton

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
OUT OF OR

*/

#import "OOSoundInternal.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOSoundSource (OOObjCBridgePrivate)

- (id)initWithCxxSource:(cxx::OOSoundSource*)source;
- (id)initWithNewCxxSource:(oo::Ref<cxx::OOSoundSource>)source;

@end

@implementation OOSoundSource

// Inside the @implementation for the private ivar.
OOSoundSource* oo::ToObjC(cxx::OOSoundSource* source)
{
    return Peers().peerFor(source, [source] { return [[OOSoundSource alloc] initWithCxxSource:source]; });
}

cxx::OOSoundSource* oo::ToCxx(OOSoundSource* source)
{
    if (source == nil)
        return nullptr;
    return source->_cxxSource.get();
}

// The facade oo::ToObjC makes (under the peer table's lock: it only stores the ivar).
- (id)initWithCxxSource:(cxx::OOSoundSource*)source
{
    self = [super init];
    if (self != nil)
        _cxxSource = oo::Ref<cxx::OOSoundSource>(source);
    return self;
}

// The facade alloc/init makes: adopts its new C++ source and records itself as its peer.
- (id)initWithNewCxxSource:(oo::Ref<cxx::OOSoundSource>)source
{
    self = [super init];
    if (self != nil) {
        _cxxSource = std::move(source);
        @autoreleasepool {
            Peers().peerFor(_cxxSource.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

+ (instancetype)sourceWithSound:(OOSound*)inSound
{
    return oo::ToObjC(cxx::OOSoundSource::sourceWithSound(inSound));
}

- (id)init
{
    return [self initWithNewCxxSource:oo::makeRef<cxx::OOSoundSource>()];
}

- (id)initWithSound:(OOSound*)inSound
{
    return [self initWithNewCxxSource:oo::makeRef<cxx::OOSoundSource>(inSound)];
}

- (void)dealloc
{
    Peers().forget(_cxxSource.get());
    [super dealloc];
}

- (std::optional<std::string>)cxx_descriptionComponents
{
    return _cxxSource->descriptionComponents();
}

- (OOSound*)sound
{
    return _cxxSource->sound();
}
- (void)setSound:(OOSound*)sound
{
    _cxxSource->setSound(sound);
}
- (BOOL)loop
{
    return _cxxSource->loop();
}
- (void)setLoop:(BOOL)loop
{
    _cxxSource->setLoop(loop);
}
- (uint8_t)repeatCount
{
    return _cxxSource->repeatCount();
}
- (void)setRepeatCount:(uint8_t)count
{
    _cxxSource->setRepeatCount(count);
}
- (BOOL)isPlaying
{
    return _cxxSource->isPlaying();
}
- (void)play
{
    _cxxSource->play();
}
- (void)playOrRepeat
{
    _cxxSource->playOrRepeat();
}
- (void)stop
{
    _cxxSource->stop();
}
+ (void)stopAll
{
    cxx::OOSoundSource::stopAll();
}

- (void)playOOSound:(OOSound*)sound
{
    _cxxSource->playOOSound(sound);
}
- (void)playSound:(OOSound*)sound repeatCount:(uint8_t)count
{
    _cxxSource->playSound(sound, count);
}
- (void)playOrRepeatSound:(OOSound*)sound
{
    _cxxSource->playOrRepeatSound(sound);
}

- (void)setPositional:(BOOL)inPositional
{
    _cxxSource->setPositional(inPositional);
}
- (BOOL)positional
{
    return _cxxSource->positional();
}
- (void)setPosition:(Vector)inPosition
{
    _cxxSource->setPosition(inPosition);
}
- (Vector)position
{
    return _cxxSource->position();
}
- (void)setGain:(float)gain
{
    _cxxSource->setGain(gain);
}
- (float)gain
{
    return _cxxSource->gain();
}

- (void)setVelocity:(Vector)inVelocity
{
    _cxxSource->setVelocity(inVelocity);
}
- (void)setOrientation:(Vector)inOrientation
{
    _cxxSource->setOrientation(inOrientation);
}
- (void)setConeAngle:(float)inAngle
{
    _cxxSource->setConeAngle(inAngle);
}
- (void)setGainInsideCone:(float)inInside outsideCone:(float)inOutside
{
    _cxxSource->setGainInsideCone(inInside, inOutside);
}
- (void)positionRelativeTo:(OOSoundReferencePoint*)inPoint
{
    _cxxSource->positionRelativeTo(inPoint);
}

@end
