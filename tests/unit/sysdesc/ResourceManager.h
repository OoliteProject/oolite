// Stub for tests/unit/sysdesc (bead oo-vjwp): only what src/Core/OOConvertSystemDescriptions.mm uses.
// ResourceManager is C++ since its Objective-C facade was deleted: the stub declares the
// two statics the tools call.
#import "OOFoundation.h"
#include "oofnd/PList.hpp"
#include "oofnd/Data.hpp"
class ResourceManager
{
public:
	static oo::PList dictionaryFromFilesNamed(const std::string &fileName, const std::optional<std::string> &folderName, bool mergeFiles);
	static bool writeDiagnosticData(const oo::Data &data, const std::string &name);
};
