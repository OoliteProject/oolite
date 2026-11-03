/*

OOALSoundChannel.h

A channel for audio playback.

This class is an implementation detail. Do not use it directly; use an
OOSoundSource to play an OOSound.

C++20 since bead oo-5vp8 (proposed ADR-0056, the Audio module: amendment oo-2en). The class is
cxx::OOSoundChannel while OOALSoundChannel+ObjCBridge.h, imported at the end of this header, keeps
the Objective-C OOSoundChannel that the mixer makes and the sound sources message, and the delegate
category; the bridge's deletion bead moves it out of namespace cxx.

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

#pragma once

#ifndef OOALSOUNDCHANNEL_H
#define OOALSOUNDCHANNEL_H

#import "OOFoundation.h"
#import "OOMaths.h"
#import "OOOpenALController.h"
#import "oofnd/objc/OOObject.h"

#include "oofnd/Ref.hpp"
#include "oofnd/objc/OOObjCRef.h"

@class OOSound, OOSoundChannel;
struct OOSoundChannelTestAccess;

namespace cxx {

class OOSoundChannel : public oo::RefCounted {
public:
    /*	Was -init, which answered nil when OpenAL would not make a source: false then (amendment
            oo-r7m0 item 2). The facade's -init runs it right after making the channel.
    */
    bool init();

    ~OOSoundChannel() override;

    void update();

    void setDelegate(id delegate);

    // Unretained pointer used to maintain simple stack
    OOSoundChannel* next();
    void setNext(OOSoundChannel* next);

    // set sound position relative to listener
    void setPosition(Vector vector);
    void setGain(float gain);
    bool playSound(::OOSound* sound, bool loop);
    void stop();

    ::OOSound* sound();

    /*	Was the private -hasStopped, which told the delegate that self had finished. The channel it
            tells of is the Objective-C one, given here: oo::ToObjC(this), or, from the facade's -dealloc
            (where -dealloc sent it), the facade itself, which no peer lookup answers any more.
    */
    void hasStopped(::OOSoundChannel* channel);

private:
    bool enqueueBuffer(::OOSound* sound);
    void getNextSoundBuffer();

    OOSoundChannel* _next = { };
    id _delegate = { };
    oo::ObjCRef<::OOSound*> _sound; // the Objective-C sound, retained as before (amendment oo-smy item 4)
    ALuint _buffer = { };
    ALuint _lastBuffer = { };
    bool _bigSound = { };
    ALuint _source = { };
    // (The Objective-C class's _playing, which nothing read or wrote, is not kept: -Wunused-private-field.)
    bool _loop = { };

    friend struct ::OOSoundChannelTestAccess; // tests only (amendment oo-862e item 2)
};

} // namespace cxx

// Transitional: the Objective-C OOSoundChannel and its delegate category, for the mixer and the
// sound sources. Deleted, with namespace cxx above, by the bridge's deletion bead.
#import "OOALSoundChannel+ObjCBridge.h"

#endif // OOALSOUNDCHANNEL_H
