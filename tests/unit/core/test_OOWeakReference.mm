/*	test_OOWeakReference.mm
	Unit tests for cxx::OOWeakReference (src/Core/OOWeakReference.h) and its Objective-C facade
	(OOWeakReference+ObjCBridge.h): bead oo-3kqi, a Phase 3 conversion in the OOColor house style
	(proposed ADR-0056, amendment oo-3kqi: the facade is the reference).

	Pins what a weak reference did before the conversion, through the Objective-C API its
	callers use: -weakRetain gives one reference per live object; the reference forwards every
	message to the object while it lives (a method of the object's own class, -class,
	-isKindOfClass:, -respondsToSelector:, the description family) and answers like nil once the
	object has gone; -hash is the reference's address shifted right by 3; the object is told when
	its reference dies (-weakRefDied:) and then makes a new one; and a class that implements
	OOWeakReferenceSupport itself is told the same. Those checks go through the facade, which is
	what every caller holds; they were run first on the Objective-C class. After the conversion:
	the C++ object answers what its facade answers, and identity: one facade per reference, which
	made its C++ object and is the only one it ever has (ToObjC never makes a new one), and the
	reference dies, for the object, when its facade does.
	Run: bash tools/check-core-tests.sh
*/

#import "OOWeakReference.h"
#import "OODescription.h"

#include "oo_test.hpp"


@interface TestThing: OOWeakRefObject
- (int) frob;
@end


@implementation TestThing

- (int) frob
{
	return 42;
}


- (std::optional<std::string>) cxx_descriptionComponents
{
	return std::string("thing");
}


- (std::optional<std::string>) cxx_shortDescriptionComponents
{
	return std::string("short thing");
}

@end


// Implements the protocol itself, as OOJSScript does.
@interface TestSupporter: OOObject <OOWeakReferenceSupport>
{
@public
	OOWeakReference	*weakSelf;
	id				diedWith;
	int				deaths;
}
@end


@implementation TestSupporter

- (id) weakRetain
{
	if (weakSelf == nil)  weakSelf = [OOWeakReference weakRefWithObject:self];
	return [weakSelf retain];
}


- (void) weakRefDied:(OOWeakReference *)weakRef
{
	diedWith = weakRef;
	deaths++;
	if (weakRef == weakSelf)  weakSelf = nil;
}


- (void) dealloc
{
	[weakSelf weakRefDrop];
	[super dealloc];
}

@end


// Forwarding goes through the floor's hook, which the game's start-up installs (or gnustep-base's
// while it is linked); the tests install the floor's, as the oofnd objc tests do.
OO_TEST(installTheFloor)
{
	OOObjCInstallFloor();
	OO_CHECK(true);
}


OO_TEST(nilGivesNil)
{
	OO_CHECK([OOWeakReference weakRefWithObject:nil] == nil);
	id none = nil;
	OO_CHECK([none weakRefUnderlyingObject] == nil);
}


OO_TEST(oneReferencePerLiveObject)
{
	TestThing *thing = [[TestThing alloc] init];
	@autoreleasepool
	{
		OOWeakReference *ref = [thing weakRetain];
		OO_CHECK(ref != nil);
		OO_CHECK(ref != (id)thing);
		OOWeakReference *again = [thing weakRetain];
		OO_CHECK(again == ref);
		OO_CHECK([thing weakSelf] == ref);
		OO_CHECK([ref weakRefUnderlyingObject] == thing);
		OO_CHECK([thing weakRefUnderlyingObject] == thing);	// OOObject's: itself
		OO_CHECK([ref weakRetain] == ref);	// a reference's -weakRetain is -retain
		[ref release];
		[again release];
		[ref release];
	}
	[thing release];
}


OO_TEST(forwardsWhileTheObjectLives)
{
	TestThing *thing = [[TestThing alloc] init];
	@autoreleasepool
	{
		id ref = [thing weakSelf];
		OO_CHECK([ref frob] == 42);
		OO_CHECK([ref class] == [TestThing class]);
		OO_CHECK([ref isKindOfClass:[TestThing class]]);
		OO_CHECK([ref isKindOfClass:[OOWeakRefObject class]]);
		OO_CHECK([ref isMemberOfClass:[TestThing class]]);
		OO_CHECK(![ref isMemberOfClass:[OOWeakReference class]]);
		OO_CHECK([ref isProxy]);
		OO_CHECK([ref respondsToSelector:@selector(frob)]);
		OO_CHECK(![ref respondsToSelector:@selector(noSuchMethod)]);
		OO_CHECK([ref respondsToSelector:@selector(weakRefDrop)]);	// its own
		OO_CHECK([ref respondsToSelector:@selector(weakRefUnderlyingObject)]);
		OO_CHECK([ref conformsToProtocol:@protocol(OOWeakReferenceSupport)]);
		OO_CHECK_EQ(oo::DescriptionOf(ref), oo::DescriptionOf(thing));
		OO_CHECK([ref cxx_descriptionComponents] == std::optional<std::string>("thing"));
		OO_CHECK([ref cxx_shortDescriptionComponents] == std::optional<std::string>("short thing"));
		OO_CHECK([ref cxx_shortDescription] == [thing cxx_shortDescription]);
		OO_CHECK_EQ([ref hash], reinterpret_cast<uintptr_t>(ref) >> 3);
	}
	[thing release];
}


OO_TEST(answersLikeNilOnceTheObjectHasGone)
{
	TestThing *thing = [[TestThing alloc] init];
	id ref = [thing weakRetain];
	uintptr_t hash = [ref hash];
	[thing release];	// the object drops its reference

	OO_CHECK([ref weakRefUnderlyingObject] == nil);
	OO_CHECK([ref frob] == 0);
	OO_CHECK([ref class] == Nil);
	OO_CHECK(![ref isKindOfClass:[TestThing class]]);
	OO_CHECK([ref respondsToSelector:@selector(frob)]);	// "responds to everything", as nil did
	OO_CHECK([ref respondsToSelector:@selector(noSuchMethod)]);
	OO_CHECK(![ref cxx_descriptionComponents].has_value());
	const std::string description = oo::DescriptionOf(ref);
	OO_CHECK(description.rfind("<Dead (null) 0x", 0) == 0 && description.back() == '>');
	OO_CHECK_EQ([ref hash], hash);
	[ref release];
}


OO_TEST(theObjectMakesANewReferenceWhenItsOldOneDies)
{
	TestThing *thing = [[TestThing alloc] init];
	id first = nil;
	@autoreleasepool
	{
		first = [thing weakRetain];
	}
	OO_CHECK([first weakRefUnderlyingObject] == thing);
	OO_CHECK_EQ([first retainCount], 1u);
	[first release];	// its last holder: the reference dies, and the object forgets it

	id second = nil;
	@autoreleasepool
	{
		second = [thing weakRetain];
	}
	OO_CHECK(second != nil);
	OO_CHECK([second weakRefUnderlyingObject] == thing);
	OO_CHECK([second frob] == 42);
	[thing release];
	OO_CHECK([second weakRefUnderlyingObject] == nil);
	[second release];
}


OO_TEST(anImplementerIsToldItsReferenceDied)
{
	TestSupporter *supporter = [[TestSupporter alloc] init];
	OOWeakReference *ref = nil;
	@autoreleasepool
	{
		ref = [supporter weakRetain];	// +weakRefWithObject: autoreleased it; this holds the one retain
	}
	OO_CHECK(ref == supporter->weakSelf);
	OO_CHECK([ref weakRefUnderlyingObject] == supporter);
	OO_CHECK(supporter->deaths == 0);
	[ref release];
	OO_CHECK(supporter->deaths == 1);
	OO_CHECK(supporter->diedWith == ref);	// told with the reference itself
	OO_CHECK(supporter->weakSelf == nil);

	// A reference that outlives its object tells nobody when it dies.
	ref = [supporter weakRetain];
	[supporter release];
	OO_CHECK([ref weakRefUnderlyingObject] == nil);
	[ref release];
}


OO_TEST(theCxxObjectAnswersWhatItsFacadeAnswers)
{
	TestThing *thing = [[TestThing alloc] init];
	@autoreleasepool
	{
		OOWeakReference *ref = [thing weakSelf];
		cxx::OOWeakReference *cxxRef = oo::ToCxx(ref);
		OO_CHECK(cxxRef != nullptr);
		OO_CHECK(cxxRef->weakRefUnderlyingObject() == thing);
		OO_CHECK(cxxRef->class_() == [TestThing class]);
		OO_CHECK(cxxRef->isProxy());
		OO_CHECK(cxxRef->isKindOfClass([TestThing class]));
		OO_CHECK(cxxRef->respondsToSelector(@selector(frob)));
		OO_CHECK(cxxRef->respondsToSelector(@selector(weakRefDrop)));
		OO_CHECK(!cxxRef->respondsToSelector(@selector(noSuchMethod)));
		OO_CHECK(cxxRef->forwardingTargetForSelector(@selector(frob)) == thing);
		OO_CHECK_EQ(cxxRef->hash(), [ref hash]);
		OO_CHECK(cxxRef->description() == [ref cxx_description]);
		OO_CHECK(cxxRef->descriptionComponents() == std::optional<std::string>("thing"));
		id retained = cxxRef->weakRetain();
		OO_CHECK(retained == ref);
		[retained release];
	}
	[thing release];
}


OO_TEST(oneFacadeWhichIsTheReference)
{
	OOWeakReference *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOWeakReference *>(nullptr)) == nil);

	TestSupporter *supporter = [[TestSupporter alloc] init];
	OOWeakReference *ref = nil;
	@autoreleasepool
	{
		ref = [supporter weakRetain];
		OO_CHECK(oo::ToObjC(oo::ToCxx(ref)) == ref);
	}

	// Keep the C++ object alone past its facade: the reference has died for the object, and it
	// never gets a second facade.
	oo::Ref<cxx::OOWeakReference> cxxRef(oo::ToCxx(ref));
	[ref release];
	OO_CHECK(supporter->deaths == 1);
	OO_CHECK(supporter->weakSelf == nil);
	@autoreleasepool
	{
		OO_CHECK(oo::ToObjC(cxxRef) == nil);
	}
	OO_CHECK(cxxRef->weakRefUnderlyingObject() == supporter);	// not dropped: only the facade's death is seen
	cxxRef = nullptr;
	[supporter release];
}


OO_TEST(allocInitIsADeadReference)
{
	OOWeakReference *ref = [[OOWeakReference alloc] init];
	OO_CHECK(ref != nil);
	OO_CHECK([ref weakRefUnderlyingObject] == nil);
	OO_CHECK([(id)ref frob] == 0);
	[ref release];
}


OO_TEST_MAIN()
