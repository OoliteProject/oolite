/*
 * NSBundle+Override.m
 *
 * Oolite Core Framework Override
 * Bypasses standard plist loading to manually locate and parse info-gnustep.plist
 * across Windows, macOS, and Linux environments safely at boot.
 */

#import "NSBundle+Override.h"
#import <Foundation/NSFileManager.h>
#import <Foundation/NSPathUtilities.h>
#import <Foundation/NSDictionary.h>

#if OOLITE_LINUX
#import <unistd.h>
#import <limits.h>
#endif

@implementation NSBundle (Override)

- (NSDictionary *)infoDictionary {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *startingDir = nil;
    NSString *resourcesFolder = nil;

#if OOLITE_WINDOWS
    // Windows: Start from the forced local working directory
    startingDir = [@"./" stringByStandardizingPath];
#else
    // Linux/GNUstep: Read from the kernel to avoid calling [[NSBundle mainBundle] executablePath],
    // which would cause an infinite loop during early bundle initialization.
    char result[PATH_MAX];
    ssize_t count = readlink("/proc/self/exe", result, PATH_MAX);
    if (count != -1) {
        NSString *exePath = [fileManager stringWithFileSystemRepresentation:result length:count];
        startingDir = [exePath stringByDeletingLastPathComponent];
    } else {
        // Fallback to local directory if /proc is inaccessible
        startingDir = [@"./" stringByStandardizingPath];
    }
#endif

    // If resourcesFolder wasn't explicitly assigned by the macOS branch, resolve it for Win/Linux
    if (!resourcesFolder) {
        NSString *primaryResourcesPath = [startingDir stringByAppendingPathComponent:@"Resources"];
        BOOL isDir = NO;

        if ([fileManager fileExistsAtPath:primaryResourcesPath isDirectory:&isDir] && isDir) {
            resourcesFolder = primaryResourcesPath;
        } else {
            // Fallback: Look in startingDir / ../share/oolite/Resources (Standard Linux system layout)
            NSString *fallbackPath = [[startingDir stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"share/oolite/Resources"];
            resourcesFolder = [fallbackPath stringByStandardizingPath];
        }
    }

    // Append the target file name to the resolved path root
    NSString *plistPath = [resourcesFolder stringByAppendingPathComponent:@"Info-gnustep.plist"];

    // Load the target configuration file
    NSDictionary *gnustepPlist = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    NSMutableDictionary *workingDict = nil;

    if (gnustepPlist) {
        workingDict = [gnustepPlist mutableCopy];
    } else {
        // Fallback block prevents runtime crashes if files are missing during dev/build refactors
        workingDict = [[NSMutableDictionary alloc] init];
        NSLog(@"[Oolite-Core] Warning: Failed to find info-gnustep.plist at calculated path: %@", plistPath);
    }

    // Return the dictionary cleanly managed for memory (Pre-ARC environments)
    return [workingDict autorelease];
}

@end