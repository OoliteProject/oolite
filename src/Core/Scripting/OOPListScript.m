/*

OOPListScript.h

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

#import "OOPListScript.h"
#import "OOPListParsing.h"
#import "PlayerEntityLegacyScriptEngine.h"

extern NSDictionary *ParseOOSScripts(NSString* script);


static NSString * const kMDKeyName			= @"name";
static NSString * const kMDKeyDescription	= @"description";
static NSString * const kMDKeyVersion		= @"version";
static NSString * const kKeyMetadata		= @"!metadata!";


@interface OOPListScript (SetUp)

+ (NSArray *)scriptsFromDictionaryOfScripts:(NSDictionary *)dictionary;
- (id)initWithName:(NSString *)name scriptArray:(NSArray *)script metadata:(NSDictionary *)metadata;

@end


@implementation OOPListScript

+ (NSArray *)scriptsInOOSFile:(NSString *)filePath
{
	NSString *script = [NSString stringWithContentsOfFile:filePath];
	return [self scriptsFromDictionaryOfScripts:ParseOOSScripts(script)];
}


+ (NSArray *)scriptsInPListFile:(NSString *)filePath
{
	NSDictionary		*dict = nil;
	
	dict = OODictionaryFromFile(filePath);
	return [self scriptsFromDictionaryOfScripts:dict];
}


- (void)dealloc
{
	[_script release];
	[_metadata release];
	
	[super dealloc];
}


- (NSString *)name
{
	return [_metadata objectForKey:kMDKeyName];
}


- (NSString *)scriptDescription
{
	return [_metadata objectForKey:kMDKeyDescription];
}


- (NSString *)version
{
	return [_metadata objectForKey:kMDKeyVersion];
}


- (void)runWithTarget:(Entity *)target
{
	if (target != nil && ![target isKindOfClass:[ShipEntity class]])
	{
		OOLog(@"script.plist.run.badTarget", @"Expected ShipEntity or nil for target, got %@.", [target class]);
		return;
	}
	
	OOLog(@"script.trace.plist.run", @"Running script %@", [self displayName]);
	OOLogIndentIf(@"script.trace.plist.run");
	
	[[PlayerEntity sharedPlayer] runScript:_script withName:[self name]	forTarget:(ShipEntity *)target];
	
	OOLogOutdentIf(@"script.trace.plist.run");
}


- (BOOL)doEvent:(NSString *)eventName withArguments:(NSArray *)argument
{
	// PList scripts don't have event handlers.
	return NO;
}

@end


@implementation OOPListScript (SetUp)

+ (NSArray *)scriptsFromDictionaryOfScripts:(NSDictionary *)dictionary
{
	NSMutableArray		*result = nil;
	NSEnumerator		*keyEnum = nil;
	NSString			*key = nil;
	NSArray				*scriptArray = nil;
	NSDictionary		*metadata = nil;
	OOPListScript		*script = nil;
	
	result = [NSMutableArray arrayWithCapacity:[dictionary count]];
	metadata = [dictionary objectForKey:kKeyMetadata];
	if (![metadata isKindOfClass:[NSDictionary class]]) metadata = nil;
	
	for (keyEnum = [dictionary keyEnumerator]; (key = [keyEnum nextObject]); )
	{
		scriptArray = [dictionary objectForKey:key];
		if ([key isKindOfClass:[NSString class]] &&
			[scriptArray isKindOfClass:[NSArray class]] &&
			![key isEqual:kKeyMetadata])
		{
			script = [[self alloc] initWithName:key scriptArray:scriptArray metadata:metadata];
			if (script != nil)
			{
				[result addObject:script];
			}
		}
	}
	
	return result;
}


- (id)initWithName:(NSString *)name scriptArray:(NSArray *)script metadata:(NSDictionary *)metadata
{
	self = [super init];
	if (self != nil)
	{
		_script = [script retain];
		if (name != nil)
		{
			if (metadata == nil)  metadata = [NSDictionary dictionaryWithObject:name forKey:kMDKeyName];
			else
			{
				NSMutableDictionary *mutableMetadata = [metadata mutableCopy];
				[mutableMetadata setObject:name forKey:kMDKeyName];
				metadata = mutableMetadata;
			}
		}
		_metadata = [metadata copy];
	}
	
	return self;
}

@end
