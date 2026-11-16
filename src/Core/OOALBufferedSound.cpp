/*

OOALBufferedSound.m


OOALBufferedSound - OpenAL sound implementation for Oolite.
Copyright (C) 2005-2013 Jens Ayton

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

#include "OOALBufferedSound.h"
#include "OOALSoundDecoder.h"

#include "oofnd/Log.hpp"

OOALBufferedSound::~OOALBufferedSound()
{
    free(_buffer);
    _buffer = NULL;
}

std::optional<std::string> OOALBufferedSound::name()
{
    return _name;
}

/*	The body of -initWithDecoder:, with self as the new sound; its [self release]; self = nil; is
        the null it answers (the object is freed as the release freed it). The decoder is the C++ one
        since bead oo-9ht.82.
*/
oo::Ref<OOALBufferedSound> OOALBufferedSound::initWithDecoder(OOALSoundDecoder* inDecoder)
{
    bool OK = true;
    oo::Ref<OOALBufferedSound> self;

    setUp();
    if (!isSoundOK() || nullptr == inDecoder)
        OK = false;

    if (OK) {
        self = oo::adopt(new OOALBufferedSound);
    }

    if (OK) {
        self->_name = inDecoder->name();
        self->_sampleRate = inDecoder->sampleRate();
        OK = inDecoder->readCreatingBuffer(&self->_buffer, &self->_size);
        self->_stereo = inDecoder->isStereo();
    }

    if (!OK) {
        self = nullptr;
    }
    return self;
}

ALuint OOALBufferedSound::soundBuffer()
{
    ALuint buffer;
    ALint error;
    OOAL(alGenBuffers(1, &buffer));
    if ((error = alGetError()) != AL_NO_ERROR) {
        OO_LOG(kOOLogSoundLoadingError, "{}", "Could not create OpenAL buffer");
        return 0;
    } else {
        if (!_stereo) {
            alBufferData(buffer, AL_FORMAT_MONO16, _buffer, (ALsizei)_size, _sampleRate);
        } else {
            alBufferData(buffer, AL_FORMAT_STEREO16, _buffer, (ALsizei)_size, _sampleRate);
        }
        return buffer;
    }
}
