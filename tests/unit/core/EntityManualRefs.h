/*

EntityManualRefs.h

The manual references to an entity's object that the tests still take (spec
009 T095): the game holds its entities by std::shared_ptr and no longer has
them. They are what the game's oo::RetainEntity(), oo::ReleaseEntity(),
oo::AutoreleaseEntity() and its two bridge adapters did, on the bridge's
manual-hold counter (oofnd/Ref.hpp), and they leave with it (T097, T098):
nothing for null or for an entity without its object; RetainEntity() and
AutoreleaseEntity() answer their argument. Templates, so that each is
instantiated where the entity's class is complete.

*/

#pragma once

#include <memory>

#include "OOEntityHold.h"
#include "oofnd/Ref.hpp"

namespace oo {

template <class E>
E* RetainEntity(E* entity) {
  if (entity != nullptr && detail::EntityHasObject(entity)) entity->retain();
  return entity;
}

template <class E>
void ReleaseEntity(E* entity) {
  if (entity != nullptr && detail::EntityHasObject(entity)) entity->release();
}

// -autorelease: the caller's +1 to the innermost oo::AutoreleaseScope.
template <class E>
E* AutoreleaseEntity(E* entity) {
  if (entity != nullptr && detail::EntityHasObject(entity))
    (void)oo::autorelease(entity);
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
