/*	test_OOPriorityQueue.mm
	Unit tests for OOPriorityQueue (src/Core/OOPriorityQueue.h): bead oo-3lj8, a Phase 3
	conversion in the house style of the OOColor exemplar (proposed ADR-0056).

	It pins what the queue computed before the conversion: extraction in comparator order, peek
	and remove, removal by comparator and by identity, the buffer's growth and shrinkage (seen
	through the description), copies, equality and hash, the objects' retain counts, and the two
	exceptions addObject() raises. The elements are Objective-C objects compared by a selector, as
	OOScriptTimer's are. The expectations were written against the Objective-C API and run on the
	unconverted class first (commit 5ce883621); the queue's one caller was adapted in the bead, so
	there is no facade and the calls here are the C++ class's. Run: bash tools/check-core-tests.sh
*/

#import "OOPriorityQueue.h"
#import "OODescription.h"
#include "oofnd/objc/OOException.h"

#include "oo_test.hpp"

#include <cstring>


// An element: an integer key, ordered by -compare: and by -compareDescending:.
@interface TestItem: OOObject
{
@public
	int			_key;
}
+ (instancetype) itemWithKey:(int)key;
- (OOComparisonResult) compare:(TestItem *)other;
- (OOComparisonResult) compareDescending:(TestItem *)other;
@end


@implementation TestItem

+ (instancetype) itemWithKey:(int)key
{
	TestItem *item = [[[self alloc] init] autorelease];
	item->_key = key;
	return item;
}

- (OOComparisonResult) compare:(TestItem *)other
{
	if (_key < other->_key)  return OOOrderedAscending;
	if (_key > other->_key)  return OOOrderedDescending;
	return OOOrderedSame;
}

- (OOComparisonResult) compareDescending:(TestItem *)other
{
	return [other compare:self];
}

@end


namespace {

std::vector<int> Keys(const std::vector<oo::ObjCRef<id>> &objects)
{
	std::vector<int> result;
	for (const auto &object : objects)  result.push_back(((TestItem *)object.get())->_key);
	return result;
}


int KeyOf(id object)
{
	return object != nil ? ((TestItem *)object)->_key : -1;
}


const int kKeys[] = { 5, 3, 9, 1, 7, 3, 8, 2, 6, 4, 0 };

}	// namespace


OO_TEST(extractsInComparatorOrder)
{
	@autoreleasepool
	{
		oo::Ref<OOPriorityQueue> queue = OOPriorityQueue::queueWithComparator(@selector(compare:));
		OO_CHECK(queue != nullptr && queue->count() == 0);
		OO_CHECK(queue->nextObject() == nil && queue->peekAtNextObject() == nil);
		for (int key : kKeys)  queue->addObject([TestItem itemWithKey:key]);
		OO_CHECK(queue->count() == 11);
		OO_CHECK(KeyOf(queue->peekAtNextObject()) == 0 && queue->count() == 11);
		OO_CHECK(KeyOf(queue->nextObject()) == 0 && queue->count() == 10);
		queue->removeNextObject();
		OO_CHECK(KeyOf(queue->peekAtNextObject()) == 2);
		OO_CHECK(Keys(queue->sortedObjects()) == std::vector<int>({ 2, 3, 3, 4, 5, 6, 7, 8, 9 }));
		OO_CHECK(queue->count() == 0);	// sortedObjects empties the queue
		queue->removeNextObject();	// on an empty queue: nothing
		OO_CHECK(queue->count() == 0);

		oo::Ref<OOPriorityQueue> descending = OOPriorityQueue::queueWithComparator(@selector(compareDescending:));
		for (int key : kKeys)  descending->addObject([TestItem itemWithKey:key]);
		OO_CHECK(Keys(descending->objectEnumerator()) == std::vector<int>({ 9, 8, 7, 6, 5, 4, 3, 3, 2, 1, 0 }));

		OO_CHECK(OOPriorityQueue::queueWithComparator(NULL) == nullptr);
	}
}


OO_TEST(removeByComparatorAndByIdentity)
{
	@autoreleasepool
	{
		oo::Ref<OOPriorityQueue> queue = OOPriorityQueue::queueWithComparator(@selector(compare:));
		TestItem *three = [TestItem itemWithKey:3];
		for (int key : kKeys)  queue->addObject(key == 3 ? three : [TestItem itemWithKey:key]);
		OO_CHECK(queue->count() == 11);

		queue->removeExactObject([TestItem itemWithKey:5]);	// equal, not identical: stays
		OO_CHECK(queue->count() == 11);
		queue->removeExactObject(three);	// the same object twice: both go
		OO_CHECK(queue->count() == 9);
		queue->removeObject([TestItem itemWithKey:5]);	// compares equal: goes
		OO_CHECK(queue->count() == 8);
		queue->removeObject([TestItem itemWithKey:42]);
		queue->removeObject(nil);
		queue->removeExactObject(nil);
		OO_CHECK(Keys(queue->sortedObjects()) == std::vector<int>({ 0, 1, 2, 4, 6, 7, 8, 9 }));
	}
}


OO_TEST(bufferGrowsAndShrinks)
{
	@autoreleasepool
	{
		oo::Ref<OOPriorityQueue> queue = OOPriorityQueue::queueWithComparator(@selector(compare:));
		std::string text = queue->description().value_or("");
		OO_CHECK(text.starts_with("<OOPriorityQueue 0x") && text.ends_with(">{count=0, capacity=0}"));

		queue->addObject([TestItem itemWithKey:1]);
		OO_CHECK(queue->description().value_or("").ends_with(">{count=1, capacity=16}"));
		for (int i = 2; i <= 17; i++)  queue->addObject([TestItem itemWithKey:i]);
		OO_CHECK(queue->description().value_or("").ends_with(">{count=17, capacity=24}"));
		for (int i = 18; i <= 40; i++)  queue->addObject([TestItem itemWithKey:i]);
		OO_CHECK(queue->description().value_or("").ends_with(">{count=40, capacity=54}"));

		// Removing down to half the capacity drops two thirds of the free space.
		while (queue->count() > 27)  queue->removeNextObject();
		OO_CHECK(queue->description().value_or("").ends_with(">{count=27, capacity=36}"));
		while (queue->count() > 1)  queue->removeNextObject();
		OO_CHECK(queue->description().value_or("").ends_with(">{count=1, capacity=16}"));
		OO_CHECK(KeyOf(queue->nextObject()) == 40);
	}
}


OO_TEST(copiesEqualityAndHash)
{
	@autoreleasepool
	{
		oo::Ref<OOPriorityQueue> queue = OOPriorityQueue::queueWithComparator(@selector(compare:));
		OO_CHECK(queue->hash() == NSNotFound);
		for (int key : kKeys)  queue->addObject([TestItem itemWithKey:key]);

		oo::Ref<OOPriorityQueue> copy = queue->copy();
		OO_CHECK(copy != queue && copy->count() == 11);
		OO_CHECK(copy->description().value_or("").ends_with(">{count=11, capacity=11}"));	// capacity is the count
		OO_CHECK(queue->isEqual(copy.get()) && copy->isEqual(queue.get()) && queue->isEqual(queue.get()));	// the same objects
		OO_CHECK(queue->hash() == (11 ^ [queue->peekAtNextObject() hash]) && queue->hash() == copy->hash());
		OO_CHECK(!queue->isEqual(nullptr));

		// Equal keys are not equal objects (TestItem's -isEqual: is identity).
		oo::Ref<OOPriorityQueue> other = OOPriorityQueue::queueWithComparator(@selector(compare:));
		for (int key : kKeys)  other->addObject([TestItem itemWithKey:key]);
		OO_CHECK(!queue->isEqual(other.get()));
		OO_CHECK(OOPriorityQueue::queueWithComparator(@selector(compare:))->isEqual(OOPriorityQueue::queueWithComparator(@selector(compareDescending:)).get()));	// both empty

		// A copy is independent.
		copy->removeNextObject();
		OO_CHECK(copy->count() == 10 && queue->count() == 11 && !queue->isEqual(copy.get()));
		copy->addObject([TestItem itemWithKey:-1]);
		OO_CHECK(KeyOf(copy->peekAtNextObject()) == -1 && KeyOf(queue->peekAtNextObject()) == 0);

		// Copying an empty queue.
		oo::Ref<OOPriorityQueue> empty = OOPriorityQueue::queueWithComparator(@selector(compare:))->copy();
		OO_CHECK(empty != nullptr && empty->count() == 0);
		empty->addObject([TestItem itemWithKey:1]);
		OO_CHECK(KeyOf(empty->nextObject()) == 1);
	}
}


OO_TEST(retainsItsObjects)
{
	TestItem *item = [[TestItem alloc] init];
	oo::Ref<OOPriorityQueue> queue = OOPriorityQueue::queueWithComparator(@selector(compare:));
	@autoreleasepool
	{
		queue->addObject(item);
		OO_CHECK([item retainCount] == 2);
		oo::Ref<OOPriorityQueue> copy = queue->copy();
		OO_CHECK([item retainCount] == 3);
		copy = nullptr;
		OO_CHECK([item retainCount] == 2);
		OO_CHECK(queue->nextObject() == item);	// removal autoreleases
		OO_CHECK([item retainCount] == 2);
	}
	OO_CHECK([item retainCount] == 1);
	@autoreleasepool
	{
		queue->addObject(item);
	}
	queue = nullptr;	// releases what it holds
	OO_CHECK([item retainCount] == 1);
	[item release];
}


OO_TEST(addObjectRaises)
{
	@autoreleasepool
	{
		oo::Ref<OOPriorityQueue> queue = OOPriorityQueue::queueWithComparator(@selector(compare:));
		const char *nilName = nullptr;
		@try
		{
			queue->addObject(nil);
		}
		@catch (OOException *e)
		{
			nilName = [e name];
		}
		OO_CHECK(nilName != nullptr && std::strcmp(nilName, OOInvalidArgumentException) == 0);

		const char *reason = nullptr;
		@try
		{
			queue->addObject([[[OOObject alloc] init] autorelease]);
		}
		@catch (OOException *e)
		{
			reason = [e reason];
		}
		OO_CHECK(reason != nullptr && std::string(reason).starts_with("Attempt to insert object (<OOObject: "));
		OO_CHECK(reason != nullptr && std::string(reason).ends_with(") which does not support comparator compare: into OOPriorityQueue."));
		OO_CHECK(queue->count() == 0);
	}
}


OO_TEST_MAIN()
