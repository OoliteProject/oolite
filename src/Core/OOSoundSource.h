// OOSoundSource.h: Selects the appropriate sound class source file
// depending on the operating system defined.
//
// Add new OS imports here. The -DOS_NAME flag in the GNUmakefile
// will select which one gets compiled.
//
// Jens Ayton, 2005-11-24

#if defined(LINUX) || defined(OOLITE_SDL_MAC)
#import "OOBasicSoundSource.h"
#else
#import "OOCASoundSource.h"
#endif

