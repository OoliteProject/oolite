/*	test_objc_call_by_name.mm
	Unit tests for OOCallByName (Core/OOCallByName.h, proposed ADR-0055 item 5, bead oo-qps.34):
	a method named at run time called through an IMP of its C++ signature.

	Core/OOCallByName.mm is compiled into this executable with OO_CALL_BY_NAME_FOUNDATION_FREE=1
	(its transitional id branch, the only bridge use, left out) and linked against libobjc2 alone
	(tools/check-oofnd-objc.sh checks the import table).
*/

#define OO_CALL_BY_NAME_FOUNDATION_FREE 1
#import "Core/OOCallByName.mm"

#include "oo_test.hpp"

#include <string>


@interface OOTestCallTarget: OOObject
{
@public
	int pings;
	int scalarCalls;
	std::string lastString;
	oo::PList lastPList;
}
- (void) ping;
- (oo::PList) answer;
- (BOOL) scalarAction;
- (void) takeString:(const std::string &)string;
- (oo::PList) echo:(const std::string &)string;
- (void) takePList:(const oo::PList &)plist;
- (void) takeInt:(int)value;
- (void) take:(const std::string &)string and:(int)value;
- (id) legacy:(id)object;
@end

@implementation OOTestCallTarget

- (void) ping
{
	pings++;
}


- (oo::PList) answer
{
	return oo::PList("forty-two");
}


- (BOOL) scalarAction
{
	scalarCalls++;
	return YES;
}


- (void) takeString:(const std::string &)string
{
	lastString = string;
}


- (oo::PList) echo:(const std::string &)string
{
	return oo::PList(string + "!");
}


- (void) takePList:(const oo::PList &)plist
{
	lastPList = plist;
}


- (void) takeInt:(int)value
{
	pings += value;
}


- (void) take:(const std::string &)string and:(int)value
{
	lastString = string;
	pings += value;
}


- (id) legacy:(id)object
{
	pings += 100;
	return object;
}

@end


// A proxy that forwards everything to its target, as OOWeakReference does.
@interface OOTestForwarder: OOObject
{
@public
	id target;
}
@end

@implementation OOTestForwarder

- (id) forwardingTargetForSelector:(SEL)selector
{
	(void)selector;
	return target;
}

@end


OO_TEST(the_reference_encodings_on_this_toolchain)
{
	// clang 22 / gnustep-2.2 on 64-bit Windows: a C++ class is encoded as its full struct layout
	// ({PList=...}), a const reference as r^ and the struct. Pinned (by shape: the layouts are
	// long) so a toolchain change that alters them is seen here, not as by-name calls that stop
	// matching.
	const Encodings &encodings = ReferenceEncodings();
	const auto startsWith = [](const std::string &text, const char *prefix) { return text.rfind(prefix, 0) == 0; };
	OO_CHECK(startsWith(encodings.plistResult, "{PList={variant<std::monostate, bool, oo::PList::Integer, double, "));
	OO_CHECK(startsWith(encodings.stringArgument, "r^{basic_string<char, std::char_traits<char>, std::allocator<char>>={_Alloc_hider=*}Q"));
	OO_CHECK_EQ(encodings.plistArgument, "r^" + encodings.plistResult);
	OO_CHECK(encodings.stringArgument != encodings.plistArgument);

	// What a method of each form reports, and what OOCallByName makes of it.
	Class target = [OOTestCallTarget class];
	OO_CHECK_EQ(OwnedEncoding(method_copyReturnType(class_getInstanceMethod(target, OOSelectorFromName("answer")))), encodings.plistResult);
	OO_CHECK_EQ(OwnedEncoding(method_copyArgumentType(class_getInstanceMethod(target, OOSelectorFromName("echo:")), 2)), encodings.stringArgument);
	OO_CHECK(ResultKind(class_getInstanceMethod(target, OOSelectorFromName("ping"))) == Kind::Void);
	OO_CHECK(ResultKind(class_getInstanceMethod(target, OOSelectorFromName("scalarAction"))) == Kind::Void);
	OO_CHECK(ResultKind(class_getInstanceMethod(target, OOSelectorFromName("legacy:"))) == Kind::Object);
	OO_CHECK(ArgumentKind(class_getInstanceMethod(target, OOSelectorFromName("takePList:"))) == Kind::PList);
	OO_CHECK(ArgumentKind(class_getInstanceMethod(target, OOSelectorFromName("takeInt:"))) == Kind::Unsupported);
	OO_CHECK(ArgumentKind(class_getInstanceMethod(target, OOSelectorFromName("take:and:"))) == Kind::Unsupported);
}


OO_TEST(no_argument)
{
	OOTestCallTarget *target = [[OOTestCallTarget alloc] init];
	OO_CHECK(OOCallByName(target, OOSelectorFromName("ping")).isNull());
	OO_CHECK_EQ(target->pings, 1);
	OO_CHECK_EQ(OOCallByName(target, OOSelectorFromName("answer")), oo::PList("forty-two"));
	OO_CHECK(OOCallByName(target, OOSelectorFromName("scalarAction")).isNull());	// the BOOL is ignored
	OO_CHECK_EQ(target->scalarCalls, 1);
	[target release];
}


OO_TEST(string_argument)
{
	OOTestCallTarget *target = [[OOTestCallTarget alloc] init];
	OO_CHECK(OOCallByName(target, OOSelectorFromName("takeString:"), std::string("hello world")).isNull());
	OO_CHECK_EQ(target->lastString, std::string("hello world"));
	OO_CHECK_EQ(OOCallByName(target, OOSelectorFromName("echo:"), "hi"), oo::PList("hi!"));
	OO_CHECK(OOCallByName(target, OOSelectorFromName("takePList:"), "as a plist").isNull());
	OO_CHECK_EQ(target->lastPList, oo::PList("as a plist"));
	[target release];
}


OO_TEST(plist_argument)
{
	OOTestCallTarget *target = [[OOTestCallTarget alloc] init];
	const oo::PList dict(oo::PList::Dict{{"key", oo::PList(3)}});
	OO_CHECK(OOCallByName(target, OOSelectorFromName("takePList:"), dict).isNull());
	OO_CHECK_EQ(target->lastPList, dict);
	OO_CHECK(OOCallByName(target, OOSelectorFromName("takeString:"), oo::PList("a string plist")).isNull());
	OO_CHECK_EQ(target->lastString, std::string("a string plist"));
	OO_CHECK(OOCallByName(target, OOSelectorFromName("takeString:"), dict).isNull());	// not a string: logged, not called
	OO_CHECK_EQ(target->lastString, std::string("a string plist"));
	[target release];
}


OO_TEST(unusable_calls_are_logged_and_not_made)
{
	OOTestCallTarget *target = [[OOTestCallTarget alloc] init];
	OO_CHECK(OOCallByName(target, OOSelectorFromName("noSuchAction")).isNull());
	OO_CHECK(OOCallByName(target, OOSelectorFromName("takeInt:"), "5").isNull());
	OO_CHECK(OOCallByName(target, OOSelectorFromName("take:and:"), "x").isNull());
	OO_CHECK(OOCallByName(target, OOSelectorFromName("ping"), "an extra argument").isNull());
	OO_CHECK(OOCallByName(target, OOSelectorFromName("takeString:")).isNull());		// a missing argument
	OO_CHECK(OOCallByName(target, OOSelectorFromName("legacy:"), "x").isNull());	// id: the bridge is out of this build
	OO_CHECK_EQ(target->pings, 0);
	OO_CHECK(target->lastString.empty());
	OO_CHECK(OOCallByName(nil, OOSelectorFromName("ping")).isNull());
	[target release];
}


OO_TEST(a_forwarding_proxy_is_followed)
{
	OOTestCallTarget *target = [[OOTestCallTarget alloc] init];
	OOTestForwarder *proxy = [[OOTestForwarder alloc] init];
	proxy->target = target;
	OO_CHECK(OOCallByName(proxy, OOSelectorFromName("takeString:"), "through the proxy").isNull());
	OO_CHECK_EQ(target->lastString, std::string("through the proxy"));
	[proxy release];
	[target release];
}


OO_TEST_MAIN()
