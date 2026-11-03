// Stub for tests/unit/expander (bead oo-3rb.61): only what src/Core/OOStringExpander.mm uses.
// ResourceManager is C++ since its Objective-C facade was deleted: the stub declares the
// one static the expander's bridge calls, over the same stub data.
#ifndef OO_EXPANDER_STUB_RESOURCEMANAGER_H
#define OO_EXPANDER_STUB_RESOURCEMANAGER_H
#import "OOFoundation.h"
#include "oofnd/PList.hpp"
class ResourceManager
{
public:
	static oo::PList whitelistDictionary();
};
#endif
