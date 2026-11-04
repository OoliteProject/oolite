/*	test_OOShaderUniformMethodType.mm
        Unit tests for src/Core/Materials/OOShaderUniformMethodType.h.

        The shader uniform member tables give the type of a bound member's
   return type by its encoding (OOShaderUniformTypeFromEncoding(), which
   compares it with a table of known ones). This pins the type each encoding is
   given (the ones the table has, and those it has not): typesFromEncodings,
   encodingsTheTableHasNot. Run: bash tools/check-core-tests.sh
*/

#include <string>
#include <vector>

#include "OOOpenGLExtensionManager.h"
#include "OORegExpMatcher.h"
#include "OOShaderUniformMethodType.h"
#include "OOTypeEncodings.h"  // @encode()'s measured literals
#include "oo_test.hpp"
#include "oofnd/PList.hpp"

/*	OOMatrix.mm (the test's matrices) links the extension manager, whose
   collaborators are stubbed as in test_OOOpenGLExtensionManager; none of them
   runs here.
*/
#include "ResourceManager.h"

// ResourceManager: C++ definitions of the statics the code under test calls,
// with the stand-in's answers.
std::vector<std::string> ResourceManager::paths() { return {}; }
oo::PList ResourceManager::dictionaryFromFilesNamed(
    const std::string& /*fileName*/,
    const std::optional<std::string>& /*folderName*/, bool /*mergeFiles*/) {
  return oo::PList(oo::PList::Dict{});
}

// OORegExpMatcher stub: answers no match.
oo::Ref<OORegExpMatcher> OORegExpMatcher::regExpMatcher() {
  return oo::makeRef<OORegExpMatcher>();
}
bool OORegExpMatcher::string(const std::string&, const std::string&) {
  return false;
}
OORegExpMatcher::~OORegExpMatcher() {}

// OOLogging.mm's (it would bring the resource manager into the link);
// OOOpenGL.mm's OOGL error check and state dump call them.
void OOLogIndent(void) {}
void OOLogOutdent(void) {}

OOShaderSetting cxx_OOShaderSettingFromString(const std::string& string) {
  return string == "SHADERS_FULL" ? SHADERS_FULL : SHADERS_NOT_SUPPORTED;
}

namespace {

// The type of a return type, by its encoding: the member tables' rows give
// @encode() of their types, the measured literals kOOTypeEncoding<> (id's keyed
// OOObjCId).
template <typename T>
OOShaderUniformType TypeOf() {
  return OOShaderUniformTypeFromEncoding(kOOTypeEncoding<T>);
}

}  // namespace

/*	The types of the return types, one each, are the types their encodings
   are given.
*/
OO_TEST(typesFromEncodings) {
  OO_CHECK(TypeOf<float>() == kOOShaderUniformTypeFloat);
  OO_CHECK(TypeOf<double>() == kOOShaderUniformTypeDouble);
  OO_CHECK(TypeOf<signed char>() == kOOShaderUniformTypeChar);
  OO_CHECK(TypeOf<unsigned char>() == kOOShaderUniformTypeUnsignedChar);
  OO_CHECK(TypeOf<signed short>() == kOOShaderUniformTypeShort);
  OO_CHECK(TypeOf<unsigned short>() == kOOShaderUniformTypeUnsignedShort);
  OO_CHECK(TypeOf<signed int>() == kOOShaderUniformTypeInt);
  OO_CHECK(TypeOf<unsigned int>() == kOOShaderUniformTypeUnsignedInt);
  OO_CHECK(TypeOf<signed long>() == kOOShaderUniformTypeLong);
  OO_CHECK(TypeOf<unsigned long>() == kOOShaderUniformTypeUnsignedLong);
  OO_CHECK(TypeOf<Vector>() == kOOShaderUniformTypeVector);
  OO_CHECK(TypeOf<HPVector>() == kOOShaderUniformTypeHPVector);
  OO_CHECK(TypeOf<Quaternion>() == kOOShaderUniformTypeQuaternion);
  OO_CHECK(TypeOf<OOMatrix>() == kOOShaderUniformTypeMatrix);
  OO_CHECK(TypeOf<NSPoint>() == kOOShaderUniformTypePoint);
  OO_CHECK(TypeOf<OOObjCId>() == kOOShaderUniformTypeObject);
}

/*	The types the table has no row for, through the encoding.
 */
OO_TEST(encodingsTheTableHasNot) {
  // BOOL is encoded as a signed char here.
  OO_CHECK(TypeOf<BOOL>() == kOOShaderUniformTypeChar);
  // The table has no long long entries: on this platform (LLP64) a long is 32
  // bits, so a long long matches nothing.
  OO_CHECK(TypeOf<long long>() == kOOShaderUniformTypeInvalid);
  OO_CHECK(TypeOf<unsigned long long>() == kOOShaderUniformTypeInvalid);
  OO_CHECK(TypeOf<void>() == kOOShaderUniformTypeInvalid);
  OO_CHECK(TypeOf<NSRect>() == kOOShaderUniformTypeInvalid);
  OO_CHECK(OOShaderUniformTypeFromEncoding(NULL) ==
           kOOShaderUniformTypeInvalid);
}

OO_TEST_MAIN()
