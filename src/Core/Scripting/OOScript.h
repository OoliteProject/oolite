/*

OOScript.h

Abstract base class for scripts.
Currently, Oolite supports three types of script: the original property list
scripts, OOS scripts which translate into plist scripts, and JavaScript
scripts. OOScript unifies the interfaces to the script types and abstracts
loading. Additionally, it falls back to a more "primitive" script if loading
of one type fails; specifically, the order of precedence is:
	script.js		(JavaScript)
	script.oos		(OOS)
	script.plist	(property list)

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

#import <Foundation/Foundation.h>

@class Entity;


@interface OOScript: NSObject

/*	Looks for path/world-scripts.plist, path/script.js, then path/script.oos,
	then path/script.plist.
	May return zero or more scripts.
*/
+ (NSArray *)worldScriptsAtPath:(NSString *)path;

//	Load named scripts from Scripts folders.
+ (NSArray *)scriptsFromFileNamed:(NSString *)fileName;
+ (NSArray *)scriptsFromList:(NSArray *)fileNames;

+ (NSArray *)scriptsFromFileAtPath:(NSString *)filePath;

- (void)resetState;	// Clear local variables, for instance.

- (NSString *)name;
- (NSString *)scriptDescription;
- (NSString *)version;
- (NSString *)displayName;	// '"name" version' if version is defined, otherwise just '"name"'.

- (void)runWithTarget:(Entity *)target;

- (BOOL)doEvent:(NSString *)eventName;
- (BOOL)doEvent:(NSString *)eventName withArguments:(NSArray *)argument;

@end
