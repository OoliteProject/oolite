/*

OOALSoundChannel.m

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

#include "OOALSoundChannel.h"
#include "OOALSound.h"
#include "OOLogging.h"
#include "OOMaths.h"

#include "oofnd/Log.hpp"
#include "oofnd/String.hpp"

// The body of -init after [super init]; [self release]; self = nil; is false.
bool OOSoundChannel::init()
{
    {
        ALuint error;
        OOAL(alGenSources(1, &_source));
        if ((error = alGetError()) != AL_NO_ERROR) {
            OO_LOG(kOOLogSoundInitError, "{}", "Could not create OpenAL source");
            return false;
        } else {
            // sources are all relative to listener, defaulting to zero vector
            OOAL(alSourcei(_source, AL_SOURCE_RELATIVE, AL_TRUE));
            OOAL(alSource3f(_source, AL_POSITION, 0.0f, 0.0f, 0.0f));
        }
    }
    return true;
}

// -dealloc: [self hasStopped] (make sure buffers are dequeued and deleted, and tell the delegate),
// which the facade's -dealloc sent until bead oo-9ht.86, then the source goes. A channel whose
// init() failed has no source (the facade of one was never made, so nothing was told).
OOSoundChannel::~OOSoundChannel()
{
    if (_source != 0)
        hasStopped();
    OOAL(alDeleteSources(1, &_source));
}

void OOSoundChannel::update()
{
    // Check if we've reached the end of a sound.
    if (_sound != nullptr) {
        ALint check;
        OOAL(alGetSourcei(_source, AL_SOURCE_STATE, &check));
        if (check == AL_STOPPED) {
            hasStopped();
        } else if (_sound->soundIncomplete()) // streaming and not finished loading
        {
            OO_LOG("sound.buffer", "Incomplete, trying next for {}", _sound->name().value_or("(null)"));
            getNextSoundBuffer();
        } else if (_loop) {
            OO_LOG("sound.buffer", "Looping, trying restart for {}", _sound->name().value_or("(null)"));
            // sound is complete, but needs to be looped, so start it again
            _sound->rewind();
            getNextSoundBuffer();
        }
    }
}

void OOSoundChannel::getNextSoundBuffer()
{
    if (!_bigSound) {
        // we've only loaded one buffer so far
        _bigSound = true;
        _lastBuffer = _buffer;
        enqueueBuffer(_sound.get());
    } else {
        // _lastBuffer has something in it, so only queue up
        // another one if we've finished with that
        ALint processed = 0;
        OOAL(alGetSourcei(_source, AL_BUFFERS_PROCESSED, &processed));
        if (processed > 0) // slot free
        {
            // dequeue and delete lastBuffer
            ALuint buffer;
            OOAL(alSourceUnqueueBuffers(_source, 1, &buffer));
            assert(buffer == _lastBuffer);
            OOAL(alDeleteBuffers(1, &_lastBuffer));
            // shuffle along, and grab the next bit
            _lastBuffer = _buffer;
            enqueueBuffer(_sound.get());
        }
    }
}

void OOSoundChannel::setDelegate(OOSoundChannelDelegate* delegate)
{
    _delegate = delegate;
}

OOSoundChannel* OOSoundChannel::next()
{
    return _next;
}

void OOSoundChannel::setNext(OOSoundChannel* next)
{
    _next = next;
}

void OOSoundChannel::setPosition(Vector vector)
{
    OOAL(alSource3f(_source, AL_POSITION, vector.x, vector.y, vector.z));
}

void OOSoundChannel::setGain(float gain)
{
    OOAL(alSourcef(_source, AL_GAIN, gain));
}

bool OOSoundChannel::playSound(OOSound* sound, bool loop)
{
    if (sound == nullptr)
        return false;

    if (_sound != nullptr)
        stop();

    _loop = loop;
    _bigSound = false;
    sound->rewind();
    if (enqueueBuffer(sound)) {
        _sound = oo::Ref<OOSound>(sound);
        return true;
    } else {
        return false;
    }
}

void OOSoundChannel::stop()
{
    if (_sound != nullptr) {
        OOAL(alSourceStop(_source));
        OOAL(alSourcei(_source, AL_BUFFER, AL_NONE));
        hasStopped();
    }
}

void OOSoundChannel::hasStopped()
{
    ALint queued;
    OOAL(alGetSourcei(_source, AL_BUFFERS_QUEUED, &queued));

    while (queued--) {
        ALuint buffer;
        OOAL(alSourceUnqueueBuffers(_source, 1, &buffer));
    }

    OOAL(alDeleteBuffers(1, &_buffer));
    if (_bigSound) {
        // then we have two buffers to cleanup
        OOAL(alDeleteBuffers(1, &_lastBuffer));
    }
    _bigSound = false;

    oo::Ref<OOSound> sound = std::move(_sound); // [sound release] at the end of the scope

    if (nullptr != _delegate) {
        _delegate->channel(this, sound.get());
    }
}

bool OOSoundChannel::enqueueBuffer(OOSound* sound)
{
    // get sound data (a message to nil answered 0)
    _buffer = sound != nullptr ? sound->soundBuffer() : 0;
    // bind sound data to buffer
    OOAL(alSourceQueueBuffers(_source, 1, &_buffer));
    ALuint error;
    if ((error = alGetError()) != AL_NO_ERROR) {
        OO_LOG("ov.debug", "Error {} queueing buffers (_source: {} ({}), _buffer: {} ({}))",
            error, _source, oo::str::pointerDescription(&_source), _buffer, oo::str::pointerDescription(&_buffer));
        return false;
    }
    ALint playing = 0;
    OOAL(alGetSourcei(_source, AL_SOURCE_STATE, &playing));
    if (playing != AL_PLAYING) {
        OOAL(alSourcePlay(_source));
        if ((error = alGetError()) != AL_NO_ERROR) {
            OO_LOG("ov.debug", "Error {} playing source", static_cast<int>(error)); // %d of the ALuint
            return false;
        }
    }
    return true;
}

OOSound* OOSoundChannel::sound()
{
    return _sound.get();
}
