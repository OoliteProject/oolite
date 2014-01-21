/*

OOCache.m
By Jens Ayton

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

/*	IMPLEMENTATION NOTES
	A cache needs to be able to implement three types of operation
	efficiently:
	  * Retrieving: looking up an element by key.
	  * Inserting: setting the element associated with a key.
	  * Deleting: removing a single element.
	  * Pruning: removing one or more least-recently used elements.
	
	An NSMutableDictionary performs the first three operations efficiently but
	has no support for pruning - specifically no support for finding the
	least-recently-accessed element. Using standard Foundation containers, i
	would be necessary to use several dictionaries and arrays, which would be
	quite inefficient since small NSArrays aren’t very good at head insertion
	or deletion. Alternatively, a standard dictionary whose value objects
	maintain an age-sorted list could be used.
	
	I chose instead to implement a custom scheme from scratch. It uses two
	parallel data structures: a doubly-linked list sorted by age, and a splay
	tree to implement insertion/deletion. The implementation is largely
	procedural C. Deserialization, pruning and modification tracking is done
	in the ObjC class; everything else is done in C functions.
	
	A SPLAY TREE is a type of semi-balanced binary search tree with certain
	useful properties:
	  * Simplicity. All look-up and restructuring operations are based on a
		single operation, splaying, which brings the node with the desired key
		(or the node whose key is "left" of the desired key, if there is no
		exact match) to the root, while maintaining the binary search tree
		invariant. Splaying itself is sufficient for look-up; insertion and
		deletion work by splaying and then manipulating at the root.
	  * Self-optimization. Because each look-up brings the sought element to
		the root, often-used elements tend to stay near the top. (Oolite often
		performs sequences of identical look-ups, for instance when creating
		an asteroid field, or the racing ring set-up which uses lots of
		identical ring segments; during combat, missiles, canisters and hull
		plates will be commonly used.) Also, this means that for a retrieve-
		attempt/insert sequence, the retrieve attempt will optimize the tree
		for the insertion.
	  * Efficiency. In addition to the self-optimization, splay trees have a
		small code size and no storage overhead for flags.
		The amortized worst-case cost of splaying (cost averaged over a
		worst-case sequence of operations) is O(log n); a single worst-case
		splay is O(n), but that worst-case also improves the balance of the
		tree, so you can't have two worst cases in a row. Insertion and
		deletion are also O(log n), consisting of a splay plus an O(1)
		operation.
	References for splay trees:
	  * http://www.cs.cmu.edu/~sleator/papers/self-adjusting.pdf
		Original research paper.
	  *	http://www.ibr.cs.tu-bs.de/courses/ss98/audii/applets/BST/SplayTree-Example.html
		Java applet demonstrating splaying.
	  * http://www.link.cs.cmu.edu/link/ftp-site/splaying/top-down-splay.c
		Sample implementation by one of the inventors. The TreeSplay(),
		TreeInsert() and CacheRemove() functions are based on this.
	
	The AGE LIST is a doubly-linked list, ordered from oldest to youngest.
	Whenever an element is retrieved or inserted, it is promoted to the
	youngest end of the age list. Pruning proceeds from the oldest end of the
	age list.
	
	if (autoPrune)
	{
		PRUNING is batched, handling 20% of the cache at once. This is primarily
		because deletion somewhat pessimizes the tree (see "Self-optimization"
		below). It also provides a bit of code coherency. To reduce pruning
		batches while in flight, pruning is also performed before serialization
		(which in turn is done, if the cache has changed, whenever the user
		docks). This has the effect that the number of items in the cache on disk
		never exceeds 80% of the prune threshold. This is probably not actually
		poinful, since pruning should be a very small portion of the per-frame run
		time in any case. Premature optimization and all that jazz.
		Pruning performs at most 0.2n deletions, and is thus O(n log n).
	}
	else
	{
		PRUNING is performed manually by calling -prune.
	}
	
	If the macro OOCACHE_PERFORM_INTEGRITY_CHECKS is set to a non-zero value,
	the integrity of the tree and the age list will be checked before and
	after each high-level operation. This is an inherently O(n) operation.
*/


#import "OOCache.h"
#import "OOStringParsing.h"


#ifndef OOCACHE_PERFORM_INTEGRITY_CHECKS
#define OOCACHE_PERFORM_INTEGRITY_CHECKS	1
#endif


// Protocol used internally to squash idiotic warnings in gnu-gcc.
@protocol OOCacheComparable <NSObject, NSCopying>
- (NSComparisonResult) compare:(id<OOCacheComparable>)other;
- (id) copy;
@end


typedef struct OOCacheImpl OOCacheImpl;
typedef struct OOCacheNode OOCacheNode;


enum { kCountUnknown = -1U };


static NSString * const kSerializedEntryKeyKey		= @"key";
static NSString * const kSerializedEntryKeyValue	= @"value";


static OOCacheImpl *CacheAllocate(void);
static void CacheFree(OOCacheImpl *cache);

static BOOL CacheInsert(OOCacheImpl *cache, id key, id value);
static BOOL CacheRemove(OOCacheImpl *cache, id key);
static BOOL CacheRemoveOldest(OOCacheImpl *cache, NSString *logKey);
static id CacheRetrieve(OOCacheImpl *cache, id key);
static unsigned CacheGetCount(OOCacheImpl *cache);
static NSArray *CacheArrayOfContentsByAge(OOCacheImpl *cache);
static NSArray *CacheArrayOfNodesByAge(OOCacheImpl *cache);
static NSString *CacheGetName(OOCacheImpl *cache);
static void CacheSetName(OOCacheImpl *cache, NSString *name);

#if OOCACHE_PERFORM_INTEGRITY_CHECKS
static NSString * const kOOLogCacheIntegrityCheck	= @"dataCache.integrityCheck";
static void CacheCheckIntegrity(OOCacheImpl *cache, NSString *context);

#define CHECK_INTEGRITY(context)	CacheCheckIntegrity(cache, (context))
#else
#define CHECK_INTEGRITY(context)	do {} while (0)
#endif


@interface OOCache (Private)

- (void)loadFromArray:(NSArray *)inArray;

@end


@implementation OOCache


- (void)dealloc
{
	CHECK_INTEGRITY(@"dealloc");
	CacheFree(cache);
	
	[super dealloc];
}


- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p>{\"%@\", %u elements, prune threshold=%u, auto-prune=%s dirty=%s}", [self class], self, [self name], CacheGetCount(cache), pruneThreshold, autoPrune ? "yes" : "no", dirty ? "yes" : "no"];
}


- (id)init
{
	return [self initWithPList:nil];
}


- (id)initWithPList:(id)pList
{
	BOOL					OK = YES;
	
	self = [super init];
	OK = self != nil;
	
	if (OK)
	{
		cache = CacheAllocate();
		if (cache == NULL) OK = NO;
	}
	
	if (pList != nil)
	{
		if (OK) OK = [pList isKindOfClass:[NSArray class]];
		if (OK) [self loadFromArray:pList];
	}
	if (OK)
	{
		pruneThreshold = kOOCacheDefaultPruneThreshold;
		autoPrune = YES;
	}
	
	if (!OK)
	{
		[self release];
		self = nil;
	}
	
	return self;
}


- (id)pListRepresentation
{
	return CacheArrayOfNodesByAge(cache);
	
	return nil;
}


- (id)objectForKey:(id)key
{
	id						result = nil;
	
	CHECK_INTEGRITY(@"objectForKey: before");
	
	result = CacheRetrieve(cache, key);
	// Note: while reordering the age list technically makes the cache dirty, it's not worth rewriting it just for that, so we don't flag it.
	
	CHECK_INTEGRITY(@"objectForKey: after");
	
	return [[result retain] autorelease];
}


- (void)setObject:inObject forKey:(id)key
{
	CHECK_INTEGRITY(@"setObject:forKey: before");
	
	if (CacheInsert(cache, key, inObject))
	{
		dirty = YES;
		if (autoPrune)  [self prune];
	}
	
	CHECK_INTEGRITY(@"setObject:forKey: after");
}


- (void)removeObjectForKey:(id)key
{
	CHECK_INTEGRITY(@"removeObjectForKey: before");
	
	if (CacheRemove(cache, key)) dirty = YES;
	
	CHECK_INTEGRITY(@"removeObjectForKey: after");
}


- (void)setPruneThreshold:(unsigned)threshold
{
	threshold = MAX(threshold, (unsigned)kOOCacheMinimumPruneThreshold);
	if (threshold != pruneThreshold)
	{
		pruneThreshold = threshold;
		if (autoPrune)  [self prune];
	}
}


- (unsigned)pruneThreshold
{
	return pruneThreshold;
}


- (void)setAutoPrune:(BOOL)flag
{
	BOOL prune = (flag != NO);
	if (prune != autoPrune)
	{
		autoPrune = prune;
		[self prune];
	}
}


- (BOOL)autoPrune
{
	return autoPrune;
}


- (void)prune
{
	unsigned				pruneCount;
	unsigned				desiredCount;
	unsigned				count;
	
	// Order of operations is to ensure rounding down.
	if (autoPrune)  desiredCount = (pruneThreshold * 4) / 5;
	else  desiredCount = pruneThreshold;
	
	if (pruneThreshold == kOOCacheNoPrune || (count = CacheGetCount(cache)) <= pruneThreshold)  return;
	
	pruneCount = count - desiredCount;
	
	NSString *logKey = [NSString stringWithFormat:@"dataCache.prune.%@", CacheGetName(cache)];
	OOLog(logKey, @"Pruning cache \"%@\" - removing %u entries", CacheGetName(cache), pruneCount);
	OOLogIndentIf(logKey);
	
	while (pruneCount--)  CacheRemoveOldest(cache, logKey);
	
	OOLogOutdentIf(logKey);
}


- (BOOL)dirty
{
	return dirty;
}


- (void)markClean
{
	dirty = NO;
}


- (NSString *)name
{
	return CacheGetName(cache);
}


- (void)setName:(NSString *)name
{
	CacheSetName(cache, name);
}


- (NSArray *) objectsByAge
{
	return CacheArrayOfContentsByAge(cache);
}

@end


@implementation OOCache (Private)

- (void)loadFromArray:(NSArray *)array
{
	NSEnumerator			*entryEnum = nil;
	NSDictionary			*entry = nil;
	NSString				*key = nil;
	id						value = nil;
	
	if (array == nil) return;
	
	for (entryEnum = [array objectEnumerator]; (entry = [entryEnum nextObject]); )
	{
		if ([entry isKindOfClass:[NSDictionary class]])
		{
			key = [entry objectForKey:kSerializedEntryKeyKey];
			value = [entry objectForKey:kSerializedEntryKeyValue];
			if ([key isKindOfClass:[NSString class]] && value != nil)
			{
				[self setObject:value forKey:key];
			}
		}
	}
}

@end


/***** Most of the implementation. In C. Because I'm inconsistent and slightly m. *****/

struct OOCacheImpl
{
	// Splay tree root
	OOCacheNode				*root;
	
	// Ends of age list
	OOCacheNode				*oldest, *youngest;
	
	unsigned				count;
	NSString				*name;
};


struct OOCacheNode
{
	// Payload
	id<OOCacheComparable>	key;
	id						value;
	
	// Splay tree
	OOCacheNode				*leftChild, *rightChild;
	
	// Age list
	OOCacheNode				*younger, *older;
};

static OOCacheNode *CacheNodeAllocate(id<OOCacheComparable> key, id value);
static void CacheNodeFree(OOCacheImpl *cache, OOCacheNode *node);
static id CacheNodeGetValue(OOCacheNode *node);
static void CacheNodeSetValue(OOCacheNode *node, id value);

#if OOCACHE_PERFORM_INTEGRITY_CHECKS
static NSString *CacheNodeGetDescription(OOCacheNode *node);
#endif

static OOCacheNode *TreeSplay(OOCacheNode **root, id<OOCacheComparable> key);
static OOCacheNode *TreeInsert(OOCacheImpl *cache, id<OOCacheComparable> key, id value);

#if OOCACHE_PERFORM_INTEGRITY_CHECKS
static unsigned TreeCountNodes(OOCacheNode *node);
static OOCacheNode *TreeCheckIntegrity(OOCacheImpl *cache, OOCacheNode *node, OOCacheNode *expectedParent, NSString *context);
#endif

static void AgeListMakeYoungest(OOCacheImpl *cache, OOCacheNode *node);
static void AgeListRemove(OOCacheImpl *cache, OOCacheNode *node);

#if OOCACHE_PERFORM_INTEGRITY_CHECKS
static void AgeListCheckIntegrity(OOCacheImpl *cache, NSString *context);
#endif


/***** CacheImpl functions *****/

static OOCacheImpl *CacheAllocate(void)
{
	return calloc(sizeof (OOCacheImpl), 1);
}


static void CacheFree(OOCacheImpl *cache)
{
	if (cache == NULL) return;
	
	CacheNodeFree(cache, cache->root);
	[cache->name autorelease];
	free(cache);
}


static BOOL CacheInsert(OOCacheImpl *cache, id key, id value)
{
	OOCacheNode				*node = NULL;
	
	if (cache == NULL || key == nil || value == nil) return NO;
	
	node = TreeInsert(cache, key, value);
	if (node != NULL)
	{
		AgeListMakeYoungest(cache, node);
		return YES;
	}
	else  return NO;
}


static BOOL CacheRemove(OOCacheImpl *cache, id key)
{
	OOCacheNode				*node = NULL, *newRoot = NULL;
	
	node = TreeSplay(&cache->root, key);
	if (node != NULL)
	{
		if (node->leftChild == NULL)  newRoot = node->rightChild;
		else
		{
			newRoot = node->leftChild;
			TreeSplay(&newRoot, key);
			newRoot->rightChild = node->rightChild;
		}
		node->leftChild = NULL;
		node->rightChild = NULL;
		
		cache->root = newRoot;
		--cache->count;
		
		AgeListRemove(cache, node);
		CacheNodeFree(cache, node);
		
		return YES;
	}
	else  return NO;
}


static BOOL CacheRemoveOldest(OOCacheImpl *cache, NSString *logKey)
{
	// This could be more efficient, but does it need to be?
	if (cache == NULL || cache->oldest == NULL) return NO;
	
	OOLog(logKey, @"Pruning cache \"%@\": removing %@", cache->name, cache->oldest->key);
	return CacheRemove(cache, cache->oldest->key);
}


static id CacheRetrieve(OOCacheImpl *cache, id key)
{
	OOCacheNode			*node = NULL;
	id					result = nil;
	
	if (cache == NULL || key == NULL) return nil;
	
	node = TreeSplay(&cache->root, key);
	if (node != NULL)
	{
		result = CacheNodeGetValue(node);
		AgeListMakeYoungest(cache, node);
	}
	return result;
}


static NSArray *CacheArrayOfContentsByAge(OOCacheImpl *cache)
{
	OOCacheNode			*node = NULL;
	NSMutableArray		*result = nil;
	
	if (cache == NULL || cache->count == 0) return nil;
	
	result = [NSMutableArray arrayWithCapacity:cache->count];
	
	for (node = cache->youngest; node != NULL; node = node->older)
	{
		[result addObject:node->value];
	}
	return result;
}


static NSArray *CacheArrayOfNodesByAge(OOCacheImpl *cache)
{
	OOCacheNode			*node = NULL;
	NSMutableArray		*result = nil;
	
	if (cache == NULL || cache->count == 0) return nil;
	
	result = [NSMutableArray arrayWithCapacity:cache->count];
	
	for (node = cache->oldest; node != NULL; node = node->younger)
	{
		[result addObject:[NSDictionary dictionaryWithObjectsAndKeys:node->key, kSerializedEntryKeyKey, node->value, kSerializedEntryKeyValue, nil]];
	}
	return result;
}


static NSString *CacheGetName(OOCacheImpl *cache)
{
	return cache->name;
}


static void CacheSetName(OOCacheImpl *cache, NSString *name)
{
	[cache->name autorelease];
	cache->name = [name copy];
}


static unsigned CacheGetCount(OOCacheImpl *cache)
{
	return cache->count;
}

#if OOCACHE_PERFORM_INTEGRITY_CHECKS

static void CacheCheckIntegrity(OOCacheImpl *cache, NSString *context)
{
	unsigned			trueCount;
	
	cache->root = TreeCheckIntegrity(cache, cache->root, NULL, context);
	
	trueCount = TreeCountNodes(cache->root);
	if (kCountUnknown == cache->count)  cache->count = trueCount;
	else if (cache->count != trueCount)
	{
		OOLog(kOOLogCacheIntegrityCheck, @"Integrity check (%@ for \"%@\"): count is %u, but should be %u.", context, cache->name, cache->count, trueCount);
		cache->count = trueCount;
	}
	
	AgeListCheckIntegrity(cache, context);
}

#endif	// OOCACHE_PERFORM_INTEGRITY_CHECKS


/***** CacheNode functions *****/

// CacheNodeAllocate(): create a cache node for a key, value pair, without inserting it in the structures.
static OOCacheNode *CacheNodeAllocate(id<OOCacheComparable> key, id value)
{
	OOCacheNode			*result = NULL;
	
	if (key == nil || value == nil) return NULL;
	
	result = calloc(sizeof *result, 1);
	if (result != NULL)
	{
		result->key = [key copy];
		result->value = [value retain];
	}
	
	return result;
}


// CacheNodeFree(): recursively delete a cache node and its children in the splay tree. To delete an individual node, first clear its child pointers.
static void CacheNodeFree(OOCacheImpl *cache, OOCacheNode *node)
{
	id key, value;
	
	if (node == NULL) return;
	
	AgeListRemove(cache, node);
	
	key = node->key;
	node->key = nil;
	[key release];
	
	value = node->value;
	node->value = nil;
	[value release];
	
	CacheNodeFree(cache, node->leftChild);
	CacheNodeFree(cache, node->rightChild);
	
	free(node);
}


// CacheNodeGetValue(): retrieve the value of a cache node
static id CacheNodeGetValue(OOCacheNode *node)
{
	if (node == NULL) return nil;
	
	return node->value;
}


// CacheNodeSetValue(): change the value of a cache node (as when setObject:forKey: is called for an existing key).
static void CacheNodeSetValue(OOCacheNode *node, id value)
{
	if (node == NULL) return;

	id tmp = node->value;
	node->value = [value retain];
	[tmp release];
}


#if OOCACHE_PERFORM_INTEGRITY_CHECKS
// CacheNodeGetDescription(): get a description of a cache node for debugging purposes.
static NSString *CacheNodeGetDescription(OOCacheNode *node)
{
	if (node == NULL) return @"0[null]";
	
	return [NSString stringWithFormat:@"%p[\"%@\"]", node, node->key];
}
#endif	// OOCACHE_PERFORM_INTEGRITY_CHECKS


/***** Tree functions *****/

/*	TreeSplay()
	This is the fundamental operation of a splay tree. It searches for a node
	with a given key, and rebalances the tree so that the found node becomes
	the root. If no match is found, the node moved to the root is the one that
	would have been found before the target, and will thus be a neighbour of
	the target if the key is subsequently inserted.
*/
static OOCacheNode *TreeSplay(OOCacheNode **root, id<OOCacheComparable> key)
{
	NSComparisonResult		order;
	OOCacheNode				N = { .leftChild = NULL, .rightChild = NULL };
	OOCacheNode				*node = NULL, *temp = NULL, *l = &N, *r = &N;
	BOOL					exact = NO;
	
	if (root == NULL || *root == NULL || key == nil) return NULL;
	
	node = *root;
	
	for (;;)
	{
#ifndef NDEBUG
		if (node == NULL)
		{
			OOLog(@"node.error",@"node is NULL");
		}
		else if (node->key == NULL)
		{
			OOLog(@"node.error",@"node->key is NULL");
		}
#endif
		order = [key compare:node->key];
		if (order == NSOrderedAscending)
		{
			// Closest match is in left subtree
			if (node->leftChild == NULL) break;
			if ([key compare:node->leftChild->key] == NSOrderedAscending)
			{
				// Rotate right
				temp = node->leftChild;
				node->leftChild = temp->rightChild;
				temp->rightChild = node;
				node = temp;
				if (node->leftChild == NULL) break;
			}
			// Link right
			r->leftChild = node;
			r = node;
			node = node->leftChild;
		}
		else if (order == NSOrderedDescending)
		{
			// Closest match is in right subtree
			if (node->rightChild == NULL) break;
			if ([key compare:node->rightChild->key] == NSOrderedDescending)
			{
				// Rotate left
				temp = node->rightChild;
				node->rightChild = temp->leftChild;
				temp->leftChild = node;
				node = temp;
				if (node->rightChild == NULL) break;
			}
			// Link left
			l->rightChild = node;
			l = node;
			node = node->rightChild;
		}
		else
		{
			// Found exact match
			exact = YES;
			break;
		}
	}
	
	// Assemble
	l->rightChild = node->leftChild;
	r->leftChild = node->rightChild;
	node->leftChild = N.rightChild;
	node->rightChild = N.leftChild;
	
	*root = node;
	return exact ? node : NULL;
}


static OOCacheNode *TreeInsert(OOCacheImpl *cache, id<OOCacheComparable> key, id value)
{
	OOCacheNode				*closest = NULL,
							*node = NULL;
	NSComparisonResult		order;
	
	if (cache == NULL || key == nil || value == nil) return NULL;
	
	if (cache->root == NULL)
	{
		node = CacheNodeAllocate(key, value);
		cache->root = node;
		cache->count = 1;
	}
	else
	{
		node = TreeSplay(&cache->root, key);
		if (node != NULL)
		{
			// Exact match: key already exists, reuse its node
			CacheNodeSetValue(node, value);
		}
		else
		{
			closest = cache->root;
			node = CacheNodeAllocate(key, value);
			if (EXPECT_NOT(node == NULL))  return NULL;
			
			order = [key compare:closest->key];
			
			if (order == NSOrderedAscending)
			{
				// Insert to left
				node->leftChild = closest->leftChild;
				node->rightChild = closest;
				closest->leftChild = NULL;
				cache->root = node;
				++cache->count;
			}
			else if (order == NSOrderedDescending)
			{
				// Insert to right
				node->rightChild = closest->rightChild;
				node->leftChild = closest;
				closest->rightChild = NULL;
				cache->root = node;
				++cache->count;
			}
			else
			{
				// Key already exists, which we should have caught above
				OOLog(@"dataCache.inconsistency", @"%s() internal inconsistency for cache \"%@\", insertion failed.", __PRETTY_FUNCTION__, cache->name);
				CacheNodeFree(cache, node);
				return NULL;
			}
		}
	}
	
	return node;
}


#if OOCACHE_PERFORM_INTEGRITY_CHECKS
static unsigned TreeCountNodes(OOCacheNode *node)
{
	if (node == NULL) return 0;
	return 1 + TreeCountNodes(node->leftChild) + TreeCountNodes(node->rightChild);
}


// TreeCheckIntegrity(): verify the links and contents of a (sub-)tree. If successful, returns the root of the subtree (which could theoretically be changed), otherwise returns NULL.
static OOCacheNode *TreeCheckIntegrity(OOCacheImpl *cache, OOCacheNode *node, OOCacheNode *expectedParent, NSString *context)
{
	NSComparisonResult		order;
	BOOL					OK = YES;
	
	if (node == NULL) return NULL;
	
	if (OK && node->key == nil)
	{
		OOLog(kOOLogCacheIntegrityCheck, @"Integrity check (%@ for \"%@\"): node \"%@\" has nil key; deleting subtree.", context, cache->name, CacheNodeGetDescription(node));
		OK = NO;
	}
	
	if (OK && node->value == nil)
	{
		OOLog(kOOLogCacheIntegrityCheck, @"Integrity check (%@ for \"%@\"): node \"%@\" has nil value, deleting.", context, cache->name, CacheNodeGetDescription(node));
		OK = NO;
	}	
	if (OK && node->leftChild != NULL)
	{
		order = [node->key compare:node->leftChild->key];
		if (order != NSOrderedDescending)
		{
			OOLog(kOOLogCacheIntegrityCheck, @"Integrity check (%@ for \"%@\"): node %@'s left child %@ is not correctly ordered. Deleting subtree.", context, cache->name, CacheNodeGetDescription(node), CacheNodeGetDescription(node->leftChild));
			CacheNodeFree(cache, node->leftChild);
			node->leftChild = NULL;
			cache->count = kCountUnknown;
		}
		else
		{
			node->leftChild = TreeCheckIntegrity(cache, node->leftChild, node, context);
		}
	}
	if (node->rightChild != NULL)
	{
		order = [node->key compare:node->rightChild->key];
		if (order != NSOrderedAscending)
		{
			OOLog(kOOLogCacheIntegrityCheck, @"Integrity check (%@ for \"%@\"): node \"%@\"'s right child \"%@\" is not correctly ordered. Deleting subtree.", context, cache->name, CacheNodeGetDescription(node), CacheNodeGetDescription(node->rightChild));
			CacheNodeFree(cache, node->rightChild);
			node->rightChild = NULL;
			cache->count = kCountUnknown;
		}
		else
		{
			node->rightChild = TreeCheckIntegrity(cache, node->rightChild, node, context);
		}
	}
	
	if (OK)  return node;
	else
	{
		cache->count = kCountUnknown;
		CacheNodeFree(cache, node);
		return NULL;
	}
}
#endif	// OOCACHE_PERFORM_INTEGRITY_CHECKS


/***** Age list functions *****/

// AgeListMakeYoungest(): place a given cache node at the youngest end of the age list.
static void AgeListMakeYoungest(OOCacheImpl *cache, OOCacheNode *node)
{
	if (cache == NULL || node == NULL) return;
	
	AgeListRemove(cache, node);
	node->older = cache->youngest;
	if (NULL != cache->youngest) cache->youngest->younger = node;
	cache->youngest = node;
	if (cache->oldest == NULL) cache->oldest = node;
}


// AgeListRemove(): remove a cache node from the age-sorted tree. Does not affect its position in the splay tree.
static void AgeListRemove(OOCacheImpl *cache, OOCacheNode *node)
{
	OOCacheNode			*younger = NULL;
	OOCacheNode			*older = NULL;
	
	if (node == NULL) return;
	
	younger = node->younger;
	older = node->older;
	
	if (cache->youngest == node) cache->youngest = older;
	if (cache->oldest == node) cache->oldest = younger;
	
	node->younger = NULL;
	node->older = NULL;
	
	if (younger != NULL) younger->older = older;
	if (older != NULL) older->younger = younger;
}


#if OOCACHE_PERFORM_INTEGRITY_CHECKS

static void AgeListCheckIntegrity(OOCacheImpl *cache, NSString *context)
{
	OOCacheNode			*node = NULL, *next = NULL;
	unsigned			seenCount = 0;
	
	if (cache == NULL || context == NULL) return;
	
	node = cache->youngest;
	
	if (node)  for (;;)
	{
		next = node->older;
		++seenCount;
		if (next == NULL) break;
		
		if (next->younger != node)
		{
			OOLog(kOOLogCacheIntegrityCheck, @"Integrity check (%@ for \"%@\"): node \"%@\" has invalid older link (should be \"%@\", is \"%@\"); repairing.", context, cache->name, CacheNodeGetDescription(next), CacheNodeGetDescription(node), CacheNodeGetDescription(next->older));
			next->older = node;
		}
		node = next;
	}
	
	if (seenCount != cache->count)
	{
		// This is especially bad since this function is called just after verifying that the count field reflects the number of objects in the tree.
		OOLog(kOOLogCacheIntegrityCheck, @"Integrity check (%@ for \"%@\"): expected %u nodes, found %u. Cannot repair; clearing cache.", context, cache->name, cache->count, seenCount);

		/* Start of temporary extra logging */
		node = cache->youngest;
	
		if (node)  
		{
			for (;;)
			{
				next = node->older;
				++seenCount;
				if (next == NULL) break;
				
				if (node->key != NULL)
				{
					OOLog(kOOLogCacheIntegrityCheck,@"Key is: %@",node->key);
				}
				else
				{
					OOLog(kOOLogCacheIntegrityCheck,@"Key is: NULL");
				}

				if (node->value != NULL)
				{
					OOLog(kOOLogCacheIntegrityCheck,@"Value is: %@",node->value);
				}
				else
				{
					OOLog(kOOLogCacheIntegrityCheck,@"Value is: NULL");
				}
				
				node = next;
			}
		}
		/* End of temporary extra logging */

		cache->count = 0;
		CacheNodeFree(cache, cache->root);
		cache->root = NULL;
		cache->youngest = NULL;
		cache->oldest = NULL;
		return;
	}
	
	if (node != cache->oldest)
	{
		OOLog(kOOLogCacheIntegrityCheck, @"Integrity check (%@ for \"%@\"): oldest pointer in cache is wrong (should be \"%@\", is \"%@\"); repairing.", context, cache->name, CacheNodeGetDescription(node), CacheNodeGetDescription(cache->oldest));
		cache->oldest = node;
	}
}

#endif	// OOCACHE_PERFORM_INTEGRITY_CHECKS


#if DEBUG_GRAPHVIZ

/*	NOTE: enabling AGE_LIST can result in graph rendering times of many hours,
	because determining paths for non-constraint arcs is NP-hard. In particular,
	I gave up on rendering a dump of a fairly minimal cache manager after
	three and a half hours. Individual caches were fine.
*/
#define AGE_LIST 0

@implementation OOCache (DebugGraphViz)

- (void) appendNodesFromSubTree:(OOCacheNode *)subTree toString:(NSMutableString *)ioString
{
	[ioString appendFormat:@"\tn%p [label=\"<f0> | <f1> %@ | <f2>\"];\n", subTree, EscapedGraphVizString([subTree->key description])];
	
	if (subTree->leftChild != NULL)
	{
		[self appendNodesFromSubTree:subTree->leftChild toString:ioString];
		[ioString appendFormat:@"\tn%p:f0 -> n%p:f1;\n", subTree, subTree->leftChild];
	}
	if (subTree->rightChild != NULL)
	{
		[self appendNodesFromSubTree:subTree->rightChild toString:ioString];
		[ioString appendFormat:@"\tn%p:f2 -> n%p:f1;\n", subTree, subTree->rightChild];
	}
}


- (NSString *) generateGraphVizBodyWithRootNamed:(NSString *)rootName
{
	NSMutableString			*result = nil;
	
	result = [NSMutableString string];
	
	// Root node representing cache
	[result appendFormat:@"\t%@ [label=\"Cache \\\"%@\\\"\" shape=box];\n"
		"\tnode [shape=record];\n\t\n", rootName, EscapedGraphVizString([self name])];
	
	if (cache == NULL)  return result;
	
	// Cache
	[self appendNodesFromSubTree:cache->root toString:result];
	
	// Arc from cache object to root node
	[result appendString:@"\tedge [color=black constraint=true];\n"];
	[result appendFormat:@"\t%@ -> n%p:f1;\n", rootName, cache->root];
	
#if AGE_LIST
	OOCacheNode				*node = NULL;
	// Arcs representing age list
	[result appendString:@"\t\n\t// Age-sorted list in blue\n\tedge [color=blue constraint=false];\n"];
	node = cache->oldest;
	while (node->younger != NULL)
	{
		[result appendFormat:@"\tn%p:f2 -> n%p:f0;\n", node, node->younger];
		node = node->younger;
	}
#endif
	
	return result;
}


- (NSString *) generateGraphViz
{
	NSMutableString			*result = nil;
	
	result = [NSMutableString string];
	
	// Header
	[result appendFormat:
		@"// OOCache dump\n\n"
		"digraph cache\n"
		"{\n"
		"\tgraph [charset=\"UTF-8\", label=\"OOCache \"%@\" debug dump\", labelloc=t, labeljust=l];\n\t\n", [self name]];
	
	[result appendString:[self generateGraphVizBodyWithRootNamed:@"cache"]];
	
	[result appendString:@"}\n"];
	
	return result;
}


- (void) writeGraphVizToURL:(NSURL *)url
{
	NSString			*graphViz = nil;
	NSData				*data = nil;
	
	graphViz = [self generateGraphViz];
	data = [graphViz dataUsingEncoding:NSUTF8StringEncoding];
	
	if (data != nil)
	{
		[data writeToURL:url atomically:YES];
	}
}


- (void) writeGraphVizToPath:(NSString *)path
{
	[self writeGraphVizToURL:[NSURL fileURLWithPath:path]];
}

@end
#endif

