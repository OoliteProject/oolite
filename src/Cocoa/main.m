#import "OOCocoa.h"
#import "OOLoggingExtended.h"


#ifndef NDEBUG
NSUInteger gDebugFlags = 0;
#endif


int main(int argc, const char *argv[])
{
	OOLoggingInit();
	return NSApplicationMain(argc, argv);
}

