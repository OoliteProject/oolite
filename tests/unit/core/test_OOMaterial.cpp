/*	test_OOMaterial.mm
        Unit tests for OOMaterial (src/Core/Materials/OOMaterial.h). The test
   materials are C++ subclasses.

        OOMaterial is the root of the material hierarchy (OOBasicMaterial and
   the three materials under it) and owns the one piece of global render state,
   the current material. So this pins, from the Objective-C bodies, what the
   root computed before the conversion, through the Objective-C API its callers
   use: the defaults a subclass inherits, -apply / +applyNone / +current (the
   previous material told what comes next, the current material retained, a
   failed -doApply leaving none), -willDealloc's imbalance path, the
   description, and [super ...] from an Objective-C subclass. Then the
   hierarchy's crossing both ways, as test_OOOXPVerifierStage.mm does, and the
   current material keeping an Objective-C material alive while C++ holds it.
   Run: bash tools/check-core-tests.sh
*/

#include <utility>
#include <vector>

#include "OODescription.h"
#include "OOLogging.h"
#include "OOMaterial.h"
#include "oo_test.hpp"

/*	The game's OOLogging.mm reaches the resource manager, so it is not
   linked. The two functions of it that the root calls are defined here instead,
   and count.
*/
static int gSubclassResponsibilities = 0;
static int gParameterErrors = 0;

void OOLogGenericSubclassResponsibilityForFunction(const char* inFunction) {
  (void)inFunction;
  gSubclassResponsibilities++;
}

void OOLogGenericParameterErrorForFunction(const char* inFunction) {
  (void)inFunction;
  gParameterErrors++;
}

// Every unapplyWithNext() sent to a test material, in order: (material, next).
static std::vector<std::pair<OOMaterial*, OOMaterial*>> gUnapplied;
static int gDeallocs = 0;

// An unconverted material was an Objective-C subclass, as OOBasicMaterial was;
// now a C++ subclass with the same overrides, named as it was so that its
// description is unchanged.
class TestObjCMaterial : public OOMaterial {
 public:
  ~TestObjCMaterial() override {
    willDealloc();
    gDeallocs++;
  }

  std::optional<std::string> name() override { return _testName; }

  bool doApply() override {
    _doApplies++;
    return _applies;
  }

  void unapplyWithNext(OOMaterial* next) override {
    gUnapplied.emplace_back(this, next);
    OOMaterial::unapplyWithNext(next);
  }

  std::string _testName;
  bool _applies = false;
  int _doApplies = 0;
};

// Asks its superclass, as OOBasicMaterial's allTextures() and doApply() do.
class TestSuperCallingMaterial : public TestObjCMaterial {
 public:
  bool doApply() override {
    return TestObjCMaterial::doApply() || isFinishedLoading();
  }
  bool wantsNormalsAsTextureCoordinates() override {
    return !TestObjCMaterial::wantsNormalsAsTextureCoordinates();
  }
};

// A converted material: a C++ subclass that overrides the virtual members.
// Global, as a game class is, so that its description names it as the game's
// would.
static int gCxxDestroyed = 0;

class TestCxxMaterial : public OOMaterial {
 public:
  explicit TestCxxMaterial(std::string testName)
      : _testName(std::move(testName)) {}
  ~TestCxxMaterial() override { gCxxDestroyed++; }

  std::optional<std::string> name() override { return _testName; }
  bool wantsNormalsAsTextureCoordinates() override { return true; }
  bool doApply() override {
    doApplies++;
    return true;
  }
  void unapplyWithNext(OOMaterial* next) override {
    unappliedNext.push_back(next);
  }

  int doApplies = 0;
  std::vector<OOMaterial*> unappliedNext;

 private:
  std::string _testName;
};

namespace {

oo::Ref<TestObjCMaterial> MakeMaterial(const char* name, bool applies = true) {
  oo::Ref<TestObjCMaterial> material = oo::makeRef<TestObjCMaterial>();
  material->_testName = name;
  material->_applies = applies;
  return material;
}

bool Unapplied(
    std::initializer_list<std::pair<OOMaterial*, OOMaterial*>> expected) {
  const bool result =
      std::vector<std::pair<OOMaterial*, OOMaterial*>>(expected) == gUnapplied;
  gUnapplied.clear();
  return result;
}

}  // namespace

OO_TEST(rootDefaults) {
  {
    const oo::Ref<OOMaterial> material = oo::makeRef<OOMaterial>();
    const int parameterErrors = gParameterErrors,
              responsibilities = gSubclassResponsibilities;
    OO_CHECK(
        !material->name().has_value());  // logs a parameter error, answers nil
    OO_CHECK(gParameterErrors == parameterErrors + 1);
    OO_CHECK(!material->doApply());  // subclass responsibility
    OO_CHECK(gSubclassResponsibilities == responsibilities + 1);
    material->ensureFinishedLoading();
    OO_CHECK(material->isFinishedLoading());
    OO_CHECK(!material->wantsNormalsAsTextureCoordinates());
    material->setBindingTarget(nil);
    material->unapplyWithNext(nullptr);
#if OO_MULTITEXTURE
    OO_CHECK(material->countOfTextureUnitsWithBaseCoordinates() == 1);
#endif
#ifndef NDEBUG
    OO_CHECK(material->allTextures().empty());
#endif
    OOMaterial::setUp();

    // The root cannot apply: doApply() answers false, so there is still no
    // current material.
    material->apply();
    OO_CHECK(OOMaterial::current() == nullptr);
  }
}

OO_TEST(applyMakesCurrent) {
  {
    const oo::Ref<TestObjCMaterial> a = MakeMaterial("A"),
                                    b = MakeMaterial("B");
    gUnapplied.clear();
    OO_CHECK(OOMaterial::current() == nullptr);

    a->apply();
    OO_CHECK(OOMaterial::current() == a.get() && a->_doApplies == 1);
    OO_CHECK(Unapplied({}));

    b->apply();  // the previous material is told what comes next
    OO_CHECK(OOMaterial::current() == b.get());
    OO_CHECK(Unapplied({{a.get(), b.get()}}));

    b->apply();  // again: told itself
    OO_CHECK(OOMaterial::current() == b.get() && b->_doApplies == 2);
    OO_CHECK(Unapplied({{b.get(), b.get()}}));

    OOMaterial::applyNone();
    OO_CHECK(OOMaterial::current() == nullptr);
    OO_CHECK(Unapplied({{b.get(), nullptr}}));

    OOMaterial::applyNone();  // nothing current: nothing told
    OO_CHECK(Unapplied({}));
  }
}

OO_TEST(failedApplyLeavesNone) {
  {
    const oo::Ref<TestObjCMaterial> a = MakeMaterial("A"),
                                    failing = MakeMaterial("Failing", false);
    a->apply();
    gUnapplied.clear();
    failing->apply();
    OO_CHECK(OOMaterial::current() == nullptr && failing->_doApplies == 1);
    OO_CHECK(Unapplied({{a.get(), failing.get()}}));
    OOMaterial::applyNone();
    OO_CHECK(Unapplied({}));
  }
}

OO_TEST(currentIsRetained) {
  const int deallocs = gDeallocs;
  TestObjCMaterial* material = nullptr;
  {
    const oo::Ref<TestObjCMaterial> made = MakeMaterial("Kept");
    material = made.get();
    material->apply();
  }
  // The maker's reference is gone; being current keeps it.
  OO_CHECK(gDeallocs == deallocs);
  {
    OO_CHECK(OOMaterial::current() == material);
    OO_CHECK(OOMaterial::current()->description().ends_with(">{\"Kept\"}"));
    gUnapplied.clear();
    OOMaterial::applyNone();
    OO_CHECK(Unapplied({{material, nullptr}}));
  }
  OO_CHECK(gDeallocs == deallocs + 1);
}

OO_TEST(willDeallocWhileCurrent) {
  {
    const oo::Ref<TestObjCMaterial> material = MakeMaterial("Imbalanced");
    material->apply();
    const unsigned retained = material->retainCount();
    gUnapplied.clear();

    // What -dealloc did first. Current: unapplied with no next, and no longer
    // current, but the reference that being current held is not released (the
    // object was being deallocated).
    material->willDealloc();
    OO_CHECK(Unapplied({{material.get(), nullptr}}));
    OO_CHECK(OOMaterial::current() == nullptr);
    OO_CHECK(material->retainCount() == retained);
    material->release();  // the reference being current held

    material->willDealloc();  // not current: nothing
    OO_CHECK(Unapplied({}));
  }
}

OO_TEST(superCallsReachTheRoot) {
  {
    const oo::Ref<TestSuperCallingMaterial> material =
        oo::makeRef<TestSuperCallingMaterial>();
    material->_applies = false;
    const int responsibilities = gSubclassResponsibilities;
    OO_CHECK(material->doApply());  // false from TestObjCMaterial, then the
                                    // root's isFinishedLoading()
    OO_CHECK(gSubclassResponsibilities == responsibilities);
    OO_CHECK(material->wantsNormalsAsTextureCoordinates());
  }
}

OO_TEST(description) {
  {
    const std::string text = MakeMaterial("Hull")->description();
    OO_CHECK(text.starts_with("<TestObjCMaterial 0x"));
    OO_CHECK(text.ends_with(">{\"Hull\"}"));
    OO_CHECK(
        oo::makeRef<OOMaterial>()->description().ends_with(">{\"(null)\"}"));
  }
}

// A C++ material's overrides and the root's defaults, as its callers reach them
// (the C++ half of cxxMaterialBehindTheFacade, whose facade half went with the
// facade).
OO_TEST(cxxMaterial) {
  {
    const oo::Ref<TestCxxMaterial> material =
        oo::makeRef<TestCxxMaterial>("Cxx");
    OO_CHECK(material->name() == std::optional<std::string>("Cxx"));
    OO_CHECK(material->wantsNormalsAsTextureCoordinates());
    OO_CHECK(material->isFinishedLoading());

    material->apply();
    OO_CHECK(material->doApplies == 1);
    OO_CHECK(OOMaterial::current().get() == material.get());
    OOMaterial::applyNone();
    OO_CHECK(material->unappliedNext == std::vector<OOMaterial*>{nullptr});
    OO_CHECK(OOMaterial::current() == nullptr);

    // Described with the C++ class's name, as [self class] named it.
    const std::string text = material->description();
    OO_CHECK(text.starts_with("<TestCxxMaterial 0x"));
    OO_CHECK(text.ends_with(">{\"Cxx\"}"));
    OO_CHECK(material->descriptionComponents() ==
             std::optional<std::string>("\"Cxx\""));
  }
}

// The current material is retained: a C++ material made current lives until it
// is no longer (the C++ half of currentIsRetainedAcrossTheBridge).
OO_TEST(currentRetainsACxxMaterial) {
  const int destroyed = gCxxDestroyed;
  {
    oo::makeRef<TestCxxMaterial>("Cxx")->apply();
  }
  OO_CHECK(gCxxDestroyed == destroyed);
  {
    OO_CHECK(OOMaterial::current()->name() ==
             std::optional<std::string>("Cxx"));
    OOMaterial::applyNone();
  }
  OO_CHECK(gCxxDestroyed == destroyed + 1);
}

OO_TEST_MAIN()
