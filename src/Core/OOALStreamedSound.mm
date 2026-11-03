/*

OOALStreamedSound.m


OOALStreamedSound - OpenAL sound implementation for Oolite.
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

#import "OOALStreamedSound.h"
#import "OOALSoundDecoder.h"

namespace cxx {

// The decoder is released by its oo::ObjCRef.
OOALStreamedSound::~OOALStreamedSound()
{
    free(_buffer);
    _buffer = NULL;
}

std::optional<std::string> OOALStreamedSound::name()
{
    return _name;
}

/*	The body of -initWithDecoder:, with self as the new sound; its [self release]; self = nil; is
        the null it answers. The decoder is still the Objective-C one, which the root's class cluster
        makes; [inDecoder retain] is the oo::ObjCRef.
*/
oo::Ref<OOALStreamedSound> OOALStreamedSound::initWithDecoder(::OOALSoundDecoder* inDecoder)
{
    bool OK = true;
    oo::Ref<OOALStreamedSound> self;

    setUp();
    if (!isSoundOK() || nil == inDecoder)
        OK = false;

    if (OK) {
        self = oo::adopt(new OOALStreamedSound);
    }

    if (OK) {
        self->_name = [inDecoder cxx_name];
        self->_sampleRate = [inDecoder sampleRate];
        self->_stereo = [inDecoder isStereo];
        self->_reachedEnd = false;
        self->_buffer = (char*)malloc(OOAL_STREAM_CHUNK_SIZE);
        self->decoder = oo::ObjCRef<::OOALSoundDecoder*>(inDecoder);
        self->rewind();
    }

    if (!OK) {
        self = nullptr;
    }
    return self;
}

void OOALStreamedSound::rewind()
{
    [decoder.get() reset];
    _reachedEnd = false;
}

bool OOALStreamedSound::soundIncomplete()
{
    return !_reachedEnd;
}

ALuint OOALStreamedSound::soundBuffer()
{
    size_t transferred = [decoder.get() streamToBuffer:_buffer];
    if (transferred < OOAL_STREAM_CHUNK_SIZE) {
        // otherwise keep going
        _reachedEnd = true;
    }

    ALuint buffer;
    ALint error;
    OOAL(alGenBuffers(1, &buffer));
    if ((error = alGetError()) != AL_NO_ERROR) {
        OO_LOG(kOOLogSoundLoadingError, "{}", "Could not create OpenAL buffer");
        return 0;
    } else {
        if (!_stereo) {
            alBufferData(buffer, AL_FORMAT_MONO16, _buffer, (ALsizei)transferred, _sampleRate);
        } else {
            alBufferData(buffer, AL_FORMAT_STEREO16, _buffer, (ALsizei)transferred, _sampleRate);
        }
        return buffer;
    }
}

} // namespace cxx
