/*

OOALSound.h

OOALSound - OpenAL sound implementation for Oolite.

C++20 since bead oo-2en, the Audio module's pattern seam (proposed ADR-0056, amendment oo-2en).
The class is cxx::OOSound while OOALSound+ObjCBridge.h, imported at the end of this header, keeps
the Objective-C OOSound that its callers message and its unconverted subclasses
(OOALBufferedSound, OOALStreamedSound, OOMusic) derive from; the bridge's deletion bead moves it
out of namespace cxx.

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

#ifndef OOALSOUND_H
#define OOALSOUND_H

#import "OOFoundation.h"
#import "OOOpenALController.h"
#import "oofnd/objc/OOObject.h"

#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

@class OOSound;

namespace cxx {

class OOSound : public oo::RefCounted {
public:
    OOSound();

    static bool setUp();
    static void update();

    static void setMasterVolume(float fraction);
    static float masterVolume();

    /*	Was -cxx_initWithContentsOfFile:, a class cluster's initialiser: it answered, in place of
            the receiver, an OOALBufferedSound for up to 1 MB of decoded data, else an
            OOALStreamedSound. The result is the Objective-C object (the sound's root facade, an
            OOSound, since beads oo-9ht.83 and oo-9ht.84), retained (proposed
            ADR-0056, amendment oo-smy item 4: an Objective-C sound's C++ part does not retain it).
            Null where it answered nil: sound not OK, no decoder for the path, or the concrete sound
            refused.
    */
    static oo::ObjCRef<::OOSound*> initWithContentsOfFile(const std::optional<std::string>& path); // nullopt: null (bead oo-3rb.292.2)

    virtual std::optional<std::string> name(); // nullopt: none (bead oo-3rb.289.3)

    static bool isSoundOK();

    virtual ALuint soundBuffer();
    virtual bool soundIncomplete();
    virtual void rewind();

    // What "%@" prints between the braces of <Class 0x...>{...} (OODescription.h). None here, as
    // OOObject answered.
    virtual std::optional<std::string> descriptionComponents() const;
};

} // namespace cxx

// Transitional: the Objective-C OOSound, for callers and subclasses not yet converted.
// Deleted, with namespace cxx above, by the bridge's deletion bead.
#import "OOALSound+ObjCBridge.h"

#endif // OOALSOUND_H
