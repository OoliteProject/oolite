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
	NSString *startingDir = [fileManager currentDirectoryPath];  // Start from cwd

	NSString *primaryResourcesPath = [startingDir stringByAppendingPathComponent:@"Resources"];
	BOOL isDir = NO;

	NSString *resourcesFolder = nil;
	if ([fileManager fileExistsAtPath:primaryResourcesPath isDirectory:&isDir] && isDir) {
		resourcesFolder = primaryResourcesPath;
	} else {
		// Fallback: Look in startingDir / ../share/oolite/Resources (Standard Linux system layout)
		NSString *fallbackPath = [[startingDir stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"share/oolite/Resources"];
		resourcesFolder = [fallbackPath stringByStandardizingPath];
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

	// Return the dictionary cleanly managed for memory
	return [workingDict autorelease];
}

@end