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

#include "OOLogging.h"
#include "OOMaths.h"
#include "OOSoundInternal.h"

#include "oofnd/String.hpp"

namespace {
// The sources that are playing, each once, retained (a Foundation mutable set before; sources
// compare by identity). Created lazily and dropped by +stopAll, as the set was (proposed ADR-0043).
std::vector<oo::Ref<OOSoundSource>>* sPlayingSoundSources = nullptr;

/*	The class as the delegate of a stopped source's channel (+channel:didFinishPlayingSound:, which
        -stop made the channel's delegate by [_channel setDelegate:[OOSoundSource class]]): it hands
        the channel back to the mixer (bead oo-9ht.86).
*/
class StoppedSourceHandler final : public OOSoundChannelDelegate {
public:
    void channel(OOSoundChannel* inChannel, OOSound* inSound) override
    {
        OOSoundSource::channelOfStoppedSource(inChannel, inSound);
    }
};

StoppedSourceHandler sStoppedSourceHandler;

// The text "%@" printed for the sound: "(null)" for none (bead oo-9ht.68 deleted its facade).
std::string SoundDescription(const OOSound* sound)
{
    return (sound != nullptr) ? sound->description() : std::string("(null)");
}
}

oo::Ref<OOSoundSource> OOSoundSource::sourceWithSound(OOSound* inSound)
{
    return oo::makeRef<OOSoundSource>(inSound);
}

OOSoundSource::OOSoundSource()
{
    _positional = false;
    _position = kZeroVector;
    _gain = OO_DEFAULT_SOUNDSOURCE_GAIN;
}

OOSoundSource::OOSoundSource(OOSound* inSound)
    : OOSoundSource()
{
    setSound(inSound);
}

// [_sound autorelease] is the oo::Ref's release: the sounds the game plays are kept by the resource
// manager's cache, and a playing channel retains its own (bead oo-9ht.88).
OOSoundSource::~OOSoundSource()
{
    stop();
}

/*	A const member, so it reads the ivars that -isPlaying, -loop and -repeatCount answered
        (amendment oo-8kx7 item 5).
*/
std::optional<std::string> OOSoundSource::descriptionComponents() const
{
    if (_channel != nullptr) {
        // The channel as %@ printed its facade (bead oo-9ht.86 deleted it): <OOSoundChannel 0x...>.
        const std::string channel = oo::str::format("<OOSoundChannel %s>", oo::str::pointerDescription(_channel).c_str());
        return oo::str::format("sound=%s, loop=%s, repeatCount=%u, playing on channel %s", SoundDescription(_sound.get()).c_str(), _loop ? "YES" : "NO", _repeatCount ? _repeatCount : 1, channel.c_str());
    } else {
        return oo::str::format("sound=%s, loop=%s, repeatCount=%u, not playing", SoundDescription(_sound.get()).c_str(), _loop ? "YES" : "NO", _repeatCount ? _repeatCount : 1);
    }
}

OOSound* OOSoundSource::sound()
{
    return _sound.get();
}

void OOSoundSource::setSound(OOSound* sound)
{
    if (_sound.get() != sound) {
        stop();
        _sound = oo::Ref<OOSound>(sound); // [_sound autorelease]; [sound retain]
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
    return _channel != nullptr;
}

/*	[self retain] and [self release] are retain() and release(), which keep this source alive while
        it plays, as the old object kept itself (bead oo-9ht.88 deleted the facade that carried them);
        the playing set holds the source.
*/
void OOSoundSource::play()
{
    if (sound() == nullptr)
        return;

    OOSoundAcquireLock();

    if (_channel)
        stop();

    ::OOSoundMixer* mixer = ::OOSoundMixer::sharedMixer();
    _channel = mixer != nullptr ? mixer->popChannel() : nullptr;
    if (nullptr != _channel) {
        _remainingCount = repeatCount();
        _channel->setDelegate(this);
        _channel->setPosition(_position);
        _channel->setGain(_gain);
        _channel->playSound(sound(), loop());
        retain();
    }

    if (EXPECT_NOT(sPlayingSoundSources == nullptr)) {
        sPlayingSoundSources = new std::vector<oo::Ref<OOSoundSource>>();
    }
    if (std::find(sPlayingSoundSources->begin(), sPlayingSoundSources->end(), this) == sPlayingSoundSources->end()) {
        sPlayingSoundSources->emplace_back(this);
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

    if (nullptr != _channel) {
        _channel->setDelegate(&sStoppedSourceHandler);
        _channel->stop();
        _channel = nullptr;

        if (sPlayingSoundSources != nullptr) {
            auto it = std::find(sPlayingSoundSources->begin(), sPlayingSoundSources->end(), this);
            if (it != sPlayingSoundSources->end())
                sPlayingSoundSources->erase(it);
        }
        release(); // may free this source: nothing after it touches the object
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
    std::vector<oo::Ref<OOSoundSource>>* playing = sPlayingSoundSources;
    sPlayingSoundSources = nullptr;

    if (playing != nullptr) {
        // In the order they started playing (the set's hash order before).
        for (const oo::Ref<OOSoundSource>& source : *playing)
            source->stop();
        delete playing;
    }
}

void OOSoundSource::playOOSound(OOSound* sound)
{
    playSound(sound, _repeatCount);
}

void OOSoundSource::playSound(OOSound* sound, uint8_t count)
{
    stop();
    setSound(sound);
    setRepeatCount(count);
    play();
}

void OOSoundSource::playOrRepeatSound(OOSound* sound)
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
        _channel->setPosition(_position);
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
        _channel->setGain(_gain);
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
void OOSoundSource::channel(::OOSoundChannel* channel, OOSound* /*sound*/)
{
    assert(_channel == channel);

    OOSoundAcquireLock();

    if (--_remainingCount) {
        _channel->playSound(sound(), false);
    } else {
        _channel->setDelegate(nullptr);
        if (::OOSoundMixer* mixer = ::OOSoundMixer::sharedMixer())
            mixer->pushChannel(_channel);
        _channel = nullptr;
        OOSoundReleaseLock();
        release(); // may free this source: nothing after it touches the object
        return;
    }
    OOSoundReleaseLock();
}

void OOSoundSource::channelOfStoppedSource(::OOSoundChannel* inChannel, OOSound* /*inSound*/)
{
    // This delegate is used for a stopped source
    if (::OOSoundMixer* mixer = ::OOSoundMixer::sharedMixer())
        mixer->pushChannel(inChannel);
}
