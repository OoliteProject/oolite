/*	oofnd/Ref.hpp
        The transitional bridge (spec 009, contracts/ownership.md): the names
   of the old intrusive reference counting (oo::RefCounted, oo::Ref<T>,
   oo::WeakRef<T>, retain/release/autorelease) kept over the standard types,
   so that the game builds and passes while its callers move to
   std::shared_ptr and std::weak_ptr. The bridge is deleted last.

        Objective-C (manual retain/release)     oofnd
        [[Foo alloc] init]          (+1)        new Foo  (+1: one manual hold)
        [x retain] / [x release]                x->retain() / x->release()
        [x autorelease]                         oo::autorelease(x)
        Foo *strongIvar                         oo::Ref<Foo> (a std::shared_ptr)
        [[[Foo alloc] init] autorelease] kept   oo::makeRef<Foo>(...)
        OO_RETURNS_RETAINED                     oo::adopt(obj) / ref.leakRef()
        [aThing weakRetain]                     oo::WeakRef<Thing> (a
   std::weak_ptr)

        SEMANTICS (the old contract, kept):

          * An object made with a bare `new` has no owner yet and counts as held
   once by its creator (a manual hold). The first thing that shares it (a Ref,
   a WeakRef, oo::adopt, oo::autorelease) creates its owning std::shared_ptr,
   with oo::Dispose as the deleter. retain() and release() count manual holds;
   while there is at least one, the object keeps a std::shared_ptr to itself.
   An object that was never shared is disposed by its last release() directly.
          * retainCount() is the owning references (the control block's
   use_count, less the object's own) plus the manual holds.
          * When the last owner goes, oo::Dispose runs willDispose() and deletes
   the object. Weak references are already empty while willDispose() runs (the
   standard behaviour; the old code kept them live until after it, which
   test_ref.cpp:514 recorded, changed with Jon's sign-off). The count reads 1
   in willDispose(), and a balanced retain and release inside it do not dispose
   again; a retain left unbalanced aborts, as before.
          * A WeakRef's identity (==, hashing) survives the object's death, and
   comparing one with an object never creates anything. dropWeakReferences()
   empties every WeakRef to the object now while it lives on; a WeakRef made
   afterwards is a new identity. Each object keeps a small token for this: a
   WeakRef holds a std::weak_ptr to the object and one to its token.
          * CYCLES ARE NOT COLLECTED, as before: break them with WeakRef.
          * AutoreleaseScope is oofnd/AutoreleaseScope.hpp's.

        THREAD SAFETY: the counts are atomic (std::shared_ptr's), and the manual
   holds and the token change under a small striped lock, so retain(),
   release() and copying or destroying a Ref are thread-safe, as before. WeakRef
   dereferencing and every WeakSet stay on one thread, as before.
*/

#pragma once

#include <array>
#include <compare>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <functional>
#include <memory>
#include <mutex>
#include <type_traits>
#include <utility>

#include "oofnd/AutoreleaseScope.hpp"
#include "oofnd/Object.hpp"

namespace oo {

class RefCounted;
template <class T>
class Ref;
template <class T>
class WeakRef;
template <class T>
class WeakSet;

namespace detail {

// The bridge's lock for an object's manual holds and token: one of a fixed set,
// chosen by the object's address, never destroyed.
inline std::mutex& bridgeLock(const void* object) noexcept {
  static auto& locks = *[]() noexcept {
    try {
      return new std::array<std::mutex, 64>();
    } catch (...) {
      std::abort();  // out of memory at the first lock
    }
  }();
  return locks[(reinterpret_cast<std::uintptr_t>(object) >> 4) % locks.size()];
}

struct WeakAccess;
template <class T>
std::shared_ptr<T> bridgeShare(T* object);

}  // namespace detail

// --- RefCounted
// --------------------------------------------------------------------------------

class RefCounted : public Object {
 public:
  void retain() const noexcept {
    std::lock_guard<std::mutex> lock(detail::bridgeLock(this));
    if (disposing()) {
      ++holds_;
      return;
    }
    if (holds_++ == 0 && owned_) self_ = selfShared();
  }

  void release() const noexcept {
    std::shared_ptr<RefCounted> dropped;
    bool disposeNow = false;
    {
      std::lock_guard<std::mutex> lock(detail::bridgeLock(this));
      if (holds_ == 0) std::abort();  // over-released
      if (--holds_ != 0 || disposing()) return;
      if (owned_)
        dropped = std::move(self_);  // may be the last owner: released below
      else
        disposeNow = true;
    }
    if (disposeNow) disposeUnowned();
  }

  // -retainCount. For tests and diagnostics only: stale as soon as read.
  std::uint32_t retainCount() const noexcept {
    std::lock_guard<std::mutex> lock(detail::bridgeLock(this));
    if (disposing()) return 1 + holds_;
    if (!owned_) return holds_;
    const long uses = weak_from_this().use_count();
    return static_cast<std::uint32_t>(uses - (self_ != nullptr ? 1 : 0)) +
           holds_;
  }

 protected:
  RefCounted() noexcept = default;

  // Copying gives a NEW object, held once by its creator and with no weak
  // references; assignment leaves holds and weak references alone.
  RefCounted(const RefCounted& other) noexcept : Object(other) {}
  RefCounted& operator=(const RefCounted&) noexcept { return *this; }

  ~RefCounted() override {
    // An owned object reaches its destructor only through oo::Dispose, with no
    // manual hold left; one left over is a retain unbalanced in willDispose().
    if (owned_ && holds_ != 0) std::abort();
  }

  // Empties the object's weak references now, while it is still alive: for an
  // object whose identity dies before it does. A WeakRef made afterwards is a
  // new identity.
  void dropWeakReferences() const noexcept {
    std::lock_guard<std::mutex> lock(detail::bridgeLock(this));
    token_.reset();
  }

 private:
  friend struct detail::WeakAccess;
  template <class T>
  friend std::shared_ptr<T> detail::bridgeShare(T* object);

  // The last owner has gone (or, never owned, the last release ran) and
  // willDispose() or the destructor is running.
  bool disposing() const noexcept {
    return disposingUnowned_ || (owned_ && weak_from_this().expired());
  }

  std::shared_ptr<RefCounted> selfShared() const {
    return std::static_pointer_cast<RefCounted>(
        const_cast<RefCounted*>(this)->shared_from_this());
  }

  // Under the lock: gives a never-shared object its owner (it has a manual
  // hold, so the owner is kept in self_).
  void ensureOwned() const noexcept {
    if (owned_) return;
    owned_ = true;
    try {
      self_ =
          std::shared_ptr<RefCounted>(const_cast<RefCounted*>(this), Dispose{});
    } catch (...) {
      std::abort();  // out of memory for a control block
    }
  }

  // Under the lock: the object's weak-identity token, made if it has none.
  const std::shared_ptr<const void>& token() const noexcept {
    if (token_ == nullptr) {
      try {
        token_ = std::make_shared<const char>('\0');
      } catch (...) {
        std::abort();
      }
    }
    return token_;
  }

  // The last release of an object that was never shared.
  void disposeUnowned() const noexcept {
    disposingUnowned_ = true;
    const_cast<RefCounted*>(this)->willDispose();
    {
      std::lock_guard<std::mutex> lock(detail::bridgeLock(this));
      if (holds_ != 0) std::abort();  // a retain left unbalanced in willDispose
    }
    delete this;
  }

  mutable std::uint32_t holds_ = 1;  // the manual holds (the +1 of new)
  mutable bool owned_ = false;       // a std::shared_ptr owns it
  mutable bool disposingUnowned_ = false;
  mutable std::shared_ptr<RefCounted> self_;   // kept while holds_ > 0
  mutable std::shared_ptr<const void> token_;  // the weak identity
};

namespace detail {

// An owning std::shared_ptr to object (made on first need). While the object is
// being disposed, a pointer that owns nothing: a balanced use inside
// willDispose() neither keeps it alive nor disposes it again.
template <class T>
std::shared_ptr<T> bridgeShare(T* object) {
  static_assert(std::is_base_of_v<RefCounted, std::remove_const_t<T>>,
                "oo::Ref requires an oo::RefCounted subclass");
  const RefCounted* counted = object;
  std::shared_ptr<RefCounted> owner;
  {
    std::lock_guard<std::mutex> lock(bridgeLock(counted));
    if (counted->disposing())
      return std::shared_ptr<T>(std::shared_ptr<void>(), object);
    counted->ensureOwned();
    owner = counted->selfShared();
  }
  return std::shared_ptr<T>(std::move(owner), object);
}

struct WeakAccess {
  // The object's std::weak_ptr and its current token, made if it has none.
  static std::pair<std::weak_ptr<Object>, std::weak_ptr<const void>> weakParts(
      const RefCounted* object) noexcept {
    std::lock_guard<std::mutex> lock(bridgeLock(object));
    if (object->disposingUnowned_) return {};
    if (!object->disposing()) object->ensureOwned();
    return {const_cast<RefCounted*>(object)->weak_from_this(), object->token()};
  }

  // The object's token if it has one; never makes one.
  static std::shared_ptr<const void> existingToken(
      const RefCounted* object) noexcept {
    std::lock_guard<std::mutex> lock(bridgeLock(object));
    return object->token_;
  }

  // For tests: whether the object has a weak identity yet (null if not).
  static const void* existingControl(const RefCounted* object) noexcept {
    return existingToken(object).get();
  }
};

// Owner-equivalence: the same control block (or both empty).
template <class A, class B>
bool sameOwner(const A& a, const B& b) noexcept {
  return !a.owner_before(b) && !b.owner_before(a);
}

}  // namespace detail

// --- Ref<T>
// ------------------------------------------------------------------------------------

// A strong reference, over a std::shared_ptr<T>. Ref<T>(T*) shares the object
// (as a retaining setter did); an owning +1 pointer goes to oo::adopt().
template <class T>
class Ref {
 public:
  using element_type = T;

  constexpr Ref() noexcept = default;
  constexpr Ref(std::nullptr_t) noexcept {}

  explicit Ref(T* object) noexcept {
    if (object != nullptr) {
      try {
        sp_ = detail::bridgeShare(object);
      } catch (...) {
        std::abort();
      }
    }
  }

  Ref(const Ref& other) noexcept = default;
  Ref(Ref&& other) noexcept = default;

  template <class U>
    requires std::is_convertible_v<U*, T*>
  Ref(const Ref<U>& other) noexcept : sp_(other.shared()) {}

  template <class U>
    requires std::is_convertible_v<U*, T*>
  Ref(Ref<U>&& other) noexcept : sp_(std::move(other).takeShared()) {}

  ~Ref() = default;

  // Assignment installs the new object before releasing the old one, like a
  // retaining setter, so a destructor triggered by the release sees the new
  // value.
  Ref& operator=(const Ref& other) noexcept {
    Ref(other).swap(*this);
    return *this;
  }

  Ref& operator=(Ref&& other) noexcept {
    Ref(std::move(other)).swap(*this);
    return *this;
  }

  template <class U>
    requires std::is_convertible_v<U*, T*>
  Ref& operator=(const Ref<U>& other) noexcept {
    Ref(other).swap(*this);
    return *this;
  }

  template <class U>
    requires std::is_convertible_v<U*, T*>
  Ref& operator=(Ref<U>&& other) noexcept {
    Ref(std::move(other)).swap(*this);
    return *this;
  }

  Ref& operator=(std::nullptr_t) noexcept {
    reset();
    return *this;
  }

  void reset() noexcept { Ref().swap(*this); }
  void reset(T* object) noexcept { Ref(object).swap(*this); }  // shares
  void swap(Ref& other) noexcept { sp_.swap(other.sp_); }

  T* get() const noexcept { return sp_.get(); }
  T& operator*() const noexcept { return *sp_; }
  T* operator->() const noexcept { return sp_.get(); }
  explicit operator bool() const noexcept { return sp_ != nullptr; }

  // Gives up ownership as a manual hold: the caller now owns the +1 (a method
  // that returns a retained object, or oo::autorelease(std::move(ref))).
  [[nodiscard]] T* leakRef() noexcept {
    T* object = sp_.get();
    if (object != nullptr) {
      object->retain();
      sp_.reset();
    }
    return object;
  }

  // Takes over an owning +1 pointer: shares it, then gives back the hold.
  [[nodiscard]] static Ref adopt(T* object) noexcept {
    Ref result(object);
    if (object != nullptr) object->release();
    return result;
  }

  // The bridge's view of the standard type, for code moving to it.
  const std::shared_ptr<T>& shared() const& noexcept { return sp_; }
  std::shared_ptr<T> takeShared() && noexcept { return std::move(sp_); }
  static Ref fromShared(std::shared_ptr<T> shared) noexcept {
    Ref result;
    result.sp_ = std::move(shared);
    return result;
  }

 private:
  std::shared_ptr<T> sp_;
};

template <class T, class U>
bool operator==(const Ref<T>& a, const Ref<U>& b) noexcept {
  return a.get() == b.get();
}
template <class T, class U>
bool operator==(const Ref<T>& a, const U* b) noexcept {
  return a.get() == b;
}
template <class T>
bool operator==(const Ref<T>& a, std::nullptr_t) noexcept {
  return a.get() == nullptr;
}
template <class T, class U>
std::strong_ordering operator<=>(const Ref<T>& a, const Ref<U>& b) noexcept {
  return std::compare_three_way{}(a.get(), b.get());
}

template <class T>
void swap(Ref<T>& a, Ref<T>& b) noexcept {
  a.swap(b);
}

template <class T>
[[nodiscard]] Ref<T> adopt(T* object) noexcept {
  return Ref<T>::adopt(object);
}

// [[T alloc] init...]: a new object owned by the returned Ref (count 1).
template <class T, class... Args>
[[nodiscard]] Ref<T> makeRef(Args&&... args) {
  return Ref<T>::adopt(new T(std::forward<Args>(args)...));
}

// The bridge's oo::makeShared and oo::share for an oo::RefCounted type: a
// RefCounted object counts its creator's +1 and makes its owner on first need,
// so it goes through the bridge (oofnd/Object.hpp's versions are for oo::Object
// types that are off it).
template <class T, class... Args>
  requires std::is_base_of_v<RefCounted, T>
[[nodiscard]] std::shared_ptr<T> makeShared(Args&&... args) {
  return makeRef<T>(std::forward<Args>(args)...).takeShared();
}

template <class T>
  requires std::is_base_of_v<RefCounted, std::remove_const_t<T>>
std::shared_ptr<T> share(T* object) {
  if (object == nullptr) return nullptr;
  return detail::bridgeShare(object);
}

// Null-safe retain/release, for translating messages to a pointer that may be
// nil.
template <class T>
T* retain(T* object) noexcept {
  if (object != nullptr) object->retain();
  return object;
}

template <class T>
void release(T* object) noexcept {
  if (object != nullptr) object->release();
}

// [object autorelease]: hands the caller's +1 to the innermost AutoreleaseScope
// on this thread, which releases it when it drains. Null-safe. Returns object.
// With no scope the +1 is kept forever and counted.
template <class T>
T* autorelease(T* object) noexcept {
  static_assert(std::is_base_of_v<RefCounted, std::remove_const_t<T>>,
                "oo::autorelease requires an oo::RefCounted subclass");
  if (object == nullptr) return object;
  if (AutoreleaseScope::current() == nullptr) {
    ++detail::tLeakedWithoutScope;  // the manual hold is never given back
    return object;
  }
  std::shared_ptr<const void> owner;
  try {
    owner = detail::bridgeShare(object);
  } catch (...) {
    std::abort();
  }
  object->release();  // the hold becomes the scope's owner
  detail::autoreleaseOwner(std::move(owner));
  return object;
}

// return [[x retain] autorelease]: autorelease the reference a Ref owns.
template <class T>
T* autorelease(Ref<T>&& ref) noexcept {
  return autorelease(ref.leakRef());
}

// --- WeakRef<T>
// --------------------------------------------------------------------------------

// A weak reference, over a std::weak_ptr: does not keep the object alive and
// reads as null once the object's last owner has gone (or after
// dropWeakReferences()). Identity (==, hashing) is the object's weak identity,
// and survives its death.
template <class T>
class WeakRef {
 public:
  using element_type = T;

  constexpr WeakRef() noexcept = default;
  constexpr WeakRef(std::nullptr_t) noexcept {}

  WeakRef(T* object) noexcept : ptr_(object) {
    static_assert(std::is_base_of_v<RefCounted, std::remove_const_t<T>>,
                  "oo::WeakRef requires an oo::RefCounted subclass");
    if (object != nullptr) {
      auto parts = detail::WeakAccess::weakParts(object);
      object_ = std::move(parts.first);
      token_ = std::move(parts.second);
    }
  }

  WeakRef(const Ref<T>& strong) noexcept : WeakRef(strong.get()) {}

  WeakRef(const WeakRef& other) noexcept = default;
  WeakRef(WeakRef&& other) noexcept
      : object_(std::move(other.object_)),
        token_(std::move(other.token_)),
        ptr_(std::exchange(other.ptr_, nullptr)) {}

  template <class U>
    requires std::is_convertible_v<U*, T*>
  WeakRef(const WeakRef<U>& other) noexcept
      : object_(other.object_), token_(other.token_), ptr_(other.ptr_) {}

  template <class U>
    requires std::is_convertible_v<U*, T*>
  WeakRef(WeakRef<U>&& other) noexcept
      : object_(std::move(other.object_)),
        token_(std::move(other.token_)),
        ptr_(std::exchange(other.ptr_, nullptr)) {}

  ~WeakRef() = default;

  WeakRef& operator=(const WeakRef& other) noexcept {
    WeakRef(other).swap(*this);
    return *this;
  }

  WeakRef& operator=(WeakRef&& other) noexcept {
    WeakRef(std::move(other)).swap(*this);
    return *this;
  }

  WeakRef& operator=(std::nullptr_t) noexcept {
    reset();
    return *this;
  }

  void reset() noexcept { WeakRef().swap(*this); }

  void swap(WeakRef& other) noexcept {
    object_.swap(other.object_);
    token_.swap(other.token_);
    std::swap(ptr_, other.ptr_);
  }

  // -weakRefUnderlyingObject: the object, unretained, or nullptr once it has
  // gone.
  T* get() const noexcept { return expired() ? nullptr : ptr_; }

  // A strong reference to the object, or a null Ref once it has gone. Use this,
  // not get(), whenever the object must survive the call being made on it.
  Ref<T> lock() const noexcept {
    if (token_.expired()) return Ref<T>();
    std::shared_ptr<Object> owner = object_.lock();
    if (owner == nullptr) return Ref<T>();
    return Ref<T>::fromShared(std::shared_ptr<T>(std::move(owner), ptr_));
  }

  bool expired() const noexcept {
    return token_.expired() || object_.expired();
  }

  friend bool operator==(const WeakRef& a, const WeakRef& b) noexcept {
    return detail::sameOwner(a.token_, b.token_);
  }

  // Does this refer to object? Never creates anything, and never mistakes a new
  // object allocated at a dead referent's address for the referent.
  friend bool operator==(const WeakRef& a, const T* object) noexcept {
    if (object == nullptr || a.ptr_ == nullptr) return false;
    const std::shared_ptr<const void> token =
        detail::WeakAccess::existingToken(object);
    return token != nullptr && detail::sameOwner(a.token_, token);
  }

  // Hash of the referent's address when the reference was made; stable across
  // its death (equality, not the hash, tells two identities apart).
  std::size_t hash() const noexcept {
    return std::hash<const void*>{}(static_cast<const void*>(ptr_));
  }

 private:
  template <class>
  friend class WeakRef;
  template <class>
  friend class WeakSet;

  std::weak_ptr<Object> object_;
  std::weak_ptr<const void> token_;
  T* ptr_ = nullptr;  // meaningful only while the reference is live
};

}  // namespace oo

template <class T>
struct std::hash<oo::Ref<T>> {
  std::size_t operator()(const oo::Ref<T>& ref) const noexcept {
    return std::hash<T*>{}(ref.get());
  }
};

template <class T>
struct std::hash<oo::WeakRef<T>> {
  std::size_t operator()(const oo::WeakRef<T>& ref) const noexcept {
    return ref.hash();
  }
};
