// Stub for tests/unit/sysdesc (bead oo-vjwp): only what src/Core/OOConvertSystemDescriptions.mm uses.
#pragma once
#include "OOFoundation.h"
#include "oofnd/PList.hpp"
#ifndef OO_LOCALIZATION_TOOLS
#define OO_LOCALIZATION_TOOLS	1
#endif
// The universe is C++ since bead oo-ql9rn deleted its Objective-C facade: the tools call the member
// of the same name (the Objective-C form the stub declared went with the facade).
class Universe
{
public:
	const oo::PList *descriptions();
};
Universe *OOGetUniverse(void);
#define UNIVERSE OOGetUniverse()
