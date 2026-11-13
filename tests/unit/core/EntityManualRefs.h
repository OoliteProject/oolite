/*

EntityManualRefs.h

The manual references to an entity's object that the tests still take: the
game holds its entities by std::shared_ptr and no longer has them. They are what the game's oo::RetainEntity(), oo::ReleaseEntity(),
oo::AutoreleaseEntity() and the bridge's two adapters did, on standard types:
each object's manual references are a list of owning references, one per
retain, given back one per release (a release with none aborts, as before):
nothing for null or for an entity without its object; RetainEntity() and
AutoreleaseEntity() answer their argument. Templates, so that each is
instantiated where the entity's class is complete.

*/

#pragma once

#include <cstdlib>
#include <memory>
#include <type_traits>
#include <unordered_map>
#include <utility>
#include <vector>

#include "OOEntityHold.h"
#include "oofnd/AutoreleaseScope.hpp"
#include "oofnd/Object.hpp"

namespace oo {

namespace test_detail {

// The manual references taken on an oo::Object entity: one owning reference
// each, given back one at a time (never destroyed, so no static destructor
// runs at exit).
inline std::unordered_map<const void*, std::vector<std::shared_ptr<const void>>>&
ManualHolds() {
  static auto& holds = *new std::unordered_map<
      const void*, std::vector<std::shared_ptr<const void>>>();
  return holds;
}

}  // namespace test_detail

// The same manual references for any object the tests own by hand (a view, a
// texture, a script...): Retain(), Release() and Autorelease() on the list
// above; NewRetained<T>() is new T with its +1 ([[T alloc] init]).
namespace test {

template <class T>
T* Retain(T* object) {
  if (object == nullptr) return object;
  test_detail::ManualHolds()[object].push_back(oo::share(object));
  return object;
}

template <class T>
void Release(T* object) {
  if (object == nullptr) return;
  auto found = test_detail::ManualHolds().find(object);
  if (found == test_detail::ManualHolds().end() || found->second.empty())
    std::abort();  // a release with no retain to give back, as before
  std::shared_ptr<const void> last = std::move(found->second.back());
  found->second.pop_back();
  if (found->second.empty()) test_detail::ManualHolds().erase(found);
  last.reset();  // may destroy the object
}

// -autorelease: one of the object's manual references to the innermost
// oo::AutoreleaseScope (the bridge's oo::autorelease(T*)). Null is answered as
// it is.
template <class T>
T* Autorelease(T* object) {
  if (object == nullptr) return object;
  auto found = test_detail::ManualHolds().find(object);
  if (found == test_detail::ManualHolds().end() || found->second.empty())
    std::abort();  // no +1 to hand on
  std::shared_ptr<const void> last = std::move(found->second.back());
  found->second.pop_back();
  if (found->second.empty()) test_detail::ManualHolds().erase(found);
  (void)oo::autorelease(oo::share(object));  // the scope's reference
  last.reset();
  return object;
}

template <class T, class... Args>
T* NewRetained(Args&&... args) {
  const std::shared_ptr<T> object =
      oo::makeShared<T>(std::forward<Args>(args)...);
  test_detail::ManualHolds()[object.get()].push_back(object);
  return object.get();
}

}  // namespace test

template <class E>
E* RetainEntity(E* entity) {
  if (entity == nullptr || !detail::EntityHasObject(entity)) return entity;
  test_detail::ManualHolds()[entity].push_back(oo::share(entity));
  return entity;
}

template <class E>
void ReleaseEntity(E* entity) {
  if (entity == nullptr || !detail::EntityHasObject(entity)) return;
  auto found = test_detail::ManualHolds().find(entity);
  if (found == test_detail::ManualHolds().end() || found->second.empty())
    std::abort();  // a release with no retain to give back, as before
  std::shared_ptr<const void> last = std::move(found->second.back());
  found->second.pop_back();
  if (found->second.empty()) test_detail::ManualHolds().erase(found);
  last.reset();  // may dispose the entity
}

// -autorelease: the caller's +1 to the innermost oo::AutoreleaseScope.
template <class E>
E* AutoreleaseEntity(E* entity) {
  if (entity == nullptr || !detail::EntityHasObject(entity)) return entity;
  auto found = test_detail::ManualHolds().find(entity);
  if (found == test_detail::ManualHolds().end() || found->second.empty())
    std::abort();  // no +1 to hand on
  std::shared_ptr<const void> last = std::move(found->second.back());
  found->second.pop_back();
  if (found->second.empty()) test_detail::ManualHolds().erase(found);
  (void)oo::autorelease(oo::share(entity));  // the scope's reference
  last.reset();
  return entity;
}

// The entity with a +1 the caller gives back (what the game's makers answered
// before they answered a std::shared_ptr).
template <class E>
E* RetainedEntity(const std::shared_ptr<E>& entity) {
  (void)RetainEntity(entity.get());
  return entity.get();
}

// Takes over a +1: the owning reference, the +1 given back.
template <class E>
std::shared_ptr<E> AdoptHold(E* entity) {
  std::shared_ptr<E> hold = Hold(entity);
  if (hold != nullptr) ReleaseEntity(entity);
  return hold;
}

}  // namespace oo
