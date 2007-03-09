/*

OOCache.m
By Jens Ayton

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

#import "OOCache.h"
#import "OOCacheManager.h"


#define PERFORM_INTEGRITY_CHECKS			1


static NSString * const kOOLogCacheIntegrityCheck = @"dataCache.integrityCheck";


typedef struct OOCacheImpl OOCacheImpl;
typedef struct OOCacheNode OOCacheNode;


enum { kCountUnknown = -1UL };

static NSString * const kSerializedEntryKeyKey		= @"key";
static NSString * const kSerializedEntryKeyValue	= @"value";


static OOCacheImpl *CacheAllocate(void);
static void CacheFree(OOCacheImpl *cache);

static BOOL CacheInsert(OOCacheImpl *cache, NSString *key, id value);
static BOOL CacheRemove(OOCacheImpl *cache, NSString *key);
static BOOL CacheRemoveOldest(OOCacheImpl *cache);
static id CacheRetrieve(OOCacheImpl *cache, NSString *key);
static unsigned CacheGetCount(OOCacheImpl *cache);
static NSArray *CacheArrayOfNodesByAge(OOCacheImpl *cache);

static void CacheCheckIntegrity(OOCacheImpl *cache, NSString *context);

#if PERFORM_INTEGRITY_CHECKS
	#define CHECK_INTEGRITY(context)	CacheCheckIntegrity(cache, (context))
#else
	#define CHECK_INTEGRITY(context)	do {} while (0)
#endif


@interface OOCache (Private)

- (void)loadFromArray:(NSArray *)inArray;
- (void)prune;

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
	return [NSString stringWithFormat:@"<%@ %p>{%u elements, prune threshold=%u, dirty=%s}", [self class], self, CacheGetCount(cache), pruneThreshold, dirty ? "yes" : "no"];
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
	if (OK) pruneThreshold = kOOCacheDefaultPruneThreshold;
	
	if (!OK)
	{
		[self release];
		self = nil;
	}
	
	return self;
}


- (id)pListRepresentation
{
	[self prune];
	return CacheArrayOfNodesByAge(cache);
	
	return nil;
}


- (id)objectForKey:(NSString *)key
{
	id						result = nil;
	
	CHECK_INTEGRITY(@"objectForKey: before");
	
	result = CacheRetrieve(cache, key);
	// Note: while reordering the age list technically makes the cache dirty, it's not worth rewriting it just for that, so we don't flag it.
	
	CHECK_INTEGRITY(@"objectForKey: after");
	
	return [[result retain] autorelease];
}


- (void)setObject:inObject forKey:(NSString *)key
{
	CHECK_INTEGRITY(@"setObject:forKey: before");
	
	if (CacheInsert(cache, key, inObject))
	{
		dirty = YES;
		if (pruneThreshold < CacheGetCount(cache)) [self prune];
	}
	
	CHECK_INTEGRITY(@"setObject:forKey: after");
}


- (void)removeObjectForKey:(NSString *)key
{
	CHECK_INTEGRITY(@"removeObjectForKey: before");
	
	if (CacheRemove(cache, key)) dirty = YES;
	
	CHECK_INTEGRITY(@"removeObjectForKey: after");
}


- (void)setPruneThreshold:(unsigned)threshold
{
	pruneThreshold = threshold;
}


- (unsigned)pruneThreshold
{
	return pruneThreshold;
}


- (BOOL)dirty
{
	return dirty;
}


- (void)markClean
{
	dirty = NO;
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


- (void)prune
{
	unsigned				pruneCount;
	unsigned				desiredCount;
	
	// Order of operations is to ensure rounding down.
	desiredCount = (pruneThreshold * 4) / 5;
	if (CacheGetCount(cache) < desiredCount) return;
	
	pruneCount = pruneThreshold - desiredCount;
	while (pruneCount--) CacheRemoveOldest(cache);
}

@end


/***** Most of the implementation. In C. Because I'm inconsistent and slightly mad. *****/

struct OOCacheImpl
{
	// Splay tree root
	OOCacheNode				*root;
	
	// Ends of age list
	OOCacheNode				*oldest, *youngest;
	
	unsigned				count;
};


struct OOCacheNode
{
	// Payload
	NSString				*key;
	id						value;
	
	// Splay tree
	OOCacheNode				*leftChild, *rightChild;
	
	// Age list
	OOCacheNode				*younger, *older;
};

static OOCacheNode *CacheNodeAllocate(id key, id value);
static void CacheNodeFree(OOCacheImpl *cache, OOCacheNode *node);
static id CacheNodeGetValue(OOCacheNode *node);
static void CacheNodeSetValue(OOCacheNode *node, id value);

static OOCacheNode *TreeSplay(OOCacheNode **root, NSString *key);
static OOCacheNode *TreeInsert(OOCacheImpl *cache, NSString *key, id value);
static unsigned TreeCountNodes(OOCacheNode *node);
static OOCacheNode *TreeCheckIntegrity(OOCacheImpl *cache, OOCacheNode *node, OOCacheNode *expectedParent, NSString *context);

static void AgeListMakeYoungest(OOCacheImpl *cache, OOCacheNode *node);
static void AgeListRemove(OOCacheImpl *cache, OOCacheNode *node);
static void AgeListCheckIntegrity(OOCacheImpl *cache, NSString *context);


/***** CacheImpl functions *****/

static OOCacheImpl *CacheAllocate(void)
{
	return calloc(sizeof (OOCacheImpl), 1);
}


static void CacheFree(OOCacheImpl *cache)
{
	if (cache == NULL) return;
	
	CacheNodeFree(cache, cache->root);
	free(cache);
}


static BOOL CacheInsert(OOCacheImpl *cache, NSString *key, id value)
{
	OOCacheNode				*node = NULL;
	
	if (cache == NULL || key == nil || value == nil) return NO;
	
	node = TreeInsert(cache, key, value);
	if (node != NULL)
	{
		AgeListMakeYoungest(cache, node);
		++cache->count;
		return YES;
	}
	else  return NO;
}


static BOOL CacheRemove(OOCacheImpl *cache, NSString *key)
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
		
		AgeListRemove(cache, node);
		CacheNodeFree(cache, node);
		
		cache->root = newRoot;
		--cache->count;
		return YES;
	}
	else  return NO;
}


static BOOL CacheRemoveOldest(OOCacheImpl *cache)
{
	// This could be more efficient, but does it need to be?
	if (cache == NULL || cache->oldest == NULL) return NO;
	
	OOLog(@"dataCache.prune", @"Pruning cache: removing %@", cache->oldest->key);
	return CacheRemove(cache, cache->oldest->key);
}


static id CacheRetrieve(OOCacheImpl *cache, NSString *key)
{
	OOCacheNode			*node = nil;
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


static NSArray *CacheArrayOfNodesByAge(OOCacheImpl *cache)
{
	unsigned			i, count;
	OOCacheNode			*node = NULL;
	NSMutableArray		*result = nil;
	
	if (cache == NULL || cache->count == 0) return nil;
	
	count = cache->count;
	result = [NSMutableArray arrayWithCapacity:count];
	node = cache->oldest;
	
	for (i = 0; i != count; ++i)
	{
		[result addObject:[NSDictionary dictionaryWithObjectsAndKeys:node->key, kSerializedEntryKeyKey, node->value, kSerializedEntryKeyValue, nil]];
		node = node->younger;
	}
	return result;
}


static unsigned CacheGetCount(OOCacheImpl *cache)
{
	return cache->count;
}


static void CacheCheckIntegrity(OOCacheImpl *cache, NSString *context)
{
	unsigned			trueCount;
	
	cache->root = TreeCheckIntegrity(cache, cache->root, NULL, context);
	
	trueCount = TreeCountNodes(cache->root);
	if (kCountUnknown == cache->count)  cache->count = trueCount;
	else if (cache->count != trueCount)
	{
		OOLog(kOOLogCacheIntegrityCheck, @"Count is %u, but should be %u.", cache->count, trueCount);
		cache->count = trueCount;
	}
	
	AgeListCheckIntegrity(cache, context);
}


/***** CacheNode functions *****/

// CacheNodeAllocate(): create a cache node for a key, value pair, without inserting it in the structures.
static OOCacheNode *CacheNodeAllocate(id key, id value)
{
	OOCacheNode			*result = NULL;
	
	if (key == nil || value == nil) return nil;
	
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
	if (node == NULL) return;
	
	AgeListRemove(cache, node);
	
	[node->key release];
	[node->value release];
	
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
	
	[node->value release];
	node->value = [value retain];
}


// CacheNodeGetDescription(): get a description of a cache node for debugging purposes.
static NSString *CacheNodeGetDescription(OOCacheNode *node)
{
	if (node == NULL) return @"0[null]";
	
	return [NSString stringWithFormat:@"%p[\"%@\"]", node, node->key];
}


/***** Tree functions *****/

/*	TreeSplay()
	This is the fundamental operation of a splay tree. It searches for a node
	with a given key, and rebalances the tree so that the found node becomes
	the root. If no match is found, the node moved to the root is the one that
	would have been found before the target, and will thus be a neighbour of
	the target if the key is subsequently inserted.
*/
static OOCacheNode *TreeSplay(OOCacheNode **root, NSString *key)
{
	NSComparisonResult		order;
	OOCacheNode				N = { leftChild: NULL, rightChild: NULL };
	OOCacheNode				*node = NULL, *temp = NULL, *l = &N, *r = &N;
	BOOL					exact = NO;
	
	if (root == NULL || *root == NULL || key == nil) return NULL;
	
	node = *root;
	
	for (;;)
	{
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


static OOCacheNode *TreeInsert(OOCacheImpl *cache, NSString *key, id value)
{
	OOCacheNode				*closest = NULL,
							*node = NULL;
	NSComparisonResult		order;
	
	if (cache == NULL || key == nil || value == nil) return NULL;
	
	if (cache->root == NULL)
	{
		node = CacheNodeAllocate(key, value);
		cache->root = node;
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
			order = [key compare:closest->key];
			
			if (order == NSOrderedAscending)
			{
				// Insert to left
				node->leftChild = closest->leftChild;
				node->rightChild = closest;
				closest->leftChild = NULL;
				cache->root = node;
			}
			else if (order == NSOrderedDescending)
			{
				// Insert to right
				node->rightChild = closest->rightChild;
				node->leftChild = closest;
				closest->rightChild = NULL;
				cache->root = node;
			}
			else
			{
				// Key already exists, which we should have caught above
				OOLog(@"dataCache.inconsistency", @"CNInsert() internal inconsistency, insertion failed.");
				CacheNodeFree(cache, node);
				return NULL;
			}
		}
	}
	
	return node;
}


static unsigned TreeCountNodes(OOCacheNode *node)
{
	if (node == NULL) return 0;
	return 1 + TreeCountNodes(node->leftChild) + TreeCountNodes(node->rightChild);
}


// TreeCheckIntegrity(): verify the links and contents of a (sub-)tree. If successful, returns the root of the subtree (which could theoretically be changed), otherwise returns NULL. Does not verify age list.
static OOCacheNode *TreeCheckIntegrity(OOCacheImpl *cache, OOCacheNode *node, OOCacheNode *expectedParent, NSString *context)
{
	NSComparisonResult		order;
	BOOL					OK = YES;
	
	if (node == NULL) return NULL;
	
	if (OK && node->key == nil)
	{
		OOLog(kOOLogCacheIntegrityCheck, @"Integrity check (%@): node %@ has nil key; deleting subtree.", context, CacheNodeGetDescription(node));
		OK = NO;
	}
	
	if (OK && node->value == nil)
	{
		OOLog(kOOLogCacheIntegrityCheck, @"Integrity check (%@): node %@ has nil value, deleting.", context, CacheNodeGetDescription(node));
		OK = NO;
	}	
	if (OK && node->leftChild != NULL)
	{
		order = [node->key compare:node->leftChild->key];
		if (order != NSOrderedDescending)
		{
			OOLog(kOOLogCacheIntegrityCheck, @"Integrity check (%@): node %@'s left child %@ is not correctly ordered. Deleting subtree.", context, CacheNodeGetDescription(node), CacheNodeGetDescription(node->leftChild));
			CacheNodeFree(cache, node->leftChild);
			node->leftChild = nil;
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
			OOLog(kOOLogCacheIntegrityCheck, @"Integrity check (%@): node %@'s right child %@ is not correctly ordered. Deleting subtree.", context, CacheNodeGetDescription(node), CacheNodeGetDescription(node->rightChild));
			CacheNodeFree(cache, node->rightChild);
			node->rightChild = nil;
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
		if (next == nil) break;
		
		if (next->younger != node)
		{
			OOLog(kOOLogCacheIntegrityCheck, @"Integrity check (%@): node %@ has invalid older link (should be %@, is %@); repairing.", context, CacheNodeGetDescription(next), CacheNodeGetDescription(node), CacheNodeGetDescription(next->older));
			next->older = node;
		}
		node = next;
	}
	
	if (seenCount != cache->count)
	{
		// This is especially bad since this function is called just after verifying that the count field reflects the number of objects in the tree.
		OOLog(kOOLogCacheIntegrityCheck, @"Integrity check (%@): expected %u nodes, found %u. Cannot repair; clearing cache.", context, cache->count, seenCount);
		cache->count = 0;
		CacheNodeFree(cache, cache->root);
		cache->root = NULL;
		cache->youngest = NULL;
		cache->oldest = NULL;
		return;
	}
	
	if (node != cache->oldest)
	{
		OOLog(kOOLogCacheIntegrityCheck, @"Integrity check (%@): oldest pointer in cache is wrong (should be %@, is %@); repairing.", context, CacheNodeGetDescription(node), CacheNodeGetDescription(cache->oldest));
		cache->oldest = node;
	}
}
