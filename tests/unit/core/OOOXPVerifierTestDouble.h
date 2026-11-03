/*	OOOXPVerifierTestDouble.h
	The OOOXPVerifier the OXPVerifier stage tests link instead of the real one (bead oo-9ht.65,
	from oo-4amcj). The verifier and the resource manager reach the whole game, so they are not
	linked; the stages talk to the verifier through its interface only, so the test is the
	verifier: the configuration is a verifyOXP.plist of the test's, registration keeps stages by
	name and counts them (Registrations()).

	It was pasted into each stage test; this is that code, moved, with the same methods and the
	same behaviour. Since bead oo-9ht.4 deleted the stage facade it keeps, and answers, the C++
	stages themselves (it kept their facades), as the verifier does. Since bead oo-qg71f the
	stages keep and call the C++ verifier, so the double defines cxx::OOOXPVerifier's members
	the stages call (it was an @implementation of the Objective-C facade class, with its own
	ivars): its state is the class's own members, its answers are unchanged, and a test makes one
	with OOOXPVerifierTestAccess::Make and counts registrations with ::Registrations.

	Include it once, from a stage test, after its imports.
*/

#ifndef OO_TESTS_UNIT_CORE_OOOXPVERIFIERTESTDOUBLE_H
#define OO_TESTS_UNIT_CORE_OOOXPVERIFIERTESTDOUBLE_H

#import "OOOXPVerifier.h"
#import "OOOXPVerifierStage.h"
#include "oofnd/PListParsing.hpp"

#include <map>
#include <optional>
#include <set>
#include <string>
#include <vector>


static int gRegistrations = 0;


/*	Making a verifier (its constructor is private; the class names this struct its friend for
	tests). The double's verifiers are kept until the test exits, as each facade the double made
	(autoreleased) lived to the end of its test's autorelease pool; never destroyed, so none is
	released while the process exits.
*/
struct OOOXPVerifierTestAccess
{
	// The verifier of the OXP at path, configured by the verifyOXP.plist text configuration.
	static cxx::OOOXPVerifier *Make(const std::string &path, const char *configuration)
	{
		static auto *kept = new std::vector<oo::Ref<cxx::OOOXPVerifier>>;
		const oo::Ref<cxx::OOOXPVerifier> verifier = oo::adopt(new cxx::OOOXPVerifier());
		verifier->_basePath = path;
		verifier->_verifierPList = *oo::parsePropertyListData(configuration);
		verifier->_openForRegistration = true;
		kept->push_back(verifier);
		return verifier.get();
	}

	// Stages registered with any double so far.
	static int Registrations()	{ return gRegistrations; }
};


/*	The verifier's members that the stages call, defined here because OOOXPVerifier.mm is not
	linked. Each body is the one the double's Objective-C method had (the ivars it read are the
	class's own members now); nothing else of the class is defined, so nothing else may be called.
*/
void cxx::OOOXPVerifier::registerStage(::OOOXPVerifierStage *stage)
{
	_stagesByName[*stage->name()] = oo::Ref<::OOOXPVerifierStage>(stage);
	stage->setVerifier(this);
	gRegistrations++;
}


std::optional<std::string> cxx::OOOXPVerifier::oxpPath()			{ return _basePath; }
std::optional<std::string> cxx::OOOXPVerifier::oxpDisplayName()		{ return "Test.oxp"; }


::OOOXPVerifierStage *cxx::OOOXPVerifier::stageWithName(const std::string &name)
{
	const auto found = _stagesByName.find(name);
	return found != _stagesByName.end() ? found->second.get() : nullptr;
}


oo::PList cxx::OOOXPVerifier::configurationValueForKey(const std::string &key)
{
	const oo::PList *value = _verifierPList.find(key);
	return value != nullptr ? *value : oo::PList();
}


oo::PList cxx::OOOXPVerifier::configurationArrayForKey(const std::string &key)
{
	const oo::PList *array = _verifierPList.get<oo::PList::Array>(key);
	return array != nullptr ? *array : oo::PList();
}


oo::PList cxx::OOOXPVerifier::configurationDictionaryForKey(const std::string &key)
{
	const oo::PList *dictionary = _verifierPList.get<oo::PList::Dict>(key);
	return dictionary != nullptr ? *dictionary : oo::PList();
}


std::optional<std::string> cxx::OOOXPVerifier::configurationStringForKey(const std::string &key)
{
	const oo::PList *value = _verifierPList.find(key);
	if (value == nullptr || !(value->isString() || value->isNumber()))  return std::nullopt;
	return _verifierPList.get<std::string>(key);
}


std::optional<std::vector<std::string>> cxx::OOOXPVerifier::configurationSetForKey(const std::string &key)
{
	const oo::PList *array = _verifierPList.get<oo::PList::Array>(key);
	if (array == nullptr)  return std::nullopt;

	std::set<std::string> strings;
	for (const oo::PList &element : *array->getIf<oo::PList::Array>())
	{
		if (const std::string *string = element.getIf<std::string>())  strings.insert(*string);
	}
	return std::vector<std::string>(strings.begin(), strings.end());
}

#endif	// OO_TESTS_UNIT_CORE_OOOXPVERIFIERTESTDOUBLE_H
