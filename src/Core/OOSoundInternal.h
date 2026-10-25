#pragma once

#include "OOSound.h"

#if OOLITE_OPENAL

#include "OOALSoundMixer.h"
#include "OOALSoundChannel.h"

#define OOSoundAcquireLock() do {} while(0)
#define OOSoundReleaseLock() do {} while(0)

#else

#warning No sound implementation selected. Currently, the only option is OOLITE_OPENAL. There are SDL and Mac CoreAudio implementations in the revision history.

#endif
