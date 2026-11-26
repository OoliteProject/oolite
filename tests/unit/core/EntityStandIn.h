/*	EntityStandIn.h
        For a narrow test whose stand-in for the C++ root entity answers a
   virtual member (as UniverseStandIn.h for the universe): the stand-in
   derives from oo::RefCounted and ::OOJSPrivateObject, in that order, as the
   game's class does, and expands OO_ENTITY_STAND_IN_VIRTUAL_MEMBERS first, so
   its vtable has the game's slots; the test's subclass overrides the members
   the code under test calls. Every other virtual member answers zero (never
   reached: the Objective-C stand-in did not answer it).
*/
#pragma once

#include "EntityVirtualMembers.h"
#include "OOJSPrivateObject.h"
#include "oofnd/Ref.hpp"

#define OO_ENTITY_STAND_IN_VIRTUAL_MEMBERS      \
  OO_ENTITY_VIRTUAL_MEMBERS({}, { return {}; }) \
  OO_ENTITY_DEBUG_VIRTUAL_MEMBERS({}, { return {}; })
