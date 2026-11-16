/*	test_OOOXPVerifierStage.mm
	Unit tests for cxx::OOOXPVerifierStage (src/Core/OXPVerifier/OOOXPVerifierStage.h) and its
	Objective-C facade (OOOXPVerifierStage+ObjCBridge.h): bead oo-cwz, the Phase 3 class-HIERARCHY
	exemplar (proposed ADR-0056, Amendment 1).

	The base class has a dozen Objective-C subclasses that convert in their own beads, and the
	Objective-C OOOXPVerifier drives every stage. So this pins, from the Objective-C bodies, what
	the base computed before the conversion, through the Objective-C API those callers use: the
	defaults a subclass inherits, the dependency graph (direct and recursive dependency, no
	duplicates, dependents told once in registration order), running and skipping, an exception
	from -run caught, the description, and [super ...] from an Objective-C subclass. Then the
	hierarchy's crossing both ways: a C++ stage (the converted kind) behind the facade, an
	Objective-C stage (the unconverted kind) behind a C++ pointer, identity kept, virtual dispatch
	reaching the subclass on each side. Run: bash tools/check-core-tests.sh
*/

#import "OOOXPVerifierStageInternal.h"
#import "OODescription.h"
#include "oofnd/objc/OOException.h"

#import "OOLogging.h"
#include "oo_test.hpp"


/*	The game's OOLogging.mm reaches the resource manager, so it is not linked. The one function of
	it that the base calls is defined here instead, and counts: "subclass responsibility" is
	checked, not only logged.
*/
static int gSubclassResponsibilities = 0;

void OOLogGenericSubclassResponsibilityForFunction(const char *inFunction)
{
	(void)inFunction;
	gSubclassResponsibilities++;
}


// An unconverted stage: an Objective-C subclass that overrides the subclass responsibilities.
@interface TestObjCStage: OOOXPVerifierStage
{
@public
	std::string									_testName;
	std::optional<std::vector<std::string>>		_testDependencies;
	int											_runs;
	BOOL										_raise;
}
@end


@implementation TestObjCStage

- (std::optional<std::string>)cxx_name						{ return _testName; }
- (std::optional<std::vector<std::string>>)cxx_dependencies	{ return _testDependencies; }

- (void)run
{
	_runs++;
	if (_raise)  [OOException raise:"TestException" format:"%s", "raised by the test"];
}

@end


// Extends its superclass's dependents through [super dependents], as OOTextureHandlingStage does.
@interface TestSuperCallingStage: TestObjCStage
@end


@implementation TestSuperCallingStage

- (std::optional<std::vector<std::string>>)dependents
{
	std::vector<std::string> result = [super dependents].value_or(std::vector<std::string>());
	result.push_back("Listing unused files");
	return result;
}

@end


// A converted stage: a C++ subclass that overrides the virtual members. Global, as a game class
// is, so that its description names it as the game's would.
class TestCxxStage : public cxx::OOOXPVerifierStage
{
public:
	explicit TestCxxStage(std::string testName) : _testName(std::move(testName)) {}

	std::optional<std::string> name() override						{ return _testName; }
	std::optional<std::vector<std::string>> dependents() override	{ return std::vector<std::string>{ "Dependent" }; }
	bool shouldRun() override										{ return _shouldRun; }
	void run() override												{ runs++; }

	int		runs = 0;
	bool	_shouldRun = false;

private:
	std::string _testName;
};


namespace {

TestObjCStage *MakeStage(const char *name)
{
	TestObjCStage *stage = [[[TestObjCStage alloc] init] autorelease];
	stage->_testName = name;
	return stage;
}


bool Holds(const std::vector<oo::ObjCRef<OOOXPVerifierStage *>> &stages, std::initializer_list<OOOXPVerifierStage *> expected)
{
	if (stages.size() != expected.size())  return false;
	std::size_t i = 0;
	for (OOOXPVerifierStage *stage : expected)
	{
		if (stages[i++].get() != stage)  return false;
	}
	return true;
}

}	// namespace


OO_TEST(baseDefaults)
{
	@autoreleasepool
	{
		OOOXPVerifierStage *stage = [[[OOOXPVerifierStage alloc] init] autorelease];
		const int before = gSubclassResponsibilities;
		OO_CHECK(![stage cxx_name].has_value());	// subclass responsibility: logs, answers nil
		OO_CHECK(gSubclassResponsibilities == before + 1);
		[stage run];
		OO_CHECK(gSubclassResponsibilities == before + 2);
		OO_CHECK(![stage cxx_dependencies].has_value());
		OO_CHECK(![stage dependents].has_value());
		OO_CHECK([stage shouldRun]);
		OO_CHECK(![stage completed]);
		OO_CHECK(![stage canRun]);
		OO_CHECK([stage verifier] == nil);
		OO_CHECK([stage resolvedDependencies].empty() && [stage resolvedDependents].empty());
		[stage dependencyRegistrationComplete];
		OO_CHECK([stage canRun]);	// nothing to wait for
	}
}


OO_TEST(verifierIsNotRetained)
{
	@autoreleasepool
	{
		OOObject *object = [[OOObject alloc] init];
		OOOXPVerifier *verifier = (OOOXPVerifier *)object;
		TestObjCStage *stage = MakeStage("Stage");
		const unsigned before = [object retainCount];
		[stage setVerifier:verifier];
		OO_CHECK([object retainCount] == before);
		@autoreleasepool
		{
			OO_CHECK([stage verifier] == verifier);
		}
		OO_CHECK([object retainCount] == before);
		[object release];
	}
}


OO_TEST(dependencyGraph)
{
	@autoreleasepool
	{
		TestObjCStage *a = MakeStage("A"), *b = MakeStage("B"), *c = MakeStage("C"), *d = MakeStage("D");
		[b registerDependency:a];
		[c registerDependency:b];
		[c registerDependency:b];	// no duplicates
		[d registerDependency:a];

		OO_CHECK([b isDependentOf:a] && [c isDependentOf:b]);
		OO_CHECK([c isDependentOf:a]);	// recursive
		OO_CHECK(![a isDependentOf:c] && ![b isDependentOf:c] && ![d isDependentOf:b]);
		OO_CHECK(![c isDependentOf:nil]);
		OO_CHECK(Holds([c resolvedDependencies], { b }));
		OO_CHECK(Holds([a resolvedDependents], { b, d }));	// registration order
		OO_CHECK(Holds([b resolvedDependents], { c }));

		for (TestObjCStage *stage : { a, b, c, d })  [stage dependencyRegistrationComplete];
		OO_CHECK([a canRun] && ![b canRun] && ![c canRun] && ![d canRun]);

		[a performRun];
		OO_CHECK(a->_runs == 1 && [a completed] && ![a canRun]);
		OO_CHECK([b canRun] && [d canRun] && ![c canRun]);	// every dependent told

		[b noteSkipped];
		OO_CHECK(b->_runs == 0 && [b completed] && ![b canRun]);
		OO_CHECK([c canRun]);
	}
}


OO_TEST(exceptionInRunIsCaught)
{
	@autoreleasepool
	{
		TestObjCStage *raising = MakeStage("Raising"), *after = MakeStage("After");
		raising->_raise = YES;
		[after registerDependency:raising];
		[raising dependencyRegistrationComplete];
		[after dependencyRegistrationComplete];

		[raising performRun];	// logs verifyOXP.exception
		OO_CHECK(raising->_runs == 1 && [raising completed]);
		OO_CHECK([after canRun]);
	}
}


OO_TEST(superCallsReachTheBase)
{
	@autoreleasepool
	{
		TestSuperCallingStage *stage = [[[TestSuperCallingStage alloc] init] autorelease];
		const std::optional<std::vector<std::string>> dependents = [stage dependents];
		OO_CHECK(dependents == std::vector<std::string>{ "Listing unused files" });
	}
}


OO_TEST(description)
{
	@autoreleasepool
	{
		const std::string text = oo::DescriptionOf(MakeStage("Checking things"));
		OO_CHECK(text.starts_with("<TestObjCStage 0x"));
		OO_CHECK(text.ends_with(">{\"Checking things\"}"));
		OO_CHECK(oo::DescriptionOf([[[OOOXPVerifierStage alloc] init] autorelease]).ends_with(">{\"(null)\"}"));
	}
}


OO_TEST(cxxStageBehindTheFacade)
{
	@autoreleasepool
	{
		const oo::Ref<TestCxxStage> stage = oo::makeRef<TestCxxStage>("Cxx");
		OOOXPVerifierStage *facade = oo::ToObjC(stage.get());
		OO_CHECK(facade != nil && facade == oo::ToObjC(stage.get()));	// one live facade
		OO_CHECK(oo::ToCxx(facade) == stage.get());

		// The Objective-C verifier's messages reach the C++ overrides, and the base's defaults.
		OO_CHECK([facade cxx_name] == std::optional<std::string>("Cxx"));
		OO_CHECK(![facade cxx_dependencies].has_value());
		OO_CHECK([facade dependents] == std::vector<std::string>{ "Dependent" });
		OO_CHECK(![facade shouldRun]);
		[facade dependencyRegistrationComplete];
		[facade performRun];
		OO_CHECK(stage->runs == 1 && [facade completed] && stage->completed());

		// Described with the C++ class's name, as [self class] named it.
		const std::string text = oo::DescriptionOf(facade);
		OO_CHECK(text.starts_with("<TestCxxStage 0x"));
		OO_CHECK(text.ends_with(">{\"Cxx\"}"));
		OO_CHECK(stage->descriptionComponents() == std::optional<std::string>("\"Cxx\""));
	}
}


OO_TEST(objCStageBehindACxxPointer)
{
	@autoreleasepool
	{
		TestObjCStage *objCStage = MakeStage("ObjC");
		cxx::OOOXPVerifierStage *part = oo::ToCxx(objCStage);
		OO_CHECK(part != nullptr && oo::ToObjC(part) == objCStage);	// the object itself

		// Virtual calls from C++ reach the Objective-C overrides.
		OO_CHECK(part->name() == std::optional<std::string>("ObjC"));
		objCStage->_testDependencies = std::vector<std::string>{ "Cxx" };
		OO_CHECK(part->dependencies() == objCStage->_testDependencies);
		OO_CHECK(part->shouldRun());	// not overridden: the base's answer
		OO_CHECK(!part->dependents().has_value());

		// [super dependents] on the Objective-C side still reaches the base, not back to the subclass.
		TestSuperCallingStage *superCalling = [[[TestSuperCallingStage alloc] init] autorelease];
		OO_CHECK(oo::ToCxx(superCalling)->dependents() == std::vector<std::string>{ "Listing unused files" });
	}
}


OO_TEST(mixedDependencyGraph)
{
	@autoreleasepool
	{
		const oo::Ref<TestCxxStage> cxxStage = oo::makeRef<TestCxxStage>("Cxx");
		cxxStage->_shouldRun = true;
		TestObjCStage *objCStage = MakeStage("ObjC");

		// The Objective-C verifier wires a C++ stage in through its facade.
		[objCStage registerDependency:oo::ToObjC(cxxStage.get())];
		OO_CHECK([objCStage isDependentOf:oo::ToObjC(cxxStage.get())]);
		OO_CHECK(oo::ToCxx(objCStage)->isDependentOf(cxxStage.get()));
		OO_CHECK(Holds([oo::ToObjC(cxxStage.get()) resolvedDependents], { objCStage }));
		OO_CHECK(cxxStage->resolvedDependents().size() == 1 && cxxStage->resolvedDependents()[0] == oo::ToCxx(objCStage));

		cxxStage->dependencyRegistrationComplete();
		oo::ToCxx(objCStage)->dependencyRegistrationComplete();
		OO_CHECK(cxxStage->canRun() && ![objCStage canRun]);
		cxxStage->performRun();
		OO_CHECK(cxxStage->runs == 1 && [objCStage canRun]);
		oo::ToCxx(objCStage)->performRun();	// virtual run() reaches -run
		OO_CHECK(objCStage->_runs == 1 && [objCStage completed]);
	}
}


OO_TEST(nilAndLifetime)
{
	OOOXPVerifierStage *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOOXPVerifierStage *>(nullptr)) == nil);
	OO_CHECK(![none cxx_name].has_value());

	// An Objective-C stage's C++ part outlives it only as a reference another stage holds; it
	// then answers as a message to the released stage's nil would.
	oo::Ref<cxx::OOOXPVerifierStage> part;
	@autoreleasepool
	{
		part = oo::Ref<cxx::OOOXPVerifierStage>(oo::ToCxx(MakeStage("Gone")));
	}
	OO_CHECK(!part->name().has_value());
	OO_CHECK(oo::ToObjC(part) == nil);
}

OO_TEST_MAIN()
