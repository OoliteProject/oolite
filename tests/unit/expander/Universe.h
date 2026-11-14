// Stub for tests/unit/expander: only what
// src/Core/OOStringExpander.mm uses.
#pragma once
#include "OOFoundation.h"
#include "OOMaths.h"
#include "OOTypes.h"
#ifdef __cplusplus
#include <optional>
#include <string>

#include "oofnd/PList.hpp"
#endif
// The system manager is C++: the bridge calls its member.
class OOHarnessSystemManager {
 public:
  Random_Seed getRandomSeedForCurrentSystem();
};
// The universe is C++: the bridge calls the members of the same names, as
// OOStringExpander.mm calls them in the game:
//   [UNIVERSE cxx_descriptions]                  -> descriptions()
//   [UNIVERSE cxx_getSystemName:s (forGalaxy:g)] -> getSystemName(s (, g))
//   [UNIVERSE systemManager]                     -> getSystemManager()
class Universe {
 public:
  const oo::PList* descriptions();
  std::optional<std::string> getSystemName(OOSystemID sys);
  std::optional<std::string> getSystemName(OOSystemID sys, OOGalaxyID gal);
  OOHarnessSystemManager* getSystemManager();
};
#ifdef __cplusplus
extern "C" {
#endif
Universe* OOGetUniverse(void);
#ifdef __cplusplus
}
#endif
#define UNIVERSE OOGetUniverse()
