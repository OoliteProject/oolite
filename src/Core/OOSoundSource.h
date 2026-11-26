/*

OOSoundSource.h

A sound source.
Each playing sound is associated with a sound source, either explicitly or by
creating one on the fly. Each sound source can play one sound at a time, and
has a number of attributes related to positional audio (which is currently
unimplemented).

C++20 since bead oo-zoj3 (proposed ADR-0056, the Audio module: amendment oo-2en). Bead oo-9ht.88
deleted its Objective-C facade and moved it to the global namespace: the player, the JS
SoundSource, the music, the trumbles and the pools hold and call the C++ source. A playing source
is its channel's delegate (OOSoundChannelDelegate) since bead oo-9ht.86, and keeps itself alive
while it plays (a retain of its own, as the facade's [self retain] did).


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

#ifndef OOSOUNDSOURCE_H
#define OOSOUNDSOURCE_H

#include "OOALSoundChannel.h"
#include "OOMaths.h"
#include "OOSoundSource.h"

#include "oofnd/Ref.hpp"

#ifndef OO_DEFAULT_SOUNDSOURCE_GAIN
#define OO_DEFAULT_SOUNDSOURCE_GAIN 1.0f
#endif

class OOSoundReferencePoint; // C++ (OOBasicSoundReferencePoint.h, bead oo-odlx)
struct OOSoundSourceTestAccess;

class OOSoundSource : public oo::RefCounted, public ::OOSoundChannelDelegate {
public:
    OOSoundSource(); // was -init
    explicit OOSoundSource(OOSound* inSound); // was -initWithSound:
    ~OOSoundSource() override;

    static oo::Ref<OOSoundSource> sourceWithSound(OOSound* inSound);

    // These options should be set before playing. Effect of setting them while playing is undefined.
    OOSound* sound();
    void setSound(OOSound* inSound);
    bool loop();
    void setLoop(bool inLoop);
    uint8_t repeatCount();
    void setRepeatCount(uint8_t inCount);

    bool isPlaying();
    void play();
    void playOrRepeat();
    void stop();

    static void stopAll();

    // Conveniences:
    void playOOSound(OOSound* inSound);
    void playSound(OOSound* inSound, uint8_t inCount);
    void playOrRepeatSound(OOSound* inSound);

    // Positional audio attributes are used in this implementation
    void setPositional(bool inPositional);
    bool positional();
    void setPosition(Vector inPosition);
    Vector position();
    void setGain(float gain);
    float gain();

    // *Advanced* positional audio attributes are ignored in this implementation
    void setVelocity(Vector inVelocity);
    void setOrientation(Vector inOrientation);
    void setConeAngle(float inAngle);
    void setGainInsideCone(float inInside, float inOutside);
    void positionRelativeTo(OOSoundReferencePoint* inPoint);

    // OOSoundChannelDelegate: was -channel:didFinishPlayingSound:, which the channel sent to the
    // playing source's facade until bead oo-9ht.86.
    void channel(::OOSoundChannel* channel, OOSound* sound) override;

    /*	Was +channel:didFinishPlayingSound:, the class as the delegate of a stopped source's channel.
            Its first keyword is the instance member's, which a static member cannot overload. The
            channel reaches it through the stopped-source handler in OOSoundSource.mm.
    */
    static void channelOfStoppedSource(::OOSoundChannel* inChannel, OOSound* inSound);

    // What "%@" prints between the braces of <OOSoundSource 0x...>{...} (OODescription.h).
    std::optional<std::string> descriptionComponents() const;

private:
    oo::Ref<OOSound> _sound; // retained, as the Objective-C sound was
    ::OOSoundChannel* _channel = { }; // borrowed from the mixer, not retained, as before
    bool _loop = { };
    uint8_t _repeatCount = { },
            _remainingCount = { };
    Vector _position = { };
    bool _positional = { };
    float _gain = { };

    friend struct ::OOSoundSourceTestAccess; // tests only (amendment oo-862e item 2)
};

#endif // OOSOUNDSOURCE_H
