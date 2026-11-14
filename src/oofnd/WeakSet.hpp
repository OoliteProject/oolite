/*	oofnd/WeakSet.hpp
        oo::WeakSet<T>: a mutable set of zeroing weak references, the
   replacement for OOWeakSet (src/Core/OOWeakSet.h). Same semantics:

          * When a member object is deallocated it silently leaves the set and
   count() drops. There is no notification, and so no immutable variant.
          * Members are uniqued by object identity (pointer equality), not by
   value.
          * add(nullptr) is silently ignored; remove() of a non-member is not an
   error.
          * Copying yields a set of the currently live members.
          * Not thread-safe: all use on one thread, which must also make the
   members' final releases (OOWeakSet.h states the same contract).

        OOWeakSet method              oo::WeakSet<T>
        ----------------------------
   ----------------------------------------------------------------- -count
   count()          (empty() too) -containsObject:              contains(obj)
        -addObject: / -removeObject:  add(obj) / remove(obj)
        -addObjectsByEnumerating:     addAll(range of T* or std::shared_ptr<T>)
        -allObjects                   allObjects()     (live members, retained,
   as NSArray retained them) -makeObjectsPerformSelector:  forEach(f) (f(T&) for
   each live member) -removeAllObjects             removeAll() -isEqual: ==
   (same live members) -objectEnumerator             allObjects() or forEach()

        One deliberate strengthening: iteration is in insertion order. NSSet's
   order was unspecified (pointer-hash order, so it varied run to run);
   insertion order is deterministic, which can only help the game's integration
   tests.

        forEach() iterates over a retained snapshot, so the callback may add or
   remove members, or drop the last other reference to one, without invalidating
   the iteration (mutating an NSSet during enumeration raised an exception
   instead).
*/

#pragma once

#include <algorithm>
#include <cstddef>
#include <memory>
#include <ranges>
#include <set>
#include <utility>
#include <vector>

#include "oofnd/Object.hpp"

namespace oo {

template <class T>
class WeakSet {
 public:
  WeakSet() = default;
  explicit WeakSet(std::size_t capacityHint) { entries_.reserve(capacityHint); }

  WeakSet(const WeakSet& other) { addLiveFrom(other); }
  WeakSet(WeakSet&&) noexcept = default;
  WeakSet& operator=(const WeakSet& other) {
    if (this != &other) {
      WeakSet copy(other);
      *this = std::move(copy);
    }
    return *this;
  }
  WeakSet& operator=(WeakSet&&) noexcept = default;
  ~WeakSet() = default;

  std::size_t count() const {
    compact();
    return entries_.size();
  }

  bool empty() const { return count() == 0; }

  bool contains(const T* object) const {
    if (object == nullptr) return false;
    compact();
    const Key identity = identityOf(object);
    return !isUnset(identity) && index_.contains(identity);
  }

  void add(T* object) {
    if (object == nullptr) return;
    compact();
    std::weak_ptr<T> weak = share(object);
    if (index_.insert(Key(weak)).second) entries_.push_back(std::move(weak));
  }

  void add(const std::shared_ptr<T>& object) { add(object.get()); }

  void remove(const T* object) {
    if (object == nullptr) return;
    const Key identity = identityOf(object);
    if (isUnset(identity) || index_.erase(identity) == 0) return;
    std::erase_if(entries_, [&identity](const std::weak_ptr<T>& w) {
      return sameObject(w, identity);
    });
  }

  template <std::ranges::input_range R>
  void addAll(R&& range) {
    for (auto&& element : range) add(element);
  }

  void removeAll() noexcept {
    entries_.clear();
    index_.clear();
  }

  // The live members, owned, in insertion order.
  std::vector<std::shared_ptr<T>> allObjects() const {
    std::vector<std::shared_ptr<T>> result;
    result.reserve(entries_.size());
    for (const std::weak_ptr<T>& w : entries_) {
      if (std::shared_ptr<T> strong = w.lock())
        result.push_back(std::move(strong));
    }
    return result;
  }

  // Calls f(T&) on each live member, in insertion order, over an owned
  // snapshot.
  template <class F>
  void forEach(F&& f) const {
    for (const std::shared_ptr<T>& member : allObjects()) f(*member);
  }

  friend bool operator==(const WeakSet& a, const WeakSet& b) {
    if (a.count() != b.count()) return false;
    for (const std::weak_ptr<T>& w : a.entries_) {
      if (!b.index_.contains(Key(w))) return false;
    }
    return true;
  }

 private:
  using Key = std::weak_ptr<const void>;

  // The object's weak identity, empty for an object no shared_ptr owns (which
  // is then never a member). Asking creates no ownership.
  static Key identityOf(const T* object) noexcept {
    return static_cast<const Object*>(object)->weak_from_this();
  }

  // OOWeakSet's -compact: drop entries whose object has gone. Logically const
  // (the set's observable contents already exclude them), hence the mutable
  // members.
  void compact() const {
    auto dead = [](const std::weak_ptr<T>& w) { return w.expired(); };
    if (std::none_of(entries_.begin(), entries_.end(), dead)) return;
    for (const std::weak_ptr<T>& w : entries_) {
      if (w.expired()) index_.erase(Key(w));
    }
    std::erase_if(entries_, dead);
  }

  void addLiveFrom(const WeakSet& other) {
    entries_.reserve(other.entries_.size());
    for (const std::weak_ptr<T>& w : other.entries_) {
      if (!w.expired() && index_.insert(Key(w)).second) entries_.push_back(w);
    }
  }

  // Each member's weak identity, by owner: an entry's weak_ptr keeps its
  // control block alive, so no other object can share it while it is listed.
  mutable std::vector<std::weak_ptr<T>> entries_;
  mutable std::set<Key, std::owner_less<Key>> index_;
};

}  // namespace oo
