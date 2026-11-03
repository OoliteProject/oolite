/*	OOOXPVerifierTestDouble.h
	The OOOXPVerifier the OXPVerifier stage tests link instead of the real one (bead oo-9ht.65,
	from oo-4amcj). The verifier and the resource manager reach the whole game, so they are not
	linked; the stages talk to the verifier through its interface only, so the test is the
	verifier: the configuration is a verifyOXP.plist of the test's, registration keeps stages by
	name and counts them (-registrations).

	It was pasted into each stage test; this is that code, moved, with the same methods and the
	same behaviour. Its state is its own ivars, declared in the @implementation (the non-fragile
	runtime allows that), not OOOXPVerifier.h's, so converting the verifier (oo-tsa4) does not
	reach into the tests. Since bead oo-9ht.4 deleted the stage facade it keeps, and answers, the
	C++ stages themselves (it kept their facades), as the verifier does.

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


@interface OOOXPVerifier ()

- (id)initWithPath:(const std::string &)path configuration:(const char *)configuration;
- (int)registrations;

@end


static int gRegistrations = 0;


@implementation OOOXPVerifier
{
	oo::PList														_doubleVerifierPList;
	std::string														_doubleBasePath;
	std::map<std::string, oo::Ref<OOOXPVerifierStage>, std::less<>>	_doubleStagesByName;
	BOOL															_doubleOpenForRegistration;
}

+ (BOOL)runVerificationIfRequested	{ return NO; }


- (int)registrations	{ return gRegistrations; }


- (id)initWithPath:(const std::string &)path configuration:(const char *)configuration
{
	self = [super init];
	if (self != nil)
	{
		_doubleBasePath = path;
		_doubleVerifierPList = *oo::parsePropertyListData(configuration);
		_doubleOpenForRegistration = YES;
	}
	return self;
}


- (void)registerStage:(OOOXPVerifierStage *)stage
{
	_doubleStagesByName[*stage->name()] = oo::Ref<OOOXPVerifierStage>(stage);
	stage->setVerifier(self);
	gRegistrations++;
}


- (std::optional<std::string>)cxx_oxpPath			{ return _doubleBasePath; }
- (std::optional<std::string>)cxx_oxpDisplayName	{ return "Test.oxp"; }


- (OOOXPVerifierStage *)cxx_stageWithName:(const std::string &)name
{
	const auto found = _doubleStagesByName.find(name);
	return found != _doubleStagesByName.end() ? found->second.get() : nullptr;
}


- (oo::PList)configurationValueForKey:(const std::string &)key
{
	const oo::PList *value = _doubleVerifierPList.find(key);
	return value != nullptr ? *value : oo::PList();
}


- (oo::PList)cxx_configurationArrayForKey:(const std::string &)key
{
	const oo::PList *array = _doubleVerifierPList.get<oo::PList::Array>(key);
	return array != nullptr ? *array : oo::PList();
}


- (oo::PList)cxx_configurationDictionaryForKey:(const std::string &)key
{
	const oo::PList *dictionary = _doubleVerifierPList.get<oo::PList::Dict>(key);
	return dictionary != nullptr ? *dictionary : oo::PList();
}


- (std::optional<std::string>)cxx_configurationStringForKey:(const std::string &)key
{
	const oo::PList *value = _doubleVerifierPList.find(key);
	if (value == nullptr || !(value->isString() || value->isNumber()))  return std::nullopt;
	return _doubleVerifierPList.get<std::string>(key);
}


- (std::optional<std::vector<std::string>>)cxx_configurationSetForKey:(const std::string &)key
{
	const oo::PList *array = _doubleVerifierPList.get<oo::PList::Array>(key);
	if (array == nullptr)  return std::nullopt;

	std::set<std::string> strings;
	for (const oo::PList &element : *array->getIf<oo::PList::Array>())
	{
		if (const std::string *string = element.getIf<std::string>())  strings.insert(*string);
	}
	return std::vector<std::string>(strings.begin(), strings.end());
}

@end

#endif	// OO_TESTS_UNIT_CORE_OOOXPVERIFIERTESTDOUBLE_H
