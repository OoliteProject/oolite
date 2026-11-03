/*

NSFileManagerOOExtensions.m

Category helpers that insulate the main oolite code from the gory details of
creating/chdiring to the commander save directory. Internals use oo::fs where
a direct file-manager call used to; the category itself is retired by oo-pwz0
once remaining callers move off it.

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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

#import "NSFileManagerOOExtensions.h"
#import "OOFoundationBridge.h"
#import "OOStringBridge.h"
#include "oofnd/FileSystem.hpp"
#include "oofnd/Log.hpp"
#include "oofnd/ResourcePaths.hpp"
#include "oofnd/String.hpp"
#import "unzip.h"
#include <stdlib.h>

@implementation NSFileManager (OOExtensions)

- (NSArray*)commanderContentsOfPath:(NSString*)savePath
{
    const oo::fs::Path saveFsPath = oo::fs::pathFromUTF8(oo::StdString(savePath));
    if (oo::fs::fileType(saveFsPath) == oo::fs::FileType::directory) {
        NSMutableArray* contents = [NSMutableArray arrayWithArray:[self oo_directoryContentsAtPath:savePath]];

        // Historical filter tested `!exists && isDirectory`, which never holds, so every entry
        // becomes a full path (see PlayerEntityLoadSave.mm lsCommanders).
        unsigned i;
        for (i = 0; i < [contents count]; i++) {
            NSString* path = [savePath stringByAppendingPathComponent:(NSString*)[contents objectAtIndex:i]];
            [contents replaceObjectAtIndex:i withObject:path];
        }

        return contents;
    } else {
        OO_LOG_ERR("savedGame.read.fail.fileNotFound", "File at path '{}' could not be found.", oo::DescriptionOf(savePath));
        return nil;
    }
}

- (NSString*)defaultCommanderPath
{
    const oo::ResourcePaths paths = oo::ResourcePaths::current();
    const oo::fs::Path savedir = paths.saveDirectory();
    const oo::fs::FileType type = oo::fs::fileType(savedir);

    // does it exist?
    if (type == oo::fs::FileType::none) {
        // it doesn't exist.
        if (oo::fs::createDirectories(savedir)) {
            return oo::NSStringFrom(oo::fs::utf8String(savedir));
        } else {
            OO_LOG_ERR("savedGame.defaultPath.create.failed", "Unable to create '{}'. Saved games will go to the home directory.", oo::fs::utf8String(savedir));
            return oo::NSStringFrom(oo::fs::utf8String(paths.homeDirectory()));
        }
    }

    // is it a directory?
    if (type != oo::fs::FileType::directory) {
        OO_LOG_ERR("savedGame.defaultPath.notDirectory", "'{}' is not a directory, saved games will go to the home directory.", oo::fs::utf8String(savedir));
        return oo::NSStringFrom(oo::fs::utf8String(paths.homeDirectory()));
    }

    return oo::NSStringFrom(oo::fs::utf8String(savedir));
}

#if OOLITE_MAC_OS_X

- (NSArray*)oo_directoryContentsAtPath:(NSString*)path
{
    return [self contentsOfDirectoryAtPath:path error:NULL];
}

- (BOOL)oo_createDirectoryAtPath:(NSString*)path attributes:(NSDictionary*)attributes
{
    (void)attributes;
    return static_cast<BOOL>(static_cast<bool>(oo::fs::createDirectories(oo::fs::pathFromUTF8(oo::StdString(path)))));
}

- (NSDictionary*)oo_fileAttributesAtPath:(NSString*)path traverseLink:(BOOL)traverseLink
{
    if (traverseLink) {
        NSString* linkDest = nil;
        do {
            linkDest = [self destinationOfSymbolicLinkAtPath:path error:NULL];
            if (linkDest != nil)
                path = linkDest;
        } while (linkDest != nil);
    }

    return [self attributesOfItemAtPath:path error:NULL];
}

- (NSDictionary*)oo_fileSystemAttributesAtPath:(NSString*)path
{
    return [self attributesOfFileSystemForPath:path error:NULL];
}

- (BOOL)oo_removeItemAtPath:(NSString*)path
{
    return static_cast<BOOL>(static_cast<bool>(oo::fs::removeItem(oo::fs::pathFromUTF8(oo::StdString(path)))));
}

- (BOOL)oo_moveItemAtPath:(NSString*)src toPath:(NSString*)dest
{
    return static_cast<BOOL>(static_cast<bool>(oo::fs::moveItem(
        oo::fs::pathFromUTF8(oo::StdString(src)),
        oo::fs::pathFromUTF8(oo::StdString(dest)))));
}

#else

- (NSArray*)oo_directoryContentsAtPath:(NSString*)path
{
    const auto names = oo::fs::directoryContents(oo::fs::pathFromUTF8(oo::StdString(path)));
    if (!names)
        return nil;
    return oo::NSArrayFromStrings(*names);
}

- (BOOL)oo_createDirectoryAtPath:(NSString*)path attributes:(NSDictionary*)attributes
{
    (void)attributes;
    return static_cast<BOOL>(static_cast<bool>(oo::fs::createDirectories(oo::fs::pathFromUTF8(oo::StdString(path)))));
}

- (NSDictionary*)oo_fileAttributesAtPath:(NSString*)path traverseLink:(BOOL)yorn
{
    return [self fileAttributesAtPath:path traverseLink:yorn];
}

- (NSDictionary*)oo_fileSystemAttributesAtPath:(NSString*)path
{
    return [self fileSystemAttributesAtPath:path];
}

- (BOOL)oo_removeItemAtPath:(NSString*)path
{
    return static_cast<BOOL>(static_cast<bool>(oo::fs::removeItem(oo::fs::pathFromUTF8(oo::StdString(path)))));
}

- (BOOL)oo_moveItemAtPath:(NSString*)src toPath:(NSString*)dest
{
    return static_cast<BOOL>(static_cast<bool>(oo::fs::moveItem(
        oo::fs::pathFromUTF8(oo::StdString(src)),
        oo::fs::pathFromUTF8(oo::StdString(dest)))));
}

#endif

#if OOLITE_SDL
- (BOOL)chdirToSnapshotPath
{
    const oo::fs::Path savedir = oo::ResourcePaths::current().snapshotDirectory();

    if (!oo::fs::setCurrentDirectory(savedir)) {
        // it probably doesn't exist.
        if (!oo::fs::createDirectories(savedir)) {
            OO_LOG("savedSnapshot.defaultPath.create.failed", "Unable to create directory {}", oo::fs::utf8String(savedir));
            return NO;
        }
        if (!oo::fs::setCurrentDirectory(savedir)) {
            OO_LOG("savedSnapshot.defaultPath.chdir.failed", "Created {} but couldn't make it the current directory.", oo::fs::utf8String(savedir));
            return NO;
        }
    }

    return YES;
}
#endif

- (BOOL)oo_oxzFileExistsAtPath:(NSString*)path
{
    NSUInteger i, cl;
    NSArray* components = [path pathComponents];
    cl = [components count];
    for (i = 0; i < cl; i++) {
        NSString* component = [components objectAtIndex:i];
        if ([[[component pathExtension] lowercaseString] isEqualToString:@"oxz"]) {
            break;
        }
    }
    // if i == cl then the path is entirely uncompressed
    if (i == cl) {
        const oo::fs::FileType type = oo::fs::fileType(oo::fs::pathFromUTF8(oo::StdString(path)));
        if (type == oo::fs::FileType::directory) {
            return NO;
        }
        return type != oo::fs::FileType::none;
    }

    NSRange range;
    range.location = 0;
    range.length = i + 1;
    NSString* zipFile = [NSString pathWithComponents:[components subarrayWithRange:range]];
    range.location = i + 1;
    range.length = cl - (i + 1);
    NSString* containedFile = [NSString pathWithComponents:[components subarrayWithRange:range]];

    unzFile uf = NULL;
    const char* zipname = [zipFile cStringUsingEncoding:NSUTF8StringEncoding];
    if (zipname != NULL) {
        uf = unzOpen64(zipname);
    }
    if (uf == NULL) {
        // no such zip file
        return NO;
    }
    const char* filename = [containedFile cStringUsingEncoding:NSUTF8StringEncoding];
    // unzLocateFile(*, *, 1) = case-sensitive extract
    BOOL result = YES;
    if (unzLocateFile(uf, filename, 1) != UNZ_OK) {
        result = NO;
    } else {
        int err = UNZ_OK;
        unz_file_info64 file_info = { 0 };
        err = unzGetCurrentFileInfo64(uf, &file_info, NULL, 0, NULL, 0, NULL, 0);
        if (err != UNZ_OK) {
            result = NO;
        } else {
        }
    }
    unzClose(uf);
    return result;
}

@end
