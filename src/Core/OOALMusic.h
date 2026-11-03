/*

OOALMusic.h

Subclass of OOSound with additional controls specific to music playback. Only
one instance of OOMusic may be playing at a time.

C++20 since bead oo-nwbw (proposed ADR-0056, the Audio module: amendment oo-2en). The class is
cxx::OOMusic, a subclass of cxx::OOSound, while OOALMusic+ObjCBridge.h, imported at the end of this
header, keeps the Objective-C OOMusic that the resource manager makes and the music controller
messages; the bridge's deletion bead moves it out of namespace cxx.


OOALSound - OpenAL sound implementation for Oolite.
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

#ifndef OOALMUSIC_H
#define OOALMUSIC_H

#import "OOALSound.h"
#import "OOFoundation.h"
#import "OOSoundSource.h"

#include "oofnd/objc/OOObjCRef.h"

namespace cxx {

class OOMusic : public OOSound {
public:
    /*	Was -cxx_initWithContentsOfFile:, OOSound's designated initialiser overridden: a music that
            wraps the sound the root's class cluster loads for the path. Null where it answered nil. It
            hides the root's factory of the same name (amendment oo-2en item 3).
    */
    static oo::Ref<OOMusic> initWithContentsOfFile(const std::optional<std::string>& inPath);

    ~OOMusic() override;

    std::optional<std::string> name() override;

    void playLooped(bool looped);
    void stop();
    bool isPlaying();
    void setMusicGain(float newValue);
    float musicGain();
    ::OOSoundSource* musicSoundSource();

private:
    OOMusic() = default;

    // The root's cluster answers an Objective-C sound, which its C++ part does not keep alive
    // (amendment oo-smy item 4): the Objective-C object is kept, retained as before.
    oo::ObjCRef<::OOSound*> sound;
};

} // namespace cxx

// Transitional: the Objective-C OOMusic, for the resource manager and the music controller.
// Deleted, with namespace cxx above, by the bridge's deletion bead.
#import "OOALMusic+ObjCBridge.h"

#endif // OOALMUSIC_H
