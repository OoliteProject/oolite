// OOSound.h: Selects the appropriate sound class source file
// depending on the operating system defined.
//
// Add new OS imports here. The -DOS_NAME flag in the GNUmakefile
// will select which one gets compiled.
//
// You should make your sound class a child of NSSound (so you get
// the sound loading functions of NSSound) and call it OOSound.
//
// Dylan Smith, 2005-04-22

#ifdef LINUX
#import "OOAlsaSound.h"
#endif

