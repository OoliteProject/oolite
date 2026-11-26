/*

OOSoundSourcePool.h

Manages a fixed number of sound sources and distributes sounds between them.
Each sound has a priority and an expiry time. When a new sound is played, it
replaces (if possible) a sound of lower priority that has expired, a sound of
the same priority that has expired, or a sound of lower priority that has not
expired.

All sounds are specified by customsounds.plist key.

C++20 since bead oo-d2y9 (proposed ADR-0056, the Audio module: amendment oo-2en). Its Objective-C
facade was deleted by bead oo-9ht.89, and the class left namespace cxx.


Copyright (C) 2008-2013 Jens Ayton

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

#ifndef OOSOUNDSOURCEPOOL_H
#define OOSOUNDSOURCEPOOL_H

#include "OOFoundation.h"
#include "OOMaths.h"
#include "OOTypes.h"
#include "oofnd/objc/OOObject.h"

#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

struct OOSoundSourcePoolElement; // OOSoundSourcePool.mm

class OOSoundSourcePool : public oo::RefCounted {
public:
    /*	Was +poolWithCount:minRepeatTime:, alloc and -initWithCount:minRepeatTime:, which answered
            nil when the sources could not be allocated: null then.
    */
    static oo::Ref<OOSoundSourcePool> poolWithCount(uint8_t count, OOTimeDelta minRepeat);

    ~OOSoundSourcePool() override;

    /*	The selectors that share playSoundWithKey: are overloads (ADR-0056 item 3), told apart by
            the types of their arguments: a priority is a float and an overlap a bool, so a caller
            passes each with its own type (1.0f, true).
    */
    void playSoundWithKey(const std::string& key, float priority, OOTimeDelta expiryTime, bool overlap, Vector position);
    void playSoundWithKey(const std::string& key, float priority, OOTimeDelta expiryTime);
    void playSoundWithKey(const std::string& key, float priority); // expiryTime:0.1 +/- 0.5
    void playSoundWithKey(const std::string& key, float priority, Vector position); // expiryTime:0.1 +/- 0.5
    void playSoundWithKey(const std::string& key, Vector position); // expiryTime:0.1 +/- 0.5
    void playSoundWithKey(const std::string& key); // priority: 1.0, expiryTime:0.1 +/- 0.5
    void playSoundWithKey(const std::string& key, bool overlap); // if overlap == NO it waits for key to finish before playing key again
    void playSoundWithKey(const std::string& key, bool overlap, Vector position);

private:
    bool initWithCount(uint8_t count, OOTimeDelta minRepeat);
    uint8_t selectSlotForPriority(float priority);

    ::OOSoundSourcePoolElement* _sources = { };
    uint8_t _count = { };
    uint8_t _latest = { };
    uint8_t _reserved = { };
    OOTimeDelta _minRepeat = { };
    OOTimeAbsolute _nextRepeat = { };
    std::optional<std::string> _lastKey; // nullopt until a repeat-limited sound plays (proposed ADR-0043)
};

#endif // OOSOUNDSOURCEPOOL_H
