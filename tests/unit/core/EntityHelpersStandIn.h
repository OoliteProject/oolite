/*	EntityHelpersStandIn.h
        For a narrow test that stands in for the root entity with its own
   Objective-C object per C++ entity (its oo::ToObjC(), declared before this is
   imported) and links code that holds, asks or describes entities through
   EntityHelpers.mm. The helpers answer on the test's objects as the game's
   answered on the facade: an entity "has its object" while its stand-in object
   exists, a hold retains and releases that object, and the descriptions are the
   object's. Import it once, in the test's own file, after its oo::ToObjC(). A
   test that links no OODescription.mm (and whose code under test describes no
   entity) defines OO_ENTITY_HELPERS_STAND_IN_NO_DESCRIPTIONS first.

        A test whose stand-in object is C++ defines
        OO_ENTITY_HELPERS_STAND_IN_CXX first and declares, before the include,
   its
        ::TestEntityObject *TestObjectOf(Entity *) in place of oo::ToObjC();
   ::TestEntityObject is an oo::RefCounted whose className() answers its
   Objective-C class's name. The helpers answer the same: the hold retains and
   releases the object, and both descriptions are what the Objective-C object
   printed: <ClassName 0x...>, then {components} where its class answered
        -cxx_descriptionComponents (the full one) or
   -cxx_shortDescriptionComponents (the short one), members of those names here.
*/
#pragma once

#include <optional>
#include <string>

#include "OODescription.h"

class Entity;

namespace oo {
namespace detail {
bool EntityHasObject(const Entity* entity) noexcept;
void EntityRetain(Entity* entity) noexcept;
void EntityRelease(Entity* entity) noexcept;
}  // namespace detail
Entity* WithObject(Entity* entity);
std::string EntityDescription(Entity* entity);
std::string EntityShortDescription(Entity* entity);
}  // namespace oo

#ifdef OO_ENTITY_HELPERS_STAND_IN_CXX

#include "oofnd/String.hpp"

bool oo::detail::EntityHasObject(const Entity* entity) noexcept {
  return entity != nullptr &&
         TestObjectOf(const_cast<Entity*>(entity)) != nullptr;
}
void oo::detail::EntityRetain(Entity* entity) noexcept {
  if (::TestEntityObject* object =
          (entity != nullptr) ? TestObjectOf(entity) : nullptr)
    object->retain();
}
void oo::detail::EntityRelease(Entity* entity) noexcept {
  if (::TestEntityObject* object =
          (entity != nullptr) ? TestObjectOf(entity) : nullptr)
    object->release();
}
Entity* oo::WithObject(Entity* entity) {
  return (entity != nullptr && TestObjectOf(entity) != nullptr) ? entity
                                                                : nullptr;
}
#ifndef OO_ENTITY_HELPERS_STAND_IN_NO_DESCRIPTIONS
// "%@" of the object (full: the description, else the short one), "(null)" for
// none.
template <class Object>
std::string TestEntityObjectDescription(Object* object, bool full = false) {
  if (object == nullptr) return "(null)";
  std::optional<std::string> components;
  if constexpr (requires { object->cxx_descriptionComponents(); }) {
    if (full) components = object->cxx_descriptionComponents();
  }
  if constexpr (requires { object->cxx_shortDescriptionComponents(); }) {
    if (!full) components = object->cxx_shortDescriptionComponents();
  }
  std::string result =
      oo::str::format("<%s %s>", object->className(),
                      oo::str::pointerDescription(object).c_str());
  if (components.has_value()) result += "{" + *components + "}";
  return result;
}
std::string oo::EntityDescription(Entity* entity) {
  return TestEntityObjectDescription(
      (entity != nullptr) ? TestObjectOf(entity) : nullptr, true);
}
std::string oo::EntityShortDescription(Entity* entity) {
  return TestEntityObjectDescription((entity != nullptr) ? TestObjectOf(entity)
                                                         : nullptr);
}
#endif

#else

bool oo::detail::EntityHasObject(const Entity* entity) noexcept {
  return entity != nullptr && oo::ToObjC(const_cast<Entity*>(entity)) != nil;
}
void oo::detail::EntityRetain(Entity* entity) noexcept {
  if (entity != nullptr) [oo::ToObjC(entity) retain];
}
void oo::detail::EntityRelease(Entity* entity) noexcept {
  if (entity != nullptr) [oo::ToObjC(entity) release];
}
Entity* oo::WithObject(Entity* entity) {
  return (entity != nullptr && oo::ToObjC(entity) != nil) ? entity : nullptr;
}
#ifndef OO_ENTITY_HELPERS_STAND_IN_NO_DESCRIPTIONS
std::string oo::EntityDescription(Entity* entity) {
  return oo::DescriptionOf(oo::ToObjC(entity));
}
std::string oo::EntityShortDescription(Entity* entity) {
  return oo::ShortDescriptionOf(oo::ToObjC(entity));
}
#endif

#endif  // OO_ENTITY_HELPERS_STAND_IN_CXX
