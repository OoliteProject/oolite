/*	test_objc_ref.mm
	Unit tests for oo::ObjCRef (src/oofnd/objc/OOObjCRef.h; the Foundation sweep, proposed
	ADR-0043): a strong reference to an Objective-C object that a std container can own.

	Also pins the compiler fact the sweep's return-type rule rests on: a message to nil whose
	method returns a C++ class by value yields ZERO-FILLED storage (on the GNUstep runtime clang
	emits the nil check and a memset; the method never runs). So an Objective-C method whose
	receiver may be nil may return by value only a type whose all-zero bytes are a valid value:
	std::vector, std::optional<T> (zero = disengaged = "nil"), oo::ObjCRef, oo::PList (zero = a
	null PList), std::string_view. NOT std::string: libstdc++'s zero-filled string has a NULL
	data(), and copying it segfaults (measured on this toolchain, 2026-09-23); nor std::map /
	std::set / std::unordered_* (their headers point at themselves). Those are returned inside a
	std::optional. See src/oofnd/README.md, "Migrating Foundation usage".

	Linked against libobjc2 alone, like the other test_*.mm (tools/check-oofnd-objc.sh).
*/

#include "oofnd/objc/OOObject.h"
#include "oofnd/objc/OOObjCRef.h"
#include "oofnd/PList.hpp"

#include "oo_test.hpp"

#include <objc/objc-arc.h>

#include <algorithm>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_set>
#include <utility>
#include <vector>

namespace {

std::vector<std::string> gDeallocated;

} // namespace

@interface OORefTestThing : OOObject
{
@public
	std::string name;
}
- (id) initWithName:(const char *)aName;
- (std::optional<std::map<std::string, float>>) mapResult;
- (oo::PList) plistResult;
- (std::vector<int>) vectorResult;
- (std::optional<std::string>) optionalResult;
- (oo::ObjCRef<id>) refResult;
- (std::vector<oo::ObjCRef<id>>) refsResult;
@end

@implementation OORefTestThing

- (id) initWithName:(const char *)aName
{
	if ((self = [super init]))  name = aName;
	return self;
}

- (void) dealloc
{
	gDeallocated.push_back(name);
	[super dealloc];
}

- (std::optional<std::map<std::string, float>>) mapResult
{
	return std::map<std::string, float>{{"a", 1.0f}};
}

- (oo::PList) plistResult
{
	return oo::PList("a string long enough to need the heap, not the small buffer");
}

- (std::vector<int>) vectorResult
{
	return {1, 2, 3};
}

- (std::optional<std::string>) optionalResult
{
	return std::string("x");
}

- (oo::ObjCRef<id>) refResult
{
	return oo::ObjCRef<id>(self);
}

- (std::vector<oo::ObjCRef<id>>) refsResult
{
	return {oo::ObjCRef<id>(self)};
}

@end

// An immortal singleton, as several Oolite managers are: objc_retain()/objc_release() must send
// it the messages, and nothing may free it.
@interface OORefTestImmortal : OOObject
@end

static int sImmortalRetains = 0;
static int sImmortalReleases = 0;

@implementation OORefTestImmortal

- (id) retain
{
	++sImmortalRetains;
	return self;
}

- (oneway void) release
{
	++sImmortalReleases;
}

@end

static OORefTestThing *NewThing(const char *name)
{
	return [[OORefTestThing alloc] initWithName:name];   // +1
}

static unsigned long Count(id object)
{
	return static_cast<unsigned long>(object_getRetainCount_np(object));
}

OO_TEST(retaining_constructor_and_destructor)
{
	gDeallocated.clear();
	OORefTestThing *thing = NewThing("a");
	OO_CHECK_EQ(Count(thing), 1UL);
	{
		oo::ObjCRef<OORefTestThing *> ref(thing);
		OO_CHECK_EQ(Count(thing), 2UL);
		OO_CHECK(ref.get() == thing);
		OO_CHECK(static_cast<bool>(ref));
	}
	OO_CHECK_EQ(Count(thing), 1UL);
	OO_CHECK(gDeallocated.empty());
	[thing release];
	OO_CHECK_EQ(gDeallocated.size(), 1u);
}

OO_TEST(adopt_takes_the_plus_one)
{
	gDeallocated.clear();
	{
		oo::ObjCRef<OORefTestThing *> ref = oo::adoptObjC(NewThing("adopted"));
		OO_CHECK_EQ(Count(ref.get()), 1UL);
	}
	OO_CHECK_EQ(gDeallocated.size(), 1u);
	OO_CHECK(gDeallocated.size() == 1 && gDeallocated[0] == "adopted");
}

OO_TEST(leak_ref_hands_the_plus_one_out)
{
	gDeallocated.clear();
	oo::ObjCRef<OORefTestThing *> ref = oo::adoptObjC(NewThing("leaked"));
	OORefTestThing *raw = ref.leakRef();
	OO_CHECK(ref.get() == nil);
	OO_CHECK_EQ(Count(raw), 1UL);
	OO_CHECK(gDeallocated.empty());
	[raw release];
	OO_CHECK_EQ(gDeallocated.size(), 1u);
}

OO_TEST(copy_move_assign_and_self_assign)
{
	gDeallocated.clear();
	oo::ObjCRef<OORefTestThing *> a = oo::adoptObjC(NewThing("c"));
	OORefTestThing *raw = a.get();
	oo::ObjCRef<OORefTestThing *> b = a;
	OO_CHECK_EQ(Count(raw), 2UL);
	oo::ObjCRef<OORefTestThing *> c = std::move(b);
	OO_CHECK(b.get() == nil);
	OO_CHECK_EQ(Count(raw), 2UL);
	oo::ObjCRef<OORefTestThing *>& alias = c;
	c = alias;   // self-assignment keeps the object alive
	OO_CHECK_EQ(Count(raw), 2UL);
	a = nullptr;
	OO_CHECK_EQ(Count(raw), 1UL);
	c = oo::adoptObjC(NewThing("d"));   // releases "c"
	OO_CHECK_EQ(gDeallocated.size(), 1u);
	OO_CHECK(gDeallocated.size() == 1 && gDeallocated[0] == "c");
	c = nullptr;
	OO_CHECK_EQ(gDeallocated.size(), 2u);
}

OO_TEST(converts_to_a_superclass_or_id_ref)
{
	gDeallocated.clear();
	oo::ObjCRef<OORefTestThing *> thing = oo::adoptObjC(NewThing("up"));
	oo::ObjCRef<id> any = thing;
	OO_CHECK_EQ(Count(thing.get()), 2UL);
	OO_CHECK(any == thing);
	oo::ObjCRef<OOObject *> base = std::move(thing);
	OO_CHECK(thing.get() == nil);
	OO_CHECK_EQ(Count(any.get()), 2UL);
	any = nullptr;
	base = nullptr;
	OO_CHECK_EQ(gDeallocated.size(), 1u);
}

OO_TEST(a_vector_owns_its_objects_as_an_nsmutablearray_did)
{
	gDeallocated.clear();
	{
		std::vector<oo::ObjCRef<OORefTestThing *>> things;
		OORefTestThing *first = NewThing("v0");
		things.emplace_back(first);   // retains, as -addObject: did
		[first release];
		things.push_back(oo::adoptObjC(NewThing("v1")));
		for (int i = 2; i < 40; ++i)  things.push_back(oo::adoptObjC(NewThing("vn")));   // reallocation moves, never double-releases
		OO_CHECK_EQ(things.size(), 40u);
		OO_CHECK_EQ(Count(things[0].get()), 1UL);
		OO_CHECK(things[1].get()->name == "v1");
		things.erase(things.begin());   // releases v0
		OO_CHECK_EQ(gDeallocated.size(), 1u);
		OO_CHECK(gDeallocated.size() == 1 && gDeallocated[0] == "v0");
		std::vector<oo::ObjCRef<OORefTestThing *>> copy = things;
		OO_CHECK_EQ(Count(things[0].get()), 2UL);
	}
	OO_CHECK_EQ(gDeallocated.size(), 40u);
}

OO_TEST(a_map_owns_its_values_as_an_nsmutabledictionary_did)
{
	gDeallocated.clear();
	{
		std::map<std::string, oo::ObjCRef<OORefTestThing *>, std::less<>> byName;
		byName["k"] = oo::adoptObjC(NewThing("m0"));
		byName["k"] = oo::adoptObjC(NewThing("m1"));   // replacing releases the old value
		OO_CHECK_EQ(gDeallocated.size(), 1u);
		auto it = byName.find(std::string_view("k"));
		OO_CHECK(it != byName.end() && it->second.get()->name == "m1");
		OO_CHECK(byName.find(std::string_view("absent")) == byName.end());
	}
	OO_CHECK_EQ(gDeallocated.size(), 2u);
}

OO_TEST(identity_equality_ordering_and_hash)
{
	oo::ObjCRef<OORefTestThing *> a = oo::adoptObjC(NewThing("h0"));
	oo::ObjCRef<OORefTestThing *> a2 = a;
	oo::ObjCRef<OORefTestThing *> b = oo::adoptObjC(NewThing("h1"));
	OO_CHECK(a == a2);
	OO_CHECK(!(a == b));
	OO_CHECK(a == static_cast<id>(a.get()));
	OO_CHECK((a <=> a2) == 0);
	OO_CHECK((a <=> b) != 0);
	oo::ObjCRef<OORefTestThing *> none;
	OO_CHECK(none == nullptr);
	OO_CHECK(!static_cast<bool>(none));
	std::unordered_set<oo::ObjCRef<OORefTestThing *>> set;
	set.insert(a);
	set.insert(a2);
	set.insert(b);
	OO_CHECK_EQ(set.size(), 2u);
	std::vector<oo::ObjCRef<OORefTestThing *>> v{b, a};
	OO_CHECK(std::find(v.begin(), v.end(), a2) != v.end());
}

OO_TEST(nil_is_a_null_ref_and_costs_nothing)
{
	oo::ObjCRef<id> ref(static_cast<id>(nil));   // objc_retain(nil) / objc_release(nil) are no-ops
	OO_CHECK(ref.get() == nil);
	oo::ObjCRef<id> copy = ref;
	OO_CHECK(copy == nullptr);
}

OO_TEST(an_immortal_is_sent_retain_and_release)
{
	OORefTestImmortal *immortal = [OORefTestImmortal new];
	sImmortalRetains = sImmortalReleases = 0;
	{
		oo::ObjCRef<OORefTestImmortal *> ref(immortal);
		oo::ObjCRef<OORefTestImmortal *> copy = ref;
	}
	OO_CHECK_EQ(sImmortalRetains, 2);
	OO_CHECK_EQ(sImmortalReleases, 2);
}

// --- the nil-message rule (the sweep's return-type rule rests on it) ------------------------------

OO_TEST(a_nil_message_zero_fills_a_cxx_result)
{
	OORefTestThing *none = nil;

	const std::vector<int> v = [none vectorResult];
	OO_CHECK(v.empty());

	const std::optional<std::string> o = [none optionalResult];
	OO_CHECK(!o.has_value());

	const oo::ObjCRef<id> r = [none refResult];
	OO_CHECK(r.get() == nil);

	const std::vector<oo::ObjCRef<id>> rs = [none refsResult];
	OO_CHECK(rs.empty());

	const std::optional<std::map<std::string, float>> m = [none mapResult];
	OO_CHECK(!m.has_value());

	const oo::PList p = [none plistResult];
	OO_CHECK(p.isNull());
	const oo::PList pCopy = p;   // a zero-filled PList is an ordinary null PList: copies, compares
	OO_CHECK(pCopy == oo::PList());

	// The same messages to a real object return the method's values.
	OORefTestThing *thing = NewThing("real");
	OO_CHECK_EQ([thing vectorResult].size(), 3u);
	OO_CHECK([thing optionalResult].value() == "x");
	OO_CHECK([thing mapResult].value().size() == 1);
	OO_CHECK([thing plistResult].isString());
	OO_CHECK([thing refResult].get() == thing);
	[thing release];
}

OO_TEST_MAIN()
