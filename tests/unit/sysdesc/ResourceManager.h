// Stub for tests/unit/sysdesc only what
// src/Core/OOConvertSystemDescriptions.mm uses.
#pragma once
// ResourceManager is C++: the stub declares the
// two statics the tools call.
#include "OOFoundation.h"
#include "oofnd/Data.hpp"
#include "oofnd/PList.hpp"
class ResourceManager {
 public:
  static oo::PList dictionaryFromFilesNamed(
      const std::string& fileName, const std::optional<std::string>& folderName,
      bool mergeFiles);
  static bool writeDiagnosticData(const oo::Data& data,
                                  const std::string& name);
};
