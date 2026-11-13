/*	oofnd/Object.hpp
        oo::Object, the common base of every shared-owned game object, and the
   deleter and helpers that go with it (spec 009, contracts/ownership.md).
   Shared ownership is std::shared_ptr<T>, observation std::weak_ptr<T>.
   Until the bridge (oofnd/Ref.hpp) is deleted, its reference-counted base is a
   subclass of oo::Object that keeps the old retain/release names.
*/

#pragma once

#include <memory>
#include <type_traits>
#include <utility>

namespace oo {

// The common base of every shared-owned game object (it replaced the
// reference-counted base). Objects are created with oo::makeShared, never
// std::make_shared, so that willDispose() runs before the destructor.
class Object : public std::enable_shared_from_this<Object> {
 public:
  virtual ~Object() = default;

 protected:
  Object() noexcept = default;
  // Copying gives a new, unowned object (as the reference-counted base's copy
  // did); assignment leaves ownership alone. (enable_shared_from_this's own
  // copy constructor leaves the copy's weak reference empty.)
  Object(const Object& other) noexcept
      : std::enable_shared_from_this<Object>(other) {}
  Object& operator=(const Object&) noexcept { return *this; }

  // Called once, by the deleter, after the last owner has released the object
  // and before its destructor. Weak references to it are already empty.
  virtual void willDispose() noexcept {}

 private:
  friend struct Dispose;
};

// The deleter every oo::makeShared object carries.
struct Dispose {
  void operator()(Object* p) const noexcept {
    p->willDispose();
    delete p;
  }
};

template <class T, class... Args>
std::shared_ptr<T> makeShared(Args&&... args) {
  return std::shared_ptr<T>(new T(std::forward<Args>(args)...), Dispose{});
}

// An owning reference from a raw pointer to an object some shared_ptr already
// owns (was Ref<T>(T*)). Null gives null; an unowned object throws
// std::bad_weak_ptr.
template <class T>
std::shared_ptr<T> share(T* p) {
  if (p == nullptr) return nullptr;
  return std::static_pointer_cast<T>(
      static_cast<Object*>(const_cast<std::remove_const_t<T>*>(p))
          ->shared_from_this());
}

// Whether two weak references observe the same object, alive or gone (the same
// owner); two that never observed one are the same.
template <class A, class B>
bool sameObject(const std::weak_ptr<A>& a, const std::weak_ptr<B>& b) noexcept {
  return !a.owner_before(b) && !b.owner_before(a);
}

// Whether a weak reference never observed an object (an empty one, not one
// whose object has gone).
template <class T>
bool isUnset(const std::weak_ptr<T>& weak) noexcept {
  return sameObject(weak, std::weak_ptr<T>());
}

}  // namespace oo
