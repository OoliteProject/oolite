/*

NSFileManagerOOExtensions.m

This extends NSFileManager and adds some methods to insulate the
main oolite code from the gory details of creating/chdiring to the
commander save directory.

Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#include <stdlib.h>
#import "ResourceManager.h"
#import "OOPListParsing.h"
#import "GameController.h"
#import "NSFileManagerOOExtensions.h"

#define kOOLogUnconvertedNSLog @"unclassified.NSFileManagerOOExtensions"


@implementation NSFileManager (OOExtensions)

- (NSArray *) commanderContentsOfPath:(NSString *)savePath
{
	BOOL pathIsDirectory = NO;
	if ([[NSFileManager defaultManager] fileExistsAtPath:savePath isDirectory:&pathIsDirectory] && pathIsDirectory)
	{
		NSMutableArray *contents = [NSMutableArray arrayWithArray:[self oo_directoryContentsAtPath:savePath]];
		
		// at this point we should strip out any files not loadable as Oolite saved games
		unsigned i;
		for (i = 0; i < [contents count]; i++)
		{
			NSString* path = [savePath stringByAppendingPathComponent: (NSString*)[contents objectAtIndex:i]];
			
			// ensure it's not a directory
			if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&pathIsDirectory] && pathIsDirectory)
			{
				
				// check file extension
				if (![[path pathExtension] isEqual:@"oolite-save"])
				{
					[contents removeObjectAtIndex: i--];
					continue;
				}
				
				// check to see if we can parse the file okay
				NSDictionary *cdr = OODictionaryFromFile(path); 
				if (!cdr)
				{
					OOLog(@"savedGame.read.fail.notDictionary", @">>>> %@ could not be parsed as a saved game.", path);
					[contents removeObjectAtIndex: i--];
					continue;
				}
			}
			
			// all okay - we can use this path!
			[contents replaceObjectAtIndex: i withObject: path];
			
		}
		
		return contents;
	}
	else
	{
		OOLogERR(@"savedGame.read.fail.fileNotFound", @"File at path '%@' could not be found.", savePath);
		return nil;
	}
}


- (NSString *) defaultCommanderPath
{
	NSString *savedir = [NSHomeDirectory() stringByAppendingPathComponent:@SAVEDIR];
	BOOL pathIsDirectory = NO;
	
	// does it exist?
	if (![[NSFileManager defaultManager] fileExistsAtPath:savedir isDirectory:&pathIsDirectory])
	{
		// it doesn't exist.
		if([self oo_createDirectoryAtPath:savedir attributes:nil])
		{
			return savedir;
		}
		else
		{
			OOLogERR(@"savedGame.defaultPath.create.failed", @"Unable to create '%@'. Saved games will go to the home directory.", savedir);
			return NSHomeDirectory();
		}
	}
	
	// is it a directory?
	if (!pathIsDirectory)
	{
		OOLogERR(@"savedGame.defaultPath.notDirectory", @"'%@' is not a directory, saved games will go to the home directory.", savedir);
		return NSHomeDirectory();
	}
	
	return savedir;
}


#if OOLITE_MAC_OS_X

- (NSArray *) oo_directoryContentsAtPath:(NSString *)path
{
	return [self contentsOfDirectoryAtPath:path error:NULL];
}


- (BOOL) oo_createDirectoryAtPath:(NSString *)path attributes:(NSDictionary *)attributes
{
	return [self createDirectoryAtPath:path withIntermediateDirectories:NO attributes:attributes error:NULL];
}


- (NSDictionary *) oo_fileAttributesAtPath:(NSString *)path traverseLink:(BOOL)traverseLink
{
	if (traverseLink)
	{
		NSString *linkDest = nil;
		do
		{
			linkDest = [self destinationOfSymbolicLinkAtPath:path error:NULL];
			if (linkDest != nil)  path = linkDest;
		} while (linkDest != nil);
	}
	
	return [self attributesOfItemAtPath:path error:NULL];
}


- (NSDictionary *) oo_fileSystemAttributesAtPath:(NSString *)path
{
	return [self attributesOfFileSystemForPath:path error:NULL];
}


- (BOOL) oo_removeItemAtPath:(NSString *)path
{
	return [self removeItemAtPath:path error:NULL];
}


- (BOOL) oo_moveItemAtPath:(NSString *)src toPath:(NSString *)dest
{
	return [self moveItemAtPath:src toPath:dest error:NULL];
}

#else

- (NSArray *) oo_directoryContentsAtPath:(NSString *)path
{
	return [self directoryContentsAtPath:path];
}


- (BOOL) oo_createDirectoryAtPath:(NSString *)path attributes:(NSDictionary *)attributes
{
	return [self createDirectoryAtPath:path attributes:attributes];
}


- (NSDictionary *) oo_fileAttributesAtPath:(NSString *)path traverseLink:(BOOL)yorn
{
	return [self fileAttributesAtPath:path traverseLink:yorn];
}


- (NSDictionary *) oo_fileSystemAttributesAtPath:(NSString *)path
{
	return [self fileSystemAttributesAtPath:path];
}


- (BOOL) oo_removeItemAtPath:(NSString *)path
{
	return [self removeFileAtPath:path handler:nil];
}


- (BOOL) oo_moveItemAtPath:(NSString *)src toPath:(NSString *)dest
{
	return [self movePath:src toPath:dest handler:nil];
}

#endif


#if OOLITE_SDL
- (BOOL) chdirToSnapshotPath
{
	// SDL: the default path for snapshots is oolite.app/oolite-saves/snapshots
	NSString *savedir = [[NSHomeDirectory() stringByAppendingPathComponent:@SAVEDIR] stringByAppendingPathComponent:@SNAPSHOTDIR];
	
	if (![self changeCurrentDirectoryPath: savedir])
	{
	   // it probably doesn't exist.
		if (![self createDirectoryAtPath: savedir attributes: nil])
		{
			OOLog(@"savedSnapshot.defaultPath.create.failed", @"Unable to create directory %@", savedir);
			return NO;
		}
		if (![self changeCurrentDirectoryPath: savedir])
		{
			OOLog(@"savedSnapshot.defaultPath.chdir.failed", @"Created %@ but couldn't make it the current directory.", savedir);
			return NO;
		}
	}
	
	return YES;
}
#endif

@end


