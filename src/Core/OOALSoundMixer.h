/*

OOALSoundMixer.h

Class responsible for managing and mixing sound channels. This class is an
implementation detail. Do not use it directly; use an OOSoundSource to play an
OOSound.

The sound sources, the root sound and the OpenAL controller call
OOSoundMixer::sharedMixer(), null-guarded.

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

#pragma once

#include "OOFoundation.h"
#include "oofnd/Object.hpp"
#include "oofnd/objc/OOObject.h"

class OOSoundChannel;

inline constexpr int kMixerGeneralChannels = 32;

class OOSoundMixer : public oo::Object {
 public:
  /*	Singleton accessor: the one mixer, made on
     first use; borrowed. Null while sound cannot be set up, and then the next
     call asks again.
  */
  static OOSoundMixer* sharedMixer();

  void update();

  // Only to be called at app shutdown, by OOOpenALController::shutdown().
  void shutdown();

  OOSoundChannel* popChannel();
  void pushChannel(OOSoundChannel* channel);

 private:
  bool init();

  // _channels shares each channel the mixer made until shutdown() (as
  // alloc/init and DESTROY did); the free list is borrowed.
  std::shared_ptr<OOSoundChannel> _channels[kMixerGeneralChannels];
  OOSoundChannel* _freeList = {};
};
