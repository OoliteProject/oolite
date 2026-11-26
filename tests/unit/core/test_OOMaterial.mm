/*	test_OOMaterial.mm
	Unit tests for cxx::OOMaterial (src/Core/Materials/OOMaterial.h) and its Objective-C facade
	(OOMaterial+ObjCBridge.h): bead oo-smy, the Materials module exemplar (proposed ADR-0056,
	amendment oo-smy).

	OOMaterial is the root of the material hierarchy (OOBasicMaterial and the three materials
	under it convert in their own beads) and owns the one piece of global render state, the
	current material. So this pins, from the Objective-C bodies, what the root computed before the
	conversion, through the Objective-C API its callers use: the defaults a subclass inherits,
	-apply / +applyNone / +current (the previous material told what comes next, the current
	material retained, a failed -doApply leaving none), -willDealloc's imbalance path, the
	description, and [super ...] from an Objective-C subclass. Then the hierarchy's crossing both
	ways, as test_OOOXPVerifierStage.mm does, and the current material keeping an Objective-C
	material alive while C++ holds it. Run: bash tools/check-core-tests.sh
*/

#import "OOMaterial.h"
#import "OODescription.h"

#import "OOLogging.h"
#include "oo_test.hpp"

#include <utility>
#include <vector>


/*	The game's OOLogging.mm reaches the resource manager, so it is not linked. The two functions
	of it that the root calls are defined here instead, and count.
*/
static int gSubclassResponsibilities = 0;
static int gParameterErrors = 0;

void OOLogGenericSubclassResponsibilityForFunction(const char *inFunction)
{
	(void)inFunction;
	gSubclassResponsibilities++;
}


void OOLogGenericParameterErrorForFunction(const char *inFunction)
{
	(void)inFunction;
	gParameterErrors++;
}


// Every -unapplyWithNext: sent to a test material, in order: (material, next).
static std::vector<std::pair<id, id>> gUnapplied;
static int gDeallocs = 0;


// An unconverted material: an Objective-C subclass, as OOBasicMaterial is.
@interface TestObjCMaterial: OOMaterial
{
@public
	std::string		_testName;
	BOOL			_applies;
	int				_doApplies;
}
@end


@implementation TestObjCMaterial

- (void)dealloc
{
	[self willDealloc];
	gDeallocs++;
	[super dealloc];
}

- (std::optional<std::string>)cxx_name		{ return _testName; }

- (BOOL)doApply
{
	_doApplies++;
	return _applies;
}

- (void)unapplyWithNext:(OOMaterial *)next
{
	gUnapplied.emplace_back(self, next);
	[super unapplyWithNext:next];
}

@end


// Asks its superclass, as OOBasicMaterial's -cxx_allTextures and -doApply do.
@interface TestSuperCallingMaterial: TestObjCMaterial
@end


@implementation TestSuperCallingMaterial

- (BOOL)doApply									{ return [super doApply] || [self isFinishedLoading]; }
- (BOOL)wantsNormalsAsTextureCoordinates		{ return ![super wantsNormalsAsTextureCoordinates]; }

@end


// A converted material: a C++ subclass that overrides the virtual members. Global, as a game class
// is, so that its description names it as the game's would.
static int gCxxDestroyed = 0;

class TestCxxMaterial : public cxx::OOMaterial
{
public:
	explicit TestCxxMaterial(std::string testName) : _testName(std::move(testName)) {}
	~TestCxxMaterial() override	{ gCxxDestroyed++; }

	std::optional<std::string> name() override			{ return _testName; }
	bool wantsNormalsAsTextureCoordinates() override	{ return true; }
	bool doApply() override								{ doApplies++; return true; }
	void unapplyWithNext(cxx::OOMaterial *next) override	{ unappliedNext.push_back(next); }

	int								doApplies = 0;
	std::vector<cxx::OOMaterial *>	unappliedNext;

private:
	std::string _testName;
};


namespace {

TestObjCMaterial *MakeMaterial(const char *name, BOOL applies = YES)
{
	TestObjCMaterial *material = [[[TestObjCMaterial alloc] init] autorelease];
	material->_testName = name;
	material->_applies = applies;
	return material;
}


bool Unapplied(std::initializer_list<std::pair<id, id>> expected)
{
	const bool result = std::vector<std::pair<id, id>>(expected) == gUnapplied;
	gUnapplied.clear();
	return result;
}

}	// namespace


OO_TEST(rootDefaults)
{
	@autoreleasepool
	{
		OOMaterial *material = [[[OOMaterial alloc] init] autorelease];
		const int parameterErrors = gParameterErrors, responsibilities = gSubclassResponsibilities;
		OO_CHECK(![material cxx_name].has_value());	// logs a parameter error, answers nil
		OO_CHECK(gParameterErrors == parameterErrors + 1);
		OO_CHECK(![material doApply]);	// subclass responsibility
		OO_CHECK(gSubclassResponsibilities == responsibilities + 1);
		[material ensureFinishedLoading];
		OO_CHECK([material isFinishedLoading]);
		OO_CHECK(![material wantsNormalsAsTextureCoordinates]);
		[material setBindingTarget:nil];
		[material unapplyWithNext:nil];
#if OO_MULTITEXTURE
		OO_CHECK([material countOfTextureUnitsWithBaseCoordinates] == 1);
#endif
#ifndef NDEBUG
		OO_CHECK([material cxx_allTextures].empty());
#endif
		[OOMaterial setUp];

		// The root cannot apply: -doApply answers NO, so there is still no current material.
		[material apply];
		OO_CHECK([OOMaterial current] == nil);
	}
}


OO_TEST(applyMakesCurrent)
{
	@autoreleasepool
	{
		TestObjCMaterial *a = MakeMaterial("A"), *b = MakeMaterial("B");
		gUnapplied.clear();
		OO_CHECK([OOMaterial current] == nil);

		[a apply];
		OO_CHECK([OOMaterial current] == a && a->_doApplies == 1);
		OO_CHECK(Unapplied({}));

		[b apply];	// the previous material is told what comes next
		OO_CHECK([OOMaterial current] == b);
		OO_CHECK(Unapplied({ { a, b } }));

		[b apply];	// again: told itself
		OO_CHECK([OOMaterial current] == b && b->_doApplies == 2);
		OO_CHECK(Unapplied({ { b, b } }));

		[OOMaterial applyNone];
		OO_CHECK([OOMaterial current] == nil);
		OO_CHECK(Unapplied({ { b, nil } }));

		[OOMaterial applyNone];	// nothing current: nothing told
		OO_CHECK(Unapplied({}));
	}
}


OO_TEST(failedApplyLeavesNone)
{
	@autoreleasepool
	{
		TestObjCMaterial *a = MakeMaterial("A"), *failing = MakeMaterial("Failing", NO);
		[a apply];
		gUnapplied.clear();
		[failing apply];
		OO_CHECK([OOMaterial current] == nil && failing->_doApplies == 1);
		OO_CHECK(Unapplied({ { a, failing } }));
		[OOMaterial applyNone];
		OO_CHECK(Unapplied({}));
	}
}


OO_TEST(currentIsRetained)
{
	const int deallocs = gDeallocs;
	TestObjCMaterial *material = nil;
	@autoreleasepool
	{
		material = MakeMaterial("Kept");
		[material apply];
	}
	// The pool released the maker's reference; being current keeps it.
	OO_CHECK(gDeallocs == deallocs);
	@autoreleasepool
	{
		OO_CHECK([OOMaterial current] == material);
		OO_CHECK(oo::DescriptionOf([OOMaterial current]).ends_with(">{\"Kept\"}"));
		gUnapplied.clear();
		[OOMaterial applyNone];
		OO_CHECK(Unapplied({ { material, nil } }));
	}
	OO_CHECK(gDeallocs == deallocs + 1);
}


OO_TEST(willDeallocWhileCurrent)
{
	@autoreleasepool
	{
		TestObjCMaterial *material = MakeMaterial("Imbalanced");
		[material apply];
		const unsigned retained = [material retainCount];
		gUnapplied.clear();

		// What -dealloc does first. Current: unapplied with no next, and no longer current, but the
		// reference that being current held is not released (the object was being deallocated).
		[material willDealloc];
		OO_CHECK(Unapplied({ { material, nil } }));
		OO_CHECK([OOMaterial current] == nil);
		OO_CHECK([material retainCount] == retained);
		[material release];	// the reference being current held

		[material willDealloc];	// not current: nothing
		OO_CHECK(Unapplied({}));
	}
}


OO_TEST(superCallsReachTheRoot)
{
	@autoreleasepool
	{
		TestSuperCallingMaterial *material = [[[TestSuperCallingMaterial alloc] init] autorelease];
		material->_applies = NO;
		const int responsibilities = gSubclassResponsibilities;
		OO_CHECK([material doApply]);	// NO from TestObjCMaterial, then the root's -isFinishedLoading
		OO_CHECK(gSubclassResponsibilities == responsibilities);
		OO_CHECK([material wantsNormalsAsTextureCoordinates]);
	}
}


OO_TEST(description)
{
	@autoreleasepool
	{
		const std::string text = oo::DescriptionOf(MakeMaterial("Hull"));
		OO_CHECK(text.starts_with("<TestObjCMaterial 0x"));
		OO_CHECK(text.ends_with(">{\"Hull\"}"));
		OO_CHECK(oo::DescriptionOf([[[OOMaterial alloc] init] autorelease]).ends_with(">{\"(null)\"}"));
	}
}


OO_TEST(cxxMaterialBehindTheFacade)
{
	@autoreleasepool
	{
		const oo::Ref<TestCxxMaterial> material = oo::makeRef<TestCxxMaterial>("Cxx");
		OOMaterial *facade = oo::ToObjC(material.get());
		OO_CHECK(facade != nil && facade == oo::ToObjC(material.get()));	// one live facade
		OO_CHECK(oo::ToCxx(facade) == material.get());

		// The callers' messages reach the C++ overrides, and the root's defaults.
		OO_CHECK([facade cxx_name] == std::optional<std::string>("Cxx"));
		OO_CHECK([facade wantsNormalsAsTextureCoordinates]);
		OO_CHECK([facade isFinishedLoading]);

		[facade apply];
		OO_CHECK(material->doApplies == 1);
		OO_CHECK([OOMaterial current] == facade && cxx::OOMaterial::current().get() == material.get());
		[OOMaterial applyNone];
		OO_CHECK(material->unappliedNext == std::vector<cxx::OOMaterial *>{ nullptr });
		OO_CHECK([OOMaterial current] == nil);

		// Described with the C++ class's name, as [self class] named it.
		const std::string text = oo::DescriptionOf(facade);
		OO_CHECK(text.starts_with("<TestCxxMaterial 0x"));
		OO_CHECK(text.ends_with(">{\"Cxx\"}"));
		OO_CHECK(material->descriptionComponents() == std::optional<std::string>("\"Cxx\""));
	}
}


OO_TEST(objCMaterialBehindACxxPointer)
{
	@autoreleasepool
	{
		TestObjCMaterial *objCMaterial = MakeMaterial("ObjC");
		cxx::OOMaterial *part = oo::ToCxx(objCMaterial);
		OO_CHECK(part != nullptr && oo::ToObjC(part) == objCMaterial);	// the object itself

		// Virtual calls from C++ reach the Objective-C overrides, or the root's own answers.
		OO_CHECK(part->name() == std::optional<std::string>("ObjC"));
		OO_CHECK(part->descriptionComponents() == std::optional<std::string>("\"ObjC\""));
		OO_CHECK(part->isFinishedLoading() && !part->wantsNormalsAsTextureCoordinates());
		TestSuperCallingMaterial *superCalling = [[[TestSuperCallingMaterial alloc] init] autorelease];
		OO_CHECK(oo::ToCxx(superCalling)->wantsNormalsAsTextureCoordinates());

		gUnapplied.clear();
		part->apply();	// virtual doApply() reaches -doApply
		OO_CHECK(objCMaterial->_doApplies == 1 && [OOMaterial current] == objCMaterial);
		cxx::OOMaterial::applyNone();	// virtual unapplyWithNext() reaches -unapplyWithNext:
		OO_CHECK(Unapplied({ { objCMaterial, nil } }));
	}
}


OO_TEST(mixedApply)
{
	@autoreleasepool
	{
		const oo::Ref<TestCxxMaterial> cxxMaterial = oo::makeRef<TestCxxMaterial>("Cxx");
		TestObjCMaterial *objCMaterial = MakeMaterial("ObjC");
		gUnapplied.clear();

		cxxMaterial->apply();
		[objCMaterial apply];	// the C++ material is told the Objective-C one comes next
		OO_CHECK(cxxMaterial->unappliedNext == std::vector<cxx::OOMaterial *>{ oo::ToCxx(objCMaterial) });
		cxxMaterial->apply();	// and the other way round
		OO_CHECK(Unapplied({ { objCMaterial, oo::ToObjC(cxxMaterial.get()) } }));
		OO_CHECK(cxx::OOMaterial::current().get() == cxxMaterial.get());
		[OOMaterial applyNone];
	}
}


// The current material is retained whichever side made it current: an Objective-C material's C++
// part does not retain its owner, so being current holds the Objective-C object.
OO_TEST(currentIsRetainedAcrossTheBridge)
{
	const int deallocs = gDeallocs, destroyed = gCxxDestroyed;
	cxx::OOMaterial *part = nullptr;
	@autoreleasepool
	{
		part = oo::ToCxx(MakeMaterial("ObjC, made current from C++"));
		part->apply();
	}
	OO_CHECK(gDeallocs == deallocs);
	@autoreleasepool
	{
		OO_CHECK(cxx::OOMaterial::current().get() == part);
		OO_CHECK(part->name() == std::optional<std::string>("ObjC, made current from C++"));
		cxx::OOMaterial::applyNone();
	}
	OO_CHECK(gDeallocs == deallocs + 1);

	@autoreleasepool
	{
		oo::makeRef<TestCxxMaterial>("Cxx")->apply();
	}
	OO_CHECK(gCxxDestroyed == destroyed);
	@autoreleasepool
	{
		OO_CHECK(cxx::OOMaterial::current()->name() == std::optional<std::string>("Cxx"));
		[OOMaterial applyNone];
	}
	OO_CHECK(gCxxDestroyed == destroyed + 1);
}


OO_TEST(nilAndLifetime)
{
	OOMaterial *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOMaterial *>(nullptr)) == nil);
	OO_CHECK(![none cxx_name].has_value());

	// An Objective-C material's C++ part outlives it only as a reference C++ holds; it then answers
	// as a message to the released material's nil would.
	oo::Ref<cxx::OOMaterial> part;
	@autoreleasepool
	{
		part = oo::Ref<cxx::OOMaterial>(oo::ToCxx(MakeMaterial("Gone")));
	}
	OO_CHECK(!part->name().has_value() && !part->doApply());
	OO_CHECK(oo::ToObjC(part) == nil);
}

OO_TEST_MAIN()
