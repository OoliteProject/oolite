/*	test_defaults_bridge.mm
	Unit test for Core/NSUserDefaults+OODefaultsBridge (bead oo-mwo0, ADR-0032 point 5 as
	amended): the game's +[NSUserDefaults standardUserDefaults] and oo::Defaults are ONE store.
	A value set through either is read back through the other, a removal through either is seen
	by both, registered defaults are shared, and -synchronize writes the domain file once, through
	oo::Defaults, with every change made through both APIs.

	Linked like the game (gnustep-base, the gnustep-2.2 runtime) with the bridge compiled in.
	The bridge is pointed at a scratch oo::Defaults (OODefaultsBridgeSetStore), so the test never
	touches a real preferences file.
*/

#import "NSUserDefaults+OODefaultsBridge.h"
#import "OOFoundationBridge.h"
#include "oofnd/Defaults.hpp"

#import <objc/runtime.h>

#include "oo_test.hpp"

#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace {

// The deferred-call queue (ADR-0040's OOScheduleDeferredCall lives in GameController.mm, which
// this test does not link): calls are recorded, and a test runs them as the frame loop would once
// their delay has passed.
struct DeferredCall
{
	id				target;
	SEL				selector;
	id				argument;
	NSTimeInterval	delay;
};
std::vector<DeferredCall> &deferredCalls()
{
	static std::vector<DeferredCall> calls;
	return calls;
}

namespace fs = oo::fs;
using oo::PList;

fs::Path scratchDirectory()
{
	std::error_code ec;
	fs::Path dir = std::filesystem::temp_directory_path(ec) / "oolite-test-defaults-bridge";
	std::filesystem::remove_all(dir, ec);
	return dir;
}

std::optional<std::string> contents(const fs::Path &file)
{
	fs::Result<oo::Data> d = fs::readFile(file);
	if (!d)  return std::nullopt;
	return d->toString();
}

// One store for the whole run: the bridge's target, set before the first +standardUserDefaults.
oo::Defaults &store()
{
	static oo::Defaults *s = new oo::Defaults(scratchDirectory(), "bridge-test");
	return *s;
}

NSUserDefaults *userDefaults()
{
	OODefaultsBridgeSetStore(&store());
	return [NSUserDefaults standardUserDefaults];
}

} // namespace


void OOScheduleDeferredCall(id target, SEL selector, id argument, NSTimeInterval delay)
{
	deferredCalls().push_back(DeferredCall{ target, selector, argument, delay });
}


OO_TEST(standardUserDefaultsIsBridged)
{
	@autoreleasepool
	{
		NSUserDefaults *ud = userDefaults();
		OO_CHECK(ud != nil);
		OO_CHECK(OODefaultsBridgeIsInstalled());
		OO_CHECK(std::string(class_getName(object_getClass(ud))) == "OODefaultsBackedUserDefaults");
		OO_CHECK([ud isKindOfClass:[NSUserDefaults class]]);
		OO_CHECK(ud == [NSUserDefaults standardUserDefaults]);	// still the one object
	}
}


OO_TEST(setThroughNSUserDefaultsReadsThroughDefaults)
{
	@autoreleasepool
	{
		NSUserDefaults *ud = userDefaults();
		[ud setObject:@"a string" forKey:@"ns-string"];
		[ud setBool:YES forKey:@"ns-bool"];
		[ud setInteger:123456789012LL forKey:@"ns-integer"];
		[ud setFloat:0.1f forKey:@"ns-float"];
		[ud setDouble:2.5 forKey:@"ns-double"];
		[ud setObject:[NSArray arrayWithObjects:@"x", @"y", nil] forKey:@"ns-array"];
		[ud setObject:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:7] forKey:@"k"] forKey:@"ns-dict"];

		oo::Defaults &d = store();
		OO_CHECK(d.stringForKey("ns-string") == std::optional<std::string>("a string"));
		OO_CHECK(d.boolForKey("ns-bool"));
		OO_CHECK_EQ(d.integerForKey("ns-integer"), 123456789012LL);
		OO_CHECK_EQ(d.floatForKey("ns-float"), 0.1f);
		OO_CHECK_EQ(d.doubleForKey("ns-double"), 2.5);
		const PList array = d.arrayForKey("ns-array");
		OO_CHECK(array.isArray() && array.count() == 2 && array.at<std::string>(1) == "y");
		const PList dict = d.dictionaryForKey("ns-dict");
		OO_CHECK(dict.isDict() && dict.get<int>("k") == 7);
	}
}


OO_TEST(setThroughDefaultsReadsThroughNSUserDefaults)
{
	@autoreleasepool
	{
		NSUserDefaults *ud = userDefaults();
		oo::Defaults &d = store();
		d.setObject("oo-string", PList(std::string("from oofnd")));
		d.setBool("oo-bool", true);
		d.setInteger("oo-integer", -42);
		d.setFloat("oo-float", 1.5f);
		d.setObject("oo-array", PList(PList::Array{PList(std::string("p")), PList(std::int64_t(3))}));

		OO_CHECK([[ud stringForKey:@"oo-string"] isEqualToString:@"from oofnd"]);
		OO_CHECK([[ud objectForKey:@"oo-string"] isEqualToString:@"from oofnd"]);
		OO_CHECK([ud boolForKey:@"oo-bool"]);
		OO_CHECK_EQ([ud integerForKey:@"oo-integer"], -42);
		OO_CHECK_EQ([ud floatForKey:@"oo-float"], 1.5f);
		NSArray *array = [ud arrayForKey:@"oo-array"];
		OO_CHECK([array count] == 2 && [[array objectAtIndex:0] isEqualToString:@"p"] && [[array objectAtIndex:1] intValue] == 3);
		OO_CHECK([ud objectForKey:@"never-set-anywhere"] == nil);
		OO_CHECK(![ud boolForKey:@"never-set-anywhere"]);
	}
}


OO_TEST(removalThroughEitherIsSeenByBoth)
{
	@autoreleasepool
	{
		NSUserDefaults *ud = userDefaults();
		oo::Defaults &d = store();
		[ud setObject:@"gone soon" forKey:@"remove-a"];
		d.removeObject("remove-a");
		OO_CHECK([ud objectForKey:@"remove-a"] == nil);

		d.setObject("remove-b", PList(std::string("gone soon")));
		[ud removeObjectForKey:@"remove-b"];
		OO_CHECK(d.object("remove-b").isNull());

		d.setObject("remove-c", PList(std::string("gone soon")));
		[ud setObject:nil forKey:@"remove-c"];	// nil removes, as in GNUstep
		OO_CHECK(d.object("remove-c").isNull());
	}
}


OO_TEST(registeredDefaultsAreShared)
{
	@autoreleasepool
	{
		NSUserDefaults *ud = userDefaults();
		[ud registerDefaults:[NSDictionary dictionaryWithObject:@"registered" forKey:@"reg-key"]];
		OO_CHECK(store().stringForKey("reg-key") == std::optional<std::string>("registered"));
		OO_CHECK([[ud stringForKey:@"reg-key"] isEqualToString:@"registered"]);
	}
}


OO_TEST(synchronizeWritesOnceThroughDefaults)
{
	@autoreleasepool
	{
		NSUserDefaults *ud = userDefaults();
		oo::Defaults &d = store();
		const fs::Path file = d.domainPath(d.domainName());

		[ud setObject:@"one" forKey:@"sync-ns"];
		d.setObject("sync-oo", PList(std::string("two")));
		OO_CHECK(!contents(file).has_value());			// nothing is written before synchronize
		OO_CHECK([ud synchronize]);

		// One file, holding the changes made through BOTH APIs, as oo::Defaults writes it.
		const std::optional<std::string> written = contents(file);
		OO_CHECK(written.has_value());
		OO_CHECK(written.has_value() && written->find("\"sync-ns\" = one;") != std::string::npos);
		OO_CHECK(written.has_value() && written->find("\"sync-oo\" = two;") != std::string::npos);
		OO_CHECK(written.has_value() && written->find("\"ns-float\" = \"0.1\";") != std::string::npos);	// %.7g, as set with -setFloat: (a double would be 0.1000000014901161)

		// Nothing left to write: a second synchronize through either API writes nothing (the file,
		// deleted behind their backs, is not recreated).
		OO_CHECK(fs::removeItem(file));
		OO_CHECK([ud synchronize]);
		OO_CHECK(d.synchronize());
		OO_CHECK(!contents(file).has_value());
	}
}


// gnustep-base's automatic save (bead oo-xeve): the first change after a save schedules one
// -synchronize 30 s later (gnustep-base 1.31.1's timer interval, probed); later changes add none;
// running it writes the pending changes once and lets the next change schedule again.
OO_TEST(firstChangeSchedulesOneDeferredSave)
{
	@autoreleasepool
	{
		NSUserDefaults *ud = userDefaults();
		oo::Defaults &d = store();
		const fs::Path file = d.domainPath(d.domainName());
		
		// The earlier tests' first change scheduled it; none of their later changes added another.
		OO_CHECK_EQ(deferredCalls().size(), 1u);
		OO_CHECK(deferredCalls().size() == 1 && deferredCalls()[0].delay == 30.0);
		OO_CHECK(deferredCalls().size() == 1 && deferredCalls()[0].target == ud);
		
		[ud setObject:@"saved later" forKey:@"deferred-key"];
		OO_CHECK_EQ(deferredCalls().size(), 1u);
		(void)fs::removeItem(file);
		OO_CHECK(!contents(file).has_value());
		
		// The interval passes: the frame loop runs the call.
		const DeferredCall call = deferredCalls()[0];
		deferredCalls().clear();
		[call.target performSelector:call.selector withObject:call.argument];
		const std::optional<std::string> written = contents(file);
		OO_CHECK(written.has_value() && written->find("\"deferred-key\" = \"saved later\";") != std::string::npos);
		OO_CHECK(deferredCalls().empty());
		
		// Written once: nothing is pending, so a synchronize writes nothing more.
		OO_CHECK(fs::removeItem(file));
		OO_CHECK([ud synchronize]);
		OO_CHECK(!contents(file).has_value());
		
		// The next change schedules the next save.
		[ud setBool:YES forKey:@"deferred-key-2"];
		OO_CHECK_EQ(deferredCalls().size(), 1u);
		OO_CHECK(deferredCalls().size() == 1 && deferredCalls()[0].delay == 30.0);
	}
}


OO_TEST_MAIN()
