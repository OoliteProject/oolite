/*	test_OODrawable.mm
	Unit tests for cxx::OODrawable (src/Core/OODrawable.h) and its Objective-C facade
	(OODrawable+ObjCBridge.h): bead oo-smy, with OOMaterial the Materials module exemplar
	(proposed ADR-0056, amendment oo-smy).

	OODrawable is the root of the drawables (OOMesh, OOPlanetDrawable and OOSkyDrawable convert
	in their own beads). It computes nothing but defaults, so this pins those, the debug size
	(-totalSize is the instance size, which a subclass extends through [super totalSize]), and
	then the hierarchy's crossing both ways, as test_OOOXPVerifierStage.mm does, including the
	bitwise copy OOMesh makes of itself. Run: bash tools/check-core-tests.sh
*/

#import "OODrawable.h"
#import "NSObjectOOExtensions.h"

#include "oo_test.hpp"

#include <cstring>


// An unconverted drawable: an Objective-C subclass, as OOMesh is.
@interface TestObjCDrawable: OODrawable
{
@public
	int		_opaqueRenders;
	GLfloat	_radius;
}
@end


@implementation TestObjCDrawable

- (void)renderOpaqueParts		{ _opaqueRenders++; }
- (BOOL)hasOpaqueParts			{ return YES; }
- (GLfloat)collisionRadius		{ return _radius; }

#ifndef NDEBUG
- (size_t)totalSize				{ return [super totalSize] + 100; }
#endif

@end


// A converted drawable: a C++ subclass. Global, as a game class is, so that its description names
// it as the game's would.
class TestCxxDrawable : public cxx::OODrawable
{
public:
	void renderTranslucentParts() override							{ translucentRenders++; }
	bool hasTranslucentParts() override								{ return true; }
	GLfloat maxDrawDistance() override								{ return 1000.0f; }
	std::optional<std::string> descriptionComponents() const override	{ return "test"; }

	int translucentRenders = 0;
};


namespace {

bool IsZero(const BoundingBox &box)
{
	return std::memcmp(&box, &kZeroBoundingBox, sizeof box) == 0;
}

}	// namespace


OO_TEST(rootDefaults)
{
	@autoreleasepool
	{
		OODrawable *drawable = [[[OODrawable alloc] init] autorelease];
		[drawable renderOpaqueParts];
		[drawable renderTranslucentParts];
		OO_CHECK(![drawable hasOpaqueParts] && ![drawable hasTranslucentParts]);
		OO_CHECK([drawable collisionRadius] == 0.0f && [drawable maxDrawDistance] == 0.0f);
		OO_CHECK(IsZero([drawable boundingBox]));
		[drawable setBindingTarget:nil];
		[drawable dumpSelfState];
#ifndef NDEBUG
		OO_CHECK([drawable cxx_allTextures].empty());
		OO_CHECK([drawable totalSize] == [drawable oo_objectSize]);
#endif
	}
}


OO_TEST(objCSubclass)
{
	@autoreleasepool
	{
		TestObjCDrawable *drawable = [[[TestObjCDrawable alloc] init] autorelease];
		drawable->_radius = 12.5f;
		[drawable renderOpaqueParts];
		OO_CHECK(drawable->_opaqueRenders == 1);
		OO_CHECK([drawable hasOpaqueParts] && ![drawable hasTranslucentParts]);
		OO_CHECK([drawable collisionRadius] == 12.5f && [drawable maxDrawDistance] == 0.0f);
#ifndef NDEBUG
		// [super totalSize] is the subclass's instance size, not the root's.
		OO_CHECK([drawable totalSize] == class_getInstanceSize([TestObjCDrawable class]) + 100);
#endif
	}
}


OO_TEST(cxxDrawableBehindTheFacade)
{
	@autoreleasepool
	{
		const oo::Ref<TestCxxDrawable> drawable = oo::makeRef<TestCxxDrawable>();
		OODrawable *facade = oo::ToObjC(drawable.get());
		OO_CHECK(facade != nil && facade == oo::ToObjC(drawable.get()));	// one live facade
		OO_CHECK(oo::ToCxx(facade) == drawable.get());

		// The entities' messages reach the C++ overrides, and the root's defaults.
		[facade renderTranslucentParts];
		OO_CHECK(drawable->translucentRenders == 1);
		OO_CHECK([facade hasTranslucentParts] && ![facade hasOpaqueParts]);
		OO_CHECK([facade maxDrawDistance] == 1000.0f && [facade collisionRadius] == 0.0f);
		OO_CHECK(IsZero([facade boundingBox]));

		const std::string text = oo::DescriptionOf(facade);
		OO_CHECK(text.starts_with("<TestCxxDrawable 0x"));
		OO_CHECK(text.ends_with(">{test}"));
	}
}


OO_TEST(objCDrawableBehindACxxPointer)
{
	@autoreleasepool
	{
		TestObjCDrawable *objCDrawable = [[[TestObjCDrawable alloc] init] autorelease];
		objCDrawable->_radius = 3.0f;
		cxx::OODrawable *part = oo::ToCxx(objCDrawable);
		OO_CHECK(part != nullptr && oo::ToObjC(part) == objCDrawable);	// the object itself

		// Virtual calls from C++ reach the Objective-C overrides, or the root's own answers.
		part->renderOpaqueParts();
		OO_CHECK(objCDrawable->_opaqueRenders == 1);
		OO_CHECK(part->hasOpaqueParts() && !part->hasTranslucentParts());
		OO_CHECK(part->collisionRadius() == 3.0f && part->maxDrawDistance() == 0.0f);
		OO_CHECK(!part->descriptionComponents().has_value());
#ifndef NDEBUG
		OO_CHECK(part->totalSize() == class_getInstanceSize([TestObjCDrawable class]) + 100);
#endif
	}
}


// OOMesh's -mutableCopyWithZone:: a new instance with the ivars copied bitwise, then the C++ ivars
// constructed afresh, the root's C++ part first.
OO_TEST(bitwiseCopy)
{
	@autoreleasepool
	{
		TestObjCDrawable *original = [[[TestObjCDrawable alloc] init] autorelease];
		original->_radius = 7.0f;

		Class cls = object_getClass(original);
		TestObjCDrawable *copy = (TestObjCDrawable *)class_createInstance(cls, 0);
		std::memcpy((void *)copy, (const void *)original, class_getInstanceSize(cls));
		oo::ConstructCxxPartOfCopy(copy);
		[copy autorelease];

		OO_CHECK(oo::ToCxx(copy) != oo::ToCxx(original));
		OO_CHECK(oo::ToObjC(oo::ToCxx(copy)) == copy && oo::ToObjC(oo::ToCxx(original)) == original);
		oo::ToCxx(copy)->renderOpaqueParts();	// reaches the copy, not the original
		OO_CHECK(copy->_opaqueRenders == 1 && original->_opaqueRenders == 0);
		OO_CHECK(oo::ToCxx(copy)->collisionRadius() == 7.0f);
	}
}


OO_TEST(nilAndLifetime)
{
	OODrawable *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OODrawable *>(nullptr)) == nil);
	OO_CHECK(![none hasOpaqueParts]);

	oo::Ref<cxx::OODrawable> part;
	@autoreleasepool
	{
		part = oo::Ref<cxx::OODrawable>(oo::ToCxx([[[TestObjCDrawable alloc] init] autorelease]));
	}
	OO_CHECK(!part->hasOpaqueParts() && part->collisionRadius() == 0.0f);
	OO_CHECK(oo::ToObjC(part) == nil);
}

OO_TEST_MAIN()
