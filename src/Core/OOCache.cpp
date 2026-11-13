/*

OOCache.cpp
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

        A Foundation mutable dictionary performs the first three operations
   efficiently but has no support for pruning - specifically no support for
   finding the least-recently-accessed element. Using standard Foundation
   containers, it would be necessary to use several dictionaries and arrays,
   which would be quite inefficient since small arrays aren’t very good at head
   insertion or deletion. Alternatively, a standard dictionary whose value
   objects maintain an age-sorted list could be used.

        I chose instead to implement a custom scheme from scratch. It uses two
        parallel data structures: a doubly-linked list sorted by age, and a
   splay tree to implement insertion/deletion. The implementation is largely
        procedural C. Deserialization, pruning and modification tracking is done
        in the OOCache class; everything else is done in C functions.

        A SPLAY TREE is a type of semi-balanced binary search tree with certain
        useful properties:
          * Simplicity. All look-up and restructuring operations are based on a
                single operation, splaying, which brings the node with the
   desired key (or the node whose key is "left" of the desired key, if there is
   no exact match) to the root, while maintaining the binary search tree
                invariant. Splaying itself is sufficient for look-up; insertion
   and deletion work by splaying and then manipulating at the root.
          * Self-optimization. Because each look-up brings the sought element to
                the root, often-used elements tend to stay near the top. (Oolite
   often performs sequences of identical look-ups, for instance when creating an
   asteroid field, or the racing ring set-up which uses lots of identical ring
   segments; during combat, missiles, canisters and hull plates will be commonly
   used.) Also, this means that for a retrieve- attempt/insert sequence, the
   retrieve attempt will optimize the tree for the insertion.
          * Efficiency. In addition to the self-optimization, splay trees have a
                small code size and no storage overhead for flags.
                The amortized worst-case cost of splaying (cost averaged over a
                worst-case sequence of operations) is O(log n); a single
   worst-case splay is O(n), but that worst-case also improves the balance of
   the tree, so you can't have two worst cases in a row. Insertion and deletion
   are also O(log n), consisting of a splay plus an O(1) operation. References
   for splay trees:
          * http://www.cs.cmu.edu/~sleator/papers/self-adjusting.pdf
                Original research paper.
          *	http://www.ibr.cs.tu-bs.de/courses/ss98/audii/applets/BST/SplayTree-Example.html
                Java applet demonstrating splaying.
          * http://www.link.cs.cmu.edu/link/ftp-site/splaying/top-down-splay.c
                Sample implementation by one of the inventors. The TreeSplay(),
                TreeInsert() and CacheRemove() functions are based on this.

        The AGE LIST is a doubly-linked list, ordered from oldest to youngest.
        Whenever an element is retrieved or inserted, it is promoted to the
        youngest end of the age list. Pruning proceeds from the oldest end of
   the age list.

        if (autoPrune)
        {
                PRUNING is batched, handling 20% of the cache at once. This is
   primarily because deletion somewhat pessimizes the tree (see
   "Self-optimization" below). It also provides a bit of code coherency. To
   reduce pruning batches while in flight, pruning is also performed before
   serialization (which in turn is done, if the cache has changed, whenever the
   user docks). This has the effect that the number of items in the cache on
   disk never exceeds 80% of the prune threshold. This is probably not actually
                poinful, since pruning should be a very small portion of the
   per-frame run time in any case. Premature optimization and all that jazz.
                Pruning performs at most 0.2n deletions, and is thus O(n log n).
        }
        else
        {
                PRUNING is performed manually by calling -prune.
        }

        If the macro OOCACHE_PERFORM_INTEGRITY_CHECKS is set to a non-zero
   value, the integrity of the tree and the age list will be checked before and
        after each high-level operation. This is an inherently O(n) operation.
*/

#include "OOCache.h"

#include <format>

#include "OOStringParsing.h"
#include "oofnd/String.hpp"
#if DEBUG_GRAPHVIZ
#include "oofnd/FileSystem.hpp"
#endif

#ifndef OOCACHE_PERFORM_INTEGRITY_CHECKS
#define OOCACHE_PERFORM_INTEGRITY_CHECKS 0
#endif

using OOCacheImpl = struct OOCacheImpl;
using OOCacheNode = struct OOCacheNode;

struct OOCacheImpl {
  // Splay tree root
  OOCacheNode* root;

  // Ends of age list
  OOCacheNode *oldest, *youngest;

  unsigned count;
  std::optional<std::string> name;  // nullopt: no name (nil)
};

struct OOCacheNode {
  // Payload (the key orders the tree by std::string::compare)
  std::string key{};
  oo::PList value{};

  // Splay tree
  OOCacheNode *leftChild = nullptr, *rightChild = nullptr;

  // Age list
  OOCacheNode *younger = nullptr, *older = nullptr;
};

#if OOCACHE_PERFORM_INTEGRITY_CHECKS
constexpr unsigned kCountUnknown = -1U;
#endif

constexpr const char* kSerializedEntryKeyKey = "key";
constexpr const char* kSerializedEntryKeyValue = "value";

static OOCacheImpl* CacheAllocate();
static void CacheFree(OOCacheImpl* cache);

static bool CacheInsert(OOCacheImpl* cache, const std::string& key,
                        const oo::PList& value);
static bool CacheRemove(OOCacheImpl* cache, const std::string& key);
static const oo::PList* CacheRetrieve(OOCacheImpl* cache,
                                      const std::string& key);
static unsigned CacheGetCount(OOCacheImpl* cache);
namespace {
bool CacheRemoveOldest(OOCacheImpl* cache, const std::string& logKey);
std::vector<oo::PList> CacheArrayOfContentsByAge(OOCacheImpl* cache);
oo::PList CacheArrayOfNodesByAge(OOCacheImpl* cache);
const std::optional<std::string>& CacheGetName(OOCacheImpl* cache);
void CacheSetName(OOCacheImpl* cache, std::optional<std::string> name);
}  // namespace

#if OOCACHE_PERFORM_INTEGRITY_CHECKS
static void CacheCheckIntegrity(OOCacheImpl* cache, const std::string& context);

#define CHECK_INTEGRITY(context) CacheCheckIntegrity(cache, (context))
#else
#define CHECK_INTEGRITY(context) \
  do {                           \
  } while (0)
#endif

OOCache::~OOCache() {
  CHECK_INTEGRITY("dealloc");
  CacheFree(cache);
}

// oo::DescriptionOf (OODescription.h) wraps this as "<OOCache 0x...>{...}",
// which is what this class's own -description printed.
std::optional<std::string> OOCache::descriptionComponents() const {
  return std::format(
      "\"{}\", {} elements, prune threshold={}, auto-prune={} dirty={}",
      CacheGetName(cache).value_or("(null)"), CacheGetCount(cache),
      _pruneThreshold, _autoPrune ? "yes" : "no", _dirty ? "yes" : "no");
}

std::shared_ptr<OOCache> OOCache::cacheWithPList(const oo::PList& pList) {
  std::shared_ptr<OOCache> result = oo::makeShared<OOCache>();
  if (!result->initWithPList(pList)) return nullptr;
  return result;
}

bool OOCache::initWithPList(const oo::PList& pList) {
  bool OK = true;

  if (OK) {
    cache = CacheAllocate();
    if (cache == nullptr) OK = false;
  }

  if (!pList.isNull()) {
    if (OK) OK = pList.isArray();
    if (OK) loadFromArray(pList);
  }
  if (OK) {
    _pruneThreshold = kOOCacheDefaultPruneThreshold;
    _autoPrune = true;
  }

  return OK;
}

oo::PList OOCache::pListRepresentation() {
  return CacheArrayOfNodesByAge(cache);
}

oo::PList OOCache::pListForKey(const std::string& key) {
  oo::PList result;

  CHECK_INTEGRITY("pListForKey() before");

  if (const oo::PList* value = CacheRetrieve(cache, key)) result = *value;
  // Note: while reordering the age list technically makes the cache dirty, it's
  // not worth rewriting it just for that, so we don't flag it.

  CHECK_INTEGRITY("pListForKey() after");

  return result;
}

void OOCache::setPList(const oo::PList& value, const std::string& key) {
  CHECK_INTEGRITY("setPList() before");

  if (CacheInsert(cache, key, value)) {
    _dirty = true;
    if (_autoPrune) prune();
  }

  CHECK_INTEGRITY("setPList() after");
}

void OOCache::removePListForKey(const std::string& key) {
  CHECK_INTEGRITY("removePListForKey() before");

  if (CacheRemove(cache, key)) _dirty = true;

  CHECK_INTEGRITY("removePListForKey() after");
}

void OOCache::setPruneThreshold(unsigned threshold) {
  threshold =
      MAX(threshold, static_cast<unsigned>(kOOCacheMinimumPruneThreshold));
  if (threshold != _pruneThreshold) {
    _pruneThreshold = threshold;
    if (_autoPrune) prune();
  }
}

unsigned OOCache::pruneThreshold() { return _pruneThreshold; }

void OOCache::setAutoPrune(bool flag) {
  bool prune = (flag != false);
  if (prune != _autoPrune) {
    _autoPrune = prune;
    this->prune();
  }
}

bool OOCache::autoPrune() { return _autoPrune; }

void OOCache::prune() {
  unsigned pruneCount;
  unsigned desiredCount;
  unsigned count;

  // Order of operations is to ensure rounding down.
  if (_autoPrune)
    desiredCount = (_pruneThreshold * 4) / 5;
  else
    desiredCount = _pruneThreshold;

  if (_pruneThreshold == kOOCacheNoPrune) return;
  count = CacheGetCount(cache);
  if (count <= _pruneThreshold) return;

  pruneCount = count - desiredCount;

  const std::string logKey =
      std::format("dataCache.prune.{}", CacheGetName(cache).value_or("(null)"));
  OO_LOG(logKey, "Pruning cache \"{}\" - removing {} entries",
         CacheGetName(cache).value_or("(null)"), pruneCount);
  oo::log::indentIf(logKey);

  while (pruneCount--) CacheRemoveOldest(cache, logKey);

  oo::log::outdentIf(logKey);
}

bool OOCache::dirty() { return _dirty; }

void OOCache::markClean() { _dirty = false; }

std::optional<std::string> OOCache::name() { return CacheGetName(cache); }

void OOCache::setName(const std::optional<std::string>& name) {
  CacheSetName(cache, name);
}

std::vector<oo::PList> OOCache::pListsByAge() {
  return CacheArrayOfContentsByAge(cache);
}

// Private

void OOCache::loadFromArray(const oo::PList& array) {
  const oo::PList::Array* entries = array.getIf<oo::PList::Array>();
  if (entries == nullptr) return;

  for (const oo::PList& entry : *entries) {
    if (entry.isDict()) {
      const oo::PList* key = entry.find(kSerializedEntryKeyKey);
      const oo::PList* value = entry.find(kSerializedEntryKeyValue);
      if (key != nullptr && key->isString() && value != nullptr) {
        setPList(*value, *key->getIf<std::string>());
      }
    }
  }
}

/***** Most of the implementation. In C. Because I'm inconsistent and slightly
 * m. *****/

static OOCacheNode* CacheNodeAllocate(const std::string& key,
                                      const oo::PList& value);
static void CacheNodeFree(OOCacheImpl* cache, OOCacheNode* node);
static const oo::PList* CacheNodeGetValue(OOCacheNode* node);
static void CacheNodeSetValue(OOCacheNode* node, const oo::PList& value);

#if OOCACHE_PERFORM_INTEGRITY_CHECKS
static std::string CacheNodeGetDescription(OOCacheNode* node);
#endif

static OOCacheNode* TreeSplay(OOCacheNode** root, const std::string& key);
static OOCacheNode* TreeInsert(OOCacheImpl* cache, const std::string& key,
                               const oo::PList& value);

#if OOCACHE_PERFORM_INTEGRITY_CHECKS
static unsigned TreeCountNodes(OOCacheNode* node);
static OOCacheNode* TreeCheckIntegrity(OOCacheImpl* cache, OOCacheNode* node,
                                       OOCacheNode* expectedParent,
                                       const std::string& context);
#endif

static void AgeListMakeYoungest(OOCacheImpl* cache, OOCacheNode* node);
static void AgeListRemove(OOCacheImpl* cache, OOCacheNode* node);

#if OOCACHE_PERFORM_INTEGRITY_CHECKS
static void AgeListCheckIntegrity(OOCacheImpl* cache,
                                  const std::string& context);
#endif

/***** CacheImpl functions *****/

static OOCacheImpl* CacheAllocate() {
  return new OOCacheImpl();  // value-initialised (zeroed), as calloc did; the
                             // name is a C++ member
}

static void CacheFree(OOCacheImpl* cache) {
  if (cache == nullptr) return;

  CacheNodeFree(cache, cache->root);
  delete cache;
}

static bool CacheInsert(OOCacheImpl* cache, const std::string& key,
                        const oo::PList& value) {
  OOCacheNode* node = nullptr;

  if (cache == nullptr || value.isNull()) return false;

  node = TreeInsert(cache, key, value);
  if (node != nullptr) {
    AgeListMakeYoungest(cache, node);
    return true;
  } else
    return false;
}

static bool CacheRemove(OOCacheImpl* cache, const std::string& key) {
  OOCacheNode *node = nullptr, *newRoot = nullptr;

  node = TreeSplay(&cache->root, key);
  if (node != nullptr) {
    if (node->leftChild == nullptr)
      newRoot = node->rightChild;
    else {
      newRoot = node->leftChild;
      TreeSplay(&newRoot, key);
      newRoot->rightChild = node->rightChild;
    }
    node->leftChild = nullptr;
    node->rightChild = nullptr;

    cache->root = newRoot;
    --cache->count;

    AgeListRemove(cache, node);
    CacheNodeFree(cache, node);

    return true;
  } else
    return false;
}

namespace {
bool CacheRemoveOldest(OOCacheImpl* cache, const std::string& logKey) {
  // This could be more efficient, but does it need to be?
  if (cache == nullptr || cache->oldest == nullptr) return false;

  OO_LOG(logKey, "Pruning cache \"{}\": removing {}",
         cache->name.value_or("(null)"), cache->oldest->key);
  const std::string key = cache->oldest->key;  // a copy: the node goes
  return CacheRemove(cache, key);
}
}  // namespace

static const oo::PList* CacheRetrieve(OOCacheImpl* cache,
                                      const std::string& key) {
  OOCacheNode* node = nullptr;
  const oo::PList* result = nullptr;

  if (cache == nullptr) return nullptr;

  node = TreeSplay(&cache->root, key);
  if (node != nullptr) {
    result = CacheNodeGetValue(node);
    AgeListMakeYoungest(cache, node);
  }
  return result;
}

namespace {

// Empty for an empty cache (the Foundation version returned nil).
std::vector<oo::PList> CacheArrayOfContentsByAge(OOCacheImpl* cache) {
  OOCacheNode* node = nullptr;
  std::vector<oo::PList> result;

  if (cache == nullptr || cache->count == 0) return result;

  result.reserve(cache->count);

  for (node = cache->youngest; node != nullptr; node = node->older) {
    result.emplace_back(node->value);
  }
  return result;
}

// Property-list data: [{key, value}, ...] from oldest to youngest; null for an
// empty cache (nil).
oo::PList CacheArrayOfNodesByAge(OOCacheImpl* cache) {
  OOCacheNode* node = nullptr;
  oo::PList::Array result;

  if (cache == nullptr || cache->count == 0) return oo::PList();

  result.reserve(cache->count);

  for (node = cache->oldest; node != nullptr; node = node->younger) {
    oo::PList::Dict entry;
    entry.emplace(kSerializedEntryKeyKey, oo::PList(node->key));
    entry.emplace(kSerializedEntryKeyValue, node->value);
    result.push_back(oo::PList(std::move(entry)));
  }
  return oo::PList(std::move(result));
}

const std::optional<std::string>& CacheGetName(OOCacheImpl* cache) {
  return cache->name;
}

void CacheSetName(OOCacheImpl* cache, std::optional<std::string> name) {
  cache->name = std::move(name);
}

}  // namespace

static unsigned CacheGetCount(OOCacheImpl* cache) { return cache->count; }

#if OOCACHE_PERFORM_INTEGRITY_CHECKS

static void CacheCheckIntegrity(OOCacheImpl* cache,
                                const std::string& context) {
  unsigned trueCount;

  cache->root = TreeCheckIntegrity(cache, cache->root, NULL, context);

  trueCount = TreeCountNodes(cache->root);
  if (kCountUnknown == cache->count)
    cache->count = trueCount;
  else if (cache->count != trueCount) {
    OO_LOG("dataCache.integrityCheck",
           "Integrity check ({} for \"{}\"): count is {}, but should be {}.",
           context, cache->name.value_or("(null)"), cache->count, trueCount);
    cache->count = trueCount;
  }

  AgeListCheckIntegrity(cache, context);
}

#endif  // OOCACHE_PERFORM_INTEGRITY_CHECKS

/***** CacheNode functions *****/

// CacheNodeAllocate(): create a cache node for a key, value pair, without
// inserting it in the structures.
static OOCacheNode* CacheNodeAllocate(const std::string& key,
                                      const oo::PList& value) {
  if (value.isNull()) return nullptr;

  // Null links, as calloc gave; the key and value are C++ members.
  return new OOCacheNode{.key = key, .value = value};
}

// CacheNodeFree(): recursively delete a cache node and its children in the
// splay tree. To delete an individual node, first clear its child pointers.
static void CacheNodeFree(OOCacheImpl* cache, OOCacheNode* node) {
  if (node == nullptr) return;

  AgeListRemove(cache, node);

  CacheNodeFree(cache, node->leftChild);
  CacheNodeFree(cache, node->rightChild);

  delete node;  // releases the key and the value
}

// CacheNodeGetValue(): retrieve the value of a cache node
static const oo::PList* CacheNodeGetValue(OOCacheNode* node) {
  if (node == nullptr) return nullptr;

  return &node->value;
}

// CacheNodeSetValue(): change the value of a cache node (as when
// setObject:forKey: is called for an existing key).
static void CacheNodeSetValue(OOCacheNode* node, const oo::PList& value) {
  if (node == nullptr) return;

  node->value = value;
}

#if OOCACHE_PERFORM_INTEGRITY_CHECKS
// CacheNodeGetDescription(): get a description of a cache node for debugging
// purposes.
static std::string CacheNodeGetDescription(OOCacheNode* node) {
  if (node == NULL) return "0[null]";

  return std::format("{}[\"{}\"]", oo::str::pointerDescription(node),
                     node->key);
}
#endif  // OOCACHE_PERFORM_INTEGRITY_CHECKS

/***** Tree functions *****/

/*	TreeSplay()
        This is the fundamental operation of a splay tree. It searches for a
   node with a given key, and rebalances the tree so that the found node becomes
        the root. If no match is found, the node moved to the root is the one
   that would have been found before the target, and will thus be a neighbour of
        the target if the key is subsequently inserted.
*/
static OOCacheNode* TreeSplay(OOCacheNode** root, const std::string& key) {
  int order;
  OOCacheNode N = {.leftChild = nullptr, .rightChild = nullptr};
  OOCacheNode *node = nullptr, *temp = nullptr, *l = &N, *r = &N;
  bool exact = false;

  if (root == nullptr || *root == nullptr) return nullptr;

  node = *root;

  for (;;) {
#ifndef NDEBUG
    if (node == nullptr) {
      OO_LOG("node.error", "{}", "node is NULL");
    }
#endif
    order = key.compare(node->key);
    if (order < 0) {
      // Closest match is in left subtree
      if (node->leftChild == nullptr) break;
      if (key.compare(node->leftChild->key) < 0) {
        // Rotate right
        temp = node->leftChild;
        node->leftChild = temp->rightChild;
        temp->rightChild = node;
        node = temp;
        if (node->leftChild == nullptr) break;
      }
      // Link right
      r->leftChild = node;
      r = node;
      node = node->leftChild;
    } else if (order > 0) {
      // Closest match is in right subtree
      if (node->rightChild == nullptr) break;
      if (key.compare(node->rightChild->key) > 0) {
        // Rotate left
        temp = node->rightChild;
        node->rightChild = temp->leftChild;
        temp->leftChild = node;
        node = temp;
        if (node->rightChild == nullptr) break;
      }
      // Link left
      l->rightChild = node;
      l = node;
      node = node->rightChild;
    } else {
      // Found exact match
      exact = true;
      break;
    }
  }

  // Assemble
  l->rightChild = node->leftChild;
  r->leftChild = node->rightChild;
  node->leftChild = N.rightChild;
  node->rightChild = N.leftChild;

  *root = node;
  return exact ? node : nullptr;
}

static OOCacheNode* TreeInsert(OOCacheImpl* cache, const std::string& key,
                               const oo::PList& value) {
  OOCacheNode *closest = nullptr, *node = nullptr;
  int order;

  if (cache == nullptr || value.isNull()) return nullptr;

  if (cache->root == nullptr) {
    node = CacheNodeAllocate(key, value);
    cache->root = node;
    cache->count = 1;
  } else {
    node = TreeSplay(&cache->root, key);
    if (node != nullptr) {
      // Exact match: key already exists, reuse its node
      CacheNodeSetValue(node, value);
    } else {
      closest = cache->root;
      node = CacheNodeAllocate(key, value);
      if (EXPECT_NOT(node == nullptr)) return nullptr;

      order = key.compare(closest->key);

      if (order < 0) {
        // Insert to left
        node->leftChild = closest->leftChild;
        node->rightChild = closest;
        closest->leftChild = nullptr;
        cache->root = node;
        ++cache->count;
      } else if (order > 0) {
        // Insert to right
        node->rightChild = closest->rightChild;
        node->leftChild = closest;
        closest->rightChild = nullptr;
        cache->root = node;
        ++cache->count;
      } else {
        // Key already exists, which we should have caught above
        OO_LOG(
            "dataCache.inconsistency",
            "{}() internal inconsistency for cache \"{}\", insertion failed.",
            __PRETTY_FUNCTION__, cache->name.value_or("(null)"));
        CacheNodeFree(cache, node);
        return nullptr;
      }
    }
  }

  return node;
}

#if OOCACHE_PERFORM_INTEGRITY_CHECKS
static unsigned TreeCountNodes(OOCacheNode* node) {
  if (node == NULL) return 0;
  return 1 + TreeCountNodes(node->leftChild) + TreeCountNodes(node->rightChild);
}

// TreeCheckIntegrity(): verify the links and contents of a (sub-)tree. If
// successful, returns the root of the subtree (which could theoretically be
// changed), otherwise returns NULL.
static OOCacheNode* TreeCheckIntegrity(OOCacheImpl* cache, OOCacheNode* node,
                                       OOCacheNode* expectedParent,
                                       const std::string& context) {
  int order;
  bool OK = true;

  if (node == NULL) return NULL;

  if (OK && node->value.isNull()) {
    OO_LOG(
        "dataCache.integrityCheck",
        "Integrity check ({} for \"{}\"): node \"{}\" has nil value, deleting.",
        context, cache->name.value_or("(null)"), CacheNodeGetDescription(node));
    OK = false;
  }
  if (OK && node->leftChild != NULL) {
    order = node->key.compare(node->leftChild->key);
    if (!(order > 0)) {
      OO_LOG("dataCache.integrityCheck",
             "Integrity check ({} for \"{}\"): node {}'s left child {} is not "
             "correctly ordered. Deleting subtree.",
             context, cache->name.value_or("(null)"),
             CacheNodeGetDescription(node),
             CacheNodeGetDescription(node->leftChild));
      CacheNodeFree(cache, node->leftChild);
      node->leftChild = NULL;
      cache->count = kCountUnknown;
    } else {
      node->leftChild =
          TreeCheckIntegrity(cache, node->leftChild, node, context);
    }
  }
  if (node->rightChild != NULL) {
    order = node->key.compare(node->rightChild->key);
    if (!(order < 0)) {
      OO_LOG("dataCache.integrityCheck",
             "Integrity check ({} for \"{}\"): node \"{}\"'s right child "
             "\"{}\" is not correctly ordered. Deleting subtree.",
             context, cache->name.value_or("(null)"),
             CacheNodeGetDescription(node),
             CacheNodeGetDescription(node->rightChild));
      CacheNodeFree(cache, node->rightChild);
      node->rightChild = NULL;
      cache->count = kCountUnknown;
    } else {
      node->rightChild =
          TreeCheckIntegrity(cache, node->rightChild, node, context);
    }
  }

  if (OK)
    return node;
  else {
    cache->count = kCountUnknown;
    CacheNodeFree(cache, node);
    return NULL;
  }
}
#endif  // OOCACHE_PERFORM_INTEGRITY_CHECKS

/***** Age list functions *****/

// AgeListMakeYoungest(): place a given cache node at the youngest end of the
// age list.
static void AgeListMakeYoungest(OOCacheImpl* cache, OOCacheNode* node) {
  if (cache == nullptr || node == nullptr) return;

  AgeListRemove(cache, node);
  node->older = cache->youngest;
  if (nullptr != cache->youngest) cache->youngest->younger = node;
  cache->youngest = node;
  if (cache->oldest == nullptr) cache->oldest = node;
}

// AgeListRemove(): remove a cache node from the age-sorted tree. Does not
// affect its position in the splay tree.
static void AgeListRemove(OOCacheImpl* cache, OOCacheNode* node) {
  OOCacheNode* younger = nullptr;
  OOCacheNode* older = nullptr;

  if (node == nullptr) return;

  younger = node->younger;
  older = node->older;

  if (cache->youngest == node) cache->youngest = older;
  if (cache->oldest == node) cache->oldest = younger;

  node->younger = nullptr;
  node->older = nullptr;

  if (younger != nullptr) younger->older = older;
  if (older != nullptr) older->younger = younger;
}

#if OOCACHE_PERFORM_INTEGRITY_CHECKS

static void AgeListCheckIntegrity(OOCacheImpl* cache,
                                  const std::string& context) {
  OOCacheNode *node = NULL, *next = NULL;
  unsigned seenCount = 0;

  if (cache == NULL) return;

  node = cache->youngest;

  if (node)
    for (;;) {
      next = node->older;
      ++seenCount;
      if (next == NULL) break;

      if (next->younger != node) {
        OO_LOG("dataCache.integrityCheck",
               "Integrity check ({} for \"{}\"): node \"{}\" has invalid older "
               "link (should be \"{}\", is \"{}\"); repairing.",
               context, cache->name.value_or("(null)"),
               CacheNodeGetDescription(next), CacheNodeGetDescription(node),
               CacheNodeGetDescription(next->older));
        next->older = node;
      }
      node = next;
    }

  if (seenCount != cache->count) {
    // This is especially bad since this function is called just after verifying
    // that the count field reflects the number of objects in the tree.
    OO_LOG("dataCache.integrityCheck",
           "Integrity check ({} for \"{}\"): expected {} nodes, found {}. "
           "Cannot repair; clearing cache.",
           context, cache->name.value_or("(null)"), cache->count, seenCount);

    /* Start of temporary extra logging */
    node = cache->youngest;

    if (node) {
      for (;;) {
        next = node->older;
        ++seenCount;
        if (next == NULL) break;

        OO_LOG("dataCache.integrityCheck", "Key is: {}", node->key);

        if (!node->value.isNull()) {
          OO_LOG("dataCache.integrityCheck", "Value is: {}",
                 oo::DescriptionOf(node->value));
        } else {
          OO_LOG("dataCache.integrityCheck", "{}", "Value is: NULL");
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

  if (node != cache->oldest) {
    OO_LOG("dataCache.integrityCheck",
           "Integrity check ({} for \"{}\"): oldest pointer in cache is wrong "
           "(should be \"{}\", is \"{}\"); repairing.",
           context, cache->name.value_or("(null)"),
           CacheNodeGetDescription(node),
           CacheNodeGetDescription(cache->oldest));
    cache->oldest = node;
  }
}

#endif  // OOCACHE_PERFORM_INTEGRITY_CHECKS

#if DEBUG_GRAPHVIZ

/*	NOTE: enabling AGE_LIST can result in graph rendering times of many
   hours, because determining paths for non-constraint arcs is NP-hard. In
   particular, I gave up on rendering a dump of a fairly minimal cache manager
   after three and a half hours. Individual caches were fine.
*/
#define AGE_LIST 0

void OOCache::appendNodesFromSubTree(OOCacheNode* subTree,
                                     std::string& ioString) {
  ioString += std::format("\tn{} [label=\"<f0> | <f1> {} | <f2>\"];\n",
                          oo::str::pointerDescription(subTree),
                          cxx_EscapedGraphVizString(subTree->key));

  if (subTree->leftChild != nullptr) {
    appendNodesFromSubTree(subTree->leftChild, ioString);
    ioString += std::format("\tn{}:f0 -> n{}:f1;\n",
                            oo::str::pointerDescription(subTree),
                            oo::str::pointerDescription(subTree->leftChild));
  }
  if (subTree->rightChild != nullptr) {
    appendNodesFromSubTree(subTree->rightChild, ioString);
    ioString += std::format("\tn{}:f2 -> n{}:f1;\n",
                            oo::str::pointerDescription(subTree),
                            oo::str::pointerDescription(subTree->rightChild));
  }
}

std::optional<std::string> OOCache::generateGraphVizBodyWithRootNamed(
    const std::string& rootName) {
  std::string result;

  // Root node representing cache
  result += std::format(
      "\t{} [label=\"Cache \\\"{}\\\"\" shape=box];\n\tnode "
      "[shape=record];\n\t\n",
      rootName,
      name().has_value() ? cxx_EscapedGraphVizString(*name())
                         : std::string("(null)"));

  if (cache == nullptr) return result;

  // Cache
  appendNodesFromSubTree(cache->root, result);

  // Arc from cache object to root node
  result += "\tedge [color=black constraint=true];\n";
  result += std::format("\t{} -> n{}:f1;\n", rootName,
                        oo::str::pointerDescription(cache->root));

#if AGE_LIST
  OOCacheNode* node = NULL;
  // Arcs representing age list
  result +=
      "\t\n\t// Age-sorted list in blue\n\tedge [color=blue "
      "constraint=false];\n";
  node = cache->oldest;
  while (node->younger != NULL) {
    result +=
        std::format("\tn{}:f2 -> n{}:f0;\n", oo::str::pointerDescription(node),
                    oo::str::pointerDescription(node->younger));
    node = node->younger;
  }
#endif

  return result;
}

std::string OOCache::generateGraphViz() {
  std::string result;

  // Header
  result += std::format(
      "// OOCache dump\n\ndigraph cache\n{{\n\tgraph [charset=\"UTF-8\", "
      "label=\"OOCache \"{}\" debug dump\", labelloc=t, labeljust=l];\n\t\n",
      name().value_or("(null)"));

  result += generateGraphVizBodyWithRootNamed("cache").value_or("");

  result += "}\n";

  return result;
}

// (-writeGraphVizToURL: folded in: its only sender was this method.)
void OOCache::writeGraphVizToPath(const std::string& path) {
  const std::string graphViz = generateGraphViz();
  (void)oo::fs::writeFile(oo::fs::pathFromUTF8(path),
                          oo::Data(graphViz.data(), graphViz.size()),
                          oo::fs::WriteMode::kAtomic);
}
#endif
