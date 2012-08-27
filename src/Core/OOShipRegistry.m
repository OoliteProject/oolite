/*

OOShipRegistry.m


Copyright (C) 2008-2012 Jens Ayton and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOShipRegistry.h"
#import "OOCacheManager.h"
#import "ResourceManager.h"
#import "OOCollectionExtractors.h"
#import "NSDictionaryOOExtensions.h"
#import "OOProbabilitySet.h"
#import "OORoleSet.h"
#import "OOStringParsing.h"
#import "OOMesh.h"
#import "GameController.h"
#import "OOLegacyScriptWhitelist.h"
#import "OODeepCopy.h"
#import "OOColor.h"
#import "Universe.h"


#define PRELOAD 0


static void DumpStringAddrs(NSDictionary *dict, NSString *context);


static OOShipRegistry	*sSingleton = nil;


static NSString * const	kShipRegistryCacheName = @"ship registry";
static NSString * const	kShipDataCacheKey = @"ship data";
static NSString * const	kPlayerShipsCacheKey = @"player ships";
static NSString * const	kDemoShipsCacheKey = @"demo ships";
static NSString * const	kConditionScriptsCacheKey = @"condition scripts";
static NSString * const	kRoleWeightsCacheKey = @"role weights";
static NSString * const	kDefaultDemoShip = @"coriolis-station";
static NSString * const	kVisualEffectRegistryCacheName = @"visual effect registry";
static NSString * const	kVisualEffectDataCacheKey = @"visual effect data";


@interface OOShipRegistry (OODataLoader)

- (void) loadShipData;
- (void) loadDemoShips;
- (void) loadCachedRoleProbabilitySets;
- (void) buildRoleProbabilitySets;

- (BOOL) applyLikeShips:(NSMutableDictionary *)ioData withKey:(NSString *)likeKey;
- (BOOL) loadAndMergeShipyard:(NSMutableDictionary *)ioData;
- (BOOL) stripPrivateKeys:(NSMutableDictionary *)ioData;
- (BOOL) makeShipEntriesMutable:(NSMutableDictionary *)ioData;
- (BOOL) loadAndApplyShipDataOverrides:(NSMutableDictionary *)ioData;
- (BOOL) canonicalizeAndTagSubentities:(NSMutableDictionary *)ioData;
- (BOOL) removeUnusableEntries:(NSMutableDictionary *)ioData shipMode:(BOOL)shipMode;
- (BOOL) sanitizeConditions:(NSMutableDictionary *)ioData;

#if PRELOAD
- (BOOL) preloadShipMeshes:(NSMutableDictionary *)ioData;
#endif

- (NSMutableDictionary *) mergeShip:(NSDictionary *)child withParent:(NSDictionary *)parent;
- (void) mergeShipRoles:(NSString *)roles forShipKey:(NSString *)shipKey intoProbabilityMap:(NSMutableDictionary *)probabilitySets;

- (NSDictionary *) canonicalizeSubentityDeclaration:(id)declaration
											forShip:(NSString *)shipKey
										   shipData:(NSDictionary *)shipData
										 fatalError:(BOOL *)outFatalError;
- (NSDictionary *) translateOldStyleSubentityDeclaration:(NSString *)declaration
												 forShip:(NSString *)shipKey
												shipData:(NSDictionary *)shipData
											  fatalError:(BOOL *)outFatalError;
- (NSDictionary *) translateOldStyleFlasherDeclaration:(NSArray *)tokens
											   forShip:(NSString *)shipKey
											fatalError:(BOOL *)outFatalError;
- (NSDictionary *) translateOldStandardBasicSubentityDeclaration:(NSArray *)tokens
														 forShip:(NSString *)shipKey
														shipData:(NSDictionary *)shipData
													  fatalError:(BOOL *)outFatalError;
- (NSDictionary *) validateNewStyleSubentityDeclaration:(NSDictionary *)declaration
												forShip:(NSString *)shipKey
											 fatalError:(BOOL *)outFatalError;
- (NSDictionary *) validateNewStyleFlasherDeclaration:(NSDictionary *)declaration
											  forShip:(NSString *)shipKey
										   fatalError:(BOOL *)outFatalError;
- (NSDictionary *) validateNewStyleStandardSubentityDeclaration:(NSDictionary *)declaration
														forShip:(NSString *)shipKey
													 fatalError:(BOOL *)outFatalError;

- (BOOL) shipIsBallTurretForKey:(NSString *)shipKey inShipData:(NSDictionary *)shipData;

@end


@implementation OOShipRegistry

+ (OOShipRegistry *) sharedRegistry
{
	if (sSingleton == nil)
	{
		sSingleton = [[self alloc] init];
	}
	
	return sSingleton;
}


+ (void) reload
{
	if (sSingleton != nil)
	{
		[sSingleton release];
		sSingleton = nil;
		
		(void) [self sharedRegistry];
	}
}


- (id) init
{
	if ((self = [super init]))
	{
		NSAutoreleasePool		*pool = [[NSAutoreleasePool alloc] init];
		OOCacheManager			*cache = [OOCacheManager sharedCache];
		
		_shipData = [[cache objectForKey:kShipDataCacheKey inCache:kShipRegistryCacheName] retain];
		_playerShips = [[cache objectForKey:kPlayerShipsCacheKey inCache:kShipRegistryCacheName] retain];
		_effectData = [[cache objectForKey:kVisualEffectDataCacheKey inCache:kVisualEffectRegistryCacheName] retain];
		if ([_shipData count] == 0)	// Don't accept nil or empty
		{
			[self loadShipData];
			if ([_shipData count] == 0)
			{
				[NSException raise:@"OOShipRegistryLoadFailure" format:@"Could not load any ship data."];
			}
			if ([_playerShips count] == 0)
			{
				[NSException raise:@"OOShipRegistryLoadFailure" format:@"Could not load any player ships."];
			}
		}
		
		_demoShips = [[cache objectForKey:kDemoShipsCacheKey inCache:kShipRegistryCacheName] retain];
		if ([_demoShips count] == 0)
		{
			[self loadDemoShips];
			if ([_demoShips count] == 0)
			{
				[NSException raise:@"OOShipRegistryLoadFailure" format:@"Could not load or synthesize any demo ships."];
			}
		}
		
		[self loadCachedRoleProbabilitySets];
		if (_probabilitySets == nil)
		{
			[self buildRoleProbabilitySets];
			if ([_probabilitySets count] == 0)
			{
				[NSException raise:@"OOShipRegistryLoadFailure" format:@"Could not load or synthesize role probability sets."];
			}
		}
		
		[pool release];
	}
	return self;
}


- (void) dealloc
{
	[_shipData release];
	[_demoShips release];
	[_playerShips release];
	[_probabilitySets release];
	
	[super dealloc];
}


- (NSDictionary *) shipInfoForKey:(NSString *)key
{
	return [_shipData objectForKey:key];
}


- (NSDictionary *) effectInfoForKey:(NSString *)key
{
	return [_effectData objectForKey:key];
}


- (NSDictionary *) shipyardInfoForKey:(NSString *)key
{
	return [[self shipInfoForKey:key] objectForKey:@"_oo_shipyard"];
}


- (OOProbabilitySet *) probabilitySetForRole:(NSString *)role
{
	if (role == nil)  return nil;
	return [_probabilitySets objectForKey:role];
}


- (NSArray *) demoShipKeys
{
	return _demoShips;
}


- (NSArray *) playerShipKeys
{
	return _playerShips;
}

@end


@implementation OOShipRegistry (OOConveniences)

- (NSArray *) shipKeysWithRole:(NSString *)role
{
	return [[self probabilitySetForRole:role] allObjects];
}


- (NSString *) randomShipKeyForRole:(NSString *)role
{
	return [[self probabilitySetForRole:role] randomObject];
}

@end


@implementation OOShipRegistry (OODataLoader)

/*	-loadShipData
	
	Load the data for all ships. This consists of five stages:
		* Load merges shipdata.plist dictionary.
		* Apply all like_ship entries.
		* Load shipdata-overrides.plist and apply patches.
		* Load shipyard.plist, add shipyard data into ship dictionaries, and
		  create _playerShips array.
		* Build role->ship type probability sets.
*/
- (void) loadShipData
{
	NSMutableDictionary		*result = nil;
	
	[_shipData release];
	_shipData = nil;
	[_playerShips release];
	_playerShips = nil;
	
	// Load shipdata.plist.
	result = [[[ResourceManager dictionaryFromFilesNamed:@"shipdata.plist"
												inFolder:@"Config"
											   mergeMode:MERGE_BASIC
												   cache:NO] mutableCopy] autorelease];
	if (result == nil)  return;
	
	DumpStringAddrs(result, @"shipdata.plist");
	
	// Make each entry mutable to simplify later stages. Also removes any entries that aren't dictionaries.
	if (![self makeShipEntriesMutable:result])  return;
	OOLog(@"shipData.load.done", @"Finished initial cleanup...");
	
	// Apply patches.
	if (![self loadAndApplyShipDataOverrides:result])  return;
	OOLog(@"shipData.load.done", @"Finished applying patches...");
	
	// Strip private keys (anything starting with _oo_).
	if (![self stripPrivateKeys:result])  return;
	OOLog(@"shipData.load.done", @"Finished stripping private keys...");
	
	// Resolve like_ship entries.
	if (![self applyLikeShips:result withKey:@"like_ship"])  return;
	OOLog(@"shipData.load.done", @"Finished resolving like_ships...");
	
	// Clean up subentity declarations and tag subentities so they won't be pruned.
	if (![self canonicalizeAndTagSubentities:result])  return;
	OOLog(@"shipData.load.done", @"Finished cleaning up subentities...");
	
	// Clean out templates and invalid entries.
	if (![self removeUnusableEntries:result shipMode:YES])  return;
	OOLog(@"shipData.load.done", @"Finished removing invalid entries...");
	
	// Add shipyard entries into shipdata entries.
	if (![self loadAndMergeShipyard:result])  return;
	OOLog(@"shipData.load.done", @"Finished adding shipyard entries...");
	
	// Sanitize conditions.
	if (![self sanitizeConditions:result])  return;
	OOLog(@"shipData.load.done", @"Finished validating data...");
	
#if PRELOAD
	// Preload and cache meshes.
	if (![self preloadShipMeshes:result])  return;
	OOLog(@"shipData.load.done", @"Finished loading meshes...");
#endif
	
	_shipData = OODeepCopy(result);
	[[OOCacheManager sharedCache] setObject:_shipData forKey:kShipDataCacheKey inCache:kShipRegistryCacheName];
	
	OOLogOutdentIf(@"shipData.load.begin");
	OOLog(@"shipData.load.done", @"Ship data loaded.");

	[_effectData release];
	_effectData = nil;

	result = [[[ResourceManager dictionaryFromFilesNamed:@"effectdata.plist"
												inFolder:@"Config"
											   mergeMode:MERGE_BASIC
												   cache:NO] mutableCopy] autorelease];
	if (result == nil)  return;

	// Make each entry mutable to simplify later stages. Also removes any entries that aren't dictionaries.
	if (![self makeShipEntriesMutable:result])  return;
	OOLog(@"effectData.load.done", @"Finished initial cleanup...");

	// Strip private keys (anything starting with _oo_).
	if (![self stripPrivateKeys:result])  return;
	OOLog(@"effectData.load.done", @"Finished stripping private keys...");
	
	// Resolve like_ship entries.
	if (![self applyLikeShips:result withKey:@"like_effect"])  return;
	OOLog(@"effectData.load.done", @"Finished resolving like_effects...");
	
	// Clean up subentity declarations and tag subentities so they won't be pruned.
	if (![self canonicalizeAndTagSubentities:result])  return;
	OOLog(@"effectData.load.done", @"Finished cleaning up subentities...");

	// Clean out templates and invalid entries.
	if (![self removeUnusableEntries:result shipMode:NO])  return;
	OOLog(@"effectData.load.done", @"Finished removing invalid entries...");
	
	_effectData = OODeepCopy(result);
	[[OOCacheManager sharedCache] setObject:_effectData forKey:kVisualEffectDataCacheKey inCache:kVisualEffectRegistryCacheName];

}


/*	-loadDemoShips
	
	Load demoships.plist, and filter out non-existent ships. If no existing
	ships remain, try adding coriolis; if this fails, add any ship in
	shipdata.
*/
- (void) loadDemoShips
{
	NSEnumerator			*enumerator = nil;
	NSString				*key = nil;
	NSArray					*initialDemoShips = nil;
	NSMutableArray			*demoShips = nil;
	
	[_demoShips release];
	_demoShips = nil;
	
	initialDemoShips = [ResourceManager arrayFromFilesNamed:@"demoships.plist"
												   inFolder:@"Config"
												   andMerge:YES
													  cache:NO];
	demoShips = [NSMutableArray arrayWithArray:initialDemoShips];
	
	// Note: iterate over initialDemoShips to avoid mutating the collection being enu,erated.
	for (enumerator = [initialDemoShips objectEnumerator]; (key = [enumerator nextObject]); )
	{
		if (![key isKindOfClass:[NSString class]] || [self shipInfoForKey:key] == nil)
		{
			[demoShips removeObject:key];
		}
	}
	
	if ([demoShips count] == 0)
	{
		if ([self shipInfoForKey:kDefaultDemoShip] != nil)  [demoShips addObject:kDefaultDemoShip];
		else  [demoShips addObject:[[_shipData allKeys] objectAtIndex:0]];
	}
	
	_demoShips = [demoShips copy];
	[[OOCacheManager sharedCache] setObject:_demoShips forKey:kDemoShipsCacheKey inCache:kShipRegistryCacheName];
}


- (void) loadCachedRoleProbabilitySets
{
	NSDictionary			*cachedSets = nil;
	NSMutableDictionary		*restoredSets = nil;
	NSEnumerator			*roleEnum = nil;
	NSString				*role = nil;
	
	cachedSets = [[OOCacheManager sharedCache] objectForKey:kRoleWeightsCacheKey inCache:kShipRegistryCacheName];
	if (cachedSets == nil)  return;
	
	restoredSets = [NSMutableDictionary dictionaryWithCapacity:[cachedSets count]];
	for (roleEnum = [cachedSets keyEnumerator]; (role = [roleEnum nextObject]); )
	{
		[restoredSets setObject:[OOProbabilitySet probabilitySetWithPropertyListRepresentation:[cachedSets objectForKey:role]] forKey:role];
	}
	
	_probabilitySets = [restoredSets copy];
}


- (void) buildRoleProbabilitySets
{
	NSMutableDictionary		*probabilitySets = nil;
	NSEnumerator			*shipEnum = nil;
	NSString				*shipKey = nil;
	NSDictionary			*shipEntry = nil;
	NSString				*roles = nil;
	NSEnumerator			*roleEnum = nil;
	NSString				*role = nil;
	OOProbabilitySet		*pset = nil;
	NSMutableDictionary		*cacheEntry = nil;
	
	probabilitySets = [NSMutableDictionary dictionary];
	
	// Build role sets
	for (shipEnum = [_shipData keyEnumerator]; (shipKey = [shipEnum nextObject]); )
	{
		shipEntry = [_shipData objectForKey:shipKey];
		roles = [shipEntry oo_stringForKey:@"roles"];
		[self mergeShipRoles:roles forShipKey:shipKey intoProbabilityMap:probabilitySets];
	}
	
	// Convert role sets to immutable form, and build cache entry.
	// Note: we iterate over a copy of the keys to avoid mutating while iterating.
	cacheEntry = [NSMutableDictionary dictionaryWithCapacity:[probabilitySets count]];
	for (roleEnum = [[probabilitySets allKeys] objectEnumerator]; (role = [roleEnum nextObject]); )
	{
		pset = [probabilitySets objectForKey:role];
		pset = [[pset copy] autorelease];
		[probabilitySets setObject:pset forKey:role];
		[cacheEntry setObject:[pset propertyListRepresentation] forKey:role];
	}
	
	_probabilitySets = [probabilitySets copy];
	[[OOCacheManager sharedCache] setObject:cacheEntry forKey:kRoleWeightsCacheKey inCache:kShipRegistryCacheName];
}


/*	-applyLikeShips:
	
	Implement like_ship by copying inherited ship and overwriting with child
	ship values. Done iteratively to report recursive references of arbitrary
	depth. Also removes and reports ships whose like_ship entry does not
	resolve, and handles reference loops by removing all ships involved.
 
	We start with a set of keys all ships that have a like_ships entry. In
	each iteration, every ship whose like_ship entry does not refer to a ship
	which itself has a like_ship entry is finalized. If the set of pending
	ships does not shrink in an iteration, the remaining ships cannot be
	resolved (either their like_ships do not exist, or they form reference
	cycles) so we stop looping and report it.
*/
- (BOOL) applyLikeShips:(NSMutableDictionary *)ioData withKey:(NSString *)likeKey
{
	NSMutableSet			*remainingLikeShips = nil;
	NSEnumerator			*enumerator = nil;
	NSString				*key = nil;
	NSString				*parentKey = nil;
	NSDictionary			*shipEntry = nil;
	NSDictionary			*parentEntry = nil;
	OOUInteger				count, lastCount;
	NSMutableArray			*reportedBadShips = nil;
	
	// Build set of ships with like_ship references
	remainingLikeShips = [NSMutableSet set];
	for (enumerator = [ioData keyEnumerator]; (key = [enumerator nextObject]); )
	{
		shipEntry = [ioData objectForKey:key];
		if ([shipEntry oo_stringForKey:likeKey] != nil)
		{
			[remainingLikeShips addObject:key];
		}
	}
	
	count = lastCount = [remainingLikeShips count];
	while (count != 0)
	{
		for (enumerator = [[[remainingLikeShips copy] autorelease] objectEnumerator]; (key = [enumerator nextObject]); )
		{
			// Look up like_ship entry
			shipEntry = [ioData objectForKey:key];
			parentKey = [shipEntry objectForKey:likeKey];
			if (![remainingLikeShips containsObject:parentKey])
			{
				// If parent is fully resolved, we can resolve this child.
				parentEntry = [ioData objectForKey:parentKey];
				shipEntry = [self mergeShip:shipEntry withParent:parentEntry];
				if (shipEntry != nil)
				{
					[remainingLikeShips removeObject:key];
					[ioData setObject:shipEntry forKey:key];
				}
			}
		}
		
		count = [remainingLikeShips count];
		if (count == lastCount)
		{
			/*	Fail: we couldn't resolve all like_ship entries.
				Remove unresolved entries, building a list of the ones that
				don't have is_external_dependency set.
			*/
			reportedBadShips = [NSMutableArray array];
			for (enumerator = [remainingLikeShips objectEnumerator]; (key = [enumerator nextObject]); )
			{
				if (![[ioData oo_dictionaryForKey:key] oo_boolForKey:@"is_external_dependency"])
				{
					[reportedBadShips addObject:key];
				}
				[ioData removeObjectForKey:key];
			}
			
			if ([reportedBadShips count] != 0)
			{
				[reportedBadShips sortUsingSelector:@selector(caseInsensitiveCompare:)];
				OOLogERR(@"shipData.merge.failed", @"one or more shipdata.plist entries have %@ references that cannot be resolved: %@", likeKey, [reportedBadShips componentsJoinedByString:@", "]); // FIXME: distinguish shipdata and effectdata
			}
			break;
		}
		lastCount = count;
	}
	
	return YES;
}


- (NSMutableDictionary *) mergeShip:(NSDictionary *)child withParent:(NSDictionary *)parent
{
	NSMutableDictionary *result = [[parent mutableCopy] autorelease];
	if (result == nil)  return nil;
	
	[result addEntriesFromDictionary:child];
	[result removeObjectForKey:@"like_ship"];
	
	// Certain properties cannot be inherited.
	if ([child oo_stringForKey:@"display_name"] == nil)  [result removeObjectForKey:@"display_name"];
	if ([child oo_stringForKey:@"is_template"] == nil)  [result removeObjectForKey:@"is_template"];
	
	// Since both 'scanClass' and 'scan_class' are accepted as valid keys for the scanClass property,
	// we may end up with conflicting scanClass and scan_class keys from like_ship relationships getting
	// merged in the result dictionary. We want to always have the child overriding the parent setting
	// and we do that by determining which of the two keys belongs to the child dictionary and removing
	// the other one from the result - Nikos 20100512
	if ([result oo_stringForKey:@"scan_class"] != nil && [result oo_stringForKey:@"scanClass"] != nil)
	{
		if ([child oo_stringForKey:@"scanClass"] != nil)
			[result removeObjectForKey:@"scan_class"];
		else
			[result removeObjectForKey:@"scanClass"];
	}
	// TODO: all normalised/non-normalised value name pairs need to be catered for. - Kaks 2010-05-13
	if ([result oo_stringForKey:@"escort_role"] != nil && [result oo_stringForKey:@"escort-role"] != nil)
	{
		if ([child oo_stringForKey:@"escort-role"] != nil)
			[result removeObjectForKey:@"escort_role"];
		else
			[result removeObjectForKey:@"escort-role"];
	}
	if ([result oo_stringForKey:@"escort_ship"] != nil && [result oo_stringForKey:@"escort-ship"] != nil)
	{
		if ([child oo_stringForKey:@"escort-ship"] != nil)
			[result removeObjectForKey:@"escort_ship"];
		else
			[result removeObjectForKey:@"escort-ship"];
	}
	if ([result oo_stringForKey:@"is_carrier"] != nil && [result oo_stringForKey:@"isCarrier"] != nil)
	{
		if ([child oo_stringForKey:@"isCarrier"] != nil)
			[result removeObjectForKey:@"is_carrier"];
		else
			[result removeObjectForKey:@"isCarrier"];
	}
	if ([result oo_stringForKey:@"has_shipyard"] != nil && [result oo_stringForKey:@"hasShipyard"] != nil)
	{
		if ([child oo_stringForKey:@"hasShipyard"] != nil)
			[result removeObjectForKey:@"has_shipyard"];
		else
			[result removeObjectForKey:@"hasShipyard"];
	}	
	return result;
}


- (BOOL) makeShipEntriesMutable:(NSMutableDictionary *)ioData
{
	NSEnumerator			*shipKeyEnum = nil;
	NSString				*shipKey = nil;
	NSDictionary			*shipEntry = nil;
	
	for (shipKeyEnum = [[ioData allKeys] objectEnumerator]; (shipKey = [shipKeyEnum nextObject]); )
	{
		shipEntry = [ioData objectForKey:shipKey];
		if (![shipEntry isKindOfClass:[NSDictionary class]])
		{
			OOLogERR(@"shipData.load.badEntry", @"the shipdata.plist entry \"%@\" is not a dictionary.", shipKey);
			[ioData removeObjectForKey:shipKey];
		}
		else
		{
			shipEntry = [shipEntry mutableCopy];
			
			[ioData setObject:shipEntry forKey:shipKey];
			[shipEntry release];
		}
	}
	
	return YES;
}


- (BOOL) loadAndApplyShipDataOverrides:(NSMutableDictionary *)ioData
{
	NSEnumerator			*shipKeyEnum = nil;
	NSString				*shipKey = nil;
	NSMutableDictionary		*shipEntry = nil;
	NSDictionary			*overrides = nil;
	NSDictionary			*overridesEntry = nil;
	
	overrides = [ResourceManager dictionaryFromFilesNamed:@"shipdata-overrides.plist"
												 inFolder:@"Config"
												mergeMode:MERGE_SMART
													cache:NO];
	
	for (shipKeyEnum = [overrides keyEnumerator]; (shipKey = [shipKeyEnum nextObject]); )
	{
		shipEntry = [ioData objectForKey:shipKey];
		if (shipEntry != nil)
		{
			overridesEntry = [overrides objectForKey:shipKey];
			if (![overridesEntry isKindOfClass:[NSDictionary class]])
			{
				OOLogERR(@"shipData.load.error", @"the shipdata-overrides.plist entry \"%@\" is not a dictionary.", shipKey);
			}
			else
			{
				[shipEntry addEntriesFromDictionary:overridesEntry];
			}
		}
	}
	
	return YES;
}


- (BOOL) stripPrivateKeys:(NSMutableDictionary *)ioData
{
	NSEnumerator			*shipKeyEnum = nil;
	NSString				*shipKey = nil;
	NSMutableDictionary		*shipEntry = nil;
	NSEnumerator			*attrKeyEnum = nil;
	NSString				*attrKey = nil;
	
	for (shipKeyEnum = [ioData keyEnumerator]; (shipKey = [shipKeyEnum nextObject]); )
	{
		shipEntry = [ioData objectForKey:shipKey];
		
		for (attrKeyEnum = [shipEntry keyEnumerator]; (attrKey = [attrKeyEnum nextObject]); )
		{
			if ([attrKey hasPrefix:@"_oo_"])
			{
				[shipEntry removeObjectForKey:attrKey];
			}
		}
	}
	
	return YES;
}


/*	-loadAndMergeShipyard:
	
	Load shipyard.plist, add its entries to appropriate shipyard entries as
	a dictionary under the key "shipyard", and build list of player ships.
	Before that, we strip out any "shipyard" entries already in shipdata, and
	apply any shipyard-overrides.plist stuff to shipyard.
*/
- (BOOL) loadAndMergeShipyard:(NSMutableDictionary *)ioData
{
	NSEnumerator			*shipKeyEnum = nil;
	NSString				*shipKey = nil;
	NSMutableDictionary		*shipEntry = nil;
	NSDictionary			*shipyard = nil;
	NSDictionary			*shipyardOverrides = nil;
	NSDictionary			*shipyardEntry = nil;
	NSDictionary			*shipyardOverridesEntry = nil;
	NSMutableSet			*playerShips = nil;
	
	// Strip out any shipyard stuff in shipdata (there shouldn't be any).
	for (shipKeyEnum = [ioData keyEnumerator]; (shipKey = [shipKeyEnum nextObject]); )
	{
		shipEntry = [ioData objectForKey:shipKey];
		if ([shipEntry objectForKey:@"_oo_shipyard"] != nil)
		{
			[shipEntry removeObjectForKey:@"_oo_shipyard"];
		}
	}
	
	shipyard = [ResourceManager dictionaryFromFilesNamed:@"shipyard.plist"
												inFolder:@"Config"
											   mergeMode:MERGE_BASIC
												   cache:NO];
	shipyardOverrides = [ResourceManager dictionaryFromFilesNamed:@"shipyard-overrides.plist"
														 inFolder:@"Config"
														mergeMode:MERGE_SMART
															cache:NO];
	
	playerShips = [NSMutableArray arrayWithCapacity:[shipyard count]];
	
	// Insert merged shipyard and shipyardOverrides entries.
	for (shipKeyEnum = [shipyard keyEnumerator]; (shipKey = [shipKeyEnum nextObject]); )
	{
		shipEntry = [ioData objectForKey:shipKey];
		if (shipEntry != nil)
		{
			shipyardEntry = [shipyard objectForKey:shipKey];
			shipyardOverridesEntry = [shipyardOverrides objectForKey:shipKey];
			shipyardEntry = [shipyardEntry dictionaryByAddingEntriesFromDictionary:shipyardOverridesEntry];
			
			[shipEntry setObject:shipyardEntry forKey:@"_oo_shipyard"];
			
			[playerShips addObject:shipKey];
		}
		else
		{
			OOLogWARN(@"shipData.load.shipyard.unknown", @"the shipyard.plist entry \"%@\" does not have a corresponding shipdata.plist entry, ignoring.", shipKey);
		}
	}
	
	_playerShips = [playerShips copy];
	[[OOCacheManager sharedCache] setObject:_playerShips forKey:kPlayerShipsCacheKey inCache:kShipRegistryCacheName];
	
	return YES;
}


- (BOOL) canonicalizeAndTagSubentities:(NSMutableDictionary *)ioData
{
	NSEnumerator			*shipKeyEnum = nil;
	NSString				*shipKey = nil;
	NSMutableDictionary		*shipEntry = nil;
	NSArray					*subentityDeclarations = nil;
	NSEnumerator			*subentityEnum = nil;
	id						subentityDecl = nil;
	NSDictionary			*subentityDict = nil;
	NSString				*subentityKey = nil;
	NSMutableDictionary		*subentityShipEntry = nil;
	NSMutableSet			*badSubentities = nil;
	NSString				*badSubentitiesList = nil;
	NSMutableArray			*okSubentities = nil;
	BOOL					remove, fatal;
	
	// Convert all subentity declarations to dictionaries and add
	// _oo_is_subentity=YES to all entries used as subentities.
	
	// Iterate over all ships. (Iterates over a copy of keys since it mutates the dictionary.)
	for (shipKeyEnum = [[ioData allKeys] objectEnumerator]; (shipKey = [shipKeyEnum nextObject]); )
	{
		shipEntry = [ioData objectForKey:shipKey];
		remove = NO;
		badSubentities = nil;
		
		// Iterate over each subentity declaration of each ship
		subentityDeclarations = [shipEntry oo_arrayForKey:@"subentities"];
		if (subentityDeclarations != nil)
		{
			okSubentities = [NSMutableArray arrayWithCapacity:[subentityDeclarations count]];
			for (subentityEnum = [subentityDeclarations objectEnumerator]; (subentityDecl = [subentityEnum nextObject]); )
			{
				subentityDict = [self canonicalizeSubentityDeclaration:subentityDecl forShip:shipKey shipData:ioData fatalError:&fatal];
				
				// If entry is broken, we need to kill this ship.
				if (fatal)
				{
					remove = YES;
				}
				else if (subentityDict != nil)
				{
					[okSubentities addObject:subentityDict];
					
					// Tag subentities.
					if (![[subentityDict oo_stringForKey:@"type"] isEqualToString:@"flasher"])
					{
						subentityKey = [subentityDict oo_stringForKey:@"subentity_key"];
						subentityShipEntry = [ioData objectForKey:subentityKey];
						if (subentityKey == nil)
						{
							// Oops, reference to non-existent subent.
							if (badSubentities == nil)  badSubentities = [NSMutableSet set];
							[badSubentities addObject:subentityKey];
						}
						else
						{
							// Subent exists, add _oo_is_subentity so roles aren't required.
							[subentityShipEntry oo_setBool:YES forKey:@"_oo_is_subentity"];
						}
					}
				}
			}
			
			// Set updated subentity list.
			if ([okSubentities count] != 0)
			{
				[shipEntry setObject:okSubentities forKey:@"subentities"];
			}
			else
			{
				[shipEntry removeObjectForKey:@"subentities"];
			}
			
			if (badSubentities != nil)
			{
				if (![shipEntry oo_boolForKey:@"is_external_dependency"])
				{
					badSubentitiesList = [[[badSubentities allObjects] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)] componentsJoinedByString:@", "];
					OOLogERR(@"shipData.load.error", @"the shipdata.plist entry \"%@\" has unresolved subentit%@ %@.", shipKey, ([badSubentities count] == 1) ? @"y" : @"ies", badSubentitiesList);
				}
				remove = YES;
			}
			
			if (remove)
			{
				// Removal is deferred to avoid bogus "entry doesn't exist" errors.
				[shipEntry oo_setBool:YES forKey:@"_oo_deferred_remove"];
			}
		}
	}
	
	return YES;
}


- (BOOL) removeUnusableEntries:(NSMutableDictionary *)ioData shipMode:(BOOL)shipMode
{
	NSEnumerator			*shipKeyEnum = nil;
	NSString				*shipKey = nil;
	NSMutableDictionary		*shipEntry = nil;
	BOOL					remove;
	NSString				*modelName = nil;
	
	// Clean out invalid entries and templates. (Iterates over a copy of keys since it mutates the dictionary.)
	for (shipKeyEnum = [[ioData allKeys] objectEnumerator]; (shipKey = [shipKeyEnum nextObject]); )
	{
		shipEntry = [ioData objectForKey:shipKey];
		remove = NO;
		
		if ([shipEntry oo_boolForKey:@"is_template"] || [shipEntry oo_boolForKey:@"_oo_deferred_remove"])  remove = YES;
		else if (shipMode && [[shipEntry oo_stringForKey:@"roles"] length] == 0 && ![shipEntry oo_boolForKey:@"_oo_is_subentity"] && ![shipEntry oo_boolForKey:@"_oo_is_effect"])
		{
			OOLogERR(@"shipData.load.error", @"the shipdata.plist entry \"%@\" specifies no %@.", shipKey, @"roles");
			remove = YES;
		}
		else
		{
			modelName = [shipEntry oo_stringForKey:@"model"];
			if (shipMode && [modelName length] == 0)
			{
				OOLogERR(@"shipData.load.error", @"the shipdata.plist entry \"%@\" specifies no %@.", shipKey, @"model");
				remove = YES;
			}
			else if ([modelName length] != 0 && [ResourceManager pathForFileNamed:modelName inFolder:@"Models"] == nil)
			{
				OOLogERR(@"shipData.load.error", @"the shipdata.plist entry \"%@\" specifies non-existent model \"%@\".", shipKey, modelName);
				remove = YES;
			}
		}
		if (remove)  [ioData removeObjectForKey:shipKey];
	}
	
	return YES;
}


/*	Transform conditions, determinant (if conditions array) and
	shipyard.conditions from hasShipyard to sanitized form.
  Also get list of condition_scripts
*/
- (BOOL) sanitizeConditions:(NSMutableDictionary *)ioData
{
	NSEnumerator			*shipKeyEnum = nil;
	NSString				*shipKey = nil;
	NSMutableDictionary		*shipEntry = nil;
	NSMutableDictionary		*mutableShipyard = nil;
	NSArray					*conditions = nil;
	NSArray					*hasShipyard = nil;
	NSArray					*shipyardConditions = nil;
	NSString        *condition_script = nil;
	NSString        *shipyard_condition_script = nil;
	
	NSMutableArray *conditionScripts = [[NSMutableArray alloc] init];

	for (shipKeyEnum = [[ioData allKeys] objectEnumerator]; (shipKey = [shipKeyEnum nextObject]); )
	{
		shipEntry = [ioData objectForKey:shipKey];
		conditions = [shipEntry objectForKey:@"conditions"];
		condition_script = [shipEntry oo_stringForKey:@"condition_script"];
		if (condition_script != nil)
		{
			if (![conditionScripts containsObject:condition_script])
			{
				[conditionScripts addObject:condition_script];
			}
		}

		hasShipyard = [shipEntry objectForKey:@"has_shipyard"];
		if (![hasShipyard isKindOfClass:[NSArray class]])  hasShipyard = nil;	// May also be fuzzy boolean
		if (hasShipyard == nil)
		{
			hasShipyard = [shipEntry objectForKey:@"hasShipyard"];
			if (![hasShipyard isKindOfClass:[NSArray class]])  hasShipyard = nil;	// May also be fuzzy boolean
		}
		shipyardConditions = [[shipEntry oo_dictionaryForKey:@"_oo_shipyard"] objectForKey:@"conditions"];
		shipyard_condition_script = [[shipEntry oo_dictionaryForKey:@"_oo_shipyard"] oo_stringForKey:@"condition_script"];
		if (shipyard_condition_script != nil)
		{
			if (![conditionScripts containsObject:shipyard_condition_script])
			{
				[conditionScripts addObject:shipyard_condition_script];
			}
		}

		
		if (conditions == nil && hasShipyard && shipyardConditions == nil)  continue;
		
		if (conditions != nil)
		{
			if ([conditions isKindOfClass:[NSArray class]])
			{
				conditions = OOSanitizeLegacyScriptConditions(conditions, [NSString stringWithFormat:@"<shipdata.plist entry \"%@\">", shipKey]);
			}
			else
			{
				OOLogWARN(@"shipdata.load.warning", @"conditions for shipdata.plist entry \"%@\" are not an array, ignoring.", shipKey);
				conditions = nil;
			}
			
			if (conditions != nil)
			{
				[shipEntry setObject:conditions forKey:@"conditions"];
			}
			else
			{
				[shipEntry removeObjectForKey:@"conditions"];
			}
		}
		
		if (hasShipyard != nil)
		{
			hasShipyard = OOSanitizeLegacyScriptConditions(hasShipyard, [NSString stringWithFormat:@"<shipdata.plist entry \"%@\" hasShipyard conditions>", shipKey]);
			
			if (hasShipyard != nil)
			{
				[shipEntry setObject:hasShipyard forKey:@"has_shipyard"];
			}
			else
			{
				[shipEntry removeObjectForKey:@"hasShipyard"];
				[shipEntry removeObjectForKey:@"has_shipyard"];
			}
		}
		
		if (shipyardConditions != nil)
		{
			mutableShipyard = [[[shipEntry oo_dictionaryForKey:@"_oo_shipyard"] mutableCopy] autorelease];
			
			if ([shipyardConditions isKindOfClass:[NSArray class]])
			{
				shipyardConditions = OOSanitizeLegacyScriptConditions(shipyardConditions, [NSString stringWithFormat:@"<shipyard.plist entry \"%@\">", shipKey]);
			}
			else
			{
				OOLogWARN(@"shipdata.load.warning", @"conditions for shipyard.plist entry \"%@\" are not an array, ignoring.", shipKey);
				shipyardConditions = nil;
			}
			
			if (shipyardConditions != nil)
			{
				[mutableShipyard setObject:shipyardConditions forKey:@"conditions"];
			}
			else
			{
				[mutableShipyard removeObjectForKey:@"conditions"];
			}
			
			[shipEntry setObject:mutableShipyard forKey:@"_oo_shipyard"];
		}
	}

	[[OOCacheManager sharedCache] setObject:conditionScripts forKey:@"ship conditions" inCache:@"condition scripts"];
	[conditionScripts release];

	return YES;
}


#if PRELOAD
- (BOOL) preloadShipMeshes:(NSMutableDictionary *)ioData
{
	NSEnumerator			*shipKeyEnum = nil;
	NSString				*shipKey = nil;
	NSMutableDictionary		*shipEntry = nil;
	BOOL					remove;
	NSString				*modelName = nil;
	OOMesh					*mesh = nil;
	NSAutoreleasePool		*pool = nil;
	OOUInteger				i = 0, count;
	
	count = [ioData count];
	
	// Preload ship meshes. (Iterates over a copy of keys since it mutates the dictionary.)
	for (shipKeyEnum = [[ioData allKeys] objectEnumerator]; (shipKey = [shipKeyEnum nextObject]); )
	{
		pool = [[NSAutoreleasePool alloc] init];
		
		[[GameController sharedController] setProgressBarValue:(float)i++ / (float)count];
		
		shipEntry = [ioData objectForKey:shipKey];
		remove = NO;
		
		modelName = [shipEntry oo_stringForKey:@"model"];
		mesh = [OOMesh meshWithName:modelName
				 materialDictionary:[shipEntry oo_dictionaryForKey:@"materials"]
				  shadersDictionary:[shipEntry oo_dictionaryForKey:@"shaders"]
							 smooth:[shipEntry oo_boolForKey:@"smooth"]
					   shaderMacros:nil
				shaderBindingTarget:nil];
		
		[pool release];	// NOTE: mesh is now invalid, but pointer nil check is OK.
		
		if (mesh == nil)
		{
			// FIXME: what if it's a subentity? Need to rearrange things.
			OOLogERR(@"shipData.load.error", @"model \"%@\" could not be loaded for ship \"%@\", removing.", modelName, shipKey);
			[ioData removeObjectForKey:shipKey];
		}
	}
	
	[[GameController sharedController] setProgressBarValue:-1.0f];
	
	return YES;
}
#endif


- (void) mergeShipRoles:(NSString *)roles
			 forShipKey:(NSString *)shipKey
	 intoProbabilityMap:(NSMutableDictionary *)probabilitySets
{
	NSDictionary			*rolesAndWeights = nil;
	NSEnumerator			*roleEnum = nil;
	NSString				*role = nil;
	OOMutableProbabilitySet	*probSet = nil;

	
	/*	probabilitySets is a dictionary whose keys are roles and whose values
		are mutable probability sets, whose values are ship keys.
		
		When creating new ships Oolite looks up this probability map.
		To upgrade all soliton 'thargon' roles to 'EQ_THARGON' we need
		to swap these roles here.
	*/
	
	rolesAndWeights = OOParseRolesFromString(roles);
  // add default [shipKey] role
	NSMutableDictionary *mutable = [NSMutableDictionary dictionaryWithDictionary:rolesAndWeights];
	[mutable setObject:[NSNumber numberWithFloat:1.0] forKey:[[[NSString alloc] initWithFormat:@"[%@]",shipKey] autorelease]];
	rolesAndWeights = mutable;
	
	id thargonValue = [rolesAndWeights objectForKey:@"thargon"];
	if (thargonValue != nil && [rolesAndWeights objectForKey:@"EQ_THARGON"] == nil)
	{
		NSMutableDictionary *mutable = [NSMutableDictionary dictionaryWithDictionary:rolesAndWeights];
		[mutable setObject:thargonValue forKey:@"EQ_THARGON"];
		rolesAndWeights = mutable;
	}
	
	for (roleEnum = [rolesAndWeights keyEnumerator]; (role = [roleEnum nextObject]); )
	{
		probSet = [probabilitySets objectForKey:role];
		if (probSet == nil)
		{
			probSet = [OOMutableProbabilitySet probabilitySet];
			[probabilitySets setObject:probSet forKey:role];
		}
		
		[probSet setWeight:[rolesAndWeights oo_floatForKey:role] forObject:shipKey];
	}
}


- (NSDictionary *) canonicalizeSubentityDeclaration:(id)declaration
											forShip:(NSString *)shipKey
										   shipData:(NSDictionary *)shipData
										 fatalError:(BOOL *)outFatalError
{
	NSDictionary			*result = nil;
	
	assert(outFatalError != NULL);
	*outFatalError = NO;
	
	if ([declaration isKindOfClass:[NSString class]])
	{
		// Update old-style string-based declaration.
		result = [self translateOldStyleSubentityDeclaration:declaration
													 forShip:shipKey
													shipData:shipData
												  fatalError:outFatalError];
		
		if (result != nil)
		{
			// Ensure internal translation made sense, and clean up a bit.
			result = [self validateNewStyleSubentityDeclaration:result
														forShip:shipKey
													 fatalError:outFatalError];
		}
	}
	else if ([declaration isKindOfClass:[NSDictionary class]])
	{
		// Validate dictionary-based declaration.
		result = [self validateNewStyleSubentityDeclaration:declaration
													forShip:shipKey
												 fatalError:outFatalError];
	}
	else
	{
		OOLogERR(@"shipData.load.error.badSubentity", @"subentity declaration for ship %@ should be string or dictionary, found %@.", shipKey, [declaration class]);
		*outFatalError = YES;
	}
	
	// For frangible ships, bad subentities are non-fatal.
	if (*outFatalError && [[shipData oo_dictionaryForKey:shipKey] oo_boolForKey:@"frangible"])  *outFatalError = NO;
	
	return result;
}


- (NSDictionary *) translateOldStyleSubentityDeclaration:(NSString *)declaration
												 forShip:(NSString *)shipKey
												shipData:(NSDictionary *)shipData
											  fatalError:(BOOL *)outFatalError
{
	NSArray					*tokens = nil;
	NSString				*subentityKey = nil;
	BOOL					isFlasher;
	
	tokens = ScanTokensFromString(declaration);
	
	subentityKey = [tokens objectAtIndex:0];
	isFlasher = [subentityKey isEqualToString:@"*FLASHER*"];
	
	// Sanity check: require eight tokens.
	if ([tokens count] != 8)
	{
		if (!isFlasher)
		{
			OOLogERR(@"shipData.load.error.badSubentity", @"the shipdata.plist entry \"%@\" has a broken subentity definition \"%@\" (should have 8 tokens, has %lu).", shipKey, subentityKey, [tokens count]);
			*outFatalError = YES;
		}
		else
		{
			OOLogWARN(@"shipData.load.warning.badFlasher", @"the shipdata.plist entry \"%@\" has a broken flasher definition (should have 8 tokens, has %lu). This flasher will be ignored.", shipKey, [tokens count]);
		}
		return nil;
	}
	
	if (isFlasher)
	{
		return [self translateOldStyleFlasherDeclaration:tokens
												 forShip:shipKey
											  fatalError:outFatalError];
	}
	else
	{
		return [self translateOldStandardBasicSubentityDeclaration:tokens
														   forShip:shipKey
														  shipData:shipData
														fatalError:outFatalError];
	}
}


- (NSDictionary *) translateOldStyleFlasherDeclaration:(NSArray *)tokens
											   forShip:(NSString *)shipKey
											fatalError:(BOOL *)outFatalError
{
	Vector					position;
	float					size, frequency, phase, hue;
	NSDictionary			*colorDict = nil;
	NSDictionary			*result = nil;
	
	position.x = [tokens oo_floatAtIndex:1];
	position.y = [tokens oo_floatAtIndex:2];
	position.z = [tokens oo_floatAtIndex:3];
	
	hue = [tokens oo_floatAtIndex:4];
	frequency = [tokens oo_floatAtIndex:5];
	phase = [tokens oo_floatAtIndex:6];
	size = [tokens oo_floatAtIndex:7];
	
	colorDict = [NSDictionary dictionaryWithObject:[NSNumber numberWithFloat:hue] forKey:@"hue"];
	
	result = [NSDictionary dictionaryWithObjectsAndKeys:
			  @"flasher", @"type",
			  OOPropertyListFromVector(position), @"position",
			  [NSArray arrayWithObject:colorDict], @"colors",
			  [NSNumber numberWithFloat:frequency], @"frequency",
			  [NSNumber numberWithFloat:phase], @"phase",
			  [NSNumber numberWithFloat:size], @"size",
			  nil];
	
	OOLog(@"shipData.translateSubentity.flasher", @"Translated flasher declaration \"%@\" to %@", [tokens componentsJoinedByString:@" "], result);
	
	return result;
}


- (NSDictionary *) translateOldStandardBasicSubentityDeclaration:(NSArray *)tokens
														 forShip:(NSString *)shipKey
														shipData:(NSDictionary *)shipData
													  fatalError:(BOOL *)outFatalError
{
	NSString				*subentityKey = nil;
	Vector					position;
	Quaternion				orientation;
	NSMutableDictionary		*result = nil;
	BOOL					isTurret, isDock = NO;
	
	subentityKey = [tokens oo_stringAtIndex:0];
	
	isTurret = [self shipIsBallTurretForKey:subentityKey inShipData:shipData];
	
	position.x = [tokens oo_floatAtIndex:1];
	position.y = [tokens oo_floatAtIndex:2];
	position.z = [tokens oo_floatAtIndex:3];
	
	orientation.w = [tokens oo_floatAtIndex:4];
	orientation.x = [tokens oo_floatAtIndex:5];
	orientation.y = [tokens oo_floatAtIndex:6];
	orientation.z = [tokens oo_floatAtIndex:7];
	
	if(orientation.w == 0 && orientation.x == 0 && orientation.y == 0 && orientation.z == 0) 
	{
		orientation.w = 1; // avoid dividing by zero.
		OOLogWARN(@"shipData.load.error", @"The ship %@ has an undefined orientation for its %@ subentity. Setting it now at (1,0,0,0)", shipKey, subentityKey);
	}
	
	quaternion_normalize(&orientation);
	
	if (!isTurret)
	{
		isDock = [subentityKey rangeOfString:@"dock"].location != NSNotFound;
	}
	
	result = [NSMutableDictionary dictionaryWithCapacity:5];
	[result setObject:isTurret ? @"ball_turret" : @"standard" forKey:@"type"];
	[result setObject:subentityKey forKey:@"subentity_key"];
	[result oo_setVector:position forKey:@"position"];
	[result oo_setQuaternion:orientation forKey:@"orientation"];
	if (isDock)  [result oo_setBool:YES forKey:@"is_dock"];
	
	OOLog(@"shipData.translateSubentity.standard", @"Translated subentity declaration \"%@\" to %@", [tokens componentsJoinedByString:@" "], result);
	
	return [[result copy] autorelease];
}


- (NSDictionary *) validateNewStyleSubentityDeclaration:(NSDictionary *)declaration
												forShip:(NSString *)shipKey
											 fatalError:(BOOL *)outFatalError
{
	NSString				*type = nil;
	
	type = [declaration oo_stringForKey:@"type"];
	if (type == nil)  type = @"standard";
	
	if ([type isEqualToString:@"flasher"])
	{
		return [self validateNewStyleFlasherDeclaration:declaration forShip:shipKey fatalError:outFatalError];
	}
	else if ([type isEqualToString:@"standard"] || [type isEqualToString:@"ball_turret"])
	{
		return [self validateNewStyleStandardSubentityDeclaration:declaration forShip:shipKey fatalError:outFatalError];
	}
	else
	{
		OOLogERR(@"shipData.load.error.badSubentity", @"subentity declaration for ship %@ does not declare a valid type (must be standard, flasher or ball_turret).", shipKey);
		*outFatalError = YES;
		return nil;
	}
}


- (NSDictionary *) validateNewStyleFlasherDeclaration:(NSDictionary *)declaration
											  forShip:(NSString *)shipKey
										   fatalError:(BOOL *)outFatalError
{
	NSMutableDictionary		*result = nil;
	Vector					position = kZeroVector;
	NSArray					*colors = nil;
	id						colorDesc = nil;
	float					size, frequency, phase, brightfraction;
	BOOL					initiallyOn;
	
#define kDefaultFlasherColor @"redColor"
	
	// "Validate" is really "clean up", since all values have defaults.
	colors = [declaration oo_arrayForKey:@"colors"];
	if ([colors count] == 0)
	{
		colorDesc = [declaration objectForKey:@"color"];
		if (colorDesc == nil) colorDesc = kDefaultFlasherColor;
		if ([colorDesc isKindOfClass:[NSArray class]])
		{
			// an easy made error is adding an array to "color" instead of "colors"
			OOLogWARN(@"shipData.load.warning.flasher.badColor", @"changing flasher for ship %@ from a color to a colors definition.", shipKey);
			colors = colorDesc;
		}
		else
		{
			colors = [NSArray arrayWithObject:colorDesc];
		}
	}
	
	// Validate colours.
	NSMutableArray *validColors = [NSMutableArray arrayWithCapacity:[colors count]];
	foreach (colorDesc, colors)
	{
		OOColor *color = [OOColor colorWithDescription:colorDesc];
		if (color != nil)
		{
			[validColors addObject:[color normalizedArray]];
		}
		else
		{
			OOLogWARN(@"shipdata.load.warning.flasher.badColor", @"skipping invalid colour specifier for flasher for ship %@.", shipKey);
		}
	}
	// Ensure there's at least one.
	if ([validColors count] == 0)
	{
		[validColors addObject:kDefaultFlasherColor];
	}
	colors = validColors;
	
	position = [declaration oo_vectorForKey:@"position"];
	
	size = [declaration oo_floatForKey:@"size" defaultValue:8.0];
	
	if (size <= 0)
	{
		OOLogWARN(@"shipData.load.warning.flasher.badSize", @"skipping flasher of invalid size %g for ship %@.", size, shipKey);
		return nil;
	}

	brightfraction = [declaration oo_floatForKey:@"bright_fraction" defaultValue:0.5];
	if (brightfraction < 0.0 || brightfraction > 1.0)
	{
		OOLogWARN(@"shipData.load.warning.flasher.badFraction", @"skipping flasher of invalid bright fraction %g for ship %@.", brightfraction, shipKey);
		return nil;
	}
	
	frequency = [declaration oo_floatForKey:@"frequency" defaultValue:2.0];
	phase = [declaration oo_floatForKey:@"phase" defaultValue:0.0];
	initiallyOn = [declaration oo_boolForKey:@"initially_on" defaultValue:YES];
	
	result = [NSMutableDictionary dictionaryWithCapacity:8];
	[result setObject:@"flasher" forKey:@"type"];
	[result setObject:colors forKey:@"colors"];
	[result oo_setVector:position forKey:@"position"];
	[result setObject:[NSNumber numberWithFloat:size] forKey:@"size"];
	[result setObject:[NSNumber numberWithFloat:frequency] forKey:@"frequency"];
	if (phase != 0)  [result setObject:[NSNumber numberWithFloat:phase] forKey:@"phase"];
	[result setObject:[NSNumber numberWithFloat:brightfraction] forKey:@"bright_fraction"];
	[result setObject:[NSNumber numberWithBool:initiallyOn] forKey:@"initially_on"];
	
	return [[result copy] autorelease];
}


- (NSDictionary *) validateNewStyleStandardSubentityDeclaration:(NSDictionary *)declaration
														forShip:(NSString *)shipKey
													 fatalError:(BOOL *)outFatalError
{
	NSMutableDictionary		*result = nil;
	NSString				*subentityKey = nil;
	Vector					position = kZeroVector;
	Quaternion				orientation = kIdentityQuaternion;
	BOOL					isTurret;
	BOOL					isDock = NO;
	float					fireRate = -1.0f; // out of range constants
	float					weaponRange = -1.0f;
	float					weaponEnergy = -1.0f;
	NSDictionary			*scriptInfo = nil;
	
	subentityKey = [declaration objectForKey:@"subentity_key"];
	if (subentityKey == nil)
	{
		OOLogERR(@"shipData.load.error.badSubentity", @"subentity declaration for ship %@ specifies no subentity_key.", shipKey);
		*outFatalError = YES;
		return nil;
	}
	
	isTurret = [[declaration oo_stringForKey:@"type"] isEqualToString:@"ball_turret"];
	if (isTurret)
	{
		fireRate = [declaration oo_floatForKey:@"fire_rate" defaultValue:-1.0f];
		if (fireRate < 0.25f && fireRate >= 0.0f)
		{
			OOLogWARN(@"shipData.load.warning.turret.badFireRate", @"ball turret fire rate of %g for subenitity of ship %@ is invalid, using 0.25.", fireRate, shipKey);
			fireRate = 0.25f;
		}
		weaponRange = [declaration oo_floatForKey:@"weapon_range" defaultValue:-1.0f];
		if (weaponRange > 7500.0f)
		{
			OOLogWARN(@"shipData.load.warning.turret.badWeaponRange", @"ball turret weapon range of %g for subenitity of ship %@ is too high, using 7500.", weaponRange, shipKey);
			weaponRange = 7500.0f; // range of primary plasma canon.
		}

		weaponEnergy = [declaration oo_floatForKey:@"weapon_energy" defaultValue:-1.0f];
		if (weaponEnergy > 100.0f)
			
		{
			OOLogWARN(@"shipData.load.warning.turret.badWeaponEnergy", @"ball turret weapon energy of %g for subenitity of ship %@ is too high, using 100.", weaponEnergy, shipKey);
			weaponEnergy = 100.0f;
		}
	}
	else
	{
		isDock = [declaration oo_boolForKey:@"is_dock"];
	}
	
	position = [declaration oo_vectorForKey:@"position"];
	orientation = [declaration oo_quaternionForKey:@"orientation"];
	quaternion_normalize(&orientation);
	
	scriptInfo = [declaration oo_dictionaryForKey:@"script_info"];
	
	result = [NSMutableDictionary dictionaryWithCapacity:10];
	[result setObject:isTurret ? @"ball_turret" : @"standard" forKey:@"type"];
	[result setObject:subentityKey forKey:@"subentity_key"];
	[result oo_setVector:position forKey:@"position"];
	[result oo_setQuaternion:orientation forKey:@"orientation"];
	if (isDock) 
	{
		[result oo_setBool:YES forKey:@"is_dock"];

		NSString* docklabel = [declaration oo_stringForKey:@"dock_label" defaultValue:@"the docking bay"];
		[result setObject:docklabel forKey:@"dock_label"];

		BOOL dockable = [declaration oo_boolForKey:@"allow_docking" defaultValue:YES];
		BOOL playerdockable = [declaration oo_boolForKey:@"disallowed_docking_collides" defaultValue:NO];
		BOOL undockable = [declaration oo_boolForKey:@"allow_launching" defaultValue:YES];

		[result oo_setBool:dockable forKey:@"allow_docking"];
		[result oo_setBool:playerdockable forKey:@"disallowed_docking_collides"];
		[result oo_setBool:undockable forKey:@"allow_launching"];

	}

	if (isTurret)
	{
		// default constants are defined and set in shipEntity
		if (fireRate > 0) [result oo_setFloat:fireRate forKey:@"fire_rate"];
		if (weaponRange >= 0) [result oo_setFloat:weaponRange forKey:@"weapon_range"];
		if (weaponEnergy >= 0) [result oo_setFloat:weaponEnergy forKey:@"weapon_energy"];
	}
	
	if (scriptInfo != nil)
	{
		[result setObject:scriptInfo forKey:@"script_info"];
	}
	
	return [[result copy] autorelease];
}


- (BOOL) shipIsBallTurretForKey:(NSString *)shipKey inShipData:(NSDictionary *)shipData
{
	// Test for presence of setup_actions containing initialiseTurret.
	NSArray					*setupActions = nil;
	NSEnumerator			*actionEnum = nil;
	NSString				*action = nil;
	
	setupActions = [[shipData oo_dictionaryForKey:shipKey] oo_arrayForKey:@"setup_actions"];
	
	for (actionEnum = [setupActions objectEnumerator]; (action = [actionEnum nextObject]); )
	{
		if ([[ScanTokensFromString(action) objectAtIndex:0] isEqualToString:@"initialiseTurret"])  return YES;
	}
	
	return NO;
}

@end


@implementation OOShipRegistry (Singleton)

/*	Canonical singleton boilerplate.
	See Cocoa Fundamentals Guide: Creating a Singleton Instance.
	See also +sharedRegistry above.
	
	NOTE: assumes single-threaded access.
*/

+ (id) allocWithZone:(NSZone *)inZone
{
	if (sSingleton == nil)
	{
		OOLog(@"shipData.load.begin", @"Loading ship data.");
		sSingleton = [super allocWithZone:inZone];
		return sSingleton;
	}
	return nil;
}


- (id) copyWithZone:(NSZone *)inZone
{
	return self;
}


- (id) retain
{
	return self;
}


- (OOUInteger) retainCount
{
	return UINT_MAX;
}


- (void) release
{}


- (id) autorelease
{
	return self;
}

@end


static void GatherStringAddrsDict(NSDictionary *dict, NSMutableSet *strings, NSString *context);
static void GatherStringAddrsArray(NSArray *array, NSMutableSet *strings, NSString *context);
static void GatherStringAddrs(id object, NSMutableSet *strings, NSString *context);


static void DumpStringAddrs(NSDictionary *dict, NSString *context)
{
	return;
	static FILE *dump = NULL;
	if (dump == NULL)  dump = fopen("strings.txt", "w");
	if (dump == NULL)  return;
	
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	NSMutableSet *strings = [NSMutableSet set];
	GatherStringAddrs(dict, strings, context);
	
	NSEnumerator *entryEnum = nil;
	NSDictionary *entry = nil;
	for (entryEnum = [strings objectEnumerator]; (entry = [entryEnum nextObject]); )
	{
		NSString *string = [entry objectForKey:@"string"];
		NSString *context = [entry objectForKey:@"context"];
		void *pointer = [[entry objectForKey:@"address"] pointerValue];
		
		string = [NSString stringWithFormat:@"%p\t%@:  \"%@\"", pointer, context, string];
		
		fprintf(dump, "%s\n", [string UTF8String]);
	}
	
	fprintf(dump, "\n");
	fflush(dump);
	[pool release];
}


static void GatherStringAddrsDict(NSDictionary *dict, NSMutableSet *strings, NSString *context)
{
	NSEnumerator *keyEnum = nil;
	id key = nil;
	NSString *keyContext = [context stringByAppendingString:@" key"];
	for (keyEnum = [dict keyEnumerator]; (key = [keyEnum nextObject]); )
	{
		GatherStringAddrs(key, strings, keyContext);
		GatherStringAddrs([dict objectForKey:key], strings, [context stringByAppendingFormat:@".%@", key]);
	}
}


static void GatherStringAddrsArray(NSArray *array, NSMutableSet *strings, NSString *context)
{
	NSEnumerator *vEnum = nil;
	NSString *v = nil;
	unsigned i = 0;
	for (vEnum = [array objectEnumerator]; (v = [vEnum nextObject]); )
	{
		GatherStringAddrs(v, strings, [context stringByAppendingFormat:@"[%u]", i++]);
	}
}


static void GatherStringAddrs(id object, NSMutableSet *strings, NSString *context)
{
	if ([object isKindOfClass:[NSString class]])
	{
		NSDictionary *entry = [NSDictionary dictionaryWithObjectsAndKeys:object, @"string", [NSValue valueWithPointer:object], @"address", context, @"context", nil];
		[strings addObject:entry];
	}
	else if ([object isKindOfClass:[NSArray class]])
	{
		GatherStringAddrsArray(object, strings, context);
	}
	else if ([object isKindOfClass:[NSDictionary class]])
	{
		GatherStringAddrsDict(object, strings, context);
	}
}
