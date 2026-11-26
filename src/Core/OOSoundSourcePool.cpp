/*

OOSoundSourcePool.m


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

#include "OOSoundSourcePool.h"
#include "OOSound.h"
#include "Universe.h"

enum {
    kNoSlot = UINT8_MAX
};

typedef struct OOSoundSourcePoolElement {
    OOSoundSource* source; // one retain, or null (C++ since bead oo-9ht.88)
    OOTimeAbsolute expiryTime;
    float priority;
} PoolElement;

oo::Ref<OOSoundSourcePool> OOSoundSourcePool::poolWithCount(uint8_t count, OOTimeDelta minRepeat)
{
    oo::Ref<OOSoundSourcePool> pool = oo::makeRef<OOSoundSourcePool>();
    if (!pool->initWithCount(count, minRepeat))
        return nullptr;
    return pool;
}

// The body of -initWithCount:minRepeatTime: after [super init]; [self release]; self = nil; is false.
bool OOSoundSourcePool::initWithCount(uint8_t count, OOTimeDelta minRepeat)
{
    {
        // Sanity-check count
        if (count == 0)
            count = 1;
        if (count == kNoSlot)
            --count;
        _count = count;
        _reserved = kNoSlot;

        if (minRepeat < 0.0)
            minRepeat = 0.0;
        _minRepeat = minRepeat;

        // Create source pool
        _sources = (PoolElement*)calloc(sizeof(PoolElement), count);
        if (_sources == NULL) {
            return false;
        }
    }
    return true;
}

OOSoundSourcePool::~OOSoundSourcePool()
{
    uint8_t i;

    for (i = 0; i != _count; i++) {
        oo::release(_sources[i].source);
    }
    free(_sources);
}

/*	The sounds and the sources are C++ since beads oo-9ht.68 and oo-9ht.88 deleted their facades:
        the sound for a key is OOSoundWithCustomSoundKey() (Universe.h) and the pool makes its sources
        (its test stands in for both; amendment oo-rmd7 item 3).
*/
void OOSoundSourcePool::playSoundWithKey(const std::string& key,
    float priority,
    OOTimeDelta expiryTime,
    bool overlap,
    Vector position)
{
    uint8_t slot;
    OOTimeAbsolute now, absExpiryTime;
    PoolElement* element = NULL;
    ::OOSound* sound = NULL;

    // Convert expiry time to absolute
    now = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0);
    absExpiryTime = expiryTime + now;

    // Avoid repeats if required
    if (now < _nextRepeat && _lastKey == key)
        return;
    if (!overlap && _reserved != kNoSlot && _sources[_reserved].source != nullptr && _sources[_reserved].source->isPlaying())
        return;

    // Look for a slot in the source list to use
    slot = selectSlotForPriority(priority);
    if (slot == kNoSlot)
        return;
    element = &_sources[slot];

    // Load sound
    sound = OOSoundWithCustomSoundKey(key);
    if (sound == nullptr)
        return;

    // Stop playing sound or set up sound source as appropriate
    if (element->source != nullptr)
        element->source->stop();
    else {
        element->source = oo::makeRef<::OOSoundSource>().leakRef();
        if (element->source == nullptr)
            return;
    }
    if (slot == _reserved)
        _reserved = kNoSlot; // _reserved has finished playing!
    if (!overlap)
        _reserved = slot;

    // Play and store metadata
    element->source->setPosition(position);
    element->source->playOOSound(sound);
    element->expiryTime = absExpiryTime;
    element->priority = priority;
    if (_minRepeat > 0.0) {
        _nextRepeat = now + _minRepeat;
        _lastKey = key;
    }

    // Set staring search location for next slot lookup
    _latest = slot;
}

void OOSoundSourcePool::playSoundWithKey(const std::string& key,
    float priority,
    OOTimeDelta expiryTime)
{
    playSoundWithKey(key,
        priority,
        expiryTime,
        true,
        kZeroVector);
}

void OOSoundSourcePool::playSoundWithKey(const std::string& key,
    float priority,
    Vector position)
{
    playSoundWithKey(key,
        priority,
        0.5 + randf() * 0.1,
        true,
        position);
}

void OOSoundSourcePool::playSoundWithKey(const std::string& key,
    float priority)
{
    playSoundWithKey(key,
        priority,
        0.5 + randf() * 0.1);
}

void OOSoundSourcePool::playSoundWithKey(const std::string& key)
{
    playSoundWithKey(key, 1.0f);
}

void OOSoundSourcePool::playSoundWithKey(const std::string& key, Vector position)
{
    playSoundWithKey(key, 1.0f, position);
}

void OOSoundSourcePool::playSoundWithKey(const std::string& key, bool overlap)
{
    playSoundWithKey(key,
        1.0f,
        0.5,
        overlap,
        kZeroVector);
}

void OOSoundSourcePool::playSoundWithKey(const std::string& key, bool overlap, Vector position)
{
    playSoundWithKey(key,
        1.0f,
        0.5,
        overlap,
        position);
}

// The private category's method.
uint8_t OOSoundSourcePool::selectSlotForPriority(float priority)
{
    uint8_t curr, count, expiredLower = kNoSlot, unexpiredLower = kNoSlot, expiredEqual = kNoSlot;
    PoolElement* element = NULL;
    OOTimeAbsolute now = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0);

#define NEXT(x) (((x) + 1) % _count)

    curr = _latest;
    count = _count;
    do {
        curr = NEXT(curr);
        element = &_sources[curr];

        if (element->source == nullptr || !element->source->isPlaying())
            return curr; // Best type of slot: empty
        else if (element->priority < priority) {
            if (element->expiryTime <= now)
                expiredLower = curr; // Second-best type: expired lower-priority
            else if (curr != _reserved)
                unexpiredLower = curr; // Third-best type: unexpired lower-priority
        } else if (element->priority == priority && element->expiryTime <= now) {
            expiredEqual = curr; // Fourth-best type: expired equal-priority.
        }
    } while (--count);

    if (expiredLower != kNoSlot)
        return expiredLower;
    if (unexpiredLower != kNoSlot)
        return unexpiredLower;
    return expiredEqual; // Will be kNoSlot if none found
}
