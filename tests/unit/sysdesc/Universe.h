// Stub for tests/unit/sysdesc only what
// src/Core/OOConvertSystemDescriptions.mm uses.
#pragma once
#include "OOFoundation.h"
#include "oofnd/PList.hpp"
#ifndef OO_LOCALIZATION_TOOLS
#define OO_LOCALIZATION_TOOLS 1
#endif
// The universe is C++: the tools call the member of the same name.
class Universe {
 public:
  const oo::PList* descriptions();
};
Universe* OOGetUniverse(void);
#define UNIVERSE OOGetUniverse()
