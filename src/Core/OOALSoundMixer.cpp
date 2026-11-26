/*

OOALSoundMixer.m

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

#include <assert.h>

#include "OOALSound.h"
#include "OOALSoundChannel.h"
#include "OOALSoundMixer.h"
#include "OOFoundation.h"

namespace {

OOSoundMixer* sSingleton = nullptr;

} // namespace

/*	The singleton category recorded the mixer in +allocWithZone:, before -init ran (amendment
        oo-z1s4 item 2); it is recorded first here too. -init's failure ([super release], which freed
        the mixer and left sSingleton pointing at it) leaves sSingleton null instead, and the next call
        asks again (amendment oo-r7m0 item 2): a dangling singleton was undefined behaviour.
*/
OOSoundMixer* OOSoundMixer::sharedMixer()
{
    if (nullptr == sSingleton) {
        sSingleton = oo::makeRef<OOSoundMixer>().leakRef();
        if (!sSingleton->init()) {
            OOSoundMixer* failed = sSingleton;
            sSingleton = nullptr;
            oo::release(failed);
        }
    }
    return sSingleton;
}

// The body of -init after [super init].
bool OOSoundMixer::init()
{
    bool OK = true;
    uint32_t idx = 0, count = kMixerGeneralChannels;
    oo::Ref<OOSoundChannel> channel;

    if (!OOSound::setUp())
        OK = false;

    if (OK) {
        // Allocate channels
        do {
            channel = oo::makeRef<OOSoundChannel>();
            if (!channel->init())
                channel = nullptr; // [[OOSoundChannel alloc] init] answered nil
            if (nullptr != channel) {
                pushChannel(channel.get());
                _channels[idx++] = channel.leakRef(); // the reference alloc/init gave
            }
        } while (--count);
    }

    return OK;
}

// only to be called at app shutdown by OOOpenALController::shutdown
void OOSoundMixer::shutdown()
{
    uint32_t i;
    for (i = 0; i < kMixerGeneralChannels; ++i) {
        if (_channels[i] != nullptr)
            oo::release(_channels[i]); // DESTROY
        _channels[i] = nullptr;
    }
}

void OOSoundMixer::update()
{
    uint32_t i;
    for (i = 0; i < kMixerGeneralChannels; ++i) {
        if (_channels[i] != nullptr)
            _channels[i]->update();
    }
}

OOSoundChannel* OOSoundMixer::popChannel()
{
    OOSoundChannel* channel = _freeList;
    _freeList = channel != nullptr ? channel->next() : nullptr; // a message to nil answered nil
    if (channel != nullptr)
        channel->setNext(nullptr);

    return channel;
}

void OOSoundMixer::pushChannel(OOSoundChannel* channel)
{
    assert(channel != nullptr);

    channel->setNext(_freeList);
    _freeList = channel;
}

// The singleton category (+allocWithZone:, -retain and the rest) is not translated: the mixer has
// no other creator and is never released (amendment oo-r7m0 item 1).
