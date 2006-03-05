// OOSound.m: Selects the appropriate sound class source file
// depending on the operating system defined.
//
// Add new OS imports here. The -DOS_NAME flag in the GNUmakefile
// will select which one gets compiled.
//
// Dylan Smith, 2005-04-22

#ifdef LINUX
#import "SDLSound.m"
#endif

