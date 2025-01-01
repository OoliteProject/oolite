#import "OOCocoa.h"
#import "OOLoggingExtended.h"
#import "OODebugFlags.h"

#ifndef NDEBUG
/**
 * Global debug flags variable, only defined in Debug builds (NDEBUG not set).
 * Can be used to enable or disable specific debugging features at runtime.
 */
NSUInteger gDebugFlags = 0;
#endif

/**
 * \ingroup cli
 * @brief Main entry point for macOS. Initializes logging and runs the application.
 *
 * This function performs the following steps:
 *  1. Calls OOLoggingInit() to configure logging for the application.
 *  2. Invokes NSApplicationMain(), which loads the main nib (or storyboard),
 *     initializes NSApplication, and starts the event loop.
 *
 * @param argc Number of command-line arguments.
 * @param argv Array of C-string argument values.
 * @return The exit code returned by NSApplicationMain.
 */
int main(int argc, const char *argv[])
{
    // Initialize any custom logging subsystems or global log preferences.
    OOLoggingInit();

    // Launch the Cocoa application, transferring control to the event loop.
    return NSApplicationMain(argc, argv);
}
