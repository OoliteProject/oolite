/*	test_objc_plist.mm
	Unit tests for Objective-C objects inside an oo::PList (Core/OOObjCPList.h, proposed
	ADR-0055 item 2, bead oo-qps.33): oo::PListObject / ObjectIn, the Object node's retain,
	identity and description, and the array forms oo::PListFromObjects / ObjCRefsIn.

	Core/OODescription.mm is compiled into this executable, which links libobjc2 and NOTHING
	from gnustep-base (tools/check-oofnd-objc.sh checks the import table): the proof that the
	Object node survives oo-qps.18.
*/

#include "oofnd/objc/OOObject.h"
#include "oofnd/objc/OOObjCRef.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"

#include "Core/OOObjCPList.h"
#import "Core/OODescription.mm"

#include "oo_test.hpp"

#include <objc/objc-arc.h>

#include <string>
#include <vector>


static int gDeallocated = 0;


@interface OOPListTestThing : OOObject
@end

@implementation OOPListTestThing

- (std::optional<std::string>) cxx_descriptionComponents
{
	return std::string("thing");
}


- (void) dealloc
{
	++gDeallocated;
	[super dealloc];
}

@end


@interface OOPListTestOther : OOObject
@end

@implementation OOPListTestOther
@end


namespace {

unsigned long Count(id object)
{
	return static_cast<unsigned long>(object_getRetainCount_np(object));
}

std::string Head(id object)
{
	return oo::str::format("<%s %s>", class_getName(object_getClass(object)), oo::str::pointerDescription(object).c_str());
}

}	// namespace


OO_TEST(nil_is_a_null_plist_and_a_null_plist_holds_no_object)
{
	OO_CHECK(oo::PListObject(nil).isNull());
	OO_CHECK(oo::ObjectIn(oo::PList()) == nil);
	OO_CHECK(oo::ObjectIn(oo::PList(std::string("a string"))) == nil);
	OO_CHECK(oo::ObjectIn(oo::PList(1)) == nil);
	OO_CHECK(oo::ObjectIn(oo::PList(oo::PList::Array{})) == nil);
}


OO_TEST(an_object_node_retains_and_gives_back_its_object)
{
	gDeallocated = 0;
	OOPListTestThing *thing = [[OOPListTestThing alloc] init];
	OO_CHECK_EQ(Count(thing), 1UL);
	{
		oo::PList node = oo::PListObject(thing);
		OO_CHECK(node.type() == oo::PList::Type::Object);
		OO_CHECK_EQ(Count(thing), 2UL);
		OO_CHECK(oo::ObjectIn(node) == thing);

		oo::PList copy = node;		// copying the tree shares the node; the object is not retained again
		OO_CHECK(oo::ObjectIn(copy) == thing);
		OO_CHECK(copy == node);
	}
	OO_CHECK_EQ(Count(thing), 1UL);
	OO_CHECK_EQ(gDeallocated, 0);
	[thing release];
	OO_CHECK_EQ(gDeallocated, 1);
}


// PList compares an Object node by the node's identity (oofnd/PList.hpp): a node equals its
// copies; two nodes made for the same object are different values.
OO_TEST(object_nodes_compare_by_node_identity)
{
	OOPListTestThing *a = [[OOPListTestThing alloc] init];
	OOPListTestThing *b = [[OOPListTestThing alloc] init];
	oo::PList node = oo::PListObject(a);
	oo::PList copy = node;
	OO_CHECK(node == copy);
	OO_CHECK(!(node == oo::PListObject(a)));
	OO_CHECK(!(node == oo::PListObject(b)));
	OO_CHECK(oo::ObjectIn(oo::PListObject(a)) == oo::ObjectIn(node));
	[a release];
	[b release];
}


OO_TEST(an_object_node_describes_itself_as_its_object)
{
	OOPListTestThing *thing = [[OOPListTestThing alloc] init];
	oo::PList node = oo::PListObject(thing);
	const oo::PList::Object *payload = node.getIf<oo::PList::Object>();
	OO_CHECK(payload != nullptr);
	if (payload != nullptr)
	{
		OO_CHECK_EQ((*payload)->description(), Head(thing) + "{thing}");
		OO_CHECK_EQ((*payload)->description(), oo::DescriptionOf(thing));
		OO_CHECK_EQ((*payload)->className(), std::string("OOPListTestThing"));
	}
	[thing release];
}


OO_TEST(plist_from_objects_is_an_array_of_object_nodes_in_order_nil_skipped)
{
	gDeallocated = 0;
	OOPListTestThing *a = [[OOPListTestThing alloc] init];
	OOPListTestThing *b = [[OOPListTestThing alloc] init];
	{
		std::vector<oo::ObjCRef<OOPListTestThing *>> refs;
		refs.emplace_back(a);
		refs.emplace_back(nullptr);
		refs.emplace_back(b);
		refs.emplace_back(a);

		oo::PList array = oo::PListFromObjects(refs);
		OO_CHECK(array.isArray());
		OO_CHECK_EQ(array.count(), size_t(3));
		const oo::PList::Array *elements = array.getIf<oo::PList::Array>();
		OO_CHECK(elements != nullptr);
		if (elements != nullptr && elements->size() == 3)
		{
			OO_CHECK(oo::ObjectIn((*elements)[0]) == a);
			OO_CHECK(oo::ObjectIn((*elements)[1]) == b);
			OO_CHECK(oo::ObjectIn((*elements)[2]) == a);
		}
		OO_CHECK_EQ(Count(a), 5UL);		// the caller's, the vector's two entries and two nodes

		OO_CHECK(oo::PListFromObjects(std::vector<oo::ObjCRef<OOPListTestThing *>>{}) == oo::PList(oo::PList::Array{}));
	}
	OO_CHECK_EQ(Count(a), 1UL);
	OO_CHECK_EQ(Count(b), 1UL);
	[a release];
	[b release];
	OO_CHECK_EQ(gDeallocated, 2);
}


OO_TEST(objc_refs_in_takes_the_object_nodes_of_an_array_others_skipped)
{
	OOPListTestThing *a = [[OOPListTestThing alloc] init];
	OOPListTestOther *other = [[OOPListTestOther alloc] init];
	oo::PList array(oo::PList::Array{
		oo::PListObject(a),
		oo::PList(std::string("not an object")),
		oo::PList(),
		oo::PListObject(other),
		oo::PList(oo::PList::Array{oo::PListObject(a)}),	// nested: not an element's object
	});

	std::vector<oo::ObjCRef<id>> refs = oo::ObjCRefsIn<id>(array);
	OO_CHECK_EQ(refs.size(), size_t(2));
	if (refs.size() == 2)
	{
		OO_CHECK(refs[0] == a);
		OO_CHECK(refs[1] == other);
	}
	OO_CHECK_EQ(Count(a), 4UL);		// the caller's, two nodes, one ref

	OO_CHECK(oo::ObjCRefsIn<id>(oo::PList()).empty());
	OO_CHECK(oo::ObjCRefsIn<id>(oo::PListObject(a)).empty());		// not an array
	OO_CHECK(oo::ObjCRefsIn<id>(oo::PList(oo::PList::Dict{{"k", oo::PListObject(a)}})).empty());

	refs.clear();
	[a release];
	[other release];
}


OO_TEST(objc_refs_in_inverts_plist_from_objects)
{
	OOPListTestThing *a = [[OOPListTestThing alloc] init];
	OOPListTestThing *b = [[OOPListTestThing alloc] init];
	std::vector<oo::ObjCRef<OOPListTestThing *>> refs;
	refs.emplace_back(b);
	refs.emplace_back(a);

	std::vector<oo::ObjCRef<OOPListTestThing *>> back = oo::ObjCRefsIn<OOPListTestThing *>(oo::PListFromObjects(refs));
	OO_CHECK(back == refs);

	refs.clear();
	back.clear();
	[a release];
	[b release];
}


OO_TEST_MAIN()
