/*	test_OODrawable.mm
        Unit tests for OODrawable (src/Core/OODrawable.h).

        OODrawable is the root of the drawables (OOMesh, OOPlanetDrawable and
   OOSkyDrawable). It computes nothing but defaults, so this pins those, the
   debug size (totalSize() is the object's own size, which a subclass extends
   through the root's totalSize()), and a subclass's overrides and description.
   The test subclass is a C++ one, its instance size the object's. Run:
   tests/run.sh unit
*/

#include <cstring>

#include "OODrawable.h"
#include "oo_test.hpp"

// A subclass that overrides the root's members.
class TestSubDrawable : public OODrawable {
 public:
  void renderOpaqueParts() override { opaqueRenders++; }
  bool hasOpaqueParts() override { return true; }
  GLfloat collisionRadius() override { return radius; }
#ifndef NDEBUG
  size_t totalSize() override { return OODrawable::totalSize() + 100; }
  size_t objectSize() const override { return sizeof *this; }
#endif

  int opaqueRenders = 0;
  GLfloat radius = 0.0f;
};

// A converted drawable: a C++ subclass. Global, as a game class is, so that its
// description names it as the game's would.
class TestCxxDrawable : public OODrawable {
 public:
  void renderTranslucentParts() override { translucentRenders++; }
  bool hasTranslucentParts() override { return true; }
  GLfloat maxDrawDistance() override { return 1000.0f; }
  std::optional<std::string> descriptionComponents() const override {
    return "test";
  }

  int translucentRenders = 0;
};

namespace {

bool IsZero(const BoundingBox& box) {
  return std::memcmp(&box, &kZeroBoundingBox, sizeof box) == 0;
}

}  // namespace

OO_TEST(rootDefaults) {
  {
    const oo::Ref<OODrawable> drawable = oo::makeRef<OODrawable>();
    drawable->renderOpaqueParts();
    drawable->renderTranslucentParts();
    OO_CHECK(!drawable->hasOpaqueParts() && !drawable->hasTranslucentParts());
    OO_CHECK(drawable->collisionRadius() == 0.0f &&
             drawable->maxDrawDistance() == 0.0f);
    OO_CHECK(IsZero(drawable->boundingBox()));
    drawable->setBindingTarget(nullptr);
    drawable->dumpSelfState();
#ifndef NDEBUG
    OO_CHECK(drawable->allTextures().empty());
    OO_CHECK(drawable->totalSize() == drawable->objectSize());
    OO_CHECK(drawable->objectSize() == sizeof(OODrawable));
#endif
  }
}

OO_TEST(objCSubclass) {
  {
    const oo::Ref<TestSubDrawable> drawable = oo::makeRef<TestSubDrawable>();
    drawable->radius = 12.5f;
    drawable->renderOpaqueParts();
    OO_CHECK(drawable->opaqueRenders == 1);
    OO_CHECK(drawable->hasOpaqueParts() && !drawable->hasTranslucentParts());
    OO_CHECK(drawable->collisionRadius() == 12.5f &&
             drawable->maxDrawDistance() == 0.0f);
#ifndef NDEBUG
    // The root's totalSize() is the subclass's size, not the root's.
    OO_CHECK(drawable->totalSize() == sizeof(TestSubDrawable) + 100);
#endif
    // Virtual calls through the root's type reach the overrides, or the root's
    // own answers.
    OODrawable* part = drawable.get();
    part->renderOpaqueParts();
    OO_CHECK(drawable->opaqueRenders == 2);
    OO_CHECK(!part->descriptionComponents().has_value());
  }
}

OO_TEST(cxxDrawableBehindTheFacade) {
  {
    const oo::Ref<TestCxxDrawable> drawable = oo::makeRef<TestCxxDrawable>();
    OODrawable* part = drawable.get();

    // The entities' calls reach the C++ overrides, and the root's defaults.
    part->renderTranslucentParts();
    OO_CHECK(drawable->translucentRenders == 1);
    OO_CHECK(part->hasTranslucentParts() && !part->hasOpaqueParts());
    OO_CHECK(part->maxDrawDistance() == 1000.0f &&
             part->collisionRadius() == 0.0f);
    OO_CHECK(IsZero(part->boundingBox()));

    const std::string text = part->description();
    OO_CHECK(text.starts_with("<TestCxxDrawable 0x"));
    OO_CHECK(text.ends_with(">{test}"));
  }
}

OO_TEST(autoreleaseKeepsTheDrawable) {
  // OODrawableAutorelease() (an entity's replaced drawable, as [drawable
  // autorelease]): the drawable lives until the pool drains.
  oo::Ref<TestCxxDrawable> drawable = oo::makeRef<TestCxxDrawable>();
  TestCxxDrawable* raw = drawable.get();
  {
    OODrawableAutorelease(oo::Ref<OODrawable>(std::move(drawable)));
    raw->renderTranslucentParts();  // still alive
    OO_CHECK(raw->translucentRenders == 1);
  }
  OODrawableAutorelease(oo::Ref<OODrawable>());  // null: nothing
}

OO_TEST_MAIN()
