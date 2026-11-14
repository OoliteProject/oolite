/*	test_OOPListSchemaVerifier.mm
	Unit tests for OOPListSchemaVerifier (src/Core/OXPVerifier/OOPListSchemaVerifier.h): bead
	oo-pni4, slice 1 of the Phase 3 slice plan docs/phases/3-slices/OOPListSchemaVerifier.md (the
	class shell, the public API and the OOPrivate verification core), in the house style of the
	OOColor exemplar (proposed ADR-0056).

	It pins what the verifier answered before the conversion, through the Objective-C API its one
	caller (OOCheckShipDataPListVerifierStage) uses: nil for a null schema, the delegate, verifying
	valid and invalid property lists (the failure the delegate is told about: code, reason, key path
	and expected type), $definitions macros and a bad schema, delegated types (answered, refused,
	throwing, or a delegate that does not handle them), a delegate that stops at the first failure,
	no failure handler at all, and +descriptionForKeyPath:. The expectations were written against
	the unconverted class and run on it first. After the conversion the class is cxx::
	OOPListSchemaVerifier behind an Objective-C facade; the test also checks the facade: the
	delegate is handed the facade it registered with, and the same answers come back.
	Run: bash tools/check-core-tests.sh test_OOPListSchemaVerifier
*/

#import "OOPListSchemaVerifier.h"
#import "OODescription.h"
#import "OOStringParsing.h"

#include "oofnd/PListParsing.hpp"
#include "oofnd/objc/OOException.h"

#include "oo_test.hpp"

#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>


// Link stubs (ADR-0056 amendment oo-zffj item 2): OOPListGameTypes.mm reaches OOStringParsing.mm's
// scanners for vector and quaternion values, whose object links the game. No schema here uses those
// types, so each stub aborts.
BOOL cxx_ScanVectorFromString(const std::optional<std::string> &, Vector *)  { std::abort(); }
BOOL cxx_ScanHPVectorFromString(const std::optional<std::string> &, HPVector *)  { std::abort(); }
BOOL cxx_ScanQuaternionFromString(const std::optional<std::string> &, Quaternion *)  { std::abort(); }


namespace {

oo::PList Parse(const char *text)
{
	auto result = oo::parsePropertyList(text);
	OO_CHECK(result.has_value());
	return result ? *result : oo::PList();
}


std::string KeyPathText(const oo::PList &keyPath)
{
	return [OOPListSchemaVerifier descriptionForKeyPath:keyPath].value_or("(nullopt)");
}


// One failure as the delegate saw it: "<code> <key path> | <reason> | <expected type>".
std::string FailureText(const OOPListSchemaVerifierError &error, const oo::PList &localSchema)
{
	const oo::PList *keyPath = error.userInfo.find(kPListKeyPathErrorKey);
	return std::to_string(error.code) + " " + KeyPathText(keyPath != nullptr ? *keyPath : oo::PList())
		+ " | " + error.failureReason.value_or("(nullopt)") + " | " + oo::DescriptionOf(localSchema);
}

}	// namespace


// A delegate that records what it is told. Delegated types answer `delegatedAnswer`, or raise.
@interface TestSchemaDelegate: OOObject
{
@public
	std::vector<std::string>	failures;
	std::vector<std::string>	delegated;		// "<name> <type key> <key path> <value>"
	std::vector<id>				verifiers;		// the verifier each call was handed
	BOOL						delegatedAnswer;
	BOOL						delegatedRaises;
	BOOL						delegatedError;
	BOOL						continueAfterFailure;
}
@end


@implementation TestSchemaDelegate

- (BOOL)verifier:(OOPListSchemaVerifier *)verifier
withPropertyList:(const oo::PList &)rootPList
		   named:(const std::string &)name
	testProperty:(const oo::PList &)subPList
		  atPath:(const oo::PList &)keyPath
	 againstType:(const oo::PList &)typeKey
		   error:(std::optional<OOPListSchemaVerifierError> *)outError
{
	(void)rootPList;
	verifiers.push_back(verifier);
	delegated.push_back(name + " " + oo::DescriptionOf(typeKey) + " " + KeyPathText(keyPath) + " " + oo::DescriptionOf(subPList));
	if (delegatedRaises)  [OOException raise:OOGenericException format:"delegate refuses %s", name.c_str()];
	if (delegatedError && outError != nullptr)  *outError = OOPListSchemaVerifierError{ "test.domain", 42, std::string("delegate's own error"), oo::PList() };
	return delegatedAnswer;
}


- (BOOL)verifier:(OOPListSchemaVerifier *)verifier
withPropertyList:(const oo::PList &)rootPList
		   named:(const std::string &)name
 failedForProperty:(const oo::PList &)subPList
	   withError:(const OOPListSchemaVerifierError &)error
	expectedType:(const oo::PList &)localSchema
{
	(void)rootPList; (void)subPList;
	verifiers.push_back(verifier);
	failures.push_back(name + ": " + FailureText(error, localSchema));
	return continueAfterFailure;
}

@end


// A delegate that handles neither delegated types nor failures.
@interface TestMuteDelegate: OOObject
@end

@implementation TestMuteDelegate
@end


namespace {

const char *const kShipSchema =
	"{ type = dictionary; allowOthers = NO; requiredKeys = ( name ); schema = {"
	"  name = string; count = positiveInteger; roles = { type = array; valueType = $role; };"
	"  scale = { type = float; minimum = 0.5; maximum = 2; };"
	"}; $definitions = { $role = { type = string; }; }; }";


oo::PList GoodShip()
{
	return oo::PList(oo::PList::Dict {
		{ "name", oo::PList("Cobra") },
		{ "count", oo::PList(3) },
		{ "roles", oo::PList(oo::PList::Array { oo::PList("trader"), oo::PList("hunter") }) },
		{ "scale", oo::PList(1.5) },
	});
}

}	// namespace


OO_TEST(nullSchemaGivesNil)
{
	OO_CHECK([OOPListSchemaVerifier verifierWithSchema:oo::PList()] == nil);
	OOPListSchemaVerifier *allocated = [[OOPListSchemaVerifier alloc] initWithSchema:oo::PList()];
	OO_CHECK(allocated == nil);
	OO_CHECK([OOPListSchemaVerifier verifierWithSchema:Parse("string")] != nil);
}


OO_TEST(keepsItsDelegate)
{
	@autoreleasepool
	{
		OOPListSchemaVerifier *verifier = [OOPListSchemaVerifier verifierWithSchema:Parse(kShipSchema)];
		OO_CHECK([verifier delegate] == nil);
		TestSchemaDelegate *delegate = [[[TestSchemaDelegate alloc] init] autorelease];
		[verifier setDelegate:delegate];
		OO_CHECK([verifier delegate] == delegate);
		OO_CHECK([delegate retainCount] == 1);	// not retained
		[verifier setDelegate:nil];
		OO_CHECK([verifier delegate] == nil);
	}
}


OO_TEST(acceptsAValidPropertyList)
{
	@autoreleasepool
	{
		OOPListSchemaVerifier *verifier = [OOPListSchemaVerifier verifierWithSchema:Parse(kShipSchema)];
		TestSchemaDelegate *delegate = [[[TestSchemaDelegate alloc] init] autorelease];
		[verifier setDelegate:delegate];
		OO_CHECK([verifier verifyPropertyList:GoodShip() named:"cobra"]);
		OO_CHECK(delegate->failures.empty());
		OO_CHECK(delegate->verifiers.empty());
	}
}


OO_TEST(reportsEachFailureToTheDelegate)
{
	@autoreleasepool
	{
		OOPListSchemaVerifier *verifier = [OOPListSchemaVerifier verifierWithSchema:Parse(kShipSchema)];
		TestSchemaDelegate *delegate = [[[TestSchemaDelegate alloc] init] autorelease];
		delegate->continueAfterFailure = YES;
		[verifier setDelegate:delegate];

		oo::PList::Dict ship = *GoodShip().getIf<oo::PList::Dict>();
		ship["count"] = oo::PList(-2);
		ship["roles"] = oo::PList(oo::PList::Array { oo::PList("trader"), oo::PList(7) });
		ship["scale"] = oo::PList(3.0);
		ship["colour"] = oo::PList("red");
		OO_CHECK(![verifier verifyPropertyList:oo::PList(ship) named:"bad"]);

		// As found before the conversion: count = -2 is not reported as a positiveInteger failure
		// (pinned, not judged).

		const std::vector<std::string> expected = {
			"bad: 9 root | Unpermitted key \"colour\" in dictionary. | {\"$definitions\" = {\"$role\" = {type = string; }; }; allowOthers = NO; requiredKeys = (name); schema = {count = positiveInteger; name = string; roles = {type = array; valueType = \"$role\"; }; scale = {maximum = 2; minimum = \"0.5\"; type = float; }; }; type = dictionary; }",
			"bad: 2 roles[1] | Expected string, found number. | $role",
			"bad: 4 scale | Number is too large (3, maximum is 2). | {maximum = 2; minimum = \"0.5\"; type = float; }",
		};
		OO_CHECK(delegate->failures == expected);
		for (id seen : delegate->verifiers)  OO_CHECK(seen == verifier);
	}
}


OO_TEST(stopsWhenTheDelegateSaysSo)
{
	@autoreleasepool
	{
		OOPListSchemaVerifier *verifier = [OOPListSchemaVerifier verifierWithSchema:Parse(kShipSchema)];
		TestSchemaDelegate *delegate = [[[TestSchemaDelegate alloc] init] autorelease];
		delegate->continueAfterFailure = NO;
		[verifier setDelegate:delegate];

		oo::PList::Dict ship = *GoodShip().getIf<oo::PList::Dict>();
		ship.erase("name");
		ship["count"] = oo::PList(-2);
		OO_CHECK(![verifier verifyPropertyList:oo::PList(ship) named:"stop"]);
		OO_CHECK_EQ(delegate->failures.size(), 1u);
		OO_CHECK(!delegate->failures.empty() && delegate->failures[0] == "stop: 10 root | Required keys (name) missing from dictionary. | {\"$definitions\" = {\"$role\" = {type = string; }; }; allowOthers = NO; requiredKeys = (name); schema = {count = positiveInteger; name = string; roles = {type = array; valueType = \"$role\"; }; scale = {maximum = 2; minimum = \"0.5\"; type = float; }; }; type = dictionary; }");
	}
}


OO_TEST(reportsABadSchema)
{
	@autoreleasepool
	{
		TestSchemaDelegate *delegate = [[[TestSchemaDelegate alloc] init] autorelease];
		delegate->continueAfterFailure = YES;

		OOPListSchemaVerifier *undefinedMacro = [OOPListSchemaVerifier verifierWithSchema:Parse("{ type = $nothing; }")];
		[undefinedMacro setDelegate:delegate];
		OO_CHECK(![undefinedMacro verifyPropertyList:oo::PList("x") named:"macro"]);

		OOPListSchemaVerifier *unknownType = [OOPListSchemaVerifier verifierWithSchema:Parse("{ type = gizmo; }")];
		[unknownType setDelegate:delegate];
		OO_CHECK(![unknownType verifyPropertyList:oo::PList("x") named:"unknown"]);

		OOPListSchemaVerifier *noType = [OOPListSchemaVerifier verifierWithSchema:Parse("{ minimum = 1; }")];
		[noType setDelegate:delegate];
		OO_CHECK(![noType verifyPropertyList:oo::PList("x") named:"untyped"]);

		const std::vector<std::string> expected = {
			"macro: 102 root | Bad schema: reference to undefined macro \"$nothing\". | {type = \"$nothing\"; }",
			"unknown: 103 root | Bad schema: unknown type \"gizmo\". | {type = gizmo; }",
			"untyped: 101 root | Bad schema: invalid type specifier for path root (no type specified). | {minimum = 1; }",
		};
		OO_CHECK(delegate->failures == expected);
	}
}


OO_TEST(asksTheDelegateAboutDelegatedTypes)
{
	@autoreleasepool
	{
		OOPListSchemaVerifier *verifier = [OOPListSchemaVerifier verifierWithSchema:Parse("{ type = array; valueType = { type = delegatedType; baseType = string; key = shipKey; }; }")];
		TestSchemaDelegate *delegate = [[[TestSchemaDelegate alloc] init] autorelease];
		delegate->continueAfterFailure = YES;
		[verifier setDelegate:delegate];
		const oo::PList list(oo::PList::Array { oo::PList("adder"), oo::PList("viper") });

		delegate->delegatedAnswer = YES;
		OO_CHECK([verifier verifyPropertyList:list named:"yes"]);

		delegate->delegatedAnswer = NO;
		OO_CHECK(![verifier verifyPropertyList:list named:"no"]);

		delegate->delegatedAnswer = YES;
		delegate->delegatedError = YES;
		OO_CHECK(![verifier verifyPropertyList:list named:"error"]);

		delegate->delegatedError = NO;
		delegate->delegatedRaises = YES;
		OO_CHECK(![verifier verifyPropertyList:list named:"raises"]);

		const std::vector<std::string> expectedDelegated = {
			"yes shipKey [0] adder",
			"yes shipKey [1] viper",
			"no shipKey [0] adder",
			"no shipKey [1] viper",
			"error shipKey [0] adder",
			"error shipKey [1] viper",
			"raises shipKey [0] adder",
			"raises shipKey [1] viper",
		};
		const std::vector<std::string> expectedFailures = {
			"no: 13 [0] | Value at [0] does not match delegated type \"shipKey\". | {baseType = string; key = shipKey; type = delegatedType; }",
			"no: 13 [1] | Value at [1] does not match delegated type \"shipKey\". | {baseType = string; key = shipKey; type = delegatedType; }",
			"error: 13 [0] | Value at [0] does not match delegated type \"shipKey\". | {baseType = string; key = shipKey; type = delegatedType; }",
			"error: 13 [1] | Value at [1] does not match delegated type \"shipKey\". | {baseType = string; key = shipKey; type = delegatedType; }",
			"raises: 13 [0] | Value at [0] does not match delegated type \"shipKey\". | {baseType = string; key = shipKey; type = delegatedType; }",
			"raises: 13 [1] | Value at [1] does not match delegated type \"shipKey\". | {baseType = string; key = shipKey; type = delegatedType; }",
		};
		OO_CHECK(delegate->delegated == expectedDelegated);
		OO_CHECK(delegate->failures == expectedFailures);
		for (id seen : delegate->verifiers)  OO_CHECK(seen == verifier);
	}
}


OO_TEST(aDelegateThatHandlesNothing)
{
	@autoreleasepool
	{
		// Delegated types pass; a failure stops verification.
		OOPListSchemaVerifier *verifier = [OOPListSchemaVerifier verifierWithSchema:Parse("{ type = array; valueType = { type = delegatedType; baseType = string; key = shipKey; }; }")];
		[verifier setDelegate:[[[TestMuteDelegate alloc] init] autorelease]];
		OO_CHECK([verifier verifyPropertyList:oo::PList(oo::PList::Array { oo::PList("adder"), oo::PList("viper") }) named:"mute"]);
		OO_CHECK(![verifier verifyPropertyList:oo::PList(4) named:"mute"]);

		OOPListSchemaVerifier *orphan = [OOPListSchemaVerifier verifierWithSchema:Parse("string")];
		OO_CHECK(![orphan verifyPropertyList:oo::PList(4) named:"orphan"]);
		OO_CHECK([orphan verifyPropertyList:oo::PList("four") named:"orphan"]);
	}
}


OO_TEST(describesKeyPaths)
{
	OO_CHECK_EQ(KeyPathText(oo::PList()), "root");
	OO_CHECK_EQ(KeyPathText(oo::PList(oo::PList::Array {})), "root");
	OO_CHECK_EQ(KeyPathText(oo::PList(oo::PList::Array { oo::PList("adder-player"), oo::PList("custom_views"), oo::PList(0), oo::PList("view_description") })), "adder-player.custom_views[0].view_description");
	OO_CHECK_EQ(KeyPathText(oo::PList(oo::PList::Array { oo::PList(2), oo::PList("x") })), "[2].x");
	OO_CHECK_EQ(KeyPathText(oo::PList(oo::PList::Array { oo::PList(1.5) })), "[1.5]");
	OO_CHECK_EQ(KeyPathText(oo::PList(oo::PList::Array { oo::PList("a"), oo::PList(oo::PList::Dict {}) })), "(nullopt)");
	OO_CHECK_EQ(KeyPathText(oo::PList("not an array")), "root");
}


// The facade (after the conversion): one live facade per C++ verifier, nil for null, and a C++-made
// verifier hands its delegate its live facade (a facade lives while someone holds it; the verifier
// does not keep one).
OO_TEST(facadeContract)
{
	@autoreleasepool
	{
		OOPListSchemaVerifier *verifier = [OOPListSchemaVerifier verifierWithSchema:Parse("string")];
		cxx::OOPListSchemaVerifier *cxxVerifier = oo::ToCxx(verifier);
		OO_CHECK(cxxVerifier != nullptr);
		OO_CHECK(oo::ToObjC(cxxVerifier) == verifier);
		OO_CHECK(oo::ToCxx(static_cast<OOPListSchemaVerifier *>(nil)) == nullptr);
		OO_CHECK(oo::ToObjC(static_cast<cxx::OOPListSchemaVerifier *>(nullptr)) == nil);
		OO_CHECK(cxx::OOPListSchemaVerifier::verifierWithSchema(oo::PList()).get() == nullptr);

		oo::Ref<cxx::OOPListSchemaVerifier> made = cxx::OOPListSchemaVerifier::verifierWithSchema(Parse("string"));
		TestSchemaDelegate *delegate = [[[TestSchemaDelegate alloc] init] autorelease];
		made->setDelegate(delegate);
		OO_CHECK(made->delegate() == delegate);
		OOPListSchemaVerifier *facade = oo::ToObjC(made.get());	// live while the pool is: the delegate is handed it
		OO_CHECK(!made->verifyPropertyList(oo::PList(4), "made"));
		OO_CHECK(made->verifyPropertyList(oo::PList("four"), "made"));
		OO_CHECK_EQ(delegate->verifiers.size(), 1u);
		OO_CHECK(!delegate->verifiers.empty() && delegate->verifiers[0] == facade);
		OO_CHECK(oo::ToCxx(facade) == made.get());
		OO_CHECK([facade verifyPropertyList:oo::PList("four") named:"facade"]);
		OO_CHECK_EQ(cxx::OOPListSchemaVerifier::descriptionForKeyPath(oo::PList(oo::PList::Array { oo::PList("a"), oo::PList(3) })).value_or(""), "a[3]");
	}
}


OO_TEST_MAIN()
