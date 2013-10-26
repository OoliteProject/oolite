/*

OOScript.m

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

#import "OOScript.h"
#import "OOJSScript.h"
#import "OOPListScript.h"
#import "OOLogging.h"
#import "Universe.h"
#import "OOJavaScriptEngine.h"
#import "OOPListParsing.h"
#import "ResourceManager.h"


static NSString * const kOOLogLoadScriptJavaScript			= @"script.load.javaScript";
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
		if ([fmgr oo_oxzFileExistsAtPath:filePath]) foundScript = YES;
		else
		{
			filePath = [path stringByAppendingPathComponent:@"script.es"];
			if ([fmgr oo_oxzFileExistsAtPath:filePath]) foundScript = YES;
		}
		if (foundScript)
		{
			OOLog(kOOLogLoadScriptJavaScript, @"Trying to load JavaScript script %@", filePath);
			OOLogIndentIf(kOOLogLoadScriptJavaScript);
			
			script = [OOJSScript scriptWithPath:filePath properties:nil];
			if (script != nil)
			{
				result = [NSArray arrayWithObject:script];
				OOLog(kOOLogLoadScriptOK, @"Successfully loaded JavaScript script %@", filePath);
			}
			else  OOLogERR(kOOLogLoadScriptParseError, @"Failed to load JavaScript script %@", filePath);
			
			OOLogOutdentIf(kOOLogLoadScriptJavaScript);
		}
	}
	
	// Third, try to load a plist script.
	if (result == nil)
	{
		filePath = [path stringByAppendingPathComponent:@"script.plist"];
		if ([fmgr oo_oxzFileExistsAtPath:filePath])
		{
			foundScript = YES;
			OOLog(kOOLogLoadScriptPList, @"Trying to load property list script %@", filePath);
			OOLogIndentIf(kOOLogLoadScriptPList);
			
			result = [OOPListScript scriptsInPListFile:filePath];
			if (result != nil)  OOLog(kOOLogLoadScriptOK, @"Successfully loaded property list script %@", filePath);
			else  OOLogERR(kOOLogLoadScriptParseError, @"Failed to load property list script %@", filePath);
			
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
	NSArray *result = nil;
	NSString *path = [ResourceManager pathForFileNamed:fileName inFolder:@"Scripts"];
	if (path != nil)
	{
		result = [self scriptsFromFileAtPath:path];
	}
	
	if (result == nil)
	{
		OOLogERR(@"script.load.notFound", @"Could not find script file %@.", fileName);
	}
	
	return result;
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
	// oo_oxzFile always returns false for directories
	if (![[NSFileManager defaultManager] oo_oxzFileExistsAtPath:filePath]) return nil;
	
	NSString *extension = [[filePath pathExtension] lowercaseString];
	
	if ([extension isEqualToString:@"js"] || [extension isEqualToString:@"es"])
	{
		NSArray		*result = nil;
		OOScript	*script = [OOJSScript scriptWithPath:filePath properties:nil];
		if (script != nil) result = [NSArray arrayWithObject:script];
		return result;
	}
	else if ([extension isEqualToString:@"plist"])
	{
		return [OOPListScript scriptsInPListFile:filePath];
	}
	
	OOLogERR(@"script.load.badName", @"Don't know how to load a script from %@.", filePath);
	return nil;
}


+ (id)jsScriptFromFileNamed:(NSString *)fileName properties:(NSDictionary *)properties
{
	NSString			*extension = nil;
	NSString			*path = nil;
	
	if ([fileName length] == 0)  return nil;
	
	extension = [[fileName pathExtension] lowercaseString];
	if ([extension isEqualToString:@"js"] || [extension isEqualToString:@"es"])
	{
		path = [ResourceManager pathForFileNamed:fileName inFolder:@"Scripts"];
		if (path == nil)
		{
			OOLogERR(@"script.load.notFound", @"Could not find script file %@.", fileName);
			return nil;
		}
		return [OOJSScript scriptWithPath:path properties:properties];
	}
	else if ([extension isEqualToString:@"plist"])
	{
		OOLogERR(@"script.load.badName", @"Can't load script named %@ - legacy scripts are not supported in this context.", fileName);
		return nil;
	}
	
	OOLogERR(@"script.load.badName", @"Don't know how to load a script from %@.", fileName);
	return nil;
}


+ (id)jsAIScriptFromFileNamed:(NSString *)fileName properties:(NSDictionary *)properties
{
	NSString			*extension = nil;
	NSString			*path = nil;
	
	if ([fileName length] == 0)  return nil;
	
	extension = [[fileName pathExtension] lowercaseString];
	if ([extension isEqualToString:@"js"] || [extension isEqualToString:@"es"])
	{
		path = [ResourceManager pathForFileNamed:fileName inFolder:@"AIs"];
		if (path == nil)
		{
			OOLogERR(@"script.load.notFound", @"Could not find script file %@.", fileName);
			return nil;
		}
		return [OOJSScript scriptWithPath:path properties:properties];
	}
	else if ([extension isEqualToString:@"plist"])
	{
		OOLogERR(@"script.load.badName", @"Can't load script named %@ - legacy scripts are not supported in this context.", fileName);
		return nil;
	}
	
	OOLogERR(@"script.load.badName", @"Don't know how to load a script from %@.", fileName);
	return nil;
}


- (NSString *)descriptionComponents
{
	return [NSString stringWithFormat:@"\"%@\" version %@", [self name], [self version]];
}


- (NSString *)name
{
	OOLogERR(kOOLogSubclassResponsibility, @"OOScript should not be used directly!");
	return nil;
}


- (NSString *)scriptDescription
{
	OOLogERR(kOOLogSubclassResponsibility, @"OOScript should not be used directly!");
	return nil;
}


- (NSString *)version
{
	OOLogERR(kOOLogSubclassResponsibility, @"OOScript should not be used directly!");
	return nil;
}


- (NSString *)displayName
{
	NSString *name = [self name];
	NSString *version = [self version];
	
	if (version != nil)  return [NSString stringWithFormat:@"%@ %@", name, version];
	else if (name != nil)  return [NSString stringWithFormat:@"%@", name];
	else  return nil;
}


- (BOOL) requiresTickle
{
	return NO;
}


- (void)runWithTarget:(Entity *)target
{
	OOLogERR(kOOLogSubclassResponsibility, @"OOScript should not be used directly!");
}

@end
