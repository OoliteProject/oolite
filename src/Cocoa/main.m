//#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "OOLogging.h"


int debug = 0;

int main(int argc, const char *argv[])
{
	OOLoggingInit();
    return NSApplicationMain(argc, argv);
}

