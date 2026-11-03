/*

OOALBufferedSound.h

OOALBufferedSound - OpenAL sound implementation for Oolite.

C++20 since bead oo-2wpb (proposed ADR-0056, the Audio module: amendment oo-2en): a subclass of
OOSound. Bead oo-9ht.83 deleted its Objective-C facade and moved it to the global namespace; the root's
class cluster makes it from the C++ decoder (bead oo-9ht.82).

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

#ifndef OOALBUFFEREDSOUND_H
#define OOALBUFFEREDSOUND_H

#include "OOALSound.h"

class OOALSoundDecoder; // only named here (OOALSoundDecoder.h)

#include "oofnd/StdLib.hpp"

class OOALBufferedSound : public OOSound {
public:
    /*	Was -initWithDecoder:, which decoded the whole sound: null where it answered nil (sound not
            OK, no decoder, or the decoder could not read the sound).
    */
    static oo::Ref<OOALBufferedSound> initWithDecoder(OOALSoundDecoder* inDecoder);

    ~OOALBufferedSound() override;

    std::optional<std::string> name() override;
    ALuint soundBuffer() override;

private:
    friend struct OOALBufferedSoundTestAccess; // the stand-ins of tests that stub the sound (bead oo-9ht.83)

    OOALBufferedSound() = default;

    char* _buffer = { };
    size_t _size = { };
    double _sampleRate = { };
    std::optional<std::string> _name; // nil-able, as the name was (proposed ADR-0043)
    bool _stereo = { };
};

#endif // OOALBUFFEREDSOUND_H
