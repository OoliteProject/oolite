/*	test_OOJSEngineTimeManagement.hpp
	The profile classes of src/Core/Scripting/OOJSEngineTimeManagement.h, as far as
	test_OOJSEngineTimeManagement.mm calls them (that header imports the engine's, which the test
	defines classes of). Member functions are defined by the game's own OOJSEngineTimeManagement.mm.
*/

#ifndef TEST_OOJSENGINETIMEMANAGEMENT_HPP
#define TEST_OOJSENGINETIMEMANAGEMENT_HPP

#include "oofnd/Ref.hpp"
#include "ooscript/JSEngine.hpp"

#include <optional>
#include <string>
#include <vector>

class OOTimeProfileEntry : public oo::RefCounted
{
public:
	std::optional<std::string> function();
	NSUInteger hitCount();
	double totalTimeSum();
	double selfTimeSum();
	double totalTimeAverage();
	double selfTimeAverage();
	double totalTimeMax();
	double selfTimeMax();
	bool isJavaScriptFrame();
	OOComparisonResult compareByTotalTime(OOTimeProfileEntry *other);
	OOComparisonResult compareByTotalTimeReverse(OOTimeProfileEntry *other);
	OOComparisonResult compareBySelfTime(OOTimeProfileEntry *other);
	OOComparisonResult compareBySelfTimeReverse(OOTimeProfileEntry *other);
	std::optional<std::string> description();
	ooscript::Value oo_jsValueInContext(ooscript::Context context);
};

class OOTimeProfile : public oo::RefCounted
{
public:
	std::optional<std::string> description();
	double totalTime();
	double javaScriptTime();
	double nativeTime();
	double extensionTime();
	double nonExtensionTime();
	double profilerOverhead();
	std::vector<oo::Ref<OOTimeProfileEntry>> profileEntries();
	ooscript::Value oo_jsValueInContext(ooscript::Context context);
};

#endif
