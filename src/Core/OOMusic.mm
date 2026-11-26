// OOMusic.m: Selects the appropriate music class source file
// depending on the operating system defined.
//
// Add new OS imports here. The -DOS_NAME flag in the GNUmakefile
// will select which one gets compiled.
//
// David Taylor, 2005-05-04

#ifdef LINUX
#import "SDLMusic.m"
#endif
