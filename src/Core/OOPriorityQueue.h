/*

OOPriorityQueue.h

A prority queue is a collection into which objects may be inserted in any
order, but (primarily) extracted in sorted order. The order is defined by the
comparison function specified at creation time, which must define a partial
order on the objects in the priority queue. The behaviour when provided with an
inconsistent comparison function is undefined. (The Objective-C OOPriorityQueue,
which ordered Objective-C objects by a comparator selector, was deleted by bead
oo-4aq6a.3: no game code used it after bead oo-9ht.35.)

The implementation is the standard one, a binary heap. It is described in
detail in most algorithm textbooks.

This collection is *not* thread-safe.


Copyright (C) 2007-2013 Jens Ayton

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

#ifndef OOPRIORITYQUEUE_H
#define OOPRIORITYQUEUE_H

#include "OOFoundation.h" // OOComparisonResult

#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

#include <utility>
#include <vector>

/*	The queue for C++ elements (bead oo-9ht.35, which deleted the OOScriptTimer facade the
        timer queue held): the elements are held by oo::Ref and ordered by a comparator function where
        the Objective-C OOPriorityQueue (deleted by bead oo-4aq6a.3) sent a selector. The heap is the
        Objective-C queue's, step for step (bubbling up on
        insertion; on removal the last element takes the removed one's place and bubbles down; the
        exact-object search goes on past a match), so elements that compare the same come out in the
        same order. Capacity is the vector's. The element type must be complete where it is used.
*/
template <typename T>
class OOPriorityQueueOf {
public:
    using Comparator = OOComparisonResult (*)(T* a, T* b);

    explicit OOPriorityQueueOf(Comparator comparator)
        : _comparator(comparator)
    {
    }

    void addObject(T* object) // null is ignored (OOPriorityQueue raised)
    {
        if (object == nullptr)
            return;
        _heap.emplace_back(object);
        bubbleUpFrom(_heap.size() - 1);
    }

    void removeExactObject(T* object) // pointer comparison; safe from the element's destructor
    {
        if (object == nullptr)
            return;
        for (size_t i = 0; i < _heap.size(); ++i) {
            if (object == _heap[i].get())
                (void)removeObjectAtIndex(i);
        }
    }

    size_t count() const { return _heap.size(); }

    T* peekAtNextObject() const { return _heap.empty() ? nullptr : _heap[0].get(); }

    // Removes the next element and answers it (null when empty), so the caller decides how long
    // it lives (OOPriorityQueue autoreleased it).
    oo::Ref<T> removeNextObject() { return removeObjectAtIndex(0); }

    // The elements in removeNextObject() order; empties the queue.
    std::vector<oo::Ref<T>> sortedObjects()
    {
        std::vector<oo::Ref<T>> result;
        result.reserve(_heap.size());
        while (!_heap.empty())
            result.push_back(removeNextObject());
        return result;
    }

private:
    static size_t LeftChild(size_t n) { return (n << 1) + 1; }
    static size_t RightChild(size_t n) { return (n << 1) + 2; }
    static size_t Parent(size_t n) { return ((n + 1) >> 1) - 1; }

    void bubbleUpFrom(size_t i)
    {
        while (0 < i) {
            const size_t pi = Parent(i);
            if (_comparator(_heap[i].get(), _heap[pi].get()) < 0) {
                std::swap(_heap[i], _heap[pi]);
                i = pi;
            } else
                break;
        }
    }

    void bubbleDownFrom(size_t i)
    {
        const size_t end = _heap.size() - 1;
        while (LeftChild(i) <= end) {
            const size_t li = LeftChild(i);
            const size_t ri = RightChild(i);
            // If left child has lower priority than right child, or there is only one child...
            const size_t next = (li == end || _comparator(_heap[li].get(), _heap[ri].get()) < 0) ? li : ri;
            if (_comparator(_heap[next].get(), _heap[i].get()) < 0) {
                // Exchange parent with lowest-priority child
                std::swap(_heap[i], _heap[next]);
                i = next;
            } else
                break;
        }
    }

    oo::Ref<T> removeObjectAtIndex(size_t i)
    {
        if (_heap.size() <= i)
            return nullptr;
        oo::Ref<T> object = std::move(_heap[i]);
        if (i < _heap.size() - 1) {
            // Overwrite object with last object in array, then push it down until the tree is
            // partially ordered.
            _heap[i] = std::move(_heap.back());
            _heap.pop_back();
            bubbleDownFrom(i);
        } else {
            // Special case: removing last (or only) object. No bubbling needed.
            _heap.pop_back();
        }
        return object;
    }

    Comparator _comparator;
    std::vector<oo::Ref<T>> _heap;
};

#endif // OOPRIORITYQUEUE_H
