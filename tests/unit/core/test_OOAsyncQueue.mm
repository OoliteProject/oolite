/*	test_OOAsyncQueue.mm
	Unit tests for OOAsyncQueue (src/Core/OOAsyncQueue.h): bead oo-fo17, a Phase 3 conversion in
	the OOColor house style (proposed ADR-0056). Its only caller, OOAsyncWorkManager.mm, was
	converted with it, so it has no Objective-C facade and the class is global. What it queues
	are still Objective-C objects (the work manager's tasks), retained and released as before.

	Pins what the queue did before the conversion: nil is refused; objects come out first in,
	first out, retained while queued and autoreleased when dequeued; tryDequeue answers nil when
	empty; emptyQueue and destruction release what is left; empty() answers true when there IS
	something queued (its body tests _head != NULL: kept bug for bug); the description
	components; and a consumer blocked in dequeue wakes for a producer on another thread.
	Run: bash tools/check-core-tests.sh
*/

#import "OOAsyncQueue.h"

#include "oo_test.hpp"

#include <thread>
#include <vector>


namespace {

id NewObject()
{
	return [[OOObject alloc] init];
}

}	// namespace


OO_TEST(nilIsRefused)
{
	@autoreleasepool
	{
		oo::Ref<OOAsyncQueue> queue = oo::makeRef<OOAsyncQueue>();
		OO_CHECK(!queue->enqueue(nil));
		OO_CHECK_EQ(queue->count(), 0u);
		OO_CHECK(queue->tryDequeue() == nil);
	}
}


OO_TEST(firstInFirstOut)
{
	id a = NewObject(), b = NewObject(), c = NewObject();
	@autoreleasepool
	{
		oo::Ref<OOAsyncQueue> queue = oo::makeRef<OOAsyncQueue>();
		OO_CHECK(queue->enqueue(a));
		OO_CHECK(queue->enqueue(b));
		OO_CHECK(queue->enqueue(c));
		OO_CHECK_EQ(queue->count(), 3u);
		OO_CHECK_EQ([a retainCount], 2u);	// the queue retains what it holds
		OO_CHECK(queue->dequeue() == a);
		OO_CHECK(queue->tryDequeue() == b);
		OO_CHECK_EQ(queue->count(), 1u);
		OO_CHECK(queue->dequeue() == c);
		OO_CHECK_EQ(queue->count(), 0u);
		OO_CHECK(queue->tryDequeue() == nil);
		OO_CHECK_EQ([a retainCount], 2u);	// dequeued: autoreleased, not yet released
	}
	OO_CHECK_EQ([a retainCount], 1u);
	OO_CHECK_EQ([b retainCount], 1u);
	OO_CHECK_EQ([c retainCount], 1u);
	[a release];
	[b release];
	[c release];
}


OO_TEST(emptyAnswersTrueWhenNotEmpty)
{
	id a = NewObject();
	@autoreleasepool
	{
		oo::Ref<OOAsyncQueue> queue = oo::makeRef<OOAsyncQueue>();
		OO_CHECK(!queue->empty());	// nothing queued: _head == NULL
		queue->enqueue(a);
		OO_CHECK(queue->empty());	// something queued
		queue->emptyQueue();
		OO_CHECK(!queue->empty());
	}
	[a release];
}


OO_TEST(emptyQueueReleasesElements)
{
	id a = NewObject(), b = NewObject();
	@autoreleasepool
	{
		oo::Ref<OOAsyncQueue> queue = oo::makeRef<OOAsyncQueue>();
		// More than the element pool holds, so some elements are freed rather than pooled.
		for (int i = 0; i < 4; i++)  queue->enqueue(a);
		for (int i = 0; i < 4; i++)  queue->enqueue(b);
		OO_CHECK_EQ(queue->count(), 8u);
		OO_CHECK_EQ([a retainCount], 5u);
		queue->emptyQueue();
		OO_CHECK_EQ(queue->count(), 0u);
		OO_CHECK_EQ([a retainCount], 1u);
		OO_CHECK_EQ([b retainCount], 1u);
		OO_CHECK(queue->tryDequeue() == nil);
		// Still usable after emptying, recycling pooled elements.
		OO_CHECK(queue->enqueue(b));
		OO_CHECK(queue->dequeue() == b);
	}
	[a release];
	[b release];
}


OO_TEST(destructionReleasesElements)
{
	id a = NewObject();
	@autoreleasepool
	{
		OOAsyncQueue *queue = new OOAsyncQueue;	// +1, as alloc/init was
		queue->enqueue(a);
		queue->enqueue(a);
		OO_CHECK_EQ([a retainCount], 3u);
		queue->release();	// logs asyncQueue.nonEmpty and flushes
	}
	OO_CHECK_EQ([a retainCount], 1u);
	[a release];
}


OO_TEST(descriptionComponents)
{
	id a = NewObject();
	@autoreleasepool
	{
		oo::Ref<OOAsyncQueue> queue = oo::makeRef<OOAsyncQueue>();
		OO_CHECK(queue->descriptionComponents() == std::optional<std::string>("0 elements"));
		queue->enqueue(a);
		queue->enqueue(a);
		OO_CHECK(queue->descriptionComponents() == std::optional<std::string>("2 elements"));
		queue->emptyQueue();
	}
	[a release];
}


OO_TEST(dequeueWaitsForAProducer)
{
	id a = NewObject(), b = NewObject();
	@autoreleasepool
	{
		oo::Ref<OOAsyncQueue> queue = oo::makeRef<OOAsyncQueue>();
		std::vector<id> received;
		std::thread consumer([&]
		{
			@autoreleasepool
			{
				received.push_back(queue->dequeue());	// blocks until the producer enqueues
				received.push_back(queue->dequeue());
			}
		});
		std::thread producer([&]
		{
			std::this_thread::sleep_for(std::chrono::milliseconds(20));
			queue->enqueue(a);
			queue->enqueue(b);
		});
		producer.join();
		consumer.join();
		OO_CHECK_EQ(received.size(), 2u);
		OO_CHECK(received.size() == 2 && received[0] == a && received[1] == b);
		OO_CHECK_EQ(queue->count(), 0u);
	}
	OO_CHECK_EQ([a retainCount], 1u);
	[a release];
	[b release];
}


OO_TEST_MAIN()
