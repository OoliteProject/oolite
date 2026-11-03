// Stub for tests/unit/expander (bead oo-3rb.61): only what src/Core/OOStringExpander.mm uses.
#pragma once
#include "OOFoundation.h"
#include "OOMaths.h"
#include "OOTypes.h"
#ifdef __cplusplus
#include "oofnd/PList.hpp"
#include <optional>
#include <string>
#endif
// The system manager is C++ since bead oo-9ht.32 deleted its facade: the bridge calls its member.
class OOHarnessSystemManager
{
public:
	Random_Seed getRandomSeedForCurrentSystem();
};
// The universe is C++ since bead oo-ql9rn deleted its Objective-C facade: the bridge calls the
// members of the same names, as OOStringExpander.mm calls them in the game:
//   [UNIVERSE cxx_descriptions]                  -> descriptions()
//   [UNIVERSE cxx_getSystemName:s (forGalaxy:g)] -> getSystemName(s (, g))
//   [UNIVERSE systemManager]                     -> getSystemManager()
// The Objective-C forms the stub declared before (-descriptions, -getSystemName:(forGalaxy:),
// answering NSDictionary / NSString) were unused and went with the facade.
class Universe
{
public:
	const oo::PList *descriptions();
	std::optional<std::string> getSystemName(OOSystemID sys);
	std::optional<std::string> getSystemName(OOSystemID sys, OOGalaxyID gal);
	OOHarnessSystemManager *getSystemManager();
};
#ifdef __cplusplus
extern "C" {
#endif
Universe *OOGetUniverse(void);
#ifdef __cplusplus
}
#endif
#define UNIVERSE OOGetUniverse()
