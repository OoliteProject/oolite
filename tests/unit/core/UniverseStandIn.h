/*	UniverseStandIn.h
        For a narrow test whose stand-in for the C++ Universe answers a virtual
   member: the stand-in derives from oo::RefCounted, as the game's class does,
   and expands OO_UNIVERSE_STAND_IN_VIRTUAL_MEMBERS first, so its vtable has
   the game's slots; the test's subclass overrides the members the code under
   test calls. Every other virtual member answers zero (never reached: the
   Objective-C stand-in did not answer it).
*/
#pragma once

#include "UniverseVirtualMembers.h"
#include "oofnd/Ref.hpp"

#define OO_UNIVERSE_STAND_IN_VIRTUAL_MEMBERS \
  OO_UNIVERSE_VIRTUAL_MEMBERS({}, { return {}; })
