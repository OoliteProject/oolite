/*	oofnd/Ref.hpp
	Intrusive reference counting that mirrors Objective-C's retain/release/autorelease 1:1
	(ADR-0003; docs/architecture.md §3.4-3.5). Replaces NSObject's refcount contract,
	the Foundation autorelease pool and OOWeakReference; oofnd/WeakSet.hpp replaces OOWeakSet.

	    Objective-C (manual retain/release)       oofnd
	    ----------------------------------------  -------------------------------------------------
	    @interface Foo : NSObject                 class Foo : public oo::RefCounted
	    [[Foo alloc] init]           (+1)         new Foo            (+1; count starts at 1)
	    [x retain]  /  [x release]                x->retain()  /  x->release()
	    [x retain] / [x release] where x may be   oo::retain(x)  /  oo::release(x)   (null-safe,
	        nil (messaging nil is a no-op)                                             as nil is)
	    [x autorelease]                           oo::autorelease(x)  (consumes the caller's +1)
	    [x retainCount]                           x->retainCount()
	    Foo *strongIvar (retained by a setter)    oo::Ref<Foo> strongIvar
	    [[[Foo alloc] init] autorelease] kept     oo::makeRef<Foo>(...)  (adopts the +1)
	    obj returned OO_RETURNS_RETAINED          oo::adopt(obj)  /  ref.leakRef()
	    thing = [aThing weakRetain]               oo::WeakRef<Thing> thing = aThing
	    [thing weakRefUnderlyingObject]           thing.get()   (nullptr once aThing is gone)
	    [thing frob] via the proxy (nil-safe)     if (oo::Ref<Thing> t = thing.lock())  t->frob();
	    pool = [[<autorelease pool> alloc] init] oo::AutoreleaseScope scope;
	    [p release] / [p drain]                   end of scope   /  scope.drain()

	SEMANTICS (proposed ADR-0026 records the choices ADR-0003 leaves open):

	  * The count starts at 1, like +alloc. `new Foo` is an owning +1 pointer; hand it to
	    oo::adopt() or oo::makeRef() (which adopt), never to Ref's retaining constructor, or the
	    object leaks. Ref<T>(T*) RETAINS, like assigning through a retaining setter.
	  * When the count reaches 0 the object's weak references are zeroed FIRST, then it is deleted
	    through its virtual destructor (-dealloc). So no WeakRef can reach an object whose
	    destructor has started: stricter than OOWeakReference, whose proxy kept forwarding until
	    the root class's -dealloc ran (the ARC-weak behaviour, and the only safe one in C++).
	  * CYCLES ARE NOT COLLECTED. Two objects that hold Refs to each other are never freed, exactly
	    as two ObjC objects that retain each other are not. Break cycles with WeakRef, which is
	    what the OOWeakReference edges in today's entity graph already do (ADR-0003).
	  * AutoreleaseScope follows the game's autorelease pool, which on this toolchain is libobjc2's
	    (ADR-0029 measurement 3): per-thread, nested, the innermost scope receives autoreleased
	    objects, draining releases them LAST-IN-FIRST-OUT (ADR-0045, superseding ADR-0026 point 4's
	    insertion order), and an object autoreleased *while* draining is pushed on top and so is
	    released next, before the older objects still pending (libobjc2's emptyPool). oo::autorelease() with no scope
	    on the thread leaks the object (GNUstep's behaviour) and is counted in
	    AutoreleaseScope::leakedWithoutScope(). Scopes must end in LIFO order on the thread that
	    opened them; anything else is a programming error and aborts.

	THREAD SAFETY (ADR-0003 makes only the count atomic; this header keeps exactly that):

	  * retain()/release(), and so copying and destroying Ref<T>, are thread-safe (atomic count),
	    as NSObject's are. The final release runs the destructor on whichever thread made it.
	  * WeakRef creation, get(), lock() and expired() on a given object, and every WeakSet, must
	    stay on one thread, which must also be the thread that makes the object's final release -
	    the contract OOWeakReference and OOWeakSet have today (OOWeakSet.h says so). The weak
	    control block's own count is atomic, so a WeakRef handle may be copied or destroyed on any
	    thread; only dereferencing it is confined.
	  * AutoreleaseScope is per-thread by construction (thread_local scope stack).
*/

#ifndef OOFND_REF_HPP
#define OOFND_REF_HPP

#include <atomic>
#include <compare>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <functional>
#include <type_traits>
#include <utility>
#include <vector>

namespace oo {

class RefCounted;
class AutoreleaseScope;
template <class T> class Ref;
template <class T> class WeakRef;
template <class T> class WeakSet;

namespace detail {

// The zeroing weak-reference control block: the C++ shape of OOWeakReference's proxy. One per
// object, created lazily by the first WeakRef (as -weakRetain created weakSelf lazily), owned
// jointly by the object (one count) and by every WeakRef to it. The object clears object_ when
// its count reaches zero, before its destructor runs.
class WeakControl
{
public:
	explicit WeakControl(const RefCounted* object) noexcept : object_(object) {}
	WeakControl(const WeakControl&) = delete;
	WeakControl& operator=(const WeakControl&) = delete;

	void retain() noexcept { count_.fetch_add(1, std::memory_order_relaxed); }
	void release() noexcept
	{
		if (count_.fetch_sub(1, std::memory_order_acq_rel) == 1)  delete this;
	}

	const RefCounted* object() const noexcept { return object_; }

private:
	friend class oo::RefCounted;
	~WeakControl() = default;

	std::atomic<std::uint32_t> count_{1};   // the object's own reference
	const RefCounted* object_;
};

struct WeakAccess;
inline void autoreleaseObject(const RefCounted* object) noexcept;

} // namespace detail

// --- RefCounted --------------------------------------------------------------------------------

class RefCounted
{
public:
	void retain() const noexcept { rc_.fetch_add(1, std::memory_order_relaxed); }

	void release() const noexcept
	{
		if (rc_.fetch_sub(1, std::memory_order_acq_rel) == 1)  dispose();
	}

	// -retainCount. For tests and diagnostics only, as in Objective-C: under concurrency the
	// value is stale as soon as it is read.
	std::uint32_t retainCount() const noexcept { return rc_.load(std::memory_order_relaxed); }

protected:
	RefCounted() noexcept = default;

	// Copying an object (the translation of -copyWithZone:) gives a NEW object with its own
	// count of 1 and no weak references; assignment leaves the count and weak references alone.
	RefCounted(const RefCounted&) noexcept {}
	RefCounted& operator=(const RefCounted&) noexcept { return *this; }

	virtual ~RefCounted()
	{
		// Only reached with weak_ set if the object was destroyed without going through
		// release() (e.g. a stack instance of a subclass); zero the weak refs regardless.
		dropWeakControl();
	}

	// Zeroes the object's weak references now, while it is still alive: for an object whose
	// identity dies before its count reaches zero (an entity's C++ part, whose Objective-C object
	// dropped its weak reference at the start of its -dealloc). A WeakRef made afterwards gets a new
	// control block, as a -weakRetain after -weakRefDrop got a new proxy.
	void dropWeakReferences() const noexcept { dropWeakControl(); }

	// The part of -dealloc that ran while the object was still whole, before [super dealloc]: called
	// once, when the count reaches zero, before the weak references are zeroed and the object is
	// deleted (bead oo-dpyk8: the entity's facade's -dealloc body). The count reads 1 while it runs,
	// so a balanced retain and release inside it do not dispose again; a retain it leaves unbalanced
	// would resurrect an object whose -dealloc has run, a programming error, and aborts.
	virtual void willDispose() noexcept {}

private:
	friend struct detail::WeakAccess;

	void dispose() const noexcept
	{
		rc_.store(1, std::memory_order_relaxed);
		const_cast<RefCounted*>(this)->willDispose();
		if (rc_.fetch_sub(1, std::memory_order_acq_rel) != 1)  std::abort();
		dropWeakControl();   // weak refs read nullptr before any destructor body runs
		delete this;
	}

	void dropWeakControl() const noexcept
	{
		if (detail::WeakControl* w = weak_)
		{
			weak_ = nullptr;
			w->object_ = nullptr;
			w->release();
		}
	}

	detail::WeakControl* weakControl() const
	{
		if (weak_ == nullptr)  weak_ = new detail::WeakControl(this);
		return weak_;
	}

	mutable std::atomic<std::uint32_t> rc_{1};
	mutable detail::WeakControl* weak_ = nullptr;   // replaces OOWeakReference *weakSelf
};

namespace detail {

struct WeakAccess
{
	static WeakControl* controlFor(const RefCounted* object) { return object->weakControl(); }
	static WeakControl* existingControl(const RefCounted* object) noexcept { return object->weak_; }
};

} // namespace detail

// --- Ref<T> ------------------------------------------------------------------------------------

// A strong reference: retains on copy and on construction from a raw pointer, releases on
// destruction, steals on move. Nullable, like an Objective-C object pointer. T may be incomplete
// where a Ref<T> is only declared (an ivar of a forward-declared class), as long as it is
// complete wherever a Ref<T> is created, copied or destroyed.
template <class T>
class Ref
{
public:
	using element_type = T;

	constexpr Ref() noexcept = default;
	constexpr Ref(std::nullptr_t) noexcept {}

	// Retains. For an owning +1 pointer (new, a copy, OO_RETURNS_RETAINED) use oo::adopt().
	explicit Ref(T* object) noexcept : ptr_(object)
	{
		if (ptr_ != nullptr)  ptr_->retain();
	}

	Ref(const Ref& other) noexcept : ptr_(other.ptr_)
	{
		if (ptr_ != nullptr)  ptr_->retain();
	}

	Ref(Ref&& other) noexcept : ptr_(std::exchange(other.ptr_, nullptr)) {}

	template <class U>
		requires std::is_convertible_v<U*, T*>
	Ref(const Ref<U>& other) noexcept : ptr_(other.get())
	{
		if (ptr_ != nullptr)  ptr_->retain();
	}

	template <class U>
		requires std::is_convertible_v<U*, T*>
	Ref(Ref<U>&& other) noexcept : ptr_(other.leakRef()) {}

	~Ref()
	{
		if (ptr_ != nullptr)  ptr_->release();
	}

	// Assignment installs the new object before releasing the old one, like a retaining setter
	// ([new retain]; [old release]), so a destructor triggered by the release sees the new value.
	Ref& operator=(const Ref& other) noexcept
	{
		Ref(other).swap(*this);
		return *this;
	}

	Ref& operator=(Ref&& other) noexcept
	{
		Ref(std::move(other)).swap(*this);
		return *this;
	}

	template <class U>
		requires std::is_convertible_v<U*, T*>
	Ref& operator=(const Ref<U>& other) noexcept
	{
		Ref(other).swap(*this);
		return *this;
	}

	template <class U>
		requires std::is_convertible_v<U*, T*>
	Ref& operator=(Ref<U>&& other) noexcept
	{
		Ref(std::move(other)).swap(*this);
		return *this;
	}

	Ref& operator=(std::nullptr_t) noexcept
	{
		reset();
		return *this;
	}

	void reset() noexcept { Ref().swap(*this); }
	void reset(T* object) noexcept { Ref(object).swap(*this); }   // retains, like the constructor
	void swap(Ref& other) noexcept { std::swap(ptr_, other.ptr_); }

	T* get() const noexcept { return ptr_; }
	T& operator*() const noexcept { return *ptr_; }
	T* operator->() const noexcept { return ptr_; }
	explicit operator bool() const noexcept { return ptr_ != nullptr; }

	// Gives up ownership without releasing: the caller now owns the +1 (a method that returns a
	// retained object, or oo::autorelease(std::move(ref))).
	[[nodiscard]] T* leakRef() noexcept { return std::exchange(ptr_, nullptr); }

	// Takes over an owning +1 pointer without retaining it.
	[[nodiscard]] static Ref adopt(T* object) noexcept
	{
		Ref result;
		result.ptr_ = object;
		return result;
	}

private:
	T* ptr_ = nullptr;
};

template <class T, class U>
bool operator==(const Ref<T>& a, const Ref<U>& b) noexcept { return a.get() == b.get(); }
template <class T, class U>
bool operator==(const Ref<T>& a, const U* b) noexcept { return a.get() == b; }
template <class T>
bool operator==(const Ref<T>& a, std::nullptr_t) noexcept { return a.get() == nullptr; }
template <class T, class U>
std::strong_ordering operator<=>(const Ref<T>& a, const Ref<U>& b) noexcept
{
	return std::compare_three_way{}(a.get(), b.get());
}

template <class T>
void swap(Ref<T>& a, Ref<T>& b) noexcept { a.swap(b); }

template <class T>
[[nodiscard]] Ref<T> adopt(T* object) noexcept { return Ref<T>::adopt(object); }

// [[T alloc] init...]: a new object owned by the returned Ref (count 1).
template <class T, class... Args>
[[nodiscard]] Ref<T> makeRef(Args&&... args) { return Ref<T>::adopt(new T(std::forward<Args>(args)...)); }

// Null-safe retain/release, for translating messages to a pointer that may be nil.
template <class T>
T* retain(T* object) noexcept
{
	if (object != nullptr)  object->retain();
	return object;
}

template <class T>
void release(T* object) noexcept
{
	if (object != nullptr)  object->release();
}

// [object autorelease]: hands the caller's +1 to the innermost AutoreleaseScope on this thread,
// which releases it when it drains. Null-safe. Returns object, like -autorelease.
template <class T>
T* autorelease(T* object) noexcept
{
	static_assert(std::is_base_of_v<RefCounted, T>, "oo::autorelease requires an oo::RefCounted subclass");
	if (object != nullptr)  detail::autoreleaseObject(object);
	return object;
}

// return [[x retain] autorelease]: autorelease the reference a Ref owns.
template <class T>
T* autorelease(Ref<T>&& ref) noexcept { return autorelease(ref.leakRef()); }

// --- WeakRef<T> --------------------------------------------------------------------------------

// A zeroing weak reference: does not keep the object alive, and reads as null once the object's
// count has reached zero. Identity (==, hashing) is the identity of the referenced object, and
// survives its death, as an OOWeakReference proxy's did.
template <class T>
class WeakRef
{
public:
	using element_type = T;

	constexpr WeakRef() noexcept = default;
	constexpr WeakRef(std::nullptr_t) noexcept {}

	WeakRef(T* object) : ptr_(object)
	{
		static_assert(std::is_base_of_v<RefCounted, T>, "oo::WeakRef requires an oo::RefCounted subclass");
		if (object != nullptr)
		{
			ctl_ = detail::WeakAccess::controlFor(object);
			ctl_->retain();
		}
	}

	WeakRef(const Ref<T>& strong) : WeakRef(strong.get()) {}

	WeakRef(const WeakRef& other) noexcept : ctl_(other.ctl_), ptr_(other.ptr_)
	{
		if (ctl_ != nullptr)  ctl_->retain();
	}

	WeakRef(WeakRef&& other) noexcept
		: ctl_(std::exchange(other.ctl_, nullptr)), ptr_(std::exchange(other.ptr_, nullptr)) {}

	template <class U>
		requires std::is_convertible_v<U*, T*>
	WeakRef(const WeakRef<U>& other) noexcept : ctl_(other.ctl_), ptr_(other.ptr_)
	{
		if (ctl_ != nullptr)  ctl_->retain();
	}

	template <class U>
		requires std::is_convertible_v<U*, T*>
	WeakRef(WeakRef<U>&& other) noexcept
		: ctl_(std::exchange(other.ctl_, nullptr)), ptr_(std::exchange(other.ptr_, nullptr)) {}

	~WeakRef()
	{
		if (ctl_ != nullptr)  ctl_->release();
	}

	WeakRef& operator=(const WeakRef& other) noexcept
	{
		WeakRef(other).swap(*this);
		return *this;
	}

	WeakRef& operator=(WeakRef&& other) noexcept
	{
		WeakRef(std::move(other)).swap(*this);
		return *this;
	}

	WeakRef& operator=(std::nullptr_t) noexcept
	{
		reset();
		return *this;
	}

	void reset() noexcept { WeakRef().swap(*this); }

	void swap(WeakRef& other) noexcept
	{
		std::swap(ctl_, other.ctl_);
		std::swap(ptr_, other.ptr_);
	}

	// -weakRefUnderlyingObject: the object, unretained, or nullptr once it has gone.
	T* get() const noexcept { return expired() ? nullptr : ptr_; }

	// A strong reference to the object, or a null Ref once it has gone. Use this, not get(),
	// whenever the object must survive the call being made on it.
	Ref<T> lock() const noexcept { return Ref<T>(get()); }

	bool expired() const noexcept { return ctl_ == nullptr || ctl_->object() == nullptr; }

	friend bool operator==(const WeakRef& a, const WeakRef& b) noexcept { return a.ctl_ == b.ctl_; }

	// Does this refer to object? Never creates a control block, and never mistakes a new object
	// allocated at a dead referent's address for the referent.
	friend bool operator==(const WeakRef& a, const T* object) noexcept
	{
		return a.ctl_ != nullptr && object != nullptr && detail::WeakAccess::existingControl(object) == a.ctl_;
	}

	// Hash of the object's identity; stable across the object's death.
	std::size_t hash() const noexcept { return std::hash<const void*>{}(ctl_); }

private:
	template <class> friend class WeakRef;
	template <class> friend class WeakSet;

	detail::WeakControl* ctl_ = nullptr;
	T* ptr_ = nullptr;   // meaningful only while ctl_->object() is non-null
};

// --- AutoreleaseScope --------------------------------------------------------------------------

namespace detail {

inline thread_local AutoreleaseScope* tInnermostScope = nullptr;
inline thread_local std::size_t tLeakedWithoutScope = 0;

} // namespace detail

// The Foundation autorelease pool as a stack-only RAII scope. See the banner for the semantics.
class AutoreleaseScope
{
public:
	AutoreleaseScope() noexcept : parent_(detail::tInnermostScope) { detail::tInnermostScope = this; }

	~AutoreleaseScope()
	{
		if (detail::tInnermostScope != this)  std::abort();   // not LIFO, or not this thread
		drain();
		detail::tInnermostScope = parent_;
	}

	AutoreleaseScope(const AutoreleaseScope&) = delete;
	AutoreleaseScope& operator=(const AutoreleaseScope&) = delete;
	static void* operator new(std::size_t) = delete;
	static void* operator new[](std::size_t) = delete;

	// Releases everything autoreleased into this scope so far, newest first, including objects
	// autoreleased by those releases (each lands on top and is released next), exactly as
	// libobjc2's objc_autoreleasePoolPop does (ADR-0045); the scope stays open. This is the
	// [pool release]; pool = [[<pool class> alloc] init]; idiom in long loops.
	void drain() noexcept
	{
		while (!pending_.empty())
		{
			const RefCounted* object = pending_.back();
			pending_.pop_back();
			object->release();   // may push_back onto pending_; that object is released next
		}
	}

	std::size_t pendingCount() const noexcept { return pending_.size(); }

	// The innermost open scope on this thread, or nullptr.
	static AutoreleaseScope* current() noexcept { return detail::tInnermostScope; }

	// How many objects this thread autoreleased with no scope open (and therefore leaked).
	static std::size_t leakedWithoutScope() noexcept { return detail::tLeakedWithoutScope; }

private:
	friend void detail::autoreleaseObject(const RefCounted* object) noexcept;

	AutoreleaseScope* parent_;
	std::vector<const RefCounted*> pending_;
};

namespace detail {

inline void autoreleaseObject(const RefCounted* object) noexcept
{
	if (AutoreleaseScope* scope = tInnermostScope)  scope->pending_.push_back(object);
	else  ++tLeakedWithoutScope;
}

} // namespace detail

} // namespace oo

template <class T>
struct std::hash<oo::Ref<T>>
{
	std::size_t operator()(const oo::Ref<T>& ref) const noexcept { return std::hash<T*>{}(ref.get()); }
};

template <class T>
struct std::hash<oo::WeakRef<T>>
{
	std::size_t operator()(const oo::WeakRef<T>& ref) const noexcept { return ref.hash(); }
};

#endif // OOFND_REF_HPP
