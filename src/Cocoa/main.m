#import "OOCocoa.h"
#import "OOLoggingExtended.h"
#import "OODebugFlags.h"


#ifndef NDEBUG
NSUInteger gDebugFlags = 0;
#endif

/**
 * \ingroup cli
 * Entry point for MacOS. Initializes logging and runs NSApplicationMain.
 *
 * @param argc the number of command line arguments
 * @param argv the string array values of the command line arguments
 * @return whatever NSApplicationMain returns
 */
int main(int argc, const char *argv[])
{
	OOLoggingInit();
	return NSApplicationMain(argc, argv);
}

