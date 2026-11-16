/*

OOALSoundMixer.h

Class responsible for managing and mixing sound channels. This class is an
implementation detail. Do not use it directly; use an OOSoundSource to play an
OOSound.

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

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@class OOSoundChannel;

enum {
    kMixerGeneralChannels = 32
};

@interface OOSoundMixer : OOObject {
    OOSoundChannel* _channels[kMixerGeneralChannels];
    OOSoundChannel* _freeList;

    uint32_t _maxChannels;
    uint32_t _playMask;
}

// Singleton accessor
+ (id)sharedMixer;

- (void)update;

// Only to be called at app shutdown, by OOOpenALController::shutdown(). (Declared here since
// bead oo-r7m0: the declaration it resolved to was OOOpenALController's own -shutdown.)
- (void)shutdown;

- (OOSoundChannel*)popChannel;
- (void)pushChannel:(OOSoundChannel*)channel;

@end
