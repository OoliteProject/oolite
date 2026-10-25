/*	oofnd/WeakSet.hpp
	oo::WeakSet<T>: a mutable set of zeroing weak references, the replacement for OOWeakSet
	(src/Core/OOWeakSet.h). Same semantics:

	  * When a member object is deallocated it silently leaves the set and count() drops. There
	    is no notification, and so no immutable variant.
	  * Members are uniqued by object identity (pointer equality), not by value.
	  * add(nullptr) is silently ignored; remove() of a non-member is not an error.
	  * Copying yields a set of the currently live members.
	  * Not thread-safe: all use on one thread, which must also make the members' final
	    releases (OOWeakSet.h states the same contract; see oofnd/Ref.hpp).

	OOWeakSet method              oo::WeakSet<T>
	----------------------------  -----------------------------------------------------------------
	-count                        count()          (empty() too)
	-containsObject:              contains(obj)
	-addObject: / -removeObject:  add(obj) / remove(obj)
	-addObjectsByEnumerating:     addAll(range of T* or oo::Ref<T>)
	-allObjects                   allObjects()     (live members, retained, as NSArray retained them)
	-makeObjectsPerformSelector:  forEach(f)       (f(T&) for each live member)
	-removeAllObjects             removeAll()
	-isEqual:                     ==               (same live members)
	-objectEnumerator             allObjects() or forEach()

	One deliberate strengthening: iteration is in insertion order. NSSet's order was unspecified
	(pointer-hash order, so it varied run to run); insertion order is deterministic, which can
	only help the golden runs.

	forEach() iterates over a retained snapshot, so the callback may add or remove members, or
	drop the last other reference to one, without invalidating the iteration (mutating an NSSet
	during enumeration raised an exception instead).
*/

#ifndef OOFND_WEAKSET_HPP
#define OOFND_WEAKSET_HPP

#include "oofnd/Ref.hpp"

#include <algorithm>
#include <cstddef>
#include <ranges>
#include <unordered_set>
#include <utility>
#include <vector>

namespace oo {

template <class T>
class WeakSet
{
public:
	WeakSet() = default;
	explicit WeakSet(std::size_t capacityHint)
	{
		entries_.reserve(capacityHint);
		index_.reserve(capacityHint);
	}

	WeakSet(const WeakSet& other) { addLiveFrom(other); }
	WeakSet(WeakSet&&) noexcept = default;
	WeakSet& operator=(const WeakSet& other)
	{
		if (this != &other)
		{
			WeakSet copy(other);
			*this = std::move(copy);
		}
		return *this;
	}
	WeakSet& operator=(WeakSet&&) noexcept = default;
	~WeakSet() = default;

	std::size_t count() const
	{
		compact();
		return entries_.size();
	}

	bool empty() const { return count() == 0; }

	bool contains(const T* object) const
	{
		if (object == nullptr)  return false;
		compact();
		const detail::WeakControl* ctl = detail::WeakAccess::existingControl(object);
		return ctl != nullptr && index_.contains(ctl);
	}

	void add(T* object)
	{
		if (object == nullptr)  return;
		compact();
		WeakRef<T> weak(object);
		if (index_.insert(weak.ctl_).second)  entries_.push_back(std::move(weak));
	}

	void add(const Ref<T>& object) { add(object.get()); }

	void remove(const T* object)
	{
		if (object == nullptr)  return;
		const detail::WeakControl* ctl = detail::WeakAccess::existingControl(object);
		if (ctl == nullptr || index_.erase(ctl) == 0)  return;
		std::erase_if(entries_, [ctl](const WeakRef<T>& w) { return w.ctl_ == ctl; });
	}

	template <std::ranges::input_range R>
	void addAll(R&& range)
	{
		for (auto&& element : range)  add(element);
	}

	void removeAll() noexcept
	{
		entries_.clear();
		index_.clear();
	}

	// The live members, retained, in insertion order.
	std::vector<Ref<T>> allObjects() const
	{
		std::vector<Ref<T>> result;
		result.reserve(entries_.size());
		for (const WeakRef<T>& w : entries_)
		{
			if (Ref<T> strong = w.lock())  result.push_back(std::move(strong));
		}
		return result;
	}

	// Calls f(T&) on each live member, in insertion order, over a retained snapshot.
	template <class F>
	void forEach(F&& f) const
	{
		for (const Ref<T>& member : allObjects())  f(*member);
	}

	friend bool operator==(const WeakSet& a, const WeakSet& b)
	{
		if (a.count() != b.count())  return false;
		for (const WeakRef<T>& w : a.entries_)
		{
			if (!b.index_.contains(w.ctl_))  return false;
		}
		return true;
	}

private:
	// OOWeakSet's -compact: drop entries whose object has gone. Logically const (the set's
	// observable contents already exclude them), hence the mutable members.
	void compact() const
	{
		auto dead = [](const WeakRef<T>& w) { return w.expired(); };
		if (std::none_of(entries_.begin(), entries_.end(), dead))  return;
		for (const WeakRef<T>& w : entries_)
		{
			if (w.expired())  index_.erase(w.ctl_);
		}
		std::erase_if(entries_, dead);
	}

	void addLiveFrom(const WeakSet& other)
	{
		entries_.reserve(other.entries_.size());
		for (const WeakRef<T>& w : other.entries_)
		{
			if (!w.expired() && index_.insert(w.ctl_).second)  entries_.push_back(w);
		}
	}

	// Each entry's WeakRef keeps its control block alive, so a control pointer in index_ can
	// never be reused by another object while it is listed.
	mutable std::vector<WeakRef<T>> entries_;
	mutable std::unordered_set<const detail::WeakControl*> index_;
};

} // namespace oo

#endif // OOFND_WEAKSET_HPP
