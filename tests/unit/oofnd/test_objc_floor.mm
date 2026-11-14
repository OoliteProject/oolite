/*	test_objc_floor.mm
	Unit tests for the Foundation-free Objective-C floor (bead oo-3rb.1, proposed ADR-0029):
	the OOObject root class and the OOConstantString/OOTinyString classes behind @"..." literals.

	This executable links libobjc2 and NOTHING from GNUstep's Foundation: tools/check-oofnd-objc.sh
	builds it with -lobjc only and then fails if its import table names any gnustep-base DLL.
	It is Objective-C++ at -std=c++20 -Wall -Wextra -Werror, with the game's runtime flags
	(-fobjc-runtime=gnustep-2.2 -fobjc-exceptions) plus -fconstant-string-class=OOConstantString.
*/

#include "oofnd/objc/OOObject.h"
#include "oofnd/objc/OOConstantString.h"
#include "oofnd/Ref.hpp"

#include "oo_test.hpp"

#include <objc/objc-arc.h>

#include <cstring>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

std::vector<std::string> gLog;
int gCxxLive = 0;

struct CxxMember
{
	CxxMember() { ++gCxxLive; }
	~CxxMember() { --gCxxLive; }
	CxxMember(const CxxMember&) = delete;
	CxxMember& operator=(const CxxMember&) = delete;
};

class Payload : public oo::RefCounted
{
public:
	~Payload() override { gLog.push_back("payload"); }
};

} // namespace

@protocol OOTestMarker
@end

@protocol OOTestUnimplemented
- (id) noSuchMethod;
@end

@interface OOTestThing : OOObject <OOTestMarker, OOCopying>
{
@public
	std::string name;           // C++ ivars: need .cxx_construct/.cxx_destruct from the root
	CxxMember member;
	oo::Ref<Payload> payload;   // the Phase 2 bridge: an oofnd Ref held by an ObjC object
}
- (id) initWithName:(const char *)aName;
- (id) echo:(id)object;
- (id) pairFirst:(id)a second:(id)b;
@end

@implementation OOTestThing

- (id) initWithName:(const char *)aName
{
	if ((self = [super init]))  name = aName;
	return self;
}

- (void) dealloc
{
	gLog.push_back(name);
	[super dealloc];
}

- (id) echo:(id)object
{
	return object;
}

- (id) pairFirst:(id)a second:(id)b
{
	return a != nil ? b : nil;
}

- (id) copyWithZone:(OOZone *)zone
{
	(void)zone;
	return [[OOTestThing alloc] initWithName:(name + "-copy").c_str()];
}

@end

// An immortal singleton, as several Oolite managers are: overriding -retain/-release takes it off
// libobjc2's fast path, so objc_retain()/objc_release() must send it the messages.
@interface OOTestImmortal : OOObject
@end

@implementation OOTestImmortal

- (id) retain
{
	return self;
}

- (oneway void) release
{
}

@end

// A singleton that allocates in +allocWithZone:, as OODebugMonitor, OOSoundMixer and others do.
static id sTestSingleton = nil;
static int sTestSingletonAllocs = 0;

@interface OOTestSingleton : OOObject
@end

@implementation OOTestSingleton

+ (id) allocWithZone:(OOZone *)zone
{
	++sTestSingletonAllocs;
	if (sTestSingleton == nil)
	{
		sTestSingleton = [super allocWithZone:zone];
		return sTestSingleton;
	}
	return nil;
}

@end

@interface OOTestForwarder : OOObject
{
@public
	id target;
	SEL lastUnrecognized;
}
@end

@implementation OOTestForwarder

- (id) forwardingTargetForSelector:(SEL)selector
{
	return sel_isEqual(selector, @selector(echo:)) ? target : nil;   // compare SELs by name: libobjc2 SELs are typed
}

- (void) doesNotRecognizeSelector:(SEL)selector
{
	lastUnrecognized = selector;   // the default aborts; recording lets the test observe the path
}

@end

@interface OOTestError : OOObject
{
@public
	int code;
}
@end

@implementation OOTestError
@end

@interface OOTestOtherError : OOObject
@end

@implementation OOTestOtherError
@end


OO_TEST(installFloorIsIdempotent)
{
	OOObjCInstallFloor();
	OOObjCInstallFloor();
	OO_CHECK(object_getClass(@"tiny") == [OOTinyString class]);
}

OO_TEST(allocRetainReleaseDeallocs)
{
	gLog.clear();
	OOTestThing *thing = [[OOTestThing alloc] initWithName:"a"];
	OO_CHECK_EQ([thing retainCount], 1u);
	OO_CHECK([thing retain] == thing);
	OO_CHECK_EQ([thing retainCount], 2u);
	[thing release];
	OO_CHECK_EQ([thing retainCount], 1u);
	OO_CHECK(gLog.empty());
	[thing release];
	OO_CHECK_EQ(gLog.size(), 1u);
	OO_CHECK(!gLog.empty() && gLog.back() == "a");

	OOObject *plain = [OOObject new];
	OO_CHECK_EQ([plain retainCount], 1u);
	[plain release];
}

OO_TEST(runtimeRetainAgreesWithMessages)
{
	gLog.clear();
	OOTestThing *thing = [[OOTestThing alloc] initWithName:"b"];
	objc_retain(thing);
	OO_CHECK_EQ(object_getRetainCount_np(thing), 2u);
	[thing release];
	OO_CHECK_EQ([thing retainCount], 1u);
	objc_release(thing);
	OO_CHECK_EQ(gLog.size(), 1u);
}

OO_TEST(cxxIvarsAreConstructedAndDestroyed)
{
	gLog.clear();
	const int before = gCxxLive;
	OOTestThing *thing = [[OOTestThing alloc] initWithName:"c"];
	OO_CHECK_EQ(gCxxLive, before + 1);
	OO_CHECK(thing->name == "c");
	thing->payload = oo::makeRef<Payload>();
	[thing release];
	OO_CHECK_EQ(gCxxLive, before);
	// -dealloc logs the name, then .cxx_destruct releases the Ref and the Payload dies.
	OO_CHECK_EQ(gLog.size(), 2u);
	OO_CHECK(gLog.size() == 2 && gLog[0] == "c" && gLog[1] == "payload");
}

OO_TEST(autoreleasePoolDrainsOnExit)
{
	gLog.clear();
	@autoreleasepool
	{
		[[[OOTestThing alloc] initWithName:"p1"] autorelease];
		@autoreleasepool
		{
			[[[OOTestThing alloc] initWithName:"inner"] autorelease];
		}
		OO_CHECK_EQ(gLog.size(), 1u);
		OO_CHECK(!gLog.empty() && gLog[0] == "inner");
		[[[OOTestThing alloc] initWithName:"p2"] autorelease];
		OO_CHECK_EQ(gLog.size(), 1u);
	}
	OO_CHECK_EQ(gLog.size(), 3u);
	// libobjc2's pool releases in REVERSE order of autorelease. So does the game's pool today:
	// on this toolchain GNUstep's Foundation pool is backed by libobjc2's (measured, ADR-0029),
	// so the floor changes nothing. (oo::AutoreleaseScope drains in insertion order: ADR-0029
	// records the mismatch.) This check pins the order so a runtime change cannot slip past.
	OO_CHECK(gLog.size() == 3 && gLog[1] == "p2" && gLog[2] == "p1");

	gLog.clear();
	void *pool = objc_autoreleasePoolPush();
	OOTestThing *kept = [[[OOTestThing alloc] initWithName:"kept"] autorelease];
	[kept retain];
	objc_autorelease([[OOTestThing alloc] initWithName:"gone"]);
	objc_autoreleasePoolPop(pool);
	OO_CHECK_EQ(gLog.size(), 1u);
	OO_CHECK(!gLog.empty() && gLog[0] == "gone");
	OO_CHECK_EQ([kept retainCount], 1u);
	[kept release];
	OO_CHECK_EQ(gLog.size(), 2u);
}

OO_TEST(weakReferencesZero)
{
	gLog.clear();
	OOTestThing *thing = [[OOTestThing alloc] initWithName:"w"];
	id weak = nil;
	objc_storeWeak(&weak, thing);
	// objc_loadWeak() autoreleases what it returns, so read it inside a pool (or it leaks).
	@autoreleasepool
	{
		OO_CHECK(objc_loadWeak(&weak) == thing);
	}
	OO_CHECK_EQ([thing retainCount], 1u);
	id strong = objc_loadWeakRetained(&weak);
	OO_CHECK(strong == thing);
	objc_release(strong);
	OO_CHECK(gLog.empty());
	[thing release];
	OO_CHECK_EQ(gLog.size(), 1u);
	OO_CHECK(objc_loadWeakRetained(&weak) == nil);
	objc_destroyWeak(&weak);
	OO_CHECK_EQ(gLog.size(), 1u);
}

OO_TEST(overriddenRetainReleaseIsHonoured)
{
	OOTestImmortal *immortal = [[OOTestImmortal alloc] init];
	objc_retain(immortal);
	objc_release(immortal);
	objc_release(immortal);
	[immortal release];
	OO_CHECK_EQ([immortal retainCount], 1u);   // never moved: the overrides were sent
	OO_CHECK([OOTestImmortal retain] == [OOTestImmortal class]);
	[OOTestImmortal release];
	[OOTestImmortal autorelease];
}

OO_TEST(introspection)
{
	OOTestThing *thing = [[OOTestThing alloc] initWithName:"i"];
	OO_CHECK([thing class] == [OOTestThing class]);
	OO_CHECK([thing superclass] == [OOObject class]);
	OO_CHECK([OOTestThing superclass] == [OOObject class]);
	OO_CHECK([thing isKindOfClass:[OOObject class]]);
	OO_CHECK([thing isKindOfClass:[OOTestThing class]]);
	OO_CHECK(![thing isKindOfClass:[OOTestImmortal class]]);
	OO_CHECK([thing isMemberOfClass:[OOTestThing class]]);
	OO_CHECK(![thing isMemberOfClass:[OOObject class]]);
	OO_CHECK([OOTestThing isSubclassOfClass:[OOObject class]]);
	OO_CHECK(![OOObject isSubclassOfClass:[OOTestThing class]]);
	OO_CHECK([thing respondsToSelector:@selector(echo:)]);
	OO_CHECK(![thing respondsToSelector:@selector(noSuchMethod)]);
	OO_CHECK([OOTestThing instancesRespondToSelector:@selector(echo:)]);
	// gnustep-base's collections cache IMPs through these (measured: without them an OOObject
	// inside an NSMutableArray raises), so they matter while the two coexist.
	OO_CHECK([thing methodForSelector:@selector(echo:)] == [OOTestThing instanceMethodForSelector:@selector(echo:)]);
	OO_CHECK(reinterpret_cast<id (*)(id, SEL, id)>([thing methodForSelector:@selector(echo:)])(thing, @selector(echo:), thing) == thing);
	OO_CHECK([OOTestThing respondsToSelector:@selector(alloc)]);
	OO_CHECK([thing conformsToProtocol:@protocol(OOTestMarker)]);
	OOObject *plain = [OOObject new];
	OO_CHECK(![plain conformsToProtocol:@protocol(OOTestMarker)]);
	[plain release];
	OO_CHECK([OOTestThing conformsToProtocol:@protocol(OOCopying)]);
	OO_CHECK(![OOTestImmortal conformsToProtocol:@protocol(OOTestMarker)]);
	OO_CHECK(![thing isProxy]);
	OO_CHECK([thing self] == thing);
	OO_CHECK([thing isEqual:thing]);
	OO_CHECK(![thing isEqual:nil]);
	OO_CHECK_EQ([thing hash], [thing hash]);
	OO_CHECK([thing performSelector:@selector(self)] == thing);
	OO_CHECK([thing performSelector:@selector(echo:) withObject:thing] == thing);
	OO_CHECK([thing performSelector:@selector(pairFirst:second:) withObject:thing withObject:[OOTestThing class]] == [OOTestThing class]);
	[thing release];
}

OO_TEST(copyGoesThroughCopyWithZone)
{
	gLog.clear();
	OOTestThing *thing = [[OOTestThing alloc] initWithName:"orig"];
	OOTestThing *copy = [thing copy];
	OO_CHECK(copy != thing);
	OO_CHECK(copy->name == "orig-copy");
	OO_CHECK_EQ([copy retainCount], 1u);
	[copy release];
	[thing release];
	OO_CHECK_EQ(gLog.size(), 2u);
}

OO_TEST(allocGoesThroughAllocWithZone)
{
	// NSObject's +alloc and +new send +allocWithZone:, so an override there sees every allocation.
	id first = [OOTestSingleton alloc];
	OO_CHECK(first != nil);
	OO_CHECK(first == sTestSingleton);
	OO_CHECK([OOTestSingleton new] == nil);
	OO_CHECK_EQ(sTestSingletonAllocs, 2);
	[[first init] release];
	sTestSingleton = nil;
}


OO_TEST(zoneIsTheOneCopyPasses)
{
	// -zone is nil, the zone -copy/-mutableCopy pass, so "zone == [self zone]" (OOMesh,
	// OOProbabilitySet) still recognises a plain -copy.
	OOTestThing *thing = [[OOTestThing alloc] initWithName:"zone"];
	OO_CHECK([thing zone] == nullptr);
	[thing release];
}


OO_TEST(hashIsGNUstepNSObjects)
{
	// gnustep-base's -[NSObject hash] is the address >> 4 (measured, bead oo-3rb.42). Rerooting
	// must keep it, or hashed collections of rerooted objects iterate in a different order.
	OOTestThing *thing = [[OOTestThing alloc] initWithName:"hash"];
	const void *address = thing;
	OO_CHECK_EQ([thing hash], reinterpret_cast<uintptr_t>(address) >> 4);
	[thing release];
}


OO_TEST(longLiteralIsAConstantString)
{
	id s = @"a string literal longer than eight";
	OO_CHECK(object_getClass(s) == [OOConstantString class]);
	OO_CHECK([s isKindOfClass:[OOObject class]]);
	OO_CHECK(std::strcmp([s UTF8String], "a string literal longer than eight") == 0);
	OO_CHECK_EQ([s length], 34u);
	OO_CHECK([s isEqual:@"a string literal longer than eight"]);
	OO_CHECK(![s isEqual:@"a different literal, also long"]);
	OO_CHECK(![s isEqual:nil]);
	OO_CHECK(![s isEqual:[OOObject class]]);
}

OO_TEST(shortLiteralIsATaggedTinyString)
{
	id t = @"hi";
	const void *address = t;
	OO_CHECK_EQ(reinterpret_cast<uintptr_t>(address) & OBJC_SMALL_OBJECT_MASK, static_cast<uintptr_t>(OO_TINY_STRING_TAG));
	OO_CHECK(object_getClass(t) == [OOTinyString class]);
	OO_CHECK([t isKindOfClass:[OOConstantString class]]);
	OO_CHECK(std::strcmp([t UTF8String], "hi") == 0);
	OO_CHECK_EQ([t length], 2u);
	OO_CHECK(object_getClass(@"12345678") == [OOTinyString class]);
	OO_CHECK(object_getClass(@"123456789") == [OOConstantString class]);
	OO_CHECK(std::strcmp([@"12345678" UTF8String], "12345678") == 0);
	OO_CHECK_EQ([@"12345678" length], 8u);
	OO_CHECK_EQ([@"" length], 0u);
	OO_CHECK(std::strcmp([@"" UTF8String], "") == 0);
	OO_CHECK([t isEqual:@"hi"]);
	OO_CHECK(![t isEqual:@"ho"]);
}

OO_TEST(nonASCIILiteralIsUTF16)
{
	OOConstantString *u = @"café \U0001F680 non-ASCII";
	OO_CHECK(object_getClass(u) == [OOConstantString class]);
	OO_CHECK_EQ(u->flags, 2u);
	OO_CHECK_EQ([u length], 17u);   // UTF-16 code units: the rocket is a surrogate pair
	OO_CHECK(std::strcmp([u UTF8String], "caf\xC3\xA9 \xF0\x9F\x9A\x80 non-ASCII") == 0);
	OO_CHECK([u UTF8String] == [u UTF8String]);   // interned, stable
	OO_CHECK_EQ(@"é"->flags, 2u);
	OO_CHECK(std::strcmp([@"é" UTF8String], "\xC3\xA9") == 0);
}

OO_TEST(equalLiteralsHashEqually)
{
	OO_CHECK_EQ([@"hi" hash], [@"hi" hash]);
	OO_CHECK_EQ([@"a string literal longer than eight" hash], [@"a string literal longer than eight" hash]);
	OO_CHECK([@"hi" hash] != [@"ho" hash]);
}

OO_TEST(literalsAreImmortal)
{
	id s = @"a string literal longer than eight";
	id t = @"tiny";
	OO_CHECK(objc_retain(s) == s);
	OO_CHECK(objc_retain(t) == t);
	objc_release(s);
	objc_release(t);
	objc_release(s);
	[s release];
	[t release];
	OO_CHECK([s retain] == s);
	OO_CHECK([s copy] == s);
	OO_CHECK([t copy] == t);
	@autoreleasepool
	{
		[s autorelease];
		objc_autorelease(t);
	}
	OO_CHECK(std::strcmp([s UTF8String], "a string literal longer than eight") == 0);
	OO_CHECK(std::strcmp([t UTF8String], "tiny") == 0);
}

OO_TEST(forwardingAndUnrecognizedSelectors)
{
	OOTestThing *target = [[OOTestThing alloc] initWithName:"target"];
	OOTestForwarder *forwarder = [[OOTestForwarder alloc] init];
	forwarder->target = target;
	OO_CHECK([(OOTestThing *)forwarder echo:target] == target);   // redirected to target
	OO_CHECK(forwarder->lastUnrecognized == nullptr);
	OO_CHECK([(id<OOTestUnimplemented>)forwarder noSuchMethod] == nil);
	OO_CHECK(forwarder->lastUnrecognized != nullptr && sel_isEqual(forwarder->lastUnrecognized, @selector(noSuchMethod)));
	[forwarder release];
	[target release];
}

OO_TEST(objcExceptionsWithoutFoundation)
{
	gLog.clear();
	int caught = 0;
	@try
	{
		OOTestError *error = [[OOTestError alloc] init];
		error->code = 42;
		@throw error;
	}
	@catch (OOTestOtherError *other)
	{
		caught = -1;
	}
	@catch (OOTestError *error)
	{
		caught = error->code;
		[error release];
	}
	@finally
	{
		gLog.push_back("finally");
	}
	OO_CHECK_EQ(caught, 42);
	OO_CHECK_EQ(gLog.size(), 1u);

	bool caughtId = false;
	@try
	{
		@throw [[OOTestOtherError alloc] init];
	}
	@catch (id any)
	{
		caughtId = [any isKindOfClass:[OOTestOtherError class]];
		[any release];
	}
	OO_CHECK(caughtId);

	// A C++ exception unwinds through Objective-C frames and @finally, and is caught by C++.
	gLog.clear();
	bool caughtCxx = false;
	try
	{
		@try
		{
			throw std::runtime_error("cxx");
		}
		@finally
		{
			gLog.push_back("objc finally");
		}
	}
	catch (const std::runtime_error &e)
	{
		caughtCxx = std::strcmp(e.what(), "cxx") == 0;
	}
	OO_CHECK(caughtCxx);
	OO_CHECK_EQ(gLog.size(), 1u);
}

OO_TEST_MAIN()
