#import "OOSound.h"

#if OOLITE_OPENAL

#import "OOALSoundMixer.h"
#import "OOALSoundChannel.h"

#define OOSoundAcquireLock() do {} while(0)
#define OOSoundReleaseLock() do {} while(0)

#elif OOLITE_SDL

#import "OOSDLSoundMixer.h"
#import "OOSDLSoundChannel.h"

#define OOSoundAcquireLock() do {} while(0)
#define OOSoundReleaseLock() do {} while(0)

#elif OOLITE_MAC_OS_X

#import "OOCASoundMixer.h"
#import "OOCASoundChannel.h"

extern NSRecursiveLock	*gOOCASoundSyncLock;

#define OOSoundAcquireLock() [gOOCASoundSyncLock lock]
#define OOSoundReleaseLock() [gOOCASoundSyncLock unlock]

#endif
