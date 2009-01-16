/*

OOShipRegistry.m


Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2008 Jens Ayton

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


#define PRELOAD 0


static OOShipRegistry	*sSingleton = nil;

static NSString * const	kShipRegistryCacheName = @"ship registry";
static NSString * const	kShipDataCacheKey = @"ship data";
static NSString * const	kPlayerShipsCacheKey = @"player ships";
static NSString * const	kDemoShipsCacheKey = @"demo ships";
static NSString * const	kRoleWeightsCacheKey = @"role weights";
static NSString * const	kDefaultDemoShip = @"coriolis-station";


@interface OOShipRegistry (OODataLoader)

- (void) loadShipData;
- (void) loadDemoShips;
- (void) loadCachedRoleProbabilitySets;
- (void) buildRoleProbabilitySets;

- (BOOL) applyLikeShips:(NSMutableDictionary *)ioData;
- (BOOL) loadAndMergeShipyard:(NSMutableDictionary *)ioData;
- (BOOL) loadAndApplyShipDataOverrides:(NSMutableDictionary *)ioData;
- (BOOL) tagSubEntities:(NSMutableDictionary *)ioData;
- (BOOL) removeUnusableEntries:(NSMutableDictionary *)ioData;
- (BOOL) sanitizeConditions:(NSMutableDictionary *)ioData;

#if PRELOAD
- (BOOL) preloadShipMeshes:(NSMutableDictionary *)ioData;
#endif

- (NSDictionary *) mergeShip:(NSDictionary *)child withParent:(NSDictionary *)parent;
- (void) mergeShipRoles:(NSString *)roles forShipKey:(NSString *)shipKey intoProbabilityMap:(NSMutableDictionary *)probabilitySets;

@end


@implementation OOShipRegistry

+ (OOShipRegistry *) sharedRegistry
{
	if (sSingleton == nil)
	{
		[[self alloc] init];
	}
	
	return sSingleton;
}


- (id) init
{
	if ((self = [super init]))
	{
		NSAutoreleasePool		*pool = [[NSAutoreleasePool alloc] init];
		OOCacheManager			*cache = [OOCacheManager sharedCache];
		
		_shipData = [[cache objectForKey:kShipDataCacheKey inCache:kShipRegistryCacheName] retain];
		_playerShips = [[cache objectForKey:kPlayerShipsCacheKey inCache:kShipRegistryCacheName] retain];
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


- (NSDictionary *) shipyardInfoForKey:(NSString *)key
{
	return [[self shipInfoForKey:key] objectForKey:@"shipyard"];
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
	NSEnumerator			*enumerator = nil;
	NSString				*key = nil;
	NSDictionary			*immutableResult = nil;
	
	OOLog(@"shipData.load.begin", @"Loading ship data...");
	OOLogIndentIf(@"shipData.load.begin");
	
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
	
	// Clean out any non-dictionaries. (Iterates over a copy of keys since it mutates the dictionary.)
	for (enumerator = [[result allKeys] objectEnumerator]; (key = [enumerator nextObject]); )
	{
		if (![[result objectForKey:key] isKindOfClass:[NSDictionary class]])
		{
			OOLog(@"shipData.load.badEntry", @"***** ERROR: the shipdata.plist entry \"%@\" is not a dictionary.", key);
			[result removeObjectForKey:key];
		}
	}
	
	// Apply patches.
	if (![self loadAndApplyShipDataOverrides:result])  return;
	
	// Tag subentities so they won't be pruned.
	if (![self tagSubEntities:result])  return;
	
	// Resolve like_ship entries.
	if (![self applyLikeShips:result])  return;
	
	// Clean out templates and invalid entries.
	if (![self removeUnusableEntries:result])  return;
	
	// Add shipyard entries into shipdata entries.
	if (![self loadAndMergeShipyard:result])  return;
	
	// Sanitize conditions.
	if (![self sanitizeConditions:result])  return;
	
#if PRELOAD
	// Preload and cache meshes.
	if (![self preloadShipMeshes:result])  return;
#endif
	
	immutableResult = [[result copy] autorelease];
	_shipData = [immutableResult retain];
	[[OOCacheManager sharedCache] setObject:_shipData forKey:kShipDataCacheKey inCache:kShipRegistryCacheName];
	
	OOLogOutdentIf(@"shipData.load.begin");
	OOLog(@"shipData.load.done", @"Ship data loaded.");
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
												   andMerge:YES];
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
		roles = [shipEntry stringForKey:@"roles"];
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
- (BOOL) applyLikeShips:(NSMutableDictionary *)ioData
{
	NSMutableSet			*remainingLikeShips = nil;
	NSEnumerator			*enumerator = nil;
	NSString				*key = nil;
	NSString				*parentKey = nil;
	NSDictionary			*shipEntry = nil;
	NSDictionary			*parentEntry = nil;
	unsigned				count, lastCount;
	NSMutableArray			*reportedBadShips = nil;
	
	// Build set of ships with like_ship references
	remainingLikeShips = [NSMutableSet set];
	for (enumerator = [ioData keyEnumerator]; (key = [enumerator nextObject]); )
	{
		shipEntry = [ioData objectForKey:key];
		if ([shipEntry stringForKey:@"like_ship"] != nil)
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
			parentKey = [shipEntry objectForKey:@"like_ship"];
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
				if (![[ioData objectForKey:key] boolForKey:@"is_external_dependency"])
				{
					[reportedBadShips addObject:key];
				}
				[ioData removeObjectForKey:key];
			}
			
			if ([reportedBadShips count] != 0)
			{
				[reportedBadShips sortUsingSelector:@selector(caseInsensitiveCompare:)];
				OOLog(@"shipData.merge.failed", @"***** ERROR: one or more shipdata.plist entries have like_ship references that cannot be resolved: %@", [reportedBadShips componentsJoinedByString:@", "]);
			}
			break;
		}
		lastCount = count;
	}
	
	return YES;
}


- (NSDictionary *) mergeShip:(NSDictionary *)child withParent:(NSDictionary *)parent
{
	NSMutableDictionary *result = [[parent mutableCopy] autorelease];
	if (result == nil)  return nil;
	
	[result addEntriesFromDictionary:child];
	[result removeObjectForKey:@"like_ship"];
	
	// Certain properties cannot be inherited.
	if ([child stringForKey:@"display_name"] == nil)  [result removeObjectForKey:@"display_name"];
	if ([child stringForKey:@"is_template"] == nil)  [result removeObjectForKey:@"is_template"];
	
	return [[result copy] autorelease];
}


- (BOOL) loadAndApplyShipDataOverrides:(NSMutableDictionary *)ioData
{
	NSEnumerator			*enumerator = nil;
	NSString				*key = nil;
	NSDictionary			*shipEntry = nil;
	NSDictionary			*overrides = nil;
	NSDictionary			*overridesEntry = nil;
	
	overrides = [ResourceManager dictionaryFromFilesNamed:@"shipdata-overrides.plist"
												 inFolder:@"Config"
												mergeMode:MERGE_SMART
													cache:NO];
	
	for (enumerator = [overrides keyEnumerator]; (key = [enumerator nextObject]); )
	{
		shipEntry = [ioData objectForKey:key];
		if (shipEntry != nil)
		{
			overridesEntry = [overrides objectForKey:key];
			if (![overridesEntry isKindOfClass:[NSDictionary class]])
			{
				OOLog(@"shipData.load.error", @"***** ERROR: the shipdata-overrides.plist entry \"%@\" is not a dictionary.", key);
			}
			else
			{
				shipEntry = [shipEntry dictionaryByAddingEntriesFromDictionary:overridesEntry];
				[ioData setObject:shipEntry forKey:key];
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
	NSEnumerator			*enumerator = nil;
	NSString				*key = nil;
	NSDictionary			*shipEntry = nil;
	NSDictionary			*shipyard = nil;
	NSDictionary			*shipyardOverrides = nil;
	NSDictionary			*shipyardEntry = nil;
	NSDictionary			*shipyardOverridesEntry = nil;
	NSMutableSet			*playerShips = nil;
	
	// Strip out any shipyard stuff in shipdata (there shouldn't be any).
	for (enumerator = [ioData keyEnumerator]; (key = [enumerator nextObject]); )
	{
		shipEntry = [ioData objectForKey:key];
		if ([shipEntry objectForKey:@"shipyard"] != nil)
		{
			[ioData setObject:[shipEntry dictionaryByRemovingObjectForKey:@"shipyard"] forKey:key];
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
	for (enumerator = [shipyard keyEnumerator]; (key = [enumerator nextObject]); )
	{
		shipEntry = [ioData objectForKey:key];
		if (shipEntry != nil)
		{
			shipyardEntry = [shipyard objectForKey:key];
			shipyardOverridesEntry = [shipyardOverrides objectForKey:key];
			shipyardEntry = [shipyardEntry dictionaryByAddingEntriesFromDictionary:shipyardOverridesEntry];
			
			shipEntry = [shipEntry dictionaryByAddingObject:shipyardEntry forKey:@"shipyard"];
			[ioData setObject:shipEntry forKey:key];
			
			[playerShips addObject:key];
		}
		else
		{
			OOLog(@"shipData.load.shipyard.unknown", @"WARNING: the shipyard.plist entry \"%@\" does not have a corresponding shipdata.plist entry, ignoring.", key);
		}
	}
	
	_playerShips = [playerShips copy];
	[[OOCacheManager sharedCache] setObject:_playerShips forKey:kPlayerShipsCacheKey inCache:kShipRegistryCacheName];
	
	return YES;
}


- (BOOL) tagSubEntities:(NSMutableDictionary *)ioData
{
	NSEnumerator			*shipKeyEnum = nil;
	NSString				*shipKey = nil;
	NSDictionary			*shipEntry = nil;
	NSArray					*subEntityDeclarations = nil;
	NSEnumerator			*subEntityEnum = nil;
	NSString				*subEntityKey = nil;
	NSArray					*subEntityDef = nil;
	NSDictionary			*subEntityShipEntry = nil;
	BOOL					remove;
	NSMutableSet			*badSubEntities = nil;
	NSString				*badSubEntitiesList = nil;
	BOOL					isFlasher;
	NSMutableArray			*okSubEntities = nil;
	
	// Add _oo_is_subentity=YES to all entries used as subentities.
	// Iterate over all ships. (Iterates over a copy of keys since it mutates the dictionary.)
	for (shipKeyEnum = [[ioData allKeys] objectEnumerator]; (shipKey = [shipKeyEnum nextObject]); )
	{
		shipEntry = [ioData objectForKey:shipKey];
		remove = NO;
		badSubEntities = nil;
		
		// Iterate over each subentity declaration of each ship
		subEntityDeclarations = [shipEntry arrayForKey:@"subentities"];
		if (subEntityDeclarations != nil)
		{
			okSubEntities = [NSMutableArray arrayWithCapacity:[subEntityDeclarations count]];
			for (subEntityEnum = [subEntityDeclarations objectEnumerator]; (subEntityKey = [subEntityEnum nextObject]); )
			{
				subEntityDef = ScanTokensFromString(subEntityKey);
				if([subEntityDef count] != 0)  subEntityKey = [subEntityDef stringAtIndex:0];
				else  subEntityKey = nil;
				isFlasher = [subEntityKey isEqualToString:@"*FLASHER*"];
				
				// While we're at it, do basic sanity checking on subentity defs.
				if ([subEntityDef count] != 8)
				{
					if (!isFlasher)
					{
						OOLog(@"shipData.load.error.badSubEntity", @"***** ERROR: the shipdata.plist entry \"%@\" has a broken subentity definition \"%@\" (should have 8 tokens, has %u).", shipKey, subEntityKey, [subEntityDef count]);
						if (![shipEntry boolForKey:@"frangible"])  remove = YES;
					}
					else
					{
						OOLog(@"shipData.load.error.badFlasher", @"----- WARNING: the shipdata.plist entry \"%@\" has a broken flasher definition \"%@\" (should have 8 tokens, has %u). This flasher will be ignored.", shipKey, subEntityKey, [subEntityDef count]);
					}
				}
				else
				{
					[okSubEntities addObject:subEntityKey];
					
					if (!isFlasher)
					{
						subEntityShipEntry = [ioData objectForKey:subEntityKey];
						if (subEntityShipEntry == nil)
						{
							// Oops, reference to non-existent subent
							if (badSubEntities == nil)  badSubEntities = [NSMutableSet set];
							[badSubEntities addObject:subEntityKey];
						}
						else if (![subEntityShipEntry boolForKey:@"_oo_is_subentity"])
						{
							// Subent exists, add _oo_is_subentity so roles aren't required
							subEntityShipEntry = [subEntityShipEntry dictionaryByAddingObject:[NSNumber numberWithBool:YES] forKey:@"_oo_is_subentity"];
							[ioData setObject:subEntityShipEntry forKey:subEntityKey];
						}
					}
				}
			}
			
			// If subentities have been excluded (i.e. there are bad flashers,
			// or there are bad subentities but the ship is frangible), copy
			// in new shortened list.
			if ([okSubEntities count] != [subEntityDeclarations count] && !remove)
			{
				shipEntry = [[shipEntry mutableCopy] autorelease];
				if ([okSubEntities count] == 0)
				{
					[(NSMutableDictionary *)shipEntry removeObjectForKey:@"subentities"];
				}
				else
				{
					[(NSMutableDictionary *)shipEntry setObject:[[okSubEntities copy] autorelease] forKey:@"subentities"];
				}
			}
		}
		
		if (badSubEntities != nil)
		{
			if (![shipEntry boolForKey:@"is_external_dependency"])
			{
				badSubEntitiesList = [[[badSubEntities allObjects] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)] componentsJoinedByString:@", "];
				OOLog(@"shipData.load.error", @"***** ERROR: the shipdata.plist entry \"%@\" has unresolved subentit%@ %@.", shipKey, ([badSubEntities count] == 1) ? @"y" : @"ies", badSubEntitiesList);
			}
			remove = YES;
		}
		
		if (remove)
		{
			// Removal is deferred to avoid bogus "entry doesn't exist" errors.
			shipEntry = [shipEntry dictionaryByAddingObject:[NSNumber numberWithBool:YES] forKey:@"_oo_deferred_remove"];
			[ioData setObject:shipEntry forKey:shipKey];
		}
	}
	
	return YES;
}


- (BOOL) removeUnusableEntries:(NSMutableDictionary *)ioData
{
	NSEnumerator			*shipKeyEnum = nil;
	NSString				*shipKey = nil;
	NSDictionary			*shipEntry = nil;
	BOOL					remove;
	NSString				*modelName = nil;
	
	// Clean out invalid entries and templates. (Iterates over a copy of keys since it mutates the dictionary.)
	for (shipKeyEnum = [[ioData allKeys] objectEnumerator]; (shipKey = [shipKeyEnum nextObject]); )
	{
		shipEntry = [ioData objectForKey:shipKey];
		remove = NO;
		
		if ([shipEntry boolForKey:@"is_template"] || [shipEntry boolForKey:@"_oo_deferred_remove"])  remove = YES;
		else if ([[shipEntry stringForKey:@"roles"] length] == 0 && ![shipEntry boolForKey:@"_oo_is_subentity"])
		{
			OOLog(@"shipData.load.error", @"***** ERROR: the shipdata.plist entry \"%@\" specifies no %@.", shipKey, @"roles");
			remove = YES;
		}
		else
		{
			modelName = [shipEntry stringForKey:@"model"];
			if ([modelName length] == 0)
			{
				OOLog(@"shipData.load.error", @"***** ERROR: the shipdata.plist entry \"%@\" specifies no %@.", shipKey, @"model");
				remove = YES;
			}
			else if ([ResourceManager pathForFileNamed:modelName inFolder:@"Models"] == nil)
			{
				OOLog(@"shipData.load.error", @"***** ERROR: the shipdata.plist entry \"%@\" specifies non-existent model \"%@\".", shipKey, modelName, @"model");
				remove = YES;
			}
		}
		if (remove)  [ioData removeObjectForKey:shipKey];
	}
	
	return YES;
}


/*	Transform conditions, determinant (if conditions array) and
	shipyard.conditions from hasShipyard to sanitized form.
*/
- (BOOL) sanitizeConditions:(NSMutableDictionary *)ioData
{
	NSEnumerator			*shipKeyEnum = nil;
	NSString				*shipKey = nil;
	NSDictionary			*shipEntry = nil;
	NSMutableDictionary		*mutableEntry = nil;
	NSMutableDictionary		*mutableShipyard = nil;
	NSArray					*conditions = nil;
	NSArray					*hasShipyard = nil;
	NSArray					*shipyardConditions = nil;
	
	for (shipKeyEnum = [[ioData allKeys] objectEnumerator]; (shipKey = [shipKeyEnum nextObject]); )
	{
		shipEntry = [ioData objectForKey:shipKey];
		conditions = [shipEntry objectForKey:@"conditions"];
		hasShipyard = [shipEntry objectForKey:@"hasShipyard"];
		if (![hasShipyard isKindOfClass:[NSArray class]])  hasShipyard = nil;	// May also be fuzzy boolean
		shipyardConditions = [[shipEntry dictionaryForKey:@"shipyard"] objectForKey:@"conditions"];
		
		if (conditions == nil && hasShipyard && shipyardConditions == nil)  continue;
		
		mutableEntry = [[shipEntry mutableCopy] autorelease];
		
		if (conditions != nil)
		{
			if ([conditions isKindOfClass:[NSArray class]])
			{
				conditions = OOSanitizeLegacyScriptConditions(conditions, [NSString stringWithFormat:@"shipdata.plist entry \"%@\"", shipKey]);
			}
			else
			{
				OOLog(@"shipdata.load.warning", @"----- WARNING: conditions for shipdata.plist entry \"%@\" are not an array, ignoring.", shipKey);
				conditions = nil;
			}
			
			if (conditions != nil)
			{
				[mutableEntry setObject:conditions forKey:@"conditions"];
			}
			else
			{
				[mutableEntry removeObjectForKey:@"conditions"];
			}
		}
		
		if (hasShipyard != nil)
		{
			hasShipyard = OOSanitizeLegacyScriptConditions(hasShipyard, [NSString stringWithFormat:@"shipdata.plist entry \"%@\" hasShipyard conditions", shipKey]);
			
			if (hasShipyard != nil)
			{
				[mutableEntry setObject:hasShipyard forKey:@"hasShipyard"];
			}
			else
			{
				[mutableEntry removeObjectForKey:@"hasShipyard"];
			}
		}
		
		if (shipyardConditions != nil)
		{
			mutableShipyard = [[[shipEntry dictionaryForKey:@"shipyard"] mutableCopy] autorelease];
			
			if ([shipyardConditions isKindOfClass:[NSArray class]])
			{
				shipyardConditions = OOSanitizeLegacyScriptConditions(shipyardConditions, [NSString stringWithFormat:@"shipyard.plist entry \"%@\"", shipKey]);
			}
			else
			{
				OOLog(@"shipdata.load.warning", @"----- WARNING: conditions for shipyard.plist entry \"%@\" are not an array, ignoring.", shipKey);
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
			
			[mutableEntry setObject:mutableShipyard forKey:@"shipyard"];
		}
		
		[ioData setObject:[[mutableEntry copy] autorelease] forKey:shipKey];
	}
	
	return YES;
}


#if PRELOAD
- (BOOL) preloadShipMeshes:(NSMutableDictionary *)ioData
{
	NSEnumerator			*shipKeyEnum = nil;
	NSString				*shipKey = nil;
	NSDictionary			*shipEntry = nil;
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
		
		modelName = [shipEntry stringForKey:@"model"];
		mesh = [OOMesh meshWithName:modelName
				 materialDictionary:nil
				  shadersDictionary:nil
							 smooth:[shipEntry boolForKey:@"smooth"]
					   shaderMacros:nil
				shaderBindingTarget:nil];
		
		[pool release];	// NOTE: mesh is now invalid, but pointer nil check is OK.
		
		if (mesh == nil)
		{
			// FIXME: what if it's a subentity? Need to rearrange things.
			OOLog(@"shipData.load.error", @"***** ERROR: model \"%@\" could not be loaded for ship \"%@\", removing.", modelName, shipKey);
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
	*/
	
	rolesAndWeights = OOParseRolesFromString(roles);
	for (roleEnum = [rolesAndWeights keyEnumerator]; (role = [roleEnum nextObject]); )
	{
		probSet = [probabilitySets objectForKey:role];
		if (probSet == nil)
		{
			probSet = [OOMutableProbabilitySet probabilitySet];
			[probabilitySets setObject:probSet forKey:role];
		}
		
		[probSet setWeight:[rolesAndWeights floatForKey:role] forObject:shipKey];
	}
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
