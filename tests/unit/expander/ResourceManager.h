// Stub for tests/unit/expander (bead oo-3rb.61): only what src/Core/OOStringExpander.mm uses.
// ResourceManager is C++ since bead oo-9ht.150 deleted its Objective-C facade: the stub declares the
// one static the expander's bridge calls, over the same stub data (bead oo-qqz6: stub-API tracking).
#ifndef OO_EXPANDER_STUB_RESOURCEMANAGER_H
#define OO_EXPANDER_STUB_RESOURCEMANAGER_H
#include "OOCocoa.h"
#include "oofnd/PList.hpp"
class ResourceManager
{
public:
	static oo::PList whitelistDictionary();
};
#endif
