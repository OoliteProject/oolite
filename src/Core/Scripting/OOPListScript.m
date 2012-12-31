/*

OOPListScript.h

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

#import "OOPListScript.h"
#import "OOPListParsing.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import "OOLegacyScriptWhitelist.h"
#import "OOCacheManager.h"
#import "OOCollectionExtractors.h"


static NSString * const kMDKeyName			= @"name";
static NSString * const kMDKeyDescription	= @"description";
static NSString * const kMDKeyVersion		= @"version";
static NSString * const kKeyMetadata		= @"!metadata!";
static NSString * const kKeyScript			= @"script";

static NSString * const kCacheName			= @"sanitized legacy scripts";


@interface OOPListScript (SetUp)

+ (NSArray *)scriptsFromDictionaryOfScripts:(NSDictionary *)dictionary filePath:(NSString *)filePath;
+ (NSArray *) loadCachedScripts:(NSDictionary *)cachedScripts;
- (id)initWithName:(NSString *)name scriptArray:(NSArray *)script metadata:(NSDictionary *)metadata;

@end


@implementation OOPListScript

+ (NSArray *)scriptsInPListFile:(NSString *)filePath
{
	NSDictionary *cachedScripts = [[OOCacheManager sharedCache] objectForKey:filePath inCache:kCacheName];
	if (cachedScripts != nil)
	{
		return [self loadCachedScripts:cachedScripts];
	}
	else
	{
		NSDictionary *dict = OODictionaryFromFile(filePath);
		if (dict == nil)  return nil;
		return [self scriptsFromDictionaryOfScripts:dict filePath:filePath];
	}
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


- (BOOL) requiresTickle
{
	return YES;
}


- (void)runWithTarget:(Entity *)target
{
	if (target != nil && ![target isKindOfClass:[ShipEntity class]])
	{
		OOLog(@"script.legacy.run.badTarget", @"Expected ShipEntity or nil for target, got %@.", [target class]);
		return;
	}
	
	OOLog(@"script.legacy.run", @"Running script %@", [self displayName]);
	OOLogIndentIf(@"script.legacy.run");
	
	[PLAYER runScriptActions:_script
			 withContextName:[self name]
				   forTarget:(ShipEntity *)target];
	
	OOLogOutdentIf(@"script.legacy.run");
}

@end


@implementation OOPListScript (SetUp)

+ (NSArray *)scriptsFromDictionaryOfScripts:(NSDictionary *)dictionary filePath:(NSString *)filePath
{
	NSMutableArray		*result = nil;
	NSEnumerator		*keyEnum = nil;
	NSString			*key = nil;
	NSArray				*scriptArray = nil;
	NSDictionary		*metadata = nil;
	NSMutableDictionary	*cachedScripts = nil;
	OOPListScript		*script = nil;
	
	NSUInteger count = [dictionary count];
	result = [NSMutableArray arrayWithCapacity:count];
	cachedScripts = [NSMutableDictionary dictionaryWithCapacity:count];
	
	metadata = [dictionary objectForKey:kKeyMetadata];
	if (![metadata isKindOfClass:[NSDictionary class]]) metadata = nil;
	
	for (keyEnum = [dictionary keyEnumerator]; (key = [keyEnum nextObject]); )
	{
		scriptArray = [dictionary objectForKey:key];
		if ([key isKindOfClass:[NSString class]] &&
			[scriptArray isKindOfClass:[NSArray class]] &&
			![key isEqual:kKeyMetadata])
		{
			scriptArray = OOSanitizeLegacyScript(scriptArray, key, NO);
			if (scriptArray != nil)
			{
				script = [[self alloc] initWithName:key scriptArray:scriptArray metadata:metadata];
				if (script != nil)
				{
					[result addObject:script];
					[cachedScripts setObject:[NSDictionary dictionaryWithObjectsAndKeys:scriptArray, kKeyScript, metadata, kKeyMetadata, nil] forKey:key];
					
					[script release];
				}
			}
		}
	}
	
	[[OOCacheManager sharedCache] setObject:cachedScripts forKey:filePath inCache:kCacheName];
	
	return [[result copy] autorelease];
}


+ (NSArray *) loadCachedScripts:(NSDictionary *)cachedScripts
{
	NSEnumerator		*keyEnum = nil;
	NSString			*key = nil;
	
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:[cachedScripts count]];
	
	for (keyEnum = [cachedScripts keyEnumerator]; (key = [keyEnum nextObject]); )
	{
		NSDictionary *cacheValue = [cachedScripts oo_dictionaryForKey:key];
		NSArray *scriptArray = [cacheValue oo_arrayForKey:kKeyScript];
		NSDictionary *metadata = [cacheValue oo_dictionaryForKey:kKeyMetadata];
		OOPListScript *script = [[self alloc] initWithName:key scriptArray:scriptArray metadata:metadata];
		if (script != nil)
		{
			[result addObject:script];
			[script release];
		}
	}
	
	return [[result copy] autorelease];
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
				NSMutableDictionary *mutableMetadata = [[metadata mutableCopy] autorelease];
				[mutableMetadata setObject:name forKey:kMDKeyName];
				metadata = mutableMetadata;
			}
		}
		_metadata = [metadata copy];
	}
	
	return self;
}

@end
