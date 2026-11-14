/*	test_objc_runtime.mm
	Unit tests for oofnd/objc/OORuntime.h (bead oo-3rb.19): class and selector names on libobjc2
	alone, the replacements for NSClassFromString / NSStringFromClass / NSSelectorFromString /
	NSStringFromSelector.
*/

#include "oofnd/objc/OORuntime.h"
#include "oofnd/objc/OOObject.h"

#include "oo_test.hpp"

#include <cstring>
#include <string>
#include <string_view>

@interface OOTestRuntimeThing : OOObject
- (id) answer;
- (id) echo:(id)object;
@end

@implementation OOTestRuntimeThing
- (id) answer
{
	return self;
}

- (id) echo:(id)object
{
	return object;
}
@end

namespace {

bool Same(const char *a, const char *b)
{
	return a != nullptr && b != nullptr && std::strcmp(a, b) == 0;
}

} // namespace

OO_TEST(classFromNameFindsRegisteredClasses)
{
	OO_CHECK(OOClassFromName("OOTestRuntimeThing") == [OOTestRuntimeThing class]);
	OO_CHECK(OOClassFromName("OOObject") == [OOObject class]);
	OO_CHECK(OOClassFromName("OONoSuchClassAnywhere") == Nil);
	OO_CHECK(OOClassFromName(static_cast<const char *>(nullptr)) == Nil);
}

OO_TEST(classFromNameTakesAnUnterminatedView)
{
	const char buffer[] = "OOTestRuntimeThingTRAILING";
	const std::string_view view(buffer, std::strlen("OOTestRuntimeThing"));
	OO_CHECK(OOClassFromName(view) == [OOTestRuntimeThing class]);
	OO_CHECK(OOClassFromName(std::string_view("OOTestRuntimeThin")) == Nil);
}

OO_TEST(classNameRoundTrips)
{
	OO_CHECK(Same(OOClassName([OOTestRuntimeThing class]), "OOTestRuntimeThing"));
	OO_CHECK(OOClassFromName(OOClassName([OOObject class])) == [OOObject class]);
	OO_CHECK(OOClassName(Nil) == nullptr);
}

OO_TEST(selectorFromNameMatchesCompiledSelectorsByName)
{
	SEL registered = OOSelectorFromName("echo:");
	OO_CHECK(registered != nullptr);
	OO_CHECK(OOSelectorsEqual(registered, @selector(echo:)));
	OO_CHECK(!OOSelectorsEqual(registered, @selector(answer)));
	OO_CHECK(OOSelectorsEqual(OOSelectorFromName(std::string_view("answerXYZ", 6)), @selector(answer)));
	OO_CHECK(OOSelectorFromName(static_cast<const char *>(nullptr)) == nullptr);
	OO_CHECK(OOSelectorsEqual(nullptr, nullptr));
	OO_CHECK(!OOSelectorsEqual(nullptr, @selector(answer)));
}

OO_TEST(aNewNameIsRegistered)
{
	SEL fresh = OOSelectorFromName("oofndTestSelectorNobodyImplements:with:");
	OO_CHECK(fresh != nullptr);
	OO_CHECK(Same(OOSelectorName(fresh), "oofndTestSelectorNobodyImplements:with:"));
	OO_CHECK(OOSelectorsEqual(fresh, OOSelectorFromName("oofndTestSelectorNobodyImplements:with:")));
}

OO_TEST(selectorNameRoundTrips)
{
	OO_CHECK(Same(OOSelectorName(@selector(echo:)), "echo:"));
	OO_CHECK(Same(OOSelectorName(OOSelectorFromName("answer")), "answer"));
	OO_CHECK(OOSelectorName(nullptr) == nullptr);
}

OO_TEST(dispatchThroughARegisteredSelector)
{
	OOTestRuntimeThing *thing = [[OOTestRuntimeThing alloc] init];
	SEL answer = OOSelectorFromName("answer");
	SEL echo = OOSelectorFromName("echo:");
	OO_CHECK([thing respondsToSelector:answer]);
	OO_CHECK([thing respondsToSelector:echo]);
	OO_CHECK(![thing respondsToSelector:OOSelectorFromName("noSuchMethodHere")]);
	OO_CHECK([thing performSelector:answer] == thing);
	OO_CHECK([thing performSelector:echo withObject:thing] == thing);
	[thing release];
}

OO_TEST_MAIN()
