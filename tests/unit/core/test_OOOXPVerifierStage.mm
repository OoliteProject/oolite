/*	test_OOOXPVerifierStage.mm
	Unit tests for OOOXPVerifierStage (src/Core/OXPVerifier/OOOXPVerifierStage.h): bead oo-cwz, the
	Phase 3 class-HIERARCHY exemplar (proposed ADR-0056, Amendment 1).

	The base class has a dozen Objective-C subclasses that convert in their own beads, and the
	Objective-C OOOXPVerifier drives every stage. So this pins, from the Objective-C bodies, what
	the base computed before the conversion, through the Objective-C API those callers use: the
	defaults a subclass inherits, the dependency graph (direct and recursive dependency, no
	duplicates, dependents told once in registration order), running and skipping, an exception
	from -run caught, the description, and [super ...] from an Objective-C subclass. Then the
	hierarchy's crossing both ways: a C++ stage (the converted kind) behind the facade, an
	Objective-C stage (the unconverted kind) behind a C++ pointer, identity kept, virtual dispatch
	reaching the subclass on each side.

	Bead oo-9ht.4 deleted the Objective-C facade (ADR-0056 amendment "deleting a facade") once the
	verifier and every stage were C++, and moved the class out of namespace cxx. The cases that
	asked through its selectors ask the C++ class with the same expectations: the Objective-C test
	stages became C++ subclasses with the same names and answers (the super call a qualified base
	call), -description is description(). What pinned only the facade (the crossings in
	cxxStageBehindTheFacade and objCStageBehindACxxPointer, and nilAndLifetime: nil crossings and
	the adapter outliving its Objective-C owner) was retired with it (ADR-0049, standing approval
	oo-9n5p9). Run: bash tools/check-core-tests.sh
*/

#import "OOOXPVerifierStage.h"
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


/*	A verifier for verifierIsNotRetained: the stage keeps the C++ verifier since bead oo-qg71f (it
	kept the Objective-C one, which the test stood in for with a plain object). Its constructor is
	private; the class names this struct its friend for tests. Nothing the verifier defines out of
	line is called, so OOOXPVerifier.mm is not linked.
*/
struct OOOXPVerifierTestAccess
{
	static oo::Ref<OOOXPVerifier> Make()	{ return oo::adopt(new OOOXPVerifier()); }
};


/*	A stage that overrides the subclass responsibilities. It was an Objective-C subclass of the
	facade (an unconverted stage) until bead oo-9ht.4; it keeps its name, so its description is the
	one the test pinned.
*/
class TestObjCStage : public OOOXPVerifierStage
{
public:
	std::optional<std::string> name() override							{ return _testName; }
	std::optional<std::vector<std::string>> dependencies() override		{ return _testDependencies; }

	void run() override
	{
		_runs++;
		if (_raise)  [OOException raise:"TestException" format:"%s", "raised by the test"];
	}

	std::string									_testName;
	std::optional<std::vector<std::string>>		_testDependencies;
	int											_runs = 0;
	bool										_raise = false;
};


// Extends its superclass's dependents through its base's dependents() ([super dependents] until
// bead oo-9ht.4), as OOTextureHandlingStage does.
class TestSuperCallingStage : public TestObjCStage
{
public:
	std::optional<std::vector<std::string>> dependents() override
	{
		std::vector<std::string> result = TestObjCStage::dependents().value_or(std::vector<std::string>());
		result.push_back("Listing unused files");
		return result;
	}
};


// A converted stage: a C++ subclass that overrides the virtual members. Global, as a game class
// is, so that its description names it as the game's would.
class TestCxxStage : public OOOXPVerifierStage
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

oo::Ref<TestObjCStage> MakeStage(const char *name)
{
	oo::Ref<TestObjCStage> stage = oo::makeRef<TestObjCStage>();
	stage->_testName = name;
	return stage;
}


bool Holds(const std::vector<oo::Ref<OOOXPVerifierStage>> &stages, std::initializer_list<OOOXPVerifierStage *> expected)
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
		const oo::Ref<OOOXPVerifierStage> stage = oo::makeRef<OOOXPVerifierStage>();
		const int before = gSubclassResponsibilities;
		OO_CHECK(!stage->name().has_value());	// subclass responsibility: logs, answers nil
		OO_CHECK(gSubclassResponsibilities == before + 1);
		stage->run();
		OO_CHECK(gSubclassResponsibilities == before + 2);
		OO_CHECK(!stage->dependencies().has_value());
		OO_CHECK(!stage->dependents().has_value());
		OO_CHECK(stage->shouldRun());
		OO_CHECK(!stage->completed());
		OO_CHECK(!stage->canRun());
		OO_CHECK(stage->verifier() == nullptr);
		OO_CHECK(stage->resolvedDependencies().empty() && stage->resolvedDependents().empty());
		stage->dependencyRegistrationComplete();
		OO_CHECK(stage->canRun());	// nothing to wait for
	}
}


OO_TEST(verifierIsNotRetained)
{
	@autoreleasepool
	{
		const oo::Ref<OOOXPVerifier> object = OOOXPVerifierTestAccess::Make();
		OOOXPVerifier *verifier = object.get();
		const oo::Ref<TestObjCStage> stage = MakeStage("Stage");
		const unsigned before = object->retainCount();
		stage->setVerifier(verifier);
		OO_CHECK(object->retainCount() == before);
		@autoreleasepool
		{
			OO_CHECK(stage->verifier() == verifier);
		}
		OO_CHECK(object->retainCount() == before);
	}
}


OO_TEST(dependencyGraph)
{
	@autoreleasepool
	{
		const oo::Ref<TestObjCStage> a = MakeStage("A"), b = MakeStage("B"), c = MakeStage("C"), d = MakeStage("D");
		b->registerDependency(a.get());
		c->registerDependency(b.get());
		c->registerDependency(b.get());	// no duplicates
		d->registerDependency(a.get());

		OO_CHECK(b->isDependentOf(a.get()) && c->isDependentOf(b.get()));
		OO_CHECK(c->isDependentOf(a.get()));	// recursive
		OO_CHECK(!a->isDependentOf(c.get()) && !b->isDependentOf(c.get()) && !d->isDependentOf(b.get()));
		OO_CHECK(!c->isDependentOf(nullptr));
		OO_CHECK(Holds(c->resolvedDependencies(), { b.get() }));
		OO_CHECK(Holds(a->resolvedDependents(), { b.get(), d.get() }));	// registration order
		OO_CHECK(Holds(b->resolvedDependents(), { c.get() }));

		for (TestObjCStage *stage : { a.get(), b.get(), c.get(), d.get() })  stage->dependencyRegistrationComplete();
		OO_CHECK(a->canRun() && !b->canRun() && !c->canRun() && !d->canRun());

		a->performRun();
		OO_CHECK(a->_runs == 1 && a->completed() && !a->canRun());
		OO_CHECK(b->canRun() && d->canRun() && !c->canRun());	// every dependent told

		b->noteSkipped();
		OO_CHECK(b->_runs == 0 && b->completed() && !b->canRun());
		OO_CHECK(c->canRun());
	}
}


OO_TEST(exceptionInRunIsCaught)
{
	@autoreleasepool
	{
		const oo::Ref<TestObjCStage> raising = MakeStage("Raising"), after = MakeStage("After");
		raising->_raise = true;
		after->registerDependency(raising.get());
		raising->dependencyRegistrationComplete();
		after->dependencyRegistrationComplete();

		raising->performRun();	// logs verifyOXP.exception
		OO_CHECK(raising->_runs == 1 && raising->completed());
		OO_CHECK(after->canRun());
	}
}


OO_TEST(superCallsReachTheBase)
{
	@autoreleasepool
	{
		const oo::Ref<TestSuperCallingStage> stage = oo::makeRef<TestSuperCallingStage>();
		const std::optional<std::vector<std::string>> dependents = stage->dependents();
		OO_CHECK(dependents == std::vector<std::string>{ "Listing unused files" });
	}
}


OO_TEST(description)
{
	@autoreleasepool
	{
		const std::string text = MakeStage("Checking things")->description();
		OO_CHECK(text.starts_with("<TestObjCStage 0x"));
		OO_CHECK(text.ends_with(">{\"Checking things\"}"));
		OO_CHECK(oo::makeRef<OOOXPVerifierStage>()->description().ends_with(">{\"(null)\"}"));
	}
}


OO_TEST(cxxStageBehindTheFacade)
{
	@autoreleasepool
	{
		const oo::Ref<TestCxxStage> stage = oo::makeRef<TestCxxStage>("Cxx");

		// The verifier's calls reach the C++ overrides, and the base's defaults.
		OO_CHECK(stage->name() == std::optional<std::string>("Cxx"));
		OO_CHECK(!stage->dependencies().has_value());
		OO_CHECK(stage->dependents() == std::vector<std::string>{ "Dependent" });
		OO_CHECK(!stage->shouldRun());
		stage->dependencyRegistrationComplete();
		stage->performRun();
		OO_CHECK(stage->runs == 1 && stage->completed() && stage->completed());

		// Described with the C++ class's name, as [self class] named it.
		const std::string text = stage->description();
		OO_CHECK(text.starts_with("<TestCxxStage 0x"));
		OO_CHECK(text.ends_with(">{\"Cxx\"}"));
		OO_CHECK(stage->descriptionComponents() == std::optional<std::string>("\"Cxx\""));
	}
}


OO_TEST(objCStageBehindACxxPointer)
{
	@autoreleasepool
	{
		const oo::Ref<TestObjCStage> objCStage = MakeStage("ObjC");
		OOOXPVerifierStage *part = objCStage.get();
		OO_CHECK(part != nullptr);

		// Virtual calls through the base reach the subclass's overrides.
		OO_CHECK(part->name() == std::optional<std::string>("ObjC"));
		objCStage->_testDependencies = std::vector<std::string>{ "Cxx" };
		OO_CHECK(part->dependencies() == objCStage->_testDependencies);
		OO_CHECK(part->shouldRun());	// not overridden: the base's answer
		OO_CHECK(!part->dependents().has_value());

		// The subclass's base call still reaches the base, not back to the subclass.
		const oo::Ref<TestSuperCallingStage> superCalling = oo::makeRef<TestSuperCallingStage>();
		OO_CHECK(static_cast<OOOXPVerifierStage *>(superCalling.get())->dependents() == std::vector<std::string>{ "Listing unused files" });
	}
}


OO_TEST(mixedDependencyGraph)
{
	@autoreleasepool
	{
		const oo::Ref<TestCxxStage> cxxStage = oo::makeRef<TestCxxStage>("Cxx");
		cxxStage->_shouldRun = true;
		const oo::Ref<TestObjCStage> objCStage = MakeStage("ObjC");

		// The verifier wires the stages together (through the facade until bead oo-9ht.4).
		objCStage->registerDependency(cxxStage.get());
		OO_CHECK(objCStage->isDependentOf(cxxStage.get()));
		OO_CHECK(objCStage->isDependentOf(cxxStage.get()));
		OO_CHECK(Holds(cxxStage->resolvedDependents(), { objCStage.get() }));
		OO_CHECK(cxxStage->resolvedDependents().size() == 1 && cxxStage->resolvedDependents()[0] == objCStage.get());

		cxxStage->dependencyRegistrationComplete();
		objCStage->dependencyRegistrationComplete();
		OO_CHECK(cxxStage->canRun() && !objCStage->canRun());
		cxxStage->performRun();
		OO_CHECK(cxxStage->runs == 1 && objCStage->canRun());
		objCStage->performRun();	// virtual run() reaches the override
		OO_CHECK(objCStage->_runs == 1 && objCStage->completed());
	}
}

OO_TEST_MAIN()
