/*

OOScript.m

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

#import "OOScript.h"
#import "OOJSScript.h"
#import "OOPListScript.h"
#import "OOLogging.h"
#import "Universe.h"
#import "OOJavaScriptEngine.h"
#import "OOPListParsing.h"
#import "ResourceManager.h"


static NSString * const kOOLogScriptSubclassResponsibility	= @"general.error.subclassResponsibility.OOScript";
static NSString * const kOOLogLoadScriptJavaScript			= @"script.load.javaScript";
static NSString * const kOOLogLoadScriptOOS					= @"script.load.oos";
static NSString * const kOOLogLoadScriptPList				= @"script.load.pList";
static NSString * const kOOLogLoadScriptOK					= @"script.load.parseOK";
static NSString * const kOOLogLoadScriptParseError			= @"script.load.parseError";
static NSString * const kOOLogLoadScriptNone				= @"script.load.none";


@implementation OOScript

+ (NSArray *)worldScriptsAtPath:(NSString *)path
{
	NSFileManager		*fmgr = nil;
	NSString			*filePath = nil;
	NSArray				*names = nil;
	NSArray				*result = nil;
	id					script = nil;
	BOOL				foundScript = NO;
	
	fmgr = [NSFileManager defaultManager];
	
	// First, look for world-scripts.plist.
	filePath = [path stringByAppendingPathComponent:@"world-scripts.plist"];
	if (filePath != nil)
	{
		names = OOArrayFromFile(filePath);
		if (names != nil)
		{
			foundScript = YES;
			result = [self scriptsFromList:names];
		}
	}
	
	// Second, try to load a JavaScript.
	if (result == nil)
	{
		filePath = [path stringByAppendingPathComponent:@"script.js"];
		if ([fmgr fileExistsAtPath:filePath]) foundScript = YES;
		else
		{
			filePath = [path stringByAppendingPathComponent:@"script.es"];
			if ([fmgr fileExistsAtPath:filePath]) foundScript = YES;
		}
		if (foundScript)
		{
			OOLog(kOOLogLoadScriptJavaScript, @"Trying to load JavaScript script %@", filePath);
			OOLogIndentIf(kOOLogLoadScriptJavaScript);
			
			script = [OOJSScript scriptWithPath:filePath];
			if (script != nil)
			{
				result = [NSArray arrayWithObject:script];
				OOLog(kOOLogLoadScriptOK, @"Successfully loaded JavaScript script %@", filePath);
			}
			else  OOLog(kOOLogLoadScriptParseError, @"*** Failed to load JavaScript script %@", filePath);
			
			OOLogOutdentIf(kOOLogLoadScriptJavaScript);
		}
	}
	
	// Third, try to load an OOS script.
	if (result == nil)
	{
		filePath = [path stringByAppendingPathComponent:@"script.oos"];
		if ([fmgr fileExistsAtPath:filePath])
		{
			foundScript = YES;
			OOLog(kOOLogLoadScriptOOS, @"Trying to load OOS script %@", filePath);
			OOLogIndentIf(kOOLogLoadScriptOOS);
			
			result = [OOPListScript scriptsInOOSFile:filePath];
			if (result != nil)  OOLog(kOOLogLoadScriptOK, @"Successfully loaded OOS script %@", filePath);
			else  OOLog(kOOLogLoadScriptParseError, @"*** Failed to load OOS script %@", filePath);
			
			OOLogOutdentIf(kOOLogLoadScriptOOS);
		}
	}
	
	// Fourth, try to load an plist script.
	if (result == nil)
	{
		filePath = [path stringByAppendingPathComponent:@"script.plist"];
		if ([fmgr fileExistsAtPath:filePath])
		{
			foundScript = YES;
			OOLog(kOOLogLoadScriptPList, @"Trying to load property list script %@", filePath);
			OOLogIndentIf(kOOLogLoadScriptPList);
			
			result = [OOPListScript scriptsInPListFile:filePath];
			if (result != nil)  OOLog(kOOLogLoadScriptOK, @"Successfully loaded property list script %@", filePath);
			else  OOLog(kOOLogLoadScriptParseError, @"*** Failed to load property list script %@", filePath);
			
			OOLogOutdentIf(kOOLogLoadScriptPList);
		}
	}
	
	if (result == nil && foundScript)
	{
		OOLog(kOOLogLoadScriptNone, @"No script could be loaded from %@", path);
	}
	
	return result;
}


+ (NSArray *)scriptsFromFileNamed:(NSString *)fileName
{
	NSEnumerator		*pathEnum = nil;
	NSString			*path = nil;
	NSString			*filePath = nil;
	NSArray				*result = nil;
	
	if (fileName == nil) return nil;
	
	for (pathEnum = [[ResourceManager paths] objectEnumerator]; (path = [pathEnum nextObject]); )
	{
		filePath = [[path stringByAppendingPathComponent:@"Scripts"] stringByAppendingPathComponent:fileName];
		result = [self scriptsFromFileAtPath:filePath];
		if (result != nil) return result;
	}
	
	OOLog(@"script.load.notFound", @"***** Could not find a valid script file named %@.", fileName);
	return nil;
}


+ (NSArray *)scriptsFromList:(NSArray *)fileNames
{
	NSEnumerator		*nameEnum = nil;
	NSString			*name = nil;
	NSMutableArray		*result = nil;
	NSArray				*scripts = nil;
	
	result = [NSMutableArray arrayWithCapacity:[fileNames count]];
	
	for (nameEnum = [fileNames objectEnumerator]; (name = [nameEnum nextObject]); )
	{
		scripts = [self scriptsFromFileNamed:name];
		if (scripts != nil)  [result addObjectsFromArray:scripts];
	}
	
	return result;
}


+ (NSArray *)scriptsFromFileAtPath:(NSString *)filePath
{
	BOOL directory;
	if (![[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&directory] || directory) return nil;
	
	NSString *extension = [[filePath pathExtension] lowercaseString];
	
	if ([extension isEqualToString:@"js"] || [extension isEqualToString:@"es"])
	{
		NSArray		*result = nil;
		OOScript	*script = [OOJSScript scriptWithPath:filePath];
		if (script != nil) result = [NSArray arrayWithObject:script];
		return result;
	}
	else if ([extension isEqualToString:@"oos"])
	{
		return [OOPListScript scriptsInOOSFile:filePath];
	}
	else if ([extension isEqualToString:@"plist"])
	{
		return [OOPListScript scriptsInPListFile:filePath];
	}
	
	OOLog(@"script.load.badName", @"***** Don't know how to load a script from %@.", filePath);
	return nil;
}


- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p>{\"%@\" version %@}", [self class], self, [self name], [self version]];
}


- (void)resetState
{
	
}


- (NSString *)name
{
	OOLog(kOOLogScriptSubclassResponsibility, @"OOScript should not be used directly!");
	return nil;
}


- (NSString *)scriptDescription
{
	OOLog(kOOLogScriptSubclassResponsibility, @"OOScript should not be used directly!");
	return nil;
}


- (NSString *)version
{
	OOLog(kOOLogScriptSubclassResponsibility, @"OOScript should not be used directly!");
	return nil;
}


- (NSString *)displayName
{
	NSString *name = [self name];
	NSString *version = [self version];
	
	if (version != NULL) return [NSString stringWithFormat:@"\"%@\" %@", name, version];
	else return [NSString stringWithFormat:@"\"%@\"", name];
}


- (void)runWithTarget:(Entity *)target
{
	OOLog(kOOLogScriptSubclassResponsibility, @"OOScript should not be used directly!");
}


- (BOOL)doEvent:(NSString *)eventName
{
	return [self doEvent:eventName withArguments:nil];
}


- (BOOL)doEvent:(NSString *)eventName withArguments:(NSArray *)arguments
{
	OOLog(kOOLogScriptSubclassResponsibility, @"OOScript should not be used directly!");
	return NO;
}

@end
