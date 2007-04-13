/*

ResourceManager.h

Singleton class responsible for loading various data files.

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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

#import "OOCocoa.h"
#import "OOOpenGL.h"

#if OOLITE_SDL
#import "SDLImage.h"
#endif


#define OOLITE_EXCEPTION_FATAL					@"OoliteFatalException"

@class OOSound, OOMusic;

extern int debug;

BOOL always_include_addons;

@interface ResourceManager : NSObject

+ (NSArray *)rootPaths;			// Places add-ons are searched for, not including add-on paths.
+ (NSString *)builtInPath;		// Path for built-in data only.
+ (NSArray *)pathsWithAddOns;	// Root paths + add-on paths.
+ (NSArray *)paths;				// builtInPath or pathsWithAddOns, depending on useAddOns state.
+ (BOOL)useAddOns;
+ (void)setUseAddOns:(BOOL)useAddOns;
+ (void)addExternalPath:(NSString *)filename;

+ (NSString *)errors;			// Errors which occured during path scanning - essentially a list of OXPs whose requires.plist is bad.

+ (NSString *) pathForFileNamed:(NSString *)fileName inFolder:(NSString *)folderName;

+ (NSDictionary *) dictionaryFromFilesNamed:(NSString *)filename inFolder:(NSString *)foldername andMerge:(BOOL) mergeFiles;
+ (NSDictionary *) dictionaryFromFilesNamed:(NSString *)filename inFolder:(NSString *)foldername andMerge:(BOOL) mergeFiles smart:(BOOL) smartMerge;
+ (NSArray *) arrayFromFilesNamed:(NSString *)filename inFolder:(NSString *)foldername andMerge:(BOOL) mergeFiles;

+ (OOSound *) ooSoundNamed:(NSString *)filename inFolder:(NSString *)foldername;
+ (OOMusic *) ooMusicNamed:(NSString *)filename inFolder:(NSString *)foldername;

#if OOLITE_MAC_OS_X && !OOLITE_SDL
+ (NSImage *) imageNamed:(NSString *)filename inFolder:(NSString *)foldername;
#elif OOLITE_SDL
+ (SDLImage *) surfaceNamed:(NSString *)filename inFolder:(NSString *)foldername;
#endif

+ (NSString *) stringFromFilesNamed:(NSString *)filename inFolder:(NSString *)foldername;

+ (NSDictionary *) loadScripts;

@end
