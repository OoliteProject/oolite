// Stub for tests/unit/sysdesc (bead oo-vjwp): only what src/Core/OOConvertSystemDescriptions.mm uses.
#import "OOFoundation.h"
#include "oofnd/PList.hpp"
@interface ResourceManager : NSObject
+ (oo::PList) cxx_dictionaryFromFilesNamed:(const std::string &)fileName
								  inFolder:(const std::optional<std::string> &)folderName
								  andMerge:(BOOL)mergeFiles;
+ (BOOL) cxx_writeDiagnosticData:(const oo::Data &)data toFileNamed:(const std::string &)name;
@end
