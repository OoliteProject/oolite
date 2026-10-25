/*	oofnd/Notification.hpp
	oo::NotificationCenter: the replacement for NSNotificationCenter / NSNotification (bead
	oo-3rb.9, ADR-0029 Decision 5). Named notifications, delivered synchronously to the observers
	whose (name, object) filter matches, on the posting thread, in registration order.

	    Foundation                                        oofnd
	    ------------------------------------------------  -----------------------------------------
	    [NSNotificationCenter defaultCenter]              oo::NotificationCenter::defaultCenter()
	    [nc addObserver:self selector:@selector(m)        nc.addObserver(self, name, obj,
	                name:n object:obj]                        [self](const oo::Notification&)
	                                                          { [self m]; })
	    [nc addObserverForName:n object:obj queue:nil     auto token = nc.addObserver(nullptr, n,
	                usingBlock:b]                             obj, f)     (remove with the token)
	    [nc removeObserver:self name:n object:obj]        nc.removeObserver(self, n, obj)
	    [nc removeObserver:self]                          nc.removeObserver(self)
	    [nc removeObserver:token]                         nc.removeObserver(token)
	    [nc postNotificationName:n object:obj]            nc.post(n, obj)
	    [notification name] / [notification object]      notification.name / notification.object
	    NSString * const kFooNotification                 inline constexpr char kFoo[] / const char *

	SEMANTICS, each as NSNotificationCenter has them:

	  * A name is a string compared by value (NSString -isEqual:). An empty name when adding
	    observes every notification; when removing it matches every name.
	  * The object is an identity (a pointer, typically an Objective-C id cast to const void *).
	    nullptr when adding observes posts from any object; when removing it matches any object.
	    It is never dereferenced, retained or compared by value.
	  * The observer pointer is an identity only (NSNotificationCenter does not retain its
	    observers either). An observer must remove itself before it is destroyed, exactly as the
	    game's -dealloc methods already do. A callback may capture it; it is not retained.
	  * post() calls the matching callbacks synchronously, on the calling thread, in registration
	    order. The set of observers is taken when the post starts: an observer added during a
	    post is not called by that post; an observer removed during a post (by itself or by an
	    earlier callback) is not called after its removal. Nested posts are allowed.
	  * Registering the same (observer, name, object) twice delivers twice, as
	    NSNotificationCenter does; one removeObserver(observer, name, object) removes both.
	  * Thread-safe: registration, removal and posting may happen on any thread. No lock is held
	    while a callback runs, so a callback may add, remove or post.
	  * There is no userInfo: no call site in the game posts one.
*/

#ifndef OOFND_NOTIFICATION_HPP
#define OOFND_NOTIFICATION_HPP

// Objective-C++ game code includes this after OOCocoa.h, whose `#define true 1` / `#define false 0`
// break the standard headers' keywords. Suspend the macros here (proposed ADR-0028, Data.hpp).
#pragma push_macro("true")
#pragma push_macro("false")
#undef true
#undef false

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace oo {

// What a callback receives: the name and object the notification was posted with.
struct Notification
{
	std::string_view name;
	const void* object = nullptr;
};

class NotificationCenter
{
public:
	using Callback = std::function<void(const Notification&)>;
	using Token = std::uint64_t;   // 0 is never a valid token

	NotificationCenter() = default;
	NotificationCenter(const NotificationCenter&) = delete;
	NotificationCenter& operator=(const NotificationCenter&) = delete;

	// The process-wide center, as +[NSNotificationCenter defaultCenter].
	static NotificationCenter& defaultCenter()
	{
		// Immortal (bead oo-9ht.173): an object freed by a pool drained at thread detach, after the
		// CRT's static destructors, may still remove its observers here.
		static NotificationCenter& center = *new NotificationCenter;
		return center;
	}

	// Registers callback for notifications named `name` (empty: all) posted by `object`
	// (nullptr: any). `observer` is the identity removeObserver(observer, ...) matches; it may be
	// nullptr for a registration that is only ever removed by its token.
	Token addObserver(const void* observer, std::string_view name, const void* object, Callback callback)
	{
		auto entry = std::make_shared<Entry>();
		entry->observer = observer;
		entry->name = std::string(name);
		entry->object = object;
		entry->callback = std::move(callback);
		std::lock_guard<std::mutex> lock(mutex_);
		entry->token = ++lastToken_;
		entries_.push_back(entry);
		return entry->token;
	}

	// Removes the one registration `token` names. An unknown or already removed token is a no-op.
	void removeObserver(Token token)
	{
		removeIf([token](const Entry& e) { return e.token == token; });
	}

	// Removes every registration of `observer`.
	void removeObserver(const void* observer)
	{
		if (observer == nullptr)  return;
		removeIf([observer](const Entry& e) { return e.observer == observer; });
	}

	// Removes observer's registrations for `name` (empty: any name) and `object` (nullptr: any).
	void removeObserver(const void* observer, std::string_view name, const void* object)
	{
		if (observer == nullptr)  return;
		removeIf([&](const Entry& e)
		{
			return e.observer == observer
				&& (name.empty() || e.name == name)
				&& (object == nullptr || e.object == object);
		});
	}

	// Delivers {name, object} to every matching observer registered when the post starts.
	void post(std::string_view name, const void* object)
	{
		std::vector<std::shared_ptr<Entry>> targets;
		{
			std::lock_guard<std::mutex> lock(mutex_);
			for (const auto& e : entries_)
			{
				if ((e->name.empty() || e->name == name) && (e->object == nullptr || e->object == object))
				{
					targets.push_back(e);
				}
			}
		}
		const Notification notification { name, object };
		for (const auto& e : targets)
		{
			{
				std::lock_guard<std::mutex> lock(mutex_);
				if (e->removed)  continue;
			}
			e->callback(notification);
		}
	}

	// Number of live registrations (for tests and diagnostics).
	std::size_t observerCount() const
	{
		std::lock_guard<std::mutex> lock(mutex_);
		return entries_.size();
	}

private:
	struct Entry
	{
		Token token = 0;
		const void* observer = nullptr;
		std::string name;
		const void* object = nullptr;
		Callback callback;
		bool removed = false;   // guarded by mutex_; a snapshot in post() checks it
	};

	template <class Pred>
	void removeIf(Pred pred)
	{
		std::vector<std::shared_ptr<Entry>> dropped;   // callbacks are destroyed outside the lock
		{
			std::lock_guard<std::mutex> lock(mutex_);
			auto keep = std::stable_partition(entries_.begin(), entries_.end(),
				[&](const std::shared_ptr<Entry>& e) { return !pred(*e); });
			for (auto it = keep; it != entries_.end(); ++it)
			{
				(*it)->removed = true;
				dropped.push_back(std::move(*it));
			}
			entries_.erase(keep, entries_.end());
		}
	}

	mutable std::mutex mutex_;
	std::vector<std::shared_ptr<Entry>> entries_;   // registration order
	Token lastToken_ = 0;
};

} // namespace oo

#pragma pop_macro("false")
#pragma pop_macro("true")

#endif // OOFND_NOTIFICATION_HPP
