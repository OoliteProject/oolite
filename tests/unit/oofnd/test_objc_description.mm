/*	test_objc_description.mm
	Unit tests for the description family on the Objective-C root (Core/OODescription.h, proposed
	ADR-0055 item 1, bead oo-qps.31): -cxx_description & co., oo::DescriptionOf /
	ShortDescriptionOf, and the transitional forwarding to a legacy id-typed override.

	Core/OODescription.mm is compiled into this executable, which links libobjc2 and NOTHING
	from gnustep-base (tools/check-oofnd-objc.sh checks the import table): the proof that the
	family survives oo-qps.18. The text is the one the legacy family printed,
	<ClassName 0xnnnnnnnn>{components}, with GNUstep's %p (oo::str::pointerDescription).
*/

#include "oofnd/objc/OOObject.h"
#include "oofnd/objc/OOConstantString.h"
#include "oofnd/String.hpp"

#import "Core/OODescription.mm"

#include "oo_test.hpp"

#include <string>


// No overrides: the root's defaults.
@interface OOTestPlain : OOObject
@end

@implementation OOTestPlain
@end


// A converted class, and a subclass that extends its components.
@interface OOTestFlipped : OOObject
@end

@implementation OOTestFlipped

- (std::optional<std::string>) cxx_descriptionComponents
{
	return std::string("1, 2");
}


- (std::optional<std::string>) cxx_shortDescriptionComponents
{
	return std::string("short");
}

@end


@interface OOTestFlippedChild : OOTestFlipped
@end

@implementation OOTestFlippedChild

- (std::optional<std::string>) cxx_descriptionComponents
{
	return "child " + [super cxx_descriptionComponents].value_or("(null)");
}

@end


// Not yet converted: legacy id-typed overrides, which the root's defaults forward to.
@interface OOTestLegacy : OOObject
- (id) descriptionComponents;
- (id) shortDescriptionComponents;
@end

@implementation OOTestLegacy

- (id) descriptionComponents
{
	return @"legacy components";
}


- (id) shortDescriptionComponents
{
	return nil;
}

@end


@interface OOTestLegacyWhole : OOObject
- (id) description;
- (id) shortDescription;
@end

@implementation OOTestLegacyWhole

- (id) description
{
	return @"the whole text";
}


- (id) shortDescription
{
	return @"short text";
}

@end


// A converted subclass of an unconverted class: [super cxx_descriptionComponents] reaches the
// superclass's legacy override through the root's forwarding.
@interface OOTestFlippedOverLegacy : OOTestLegacy
@end

@implementation OOTestFlippedOverLegacy

- (std::optional<std::string>) cxx_descriptionComponents
{
	return [super cxx_descriptionComponents].value_or("(null)") + " and more";
}

@end


// An object on another root (a Foundation object, until oo-qps.16): oo::DescriptionOf asks its
// -description.
__attribute__((objc_root_class))
@interface OOTestForeignRoot
{
	Class isa;
}
+ (id) alloc;
- (id) init;
- (Class) class;
- (id) description;
- (id) shortDescription;
@end

@implementation OOTestForeignRoot

+ (id) alloc
{
	return class_createInstance(self, 0);
}


- (id) init
{
	return self;
}


- (Class) class
{
	return object_getClass(self);
}


- (id) description
{
	return @"foreign";
}


- (id) shortDescription
{
	return @"foreign short";
}

@end


// A string on another root, as a gnustep-base string is: its -description is itself, so the
// fallback must read its text, not describe it again (that recursed without end).
__attribute__((objc_root_class))
@interface OOTestForeignString
{
	Class isa;
}
+ (id) alloc;
- (id) init;
- (id) description;
- (const char *) UTF8String;
@end

@implementation OOTestForeignString

+ (id) alloc
{
	return class_createInstance(self, 0);
}


- (id) init
{
	return self;
}


- (id) description
{
	return self;
}


- (const char *) UTF8String
{
	return "foreign string";
}

@end


namespace {

std::string Head(id object)
{
	return oo::str::format("<%s %s>", class_getName(object_getClass(object)), oo::str::pointerDescription(object).c_str());
}

}	// namespace


OO_TEST(install_the_floor_for_short_literals)
{
	OOObjCInstallFloor();
	OO_CHECK(true);
}


OO_TEST(a_plain_object_is_its_class_and_pointer)
{
	OOTestPlain *object = [[OOTestPlain alloc] init];
	OO_CHECK(![object cxx_descriptionComponents].has_value());
	OO_CHECK_EQ([object cxx_description].value_or(""), Head(object));
	OO_CHECK_EQ([object cxx_shortDescription].value_or(""), Head(object));
	OO_CHECK_EQ(oo::DescriptionOf(object), Head(object));
	OO_CHECK_EQ(oo::ShortDescriptionOf(object), Head(object));
	OO_CHECK(Head(object).rfind("<OOTestPlain 0x", 0) == 0);
	[object release];
}


OO_TEST(components_go_between_braces_and_extend_through_super)
{
	OOTestFlipped *flipped = [[OOTestFlipped alloc] init];
	OOTestFlippedChild *child = [[OOTestFlippedChild alloc] init];
	OO_CHECK_EQ(oo::DescriptionOf(flipped), Head(flipped) + "{1, 2}");
	OO_CHECK_EQ(oo::ShortDescriptionOf(flipped), Head(flipped) + "{short}");
	OO_CHECK_EQ(oo::DescriptionOf(child), Head(child) + "{child 1, 2}");
	OO_CHECK_EQ(oo::ShortDescriptionOf(child), Head(child) + "{short}");
	OO_CHECK_EQ(oo::DescriptionWithComponents(child, std::nullopt), Head(child));
	OO_CHECK_EQ(oo::DescriptionWithComponents(child, std::string("x")), Head(child) + "{x}");
	[flipped release];
	[child release];
}


OO_TEST(the_root_forwards_to_a_legacy_override)
{
	OOTestLegacy *legacy = [[OOTestLegacy alloc] init];
	OO_CHECK_EQ([legacy cxx_descriptionComponents].value_or(""), std::string("legacy components"));
	OO_CHECK(![legacy cxx_shortDescriptionComponents].has_value());		// the override returned nil
	OO_CHECK_EQ(oo::DescriptionOf(legacy), Head(legacy) + "{legacy components}");
	OO_CHECK_EQ(oo::ShortDescriptionOf(legacy), Head(legacy));
	[legacy release];

	OOTestLegacyWhole *whole = [[OOTestLegacyWhole alloc] init];
	OO_CHECK_EQ(oo::DescriptionOf(whole), std::string("the whole text"));
	OO_CHECK_EQ(oo::ShortDescriptionOf(whole), std::string("short text"));
	OO_CHECK(![whole cxx_descriptionComponents].has_value());
	[whole release];

	OOTestFlippedOverLegacy *mixed = [[OOTestFlippedOverLegacy alloc] init];
	OO_CHECK_EQ(oo::DescriptionOf(mixed), Head(mixed) + "{legacy components and more}");
	[mixed release];
}


OO_TEST(nil_classes_literals_and_foreign_objects)
{
	OOTestPlain *none = nil;
	OO_CHECK(![none cxx_description].has_value());
	OO_CHECK(![none cxx_descriptionComponents].has_value());
	OO_CHECK_EQ(oo::DescriptionOf(nil), std::string("(null)"));
	OO_CHECK_EQ(oo::ShortDescriptionOf(nil), std::string("(null)"));

	OO_CHECK_EQ(oo::DescriptionOf([OOTestFlippedChild class]), std::string("OOTestFlippedChild"));
	OO_CHECK_EQ(oo::ShortDescriptionOf([OOTestPlain class]), std::string("OOTestPlain"));

	OO_CHECK_EQ(oo::DescriptionOf(@"a literal too long for a pointer"), std::string("a literal too long for a pointer"));	// OOConstantString
	OO_CHECK_EQ(oo::DescriptionOf(@"tiny"), std::string("tiny"));				// OOTinyString
	OO_CHECK_EQ(oo::ShortDescriptionOf(@"tiny"), std::string("tiny"));

	id foreign = [[OOTestForeignRoot alloc] init];
	OO_CHECK_EQ(oo::DescriptionOf(foreign), std::string("foreign"));
	OO_CHECK_EQ(oo::ShortDescriptionOf(foreign), std::string("foreign short"));
	object_dispose(foreign);

	id string = [[OOTestForeignString alloc] init];
	OO_CHECK_EQ(oo::DescriptionOf(string), std::string("foreign string"));
	object_dispose(string);
}


OO_TEST_MAIN()
