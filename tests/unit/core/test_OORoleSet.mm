/*	test_OORoleSet.mm
	Unit tests for cxx::OORoleSet (src/Core/OORoleSet.h) and its Objective-C facade
	(OORoleSet+ObjCBridge.h): bead oo-bhb9, a Phase 3 conversion in the house style of the OOColor
	exemplar (proposed ADR-0056).

	It pins what the class computed before the conversion, written against the Objective-C API
	and run on the unconverted class first: parsing a role string (probabilities, shipKey roles,
	the thargon rewrite), the normalised role string, lookups, the two role orders, the weighted
	pick, the modified copies (and which of them return the receiver itself), equality, and the
	description. Those checks now run through the facade; the cxx* tests below repeat the answers
	on the C++ class, and the facade* tests pin its contract (nil stays nil, one facade per C++
	set, alloc/init records its facade). Run: bash tools/check-core-tests.sh
*/

#import "OORoleSet.h"
#import "OODescription.h"

#include "oo_test.hpp"


namespace {

using Roles = std::vector<std::string>;
using Probabilities = std::map<std::string, float>;

}	// namespace


OO_TEST(parseRolesFromString)
{
	OO_CHECK(OOParseRolesFromString("") == Probabilities());
	OO_CHECK(OOParseRolesFromString("trader pirate(0.5)  hunter") == Probabilities({ { "hunter", 1.0f }, { "pirate", 0.5f }, { "trader", 1.0f } }));
	OO_CHECK(OOParseRolesFromString("[shipKey] trader") == Probabilities({ { "trader", 1.0f } }));	// shipKey roles are not roles
	OO_CHECK(OOParseRolesFromString("pirate(-1) trader(0)") == Probabilities({ { "trader", 0.0f } }));	// negative is dropped, zero kept
	OO_CHECK(OOParseRolesFromString("police(x)") == Probabilities({ { "police", 1.0f } }));	// no number: probability stays 1
	OO_CHECK(OOParseRolesFromString("(0.5)") == Probabilities({ { "(0.5)", 0.5f } }));	// "(" first: the role is the whole token
	OO_CHECK(OOParseRolesFromString("a(2) a(3)") == Probabilities({ { "a", 3.0f } }));	// the last one wins
}


OO_TEST(roleStringAndLookups)
{
	@autoreleasepool
	{
		OORoleSet *set = [OORoleSet roleSetWithString:"trader pirate(0.5) hunter(0.333333333)"];
		OO_CHECK(set != nil);
		OO_CHECK([set roleString] == std::optional<std::string>("hunter(0.333333) pirate(0.5) trader"));
		OO_CHECK([set hasRole:"pirate"]);
		OO_CHECK(![set hasRole:"police"]);
		OO_CHECK(![set hasRole:""]);
		OO_CHECK([set probabilityForRole:"trader"] == 1.0f);
		OO_CHECK([set probabilityForRole:"pirate"] == 0.5f);
		OO_CHECK([set probabilityForRole:"police"] == 0.0f);
		OO_CHECK([set rolesAndProbabilities] == std::optional<Probabilities>(Probabilities({ { "hunter", 0.333333333f }, { "pirate", 0.5f }, { "trader", 1.0f } })));

		// roles is in byte order; sortedRoles (and roleString) ignore case.
		OORoleSet *mixed = [OORoleSet roleSetWithString:"b a C"];
		OO_CHECK([mixed roles] == Roles({ "C", "a", "b" }));
		OO_CHECK([mixed sortedRoles] == Roles({ "a", "b", "C" }));
		OO_CHECK([mixed roleString] == std::optional<std::string>("a b C"));

		OO_CHECK([OORoleSet roleSetWithRole:"police" probability:2.0f] != nil);
		OO_CHECK([[OORoleSet roleSetWithRole:"police" probability:2.0f] roleString] == std::optional<std::string>("police(2)"));
		OO_CHECK([[[[OORoleSet alloc] initWithRoleString:"escort(0.25)"] autorelease] roleString] == std::optional<std::string>("escort(0.25)"));
		OO_CHECK([[[[OORoleSet alloc] initWithRole:"escort" probability:1.0f] autorelease] roles] == Roles({ "escort" }));
	}
}


OO_TEST(noRolesIsNil)
{
	@autoreleasepool
	{
		OO_CHECK([OORoleSet roleSetWithString:""] == nil);
		OO_CHECK([OORoleSet roleSetWithString:"[shipKey]"] == nil);
		OO_CHECK([OORoleSet roleSetWithString:"pirate(-1)"] == nil);
		OO_CHECK([OORoleSet roleSetWithRole:"" probability:1.0f] == nil);
		OO_CHECK([OORoleSet roleSetWithRole:"pirate" probability:-1.0f] == nil);
		OO_CHECK([[OORoleSet alloc] initWithRoleString:""] == nil);
		OO_CHECK([[OORoleSet alloc] initWithRole:"pirate" probability:-0.5f] == nil);
	}
}


OO_TEST(thargonBecomesEquipment)
{
	@autoreleasepool
	{
		OORoleSet *thargon = [OORoleSet roleSetWithString:"thargon(0.3) trader"];
		OO_CHECK(![thargon hasRole:"thargon"]);
		OO_CHECK([thargon probabilityForRole:"EQ_THARGON"] == 0.3f);
		OO_CHECK([thargon roleString] == std::optional<std::string>("EQ_THARGON(0.3) trader"));

		// Not when EQ_THARGON is already there, nor when its probability is 0.
		OORoleSet *both = [OORoleSet roleSetWithString:"thargon EQ_THARGON(0.2)"];
		OO_CHECK([both roles] == Roles({ "EQ_THARGON", "thargon" }));
		OO_CHECK([both probabilityForRole:"EQ_THARGON"] == 0.2f);
		OO_CHECK([[OORoleSet roleSetWithString:"thargon(0)"] roles] == Roles({ "thargon" }));
	}
}


OO_TEST(anyRole)
{
	@autoreleasepool
	{
		OO_CHECK([[OORoleSet roleSetWithString:"pirate"] anyRole] == std::optional<std::string>("pirate"));
		// Zero total weight: the first role (in byte order) is selected, as selected <= prob at once.
		OO_CHECK([[OORoleSet roleSetWithString:"b(0) a(0)"] anyRole] == std::optional<std::string>("a"));
		OORoleSet *set = [OORoleSet roleSetWithString:"trader pirate(0.5) hunter(2)"];
		for (int i = 0; i < 100; i++)
		{
			std::optional<std::string> role = [set anyRole];
			OO_CHECK(role.has_value() && [set hasRole:*role]);
		}
		// Never picked: a role of weight 0 between weighted ones.
		OORoleSet *weighted = [OORoleSet roleSetWithString:"a(1) b(0) c(1)"];
		for (int i = 0; i < 100; i++)  OO_CHECK([weighted anyRole] != std::optional<std::string>("b"));
	}
}


OO_TEST(modifiedCopies)
{
	@autoreleasepool
	{
		OORoleSet *set = [OORoleSet roleSetWithString:"trader pirate(0.5)"];

		// Nothing to change: the receiver itself (copy is retain, as the set is immutable).
		OO_CHECK([set roleSetWithAddedRole:"trader" probability:0.25f] == set);
		OO_CHECK([set roleSetWithAddedRole:"" probability:1.0f] == set);
		OO_CHECK([set roleSetWithAddedRole:"hunter" probability:-1.0f] == set);
		OO_CHECK([set roleSetWithAddedRoleIfNotSet:"pirate" probability:0.5f] == set);
		OO_CHECK([set roleSetWithRemovedRole:"police"] == set);
		OO_CHECK([[set copy] autorelease] == set);

		OORoleSet *added = [set roleSetWithAddedRole:"hunter" probability:0.75f];
		OO_CHECK(added != set && [added roleString] == std::optional<std::string>("hunter(0.75) pirate(0.5) trader"));
		OO_CHECK([set roleString] == std::optional<std::string>("pirate(0.5) trader"));	// unchanged

		OORoleSet *changed = [set roleSetWithAddedRoleIfNotSet:"pirate" probability:2.0f];
		OO_CHECK(changed != set && [changed probabilityForRole:"pirate"] == 2.0f);

		OORoleSet *removed = [set roleSetWithRemovedRole:"pirate"];
		OO_CHECK([removed roles] == Roles({ "trader" }));

		// Removing the last role gives an empty set, not nil.
		OORoleSet *empty = [removed roleSetWithRemovedRole:"trader"];
		OO_CHECK(empty != nil && [empty roles].empty());
		OO_CHECK([empty roleString] == std::optional<std::string>(""));
		OO_CHECK([empty anyRole] == std::nullopt);
		OO_CHECK(![empty hasRole:"trader"]);
	}
}


OO_TEST(equalityAndDescription)
{
	@autoreleasepool
	{
		OORoleSet *a = [OORoleSet roleSetWithString:"trader pirate(0.5)"];
		OORoleSet *b = [OORoleSet roleSetWithString:"pirate(0.5)   trader(1)"];
		OO_CHECK(a != b && [a isEqual:b] && [b isEqual:a]);
		OO_CHECK([a hash] == 2 && [a hash] == [b hash]);
		OO_CHECK(![a isEqual:[OORoleSet roleSetWithString:"trader pirate(0.25)"]]);
		OO_CHECK(![a isEqual:nil]);

		std::string text = oo::DescriptionOf(a);
		OO_CHECK(text.starts_with("<OORoleSet 0x") && text.ends_with(">{pirate(0.5) trader}"));
	}
}


OO_TEST(nilRoleSet)
{
	OORoleSet *none = nil;
	OO_CHECK(![none roleString].has_value());
	OO_CHECK(![none hasRole:"trader"]);
	OO_CHECK([none roles].empty());
	OO_CHECK(![none anyRole].has_value());
	OO_CHECK([none roleSetWithAddedRole:"trader" probability:1.0f] == nil);
}


OO_TEST(cxxRoleSet)
{
	OO_CHECK(cxx::OORoleSet::roleSetWithString("") == nullptr);
	OO_CHECK(cxx::OORoleSet::roleSetWithString("[shipKey]") == nullptr);
	OO_CHECK(cxx::OORoleSet::roleSetWithRole("pirate", -1.0f) == nullptr);

	oo::Ref<cxx::OORoleSet> set = cxx::OORoleSet::roleSetWithString("trader pirate(0.5) thargon(0.25)");
	OO_CHECK(set != nullptr);
	OO_CHECK(set->roleString() == std::optional<std::string>("EQ_THARGON(0.25) pirate(0.5) trader"));
	OO_CHECK(set->descriptionComponents() == set->roleString());
	OO_CHECK(set->hasRole("pirate") && !set->hasRole("thargon") && !set->hasRole(""));
	OO_CHECK(set->probabilityForRole("pirate") == 0.5f && set->probabilityForRole("police") == 0.0f);
	OO_CHECK(set->roles() == Roles({ "EQ_THARGON", "pirate", "trader" }));
	OO_CHECK(set->sortedRoles() == Roles({ "EQ_THARGON", "pirate", "trader" }));
	OO_CHECK(set->rolesAndProbabilities() == std::optional<Probabilities>(Probabilities({ { "EQ_THARGON", 0.25f }, { "pirate", 0.5f }, { "trader", 1.0f } })));
	OO_CHECK(cxx::OORoleSet::roleSetWithRole("police", 1.0f)->anyRole() == std::optional<std::string>("police"));

	// Nothing to change: the receiver itself.
	OO_CHECK(set->roleSetWithAddedRole("trader", 2.0f) == set);
	OO_CHECK(set->roleSetWithAddedRoleIfNotSet("pirate", 0.5f) == set);
	OO_CHECK(set->roleSetWithRemovedRole("police") == set);

	oo::Ref<cxx::OORoleSet> added = set->roleSetWithAddedRole("hunter", 0.75f);
	OO_CHECK(added != set && added->probabilityForRole("hunter") == 0.75f);
	OO_CHECK(set->roleSetWithAddedRoleIfNotSet("pirate", 2.0f)->probabilityForRole("pirate") == 2.0f);
	oo::Ref<cxx::OORoleSet> empty = cxx::OORoleSet::roleSetWithRole("trader", 1.0f)->roleSetWithRemovedRole("trader");
	OO_CHECK(empty != nullptr && empty->roles().empty() && !empty->anyRole().has_value());

	oo::Ref<cxx::OORoleSet> same = cxx::OORoleSet::roleSetWithString("pirate(0.5) trader EQ_THARGON(0.25)");
	OO_CHECK(set->isEqual(same.get()) && set->hash() == 3 && same->hash() == 3);
	OO_CHECK(!set->isEqual(added.get()) && !set->isEqual(nullptr));
}


OO_TEST(facadeIdentity)
{
	@autoreleasepool
	{
		OORoleSet *set = [OORoleSet roleSetWithString:"trader"];
		OO_CHECK([set isKindOfClass:[OORoleSet class]]);
		OO_CHECK(oo::ToObjC(oo::ToCxx(set)) == set);
		OO_CHECK([set isEqual:oo::ToObjC(cxx::OORoleSet::roleSetWithString("trader"))]);

		// A C++ set crosses to one facade, and back to itself.
		oo::Ref<cxx::OORoleSet> cxxSet = cxx::OORoleSet::roleSetWithString("pirate");
		OORoleSet *facade = oo::ToObjC(cxxSet);
		OO_CHECK(facade != nil && facade == oo::ToObjC(cxxSet.get()));
		OO_CHECK(oo::ToCxx(facade) == cxxSet.get());
		OO_CHECK([facade roleSetWithRemovedRole:"trader"] == facade);

		// alloc/init records the new facade as its set's peer.
		OORoleSet *made = [[OORoleSet alloc] initWithRole:"escort" probability:0.5f];
		OO_CHECK(made != nil && oo::ToObjC(oo::ToCxx(made)) == made);
		OO_CHECK([made roleSetWithAddedRole:"escort" probability:1.0f] == made);
		[made release];
	}
}


OO_TEST(facadeNilStaysNil)
{
	OORoleSet *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OORoleSet *>(nullptr)) == nil);
	OO_CHECK(oo::ToObjC(cxx::OORoleSet::roleSetWithString("")) == nil);
}


OO_TEST_MAIN()
