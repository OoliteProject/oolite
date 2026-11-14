// Stub for tests/unit/expander: only what src/Core/OOStringExpander.mm uses.
// ResourceManager is C++: the stub declares the
// one static the expander's bridge calls, over the same stub data.
#pragma once
#include "OOFoundation.h"
#include "oofnd/PList.hpp"
class ResourceManager {
 public:
  static oo::PList whitelistDictionary();
};
