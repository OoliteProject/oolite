/*	test_objc_description.mm
	Unit tests for the description family on the Objective-C root (Core/OODescription.h, proposed
	ADR-0055 item 1, bead oo-qps.31): -cxx_description & co., oo::DescriptionOf /
	ShortDescriptionOf. (The cases for the transitional forwarding to a legacy id-typed override
	and for the foreign-root -description fallback were retired with that code by oo-qps.73,
	ADR-0049, Jon's approval in tools/retire-test-approvals.txt.)

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
}


OO_TEST_MAIN()
