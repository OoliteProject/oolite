/*

OOSoundSource.m


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
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOLogging.h"
#import "OOMaths.h"
#import "OOSoundInternal.h"

#include "oofnd/String.hpp"
#include "oofnd/objc/OOObjCRef.h"

namespace {
// The sources that are playing, each once, retained (a Foundation mutable set before; sources
// compare by identity). Created lazily and dropped by +stopAll, as the set was (proposed ADR-0043).
std::vector<oo::ObjCRef<::OOSoundSource*>>* sPlayingSoundSources = nullptr;
}

namespace cxx {

oo::Ref<OOSoundSource> OOSoundSource::sourceWithSound(::OOSound* inSound)
{
    return oo::makeRef<OOSoundSource>(inSound);
}

OOSoundSource::OOSoundSource()
{
    _positional = false;
    _position = kZeroVector;
    _gain = OO_DEFAULT_SOUNDSOURCE_GAIN;
}

OOSoundSource::OOSoundSource(::OOSound* inSound)
    : OOSoundSource()
{
    setSound(inSound);
}

// [_sound autorelease] is kept: the sound outlives the source until the pool drains, as before.
OOSoundSource::~OOSoundSource()
{
    stop();
    objc_autorelease(_sound.leakRef());
}

/*	A const member, so it reads the ivars that -isPlaying, -loop and -repeatCount answered
        (amendment oo-8kx7 item 5).
*/
std::optional<std::string> OOSoundSource::descriptionComponents() const
{
    if (_channel != nil) {
        return oo::str::format("sound=%s, loop=%s, repeatCount=%u, playing on channel %s", oo::DescriptionOf(_sound.get()).c_str(), _loop ? "YES" : "NO", _repeatCount ? _repeatCount : 1, oo::DescriptionOf(_channel).c_str());
    } else {
        return oo::str::format("sound=%s, loop=%s, repeatCount=%u, not playing", oo::DescriptionOf(_sound.get()).c_str(), _loop ? "YES" : "NO", _repeatCount ? _repeatCount : 1);
    }
}

::OOSound* OOSoundSource::sound()
{
    return _sound.get();
}

void OOSoundSource::setSound(::OOSound* sound)
{
    if (_sound.get() != sound) {
        stop();
        objc_autorelease(_sound.leakRef());
        _sound = oo::ObjCRef<::OOSound*>(sound);
    }
}

bool OOSoundSource::loop()
{
    return _loop;
}

void OOSoundSource::setLoop(bool loop)
{
    _loop = !!loop;
}

uint8_t OOSoundSource::repeatCount()
{
    return _repeatCount ? _repeatCount : 1;
}

void OOSoundSource::setRepeatCount(uint8_t count)
{
    _repeatCount = count;
}

bool OOSoundSource::isPlaying()
{
    return _channel != nil;
}

/*	[self retain] and [self release] retain the facade, oo::ToObjC(this), which keeps this source
        alive while it plays, as the old object kept itself; the playing set and the channel's delegate
        are the facade too (amendment oo-kdyh item 2). While the source plays, its facade is alive, so
        stop() and channel() get the same one back.
*/
void OOSoundSource::play()
{
    if (sound() == nil)
        return;

    OOSoundAcquireLock();

    if (_channel)
        stop();

    ::OOSoundSource* objCSelf = oo::ToObjC(this);
    _channel = [[::OOSoundMixer sharedMixer] popChannel];
    if (nil != _channel) {
        _remainingCount = repeatCount();
        [_channel setDelegate:objCSelf];
        [_channel setPosition:_position];
        [_channel setGain:_gain];
        [_channel playSound:sound() looped:loop()];
        objc_retain(objCSelf);
    }

    if (EXPECT_NOT(sPlayingSoundSources == nullptr)) {
        sPlayingSoundSources = new std::vector<oo::ObjCRef<::OOSoundSource*>>();
    }
    if (std::find(sPlayingSoundSources->begin(), sPlayingSoundSources->end(), objCSelf) == sPlayingSoundSources->end()) {
        sPlayingSoundSources->emplace_back(objCSelf);
    }

    OOSoundReleaseLock();
}

void OOSoundSource::playOrRepeat()
{
    if (!isPlaying())
        play();
    else
        ++_remainingCount;
}

void OOSoundSource::stop()
{
    OOSoundAcquireLock();

    if (nil != _channel) {
        ::OOSoundSource* objCSelf = oo::ToObjC(this);
        [_channel setDelegate:[::OOSoundSource class]];
        [_channel stop];
        _channel = nil;

        if (sPlayingSoundSources != nullptr) {
            auto it = std::find(sPlayingSoundSources->begin(), sPlayingSoundSources->end(), objCSelf);
            if (it != sPlayingSoundSources->end())
                sPlayingSoundSources->erase(it);
        }
        objc_release(objCSelf);
    }

    OOSoundReleaseLock();
}

void OOSoundSource::stopAll()
{
    /*	We're not allowed to mutate sPlayingSoundSources during iteration. The
            normal solution would be to copy the set, but since we know it will
            end up empty we may as well use the original set and let a new one be
            set up lazily.
    */
    std::vector<oo::ObjCRef<::OOSoundSource*>>* playing = sPlayingSoundSources;
    sPlayingSoundSources = nullptr;

    if (playing != nullptr) {
        // In the order they started playing (the set's hash order before).
        for (const oo::ObjCRef<::OOSoundSource*>& source : *playing)
            oo::ToCxx(source.get())->stop();
        delete playing;
    }
}

void OOSoundSource::playOOSound(::OOSound* sound)
{
    playSound(sound, _repeatCount);
}

void OOSoundSource::playSound(::OOSound* sound, uint8_t count)
{
    stop();
    setSound(sound);
    setRepeatCount(count);
    play();
}

void OOSoundSource::playOrRepeatSound(::OOSound* sound)
{
    if (_sound.get() != sound)
        playOOSound(sound);
    else
        playOrRepeat();
}

void OOSoundSource::setPositional(bool inPositional)
{
    if (inPositional) {
        _positional = true;
    } else {
        /* OpenAL doesn't easily do non-positional sounds beyond the
         * stereo/mono distinction, but setting the position to the
         * zero vector is probably close enough */
        _positional = false;
        setPosition(kZeroVector);
    }
}

bool OOSoundSource::positional()
{
    return _positional;
}

void OOSoundSource::setPosition(Vector inPosition)
{
    _position = inPosition;
    if (inPosition.x != 0.0 || inPosition.y != 0.0 || inPosition.z != 0.0) {
        _positional = true;
    }
    if (_channel) {
        [_channel setPosition:_position];
    }
}

Vector OOSoundSource::position()
{
    return _position;
}

void OOSoundSource::setGain(float gain)
{
    _gain = gain;
    if (_channel) {
        [_channel setGain:_gain];
    }
}

float OOSoundSource::gain()
{
    return _gain;
}

/* Following not yet implemented */
void OOSoundSource::setVelocity(Vector /*inVelocity*/)
{
}

void OOSoundSource::setOrientation(Vector /*inOrientation*/)
{
}

void OOSoundSource::setConeAngle(float /*inAngle*/)
{
}

void OOSoundSource::setGainInsideCone(float /*inInside*/, float /*inOutside*/)
{
}

void OOSoundSource::positionRelativeTo(OOSoundReferencePoint* /*inPoint*/)
{
}

// OOSoundChannelDelegate
void OOSoundSource::channel(::OOSoundChannel* channel, ::OOSound* /*sound*/)
{
    assert(_channel == channel);

    OOSoundAcquireLock();

    if (--_remainingCount) {
        [_channel playSound:sound() looped:false];
    } else {
        ::OOSoundSource* objCSelf = oo::ToObjC(this);
        [_channel setDelegate:nil];
        [[::OOSoundMixer sharedMixer] pushChannel:_channel];
        _channel = nil;
        objc_release(objCSelf);
    }
    OOSoundReleaseLock();
}

void OOSoundSource::channelOfStoppedSource(::OOSoundChannel* inChannel, ::OOSound* /*inSound*/)
{
    // This delegate is used for a stopped source
    [[::OOSoundMixer sharedMixer] pushChannel:inChannel];
}

} // namespace cxx
