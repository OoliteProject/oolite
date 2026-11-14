/*

OOALStreamedSound.h

OOALStreamedSound - OpenAL sound implementation for Oolite.

C++20 since bead oo-03g7 (proposed ADR-0056, the Audio module: amendment oo-2en). The class is
cxx::OOALStreamedSound, a subclass of cxx::OOSound, while OOALStreamedSound+ObjCBridge.h, imported
at the end of this header, keeps the Objective-C OOALStreamedSound that the root's class cluster
makes (OOALSound.mm, whose test stubs it); the bridge's deletion bead moves it out of namespace cxx.

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

#ifndef OOALSTREAMEDSOUND_H
#define OOALSTREAMEDSOUND_H

#import "OOALSoundDecoder.h"
#import "OOSound.h"

#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

namespace cxx {

class OOALStreamedSound : public OOSound {
public:
    /*	Was -initWithDecoder:, which kept the decoder to stream from: null where it answered nil
            (sound not OK, or no decoder).
    */
    static oo::Ref<OOALStreamedSound> initWithDecoder(::OOALSoundDecoder* inDecoder);

    ~OOALStreamedSound() override;

    std::optional<std::string> name() override;
    void rewind() override;
    bool soundIncomplete() override;
    ALuint soundBuffer() override;

private:
    OOALStreamedSound() = default;

    char* _buffer = { };
    // (The Objective-C class's _size, which nothing read or wrote, is not kept: -Wunused-private-field.)
    double _sampleRate = { };
    std::optional<std::string> _name; // nil-able, as the name was (proposed ADR-0043)
    bool _stereo = { };
    oo::ObjCRef<::OOALSoundDecoder*> decoder; // the Objective-C decoder, retained as before
    bool _reachedEnd = { };
};

} // namespace cxx

// Transitional: the Objective-C OOALStreamedSound, for the root's class cluster.
// Deleted, with namespace cxx above, by the bridge's deletion bead.
#import "OOALStreamedSound+ObjCBridge.h"

#endif // OOALSTREAMEDSOUND_H
