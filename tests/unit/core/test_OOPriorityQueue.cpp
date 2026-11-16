/*	test_OOPriorityQueue.mm
        Unit tests for OOPriorityQueueOf (src/Core/OOPriorityQueue.h), the
   binary heap over C++ elements that the timer queue (OOScriptTimer) holds. The
   expected orders are literals measured from a reference implementation. Run:
   bash tools/check-core-tests.sh
*/

#include <string>
#include <vector>

#include "OOPriorityQueue.h"
#include "oo_test.hpp"

// MARK: OOPriorityQueueOf
// ------------------------------------------------------

namespace {

// A C++ element: a key it is ordered by, and a tag that tells equal keys apart.
class CxxItem : public oo::RefCounted {
 public:
  CxxItem(int inKey, int inTag) : key(inKey), tag(inTag) {}
  ~CxxItem() override { sLive--; }

  static oo::Ref<CxxItem> make(int key, int tag) {
    sLive++;
    return oo::adopt(new CxxItem(key, tag));
  }

  int key;
  int tag;
  static int sLive;
};

int CxxItem::sLive = 0;

OOComparisonResult CompareCxx(CxxItem* a, CxxItem* b) {
  if (a->key < b->key) return OOOrderedAscending;
  if (a->key > b->key) return OOOrderedDescending;
  return OOOrderedSame;
}

}  // namespace

namespace {

std::string Tags(const std::vector<oo::Ref<CxxItem>>& items) {
  std::string result;
  for (const auto& item : items)
    result += std::to_string(item->key) + "." + std::to_string(item->tag) + " ";
  return result;
}

}  // namespace

OO_TEST(cxxQueueGivesTheSameOrder) {
  {
    oo::AutoreleaseScope pool;
    OOPriorityQueueOf<CxxItem> cxxQueue(CompareCxx);
    OO_CHECK(cxxQueue.count() == 0 && cxxQueue.peekAtNextObject() == nullptr);
    OO_CHECK(cxxQueue.removeNextObject() == nullptr);

    // Many equal keys, so the order among them is the heap's own.
    const int keys[] = {5, 3, 3, 1, 5, 3, 1, 5, 3, 1,
                        0, 3, 5, 1, 3, 0, 5, 3, 1, 5};
    int tag = 0;
    for (int key : keys) {
      cxxQueue.addObject(CxxItem::make(key, tag).get());
      tag++;
    }
    OO_CHECK(cxxQueue.count() == 20);
    OO_CHECK(cxxQueue.peekAtNextObject() != nullptr &&
             cxxQueue.peekAtNextObject()->key == 0);

    // Take a few, put one back, then empty the queue. The expected orders were
    // measured from a reference implementation on the same keys and steps.
    std::vector<oo::Ref<CxxItem>> cxxFirst;
    for (int i = 0; i < 4; i++) {
      cxxFirst.push_back(cxxQueue.removeNextObject());
    }
    OO_CHECK_EQ(Tags(cxxFirst), "0.10 0.15 1.6 1.13 ");
    cxxQueue.addObject(cxxFirst[1].get());
    OO_CHECK_EQ(Tags(cxxQueue.sortedObjects()),
                "0.15 1.9 1.3 1.18 3.2 3.17 3.11 3.14 3.5 3.1 3.8 5.12 5.19 "
                "5.0 5.16 5.4 5.7 ");
    OO_CHECK(cxxQueue.count() == 0);
  }
}

OO_TEST(cxxQueueHoldsAndRemovesByIdentity) {
  CxxItem::sLive = 0;
  {
    oo::AutoreleaseScope pool;
    OOPriorityQueueOf<CxxItem> queue(CompareCxx);
    oo::Ref<CxxItem> three = CxxItem::make(3, 0);
    queue.addObject(three.get());
    queue.addObject(three.get());
    queue.addObject(CxxItem::make(3, 1).get());  // held by the queue alone
    queue.addObject(CxxItem::make(1, 2).get());
    queue.addObject(nullptr);  // ignored
    OO_CHECK(queue.count() == 4);
    OO_CHECK_EQ(CxxItem::sLive, 3);

    // The search goes on past a match, so the element moved into the removed
    // one's place is not looked at again, whatever that leaves. The count was
    // measured from a reference implementation on the same steps.
    queue.removeExactObject(three.get());
    OO_CHECK(queue.count() < 4);
    OO_CHECK(queue.count() == 3);
    queue.removeExactObject(nullptr);
    OO_CHECK(queue.count() == 3);
    {
      oo::Ref<CxxItem> next =
          queue.removeNextObject();  // the caller now holds it
      OO_CHECK(next != nullptr && next->key == 1);
      OO_CHECK_EQ(CxxItem::sLive, 3);
    }
    OO_CHECK_EQ(CxxItem::sLive, 2);
  }
  OO_CHECK_EQ(CxxItem::sLive, 0);  // the queue releases what it holds
}

OO_TEST_MAIN()
