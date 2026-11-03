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
	the unconverted class and run on it first. After the conversion the class was cxx::
	OOPListSchemaVerifier behind an Objective-C facade.

	Bead oo-9ht.119 deleted the facade (ADR-0056 amendment "deleting a facade") and made the
	delegate's informal protocol the C++ interface OOPListSchemaVerifierDelegate. The cases ask
	the C++ verifier with the same expectations (+verifierWithSchema: and alloc/init as the
	factories, nil as null); the Objective-C test delegate became a C++ one recording the same
	(reference counted, so that it is still checked not retained); a delegate that answered neither
	selector cannot be written in C++, so aDelegateThatHandlesNothing verifies with no delegate,
	the path an unanswered selector took. facadeContract, which pinned only the facade (one live
	facade, oo::ToObjC/oo::ToCxx, the delegate handed the facade), was retired with it (ADR-0049,
	standing approval oo-9n5p9); its C++ API checks are delegateIsHandedTheVerifier.
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
	return OOPListSchemaVerifier::descriptionForKeyPath(keyPath).value_or("(nullopt)");
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
// (An Objective-C object answering the informal protocol until bead oo-9ht.119; reference
// counted, as that object was, so the test can check the verifier does not retain it.)
class TestSchemaDelegate : public oo::RefCounted, public OOPListSchemaVerifierDelegate
{
public:
	std::vector<std::string>				failures;
	std::vector<std::string>				delegated;		// "<name> <type key> <key path> <value>"
	std::vector<OOPListSchemaVerifier *>	verifiers;		// the verifier each call was handed
	bool									delegatedAnswer = false;
	bool									delegatedRaises = false;
	bool									delegatedError = false;
	bool									continueAfterFailure = false;

	bool verifierTestProperty(OOPListSchemaVerifier *verifier,
							  const oo::PList &rootPList,
							  const std::string &name,
							  const oo::PList &subPList,
							  const oo::PList &keyPath,
							  const oo::PList &typeKey,
							  std::optional<OOPListSchemaVerifierError> *outError) override
	{
		(void)rootPList;
		verifiers.push_back(verifier);
		delegated.push_back(name + " " + oo::DescriptionOf(typeKey) + " " + KeyPathText(keyPath) + " " + oo::DescriptionOf(subPList));
		if (delegatedRaises)  [OOException raise:OOGenericException format:"delegate refuses %s", name.c_str()];
		if (delegatedError && outError != nullptr)  *outError = OOPListSchemaVerifierError{ "test.domain", 42, std::string("delegate's own error"), oo::PList() };
		return delegatedAnswer;
	}

	bool verifierFailedForProperty(OOPListSchemaVerifier *verifier,
								   const oo::PList &rootPList,
								   const std::string &name,
								   const oo::PList &subPList,
								   const OOPListSchemaVerifierError &error,
								   const oo::PList &localSchema) override
	{
		(void)rootPList; (void)subPList;
		verifiers.push_back(verifier);
		failures.push_back(name + ": " + FailureText(error, localSchema));
		return continueAfterFailure;
	}
};


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
	OO_CHECK(OOPListSchemaVerifier::verifierWithSchema(oo::PList()) == nullptr);
	const oo::Ref<OOPListSchemaVerifier> allocated = OOPListSchemaVerifier::initWithSchema(oo::PList());
	OO_CHECK(allocated == nullptr);
	OO_CHECK(OOPListSchemaVerifier::verifierWithSchema(Parse("string")) != nullptr);
}


OO_TEST(keepsItsDelegate)
{
	@autoreleasepool
	{
		const oo::Ref<OOPListSchemaVerifier> verifier = OOPListSchemaVerifier::verifierWithSchema(Parse(kShipSchema));
		OO_CHECK(verifier->delegate() == nullptr);
		const oo::Ref<TestSchemaDelegate> delegate = oo::makeRef<TestSchemaDelegate>();
		verifier->setDelegate(delegate.get());
		OO_CHECK(verifier->delegate() == delegate.get());
		OO_CHECK(delegate->retainCount() == 1);	// not retained
		verifier->setDelegate(nullptr);
		OO_CHECK(verifier->delegate() == nullptr);
	}
}


OO_TEST(acceptsAValidPropertyList)
{
	@autoreleasepool
	{
		const oo::Ref<OOPListSchemaVerifier> verifier = OOPListSchemaVerifier::verifierWithSchema(Parse(kShipSchema));
		const oo::Ref<TestSchemaDelegate> delegate = oo::makeRef<TestSchemaDelegate>();
		verifier->setDelegate(delegate.get());
		OO_CHECK(verifier->verifyPropertyList(GoodShip(), "cobra"));
		OO_CHECK(delegate->failures.empty());
		OO_CHECK(delegate->verifiers.empty());
	}
}


OO_TEST(reportsEachFailureToTheDelegate)
{
	@autoreleasepool
	{
		const oo::Ref<OOPListSchemaVerifier> verifier = OOPListSchemaVerifier::verifierWithSchema(Parse(kShipSchema));
		const oo::Ref<TestSchemaDelegate> delegate = oo::makeRef<TestSchemaDelegate>();
		delegate->continueAfterFailure = true;
		verifier->setDelegate(delegate.get());

		oo::PList::Dict ship = *GoodShip().getIf<oo::PList::Dict>();
		ship["count"] = oo::PList(-2);
		ship["roles"] = oo::PList(oo::PList::Array { oo::PList("trader"), oo::PList(7) });
		ship["scale"] = oo::PList(3.0);
		ship["colour"] = oo::PList("red");
		OO_CHECK(!verifier->verifyPropertyList(oo::PList(ship), "bad"));

		// As found before the conversion: count = -2 is not reported as a positiveInteger failure
		// (pinned, not judged).

		const std::vector<std::string> expected = {
			"bad: 9 root | Unpermitted key \"colour\" in dictionary. | {\"$definitions\" = {\"$role\" = {type = string; }; }; allowOthers = NO; requiredKeys = (name); schema = {count = positiveInteger; name = string; roles = {type = array; valueType = \"$role\"; }; scale = {maximum = 2; minimum = \"0.5\"; type = float; }; }; type = dictionary; }",
			"bad: 2 roles[1] | Expected string, found number. | $role",
			"bad: 4 scale | Number is too large (3, maximum is 2). | {maximum = 2; minimum = \"0.5\"; type = float; }",
		};
		OO_CHECK(delegate->failures == expected);
		for (OOPListSchemaVerifier *seen : delegate->verifiers)  OO_CHECK(seen == verifier.get());
	}
}


OO_TEST(stopsWhenTheDelegateSaysSo)
{
	@autoreleasepool
	{
		const oo::Ref<OOPListSchemaVerifier> verifier = OOPListSchemaVerifier::verifierWithSchema(Parse(kShipSchema));
		const oo::Ref<TestSchemaDelegate> delegate = oo::makeRef<TestSchemaDelegate>();
		delegate->continueAfterFailure = false;
		verifier->setDelegate(delegate.get());

		oo::PList::Dict ship = *GoodShip().getIf<oo::PList::Dict>();
		ship.erase("name");
		ship["count"] = oo::PList(-2);
		OO_CHECK(!verifier->verifyPropertyList(oo::PList(ship), "stop"));
		OO_CHECK_EQ(delegate->failures.size(), 1u);
		OO_CHECK(!delegate->failures.empty() && delegate->failures[0] == "stop: 10 root | Required keys (name) missing from dictionary. | {\"$definitions\" = {\"$role\" = {type = string; }; }; allowOthers = NO; requiredKeys = (name); schema = {count = positiveInteger; name = string; roles = {type = array; valueType = \"$role\"; }; scale = {maximum = 2; minimum = \"0.5\"; type = float; }; }; type = dictionary; }");
	}
}


OO_TEST(reportsABadSchema)
{
	@autoreleasepool
	{
		const oo::Ref<TestSchemaDelegate> delegate = oo::makeRef<TestSchemaDelegate>();
		delegate->continueAfterFailure = true;

		const oo::Ref<OOPListSchemaVerifier> undefinedMacro = OOPListSchemaVerifier::verifierWithSchema(Parse("{ type = $nothing; }"));
		undefinedMacro->setDelegate(delegate.get());
		OO_CHECK(!undefinedMacro->verifyPropertyList(oo::PList("x"), "macro"));

		const oo::Ref<OOPListSchemaVerifier> unknownType = OOPListSchemaVerifier::verifierWithSchema(Parse("{ type = gizmo; }"));
		unknownType->setDelegate(delegate.get());
		OO_CHECK(!unknownType->verifyPropertyList(oo::PList("x"), "unknown"));

		const oo::Ref<OOPListSchemaVerifier> noType = OOPListSchemaVerifier::verifierWithSchema(Parse("{ minimum = 1; }"));
		noType->setDelegate(delegate.get());
		OO_CHECK(!noType->verifyPropertyList(oo::PList("x"), "untyped"));

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
		const oo::Ref<OOPListSchemaVerifier> verifier = OOPListSchemaVerifier::verifierWithSchema(Parse("{ type = array; valueType = { type = delegatedType; baseType = string; key = shipKey; }; }"));
		const oo::Ref<TestSchemaDelegate> delegate = oo::makeRef<TestSchemaDelegate>();
		delegate->continueAfterFailure = true;
		verifier->setDelegate(delegate.get());
		const oo::PList list(oo::PList::Array { oo::PList("adder"), oo::PList("viper") });

		delegate->delegatedAnswer = true;
		OO_CHECK(verifier->verifyPropertyList(list, "yes"));

		delegate->delegatedAnswer = false;
		OO_CHECK(!verifier->verifyPropertyList(list, "no"));

		delegate->delegatedAnswer = true;
		delegate->delegatedError = true;
		OO_CHECK(!verifier->verifyPropertyList(list, "error"));

		delegate->delegatedError = false;
		delegate->delegatedRaises = true;
		OO_CHECK(!verifier->verifyPropertyList(list, "raises"));

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
		for (OOPListSchemaVerifier *seen : delegate->verifiers)  OO_CHECK(seen == verifier.get());
	}
}


OO_TEST(aDelegateThatHandlesNothing)
{
	@autoreleasepool
	{
		// Delegated types pass; a failure stops verification. (A delegate that answered neither
		// selector until bead oo-9ht.119; no delegate takes the same path.)
		const oo::Ref<OOPListSchemaVerifier> verifier = OOPListSchemaVerifier::verifierWithSchema(Parse("{ type = array; valueType = { type = delegatedType; baseType = string; key = shipKey; }; }"));
		verifier->setDelegate(nullptr);
		OO_CHECK(verifier->verifyPropertyList(oo::PList(oo::PList::Array { oo::PList("adder"), oo::PList("viper") }), "mute"));
		OO_CHECK(!verifier->verifyPropertyList(oo::PList(4), "mute"));

		const oo::Ref<OOPListSchemaVerifier> orphan = OOPListSchemaVerifier::verifierWithSchema(Parse("string"));
		OO_CHECK(!orphan->verifyPropertyList(oo::PList(4), "orphan"));
		OO_CHECK(orphan->verifyPropertyList(oo::PList("four"), "orphan"));
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


// The C++ verifier hands its delegate itself (it handed the Objective-C delegate its facade until
// bead oo-9ht.119, which retired facadeContract; these are that case's C++ API checks).
OO_TEST(delegateIsHandedTheVerifier)
{
	@autoreleasepool
	{
		OO_CHECK(OOPListSchemaVerifier::verifierWithSchema(oo::PList()).get() == nullptr);

		oo::Ref<OOPListSchemaVerifier> made = OOPListSchemaVerifier::verifierWithSchema(Parse("string"));
		const oo::Ref<TestSchemaDelegate> delegate = oo::makeRef<TestSchemaDelegate>();
		made->setDelegate(delegate.get());
		OO_CHECK(made->delegate() == delegate.get());
		OO_CHECK(!made->verifyPropertyList(oo::PList(4), "made"));
		OO_CHECK(made->verifyPropertyList(oo::PList("four"), "made"));
		OO_CHECK_EQ(delegate->verifiers.size(), 1u);
		OO_CHECK(!delegate->verifiers.empty() && delegate->verifiers[0] == made.get());
		OO_CHECK_EQ(OOPListSchemaVerifier::descriptionForKeyPath(oo::PList(oo::PList::Array { oo::PList("a"), oo::PList(3) })).value_or(""), "a[3]");
	}
}


OO_TEST_MAIN()
