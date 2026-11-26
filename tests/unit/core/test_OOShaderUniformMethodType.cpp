/*	test_OOShaderUniformMethodType.mm
	Unit tests for src/Core/Materials/OOShaderUniformMethodType.h: bead oo-41vj.

	OOShaderUniformTypeFromMethod() told a shader uniform binding the return type of the method it
	is bound to, by comparing the runtime's return-type encoding with a table of known ones. Its
	file held an Objective-C template class whose only use was to give that table. This pinned,
	against a class of the test's own with one method per return type, the type each method is
	given (the ones the table has, and those it has not), NULL, and the two call helpers.

	Bead oo-4aq6a.7 deleted the Objective-C binding target and with it OOShaderUniformTypeFromMethod()
	and the call helpers (OOCallIntegerMethod, OOCallFloatMethod): typesFromMethods,
	typesTheTableHasNot and callHelpers retired with them (ADR-0062 item 2; std-2026-10-19 item 2),
	after the same types were re-pinned through OOShaderUniformTypeFromEncoding(), which the member
	tables use (ADR-0062 item 3): typesFromEncodings, encodingsTheTableHasNot.
	Run: bash tools/check-core-tests.sh
*/

#include "OOShaderUniformMethodType.h"
#include "OORegExpMatcher.h"
#include "OOOpenGLExtensionManager.h"
#include "oofnd/PList.hpp"
#include "OOTypeEncodings.h"	// @encode()'s measured literals (bead oo-dbz.3)

#include "oo_test.hpp"

#include <string>
#include <vector>


/*	OOMatrix.mm (the test's matrices) links the extension manager, whose collaborators are stubbed
	as in test_OOOpenGLExtensionManager; none of them runs here.
*/
#include "ResourceManager.h"

// ResourceManager is C++ since bead oo-9ht.150 deleted its Objective-C facade: C++ definitions of the
// statics the code under test calls, with the Objective-C stand-in's answers.
std::vector<std::string> ResourceManager::paths()  { return {}; }
oo::PList ResourceManager::dictionaryFromFilesNamed(const std::string &/*fileName*/, const std::optional<std::string> &/*folderName*/, bool /*mergeFiles*/)  { return oo::PList(oo::PList::Dict{}); }



// OORegExpMatcher is C++ since its facade was deleted (bead oo-9ht.12): the stub answers no match.
oo::Ref<OORegExpMatcher> OORegExpMatcher::regExpMatcher()  { return oo::makeRef<OORegExpMatcher>(); }
bool OORegExpMatcher::string(const std::string &, const std::string &)  { return false; }
OORegExpMatcher::~OORegExpMatcher()  {}


// OOLogging.mm's (it would bring the resource manager into the link); OOOpenGL.mm's OOGL error
// check and state dump call them.
void OOLogIndent(void)  {}
void OOLogOutdent(void)  {}


OOShaderSetting cxx_OOShaderSettingFromString(const std::string &string)
{
	return string == "SHADERS_FULL" ? SHADERS_FULL : SHADERS_NOT_SUPPORTED;
}


namespace {

// The type of a return type, by its encoding: the encodings TestReturns's methods had (bead
// oo-4aq6a.7 deleted the method path; the member tables' rows give @encode() of their types, the
// measured literals kOOTypeEncoding<> since bead oo-dbz.3, id's keyed OOObjCId).
template <typename T>
OOShaderUniformType TypeOf()
{
	return OOShaderUniformTypeFromEncoding(kOOTypeEncoding<T>);
}

}	// namespace


/*	Re-pinned through the encoding (ADR-0062 item 3): the types the methods of the deleted case
	typesFromMethods were given, one return type each, are the types their encodings are given.
	(Its withArgument: check - arguments are not considered - was the method path's alone.)
*/
OO_TEST(typesFromEncodings)
{
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


/*	The same for typesTheTableHasNot (ADR-0062 item 3); its method-only checks (a selector with no
	method, a NULL Method) retire with the method path (item 2), and NULL is the encoding's.
*/
OO_TEST(encodingsTheTableHasNot)
{
	// BOOL is encoded as a signed char here.
	OO_CHECK(TypeOf<BOOL>() == kOOShaderUniformTypeChar);
	// The table has no long long entries: on this platform (LLP64) a long is 32 bits, so a long
	// long matches nothing.
	OO_CHECK(TypeOf<long long>() == kOOShaderUniformTypeInvalid);
	OO_CHECK(TypeOf<unsigned long long>() == kOOShaderUniformTypeInvalid);
	OO_CHECK(TypeOf<void>() == kOOShaderUniformTypeInvalid);
	OO_CHECK(TypeOf<NSRect>() == kOOShaderUniformTypeInvalid);
	OO_CHECK(OOShaderUniformTypeFromEncoding(NULL) == kOOShaderUniformTypeInvalid);
}

OO_TEST_MAIN()
