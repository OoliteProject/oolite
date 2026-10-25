// Stub for tests/unit/sysdesc (bead oo-vjwp): only what src/Core/OOConvertSystemDescriptions.mm uses.
#pragma once
// ResourceManager is C++ since bead oo-9ht.150 deleted its Objective-C facade: the stub declares the
// two statics the tools call.
#include "OOCocoa.h"
#include "oofnd/PList.hpp"
#include "oofnd/Data.hpp"
class ResourceManager
{
public:
	static oo::PList dictionaryFromFilesNamed(const std::string &fileName, const std::optional<std::string> &folderName, bool mergeFiles);
	static bool writeDiagnosticData(const oo::Data &data, const std::string &name);
};
