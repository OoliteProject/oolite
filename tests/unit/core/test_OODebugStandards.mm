/*	test_OODebugStandards.mm
	Unit tests for the OXP standards checks (src/Core/Debug/OODebugStandards.h): bead oo-izk8,
	a Debug module file with no class, converted after the pattern seam oo-kq7 (proposed
	ADR-0056, amendments oo-kq7 and oo-ppc item 2).

	The checks read "enforce-oxp-standards" from the user's defaults (clamped to off..quit),
	log a deprecation or an error unless enforcement is off, and ask the game controller to quit
	in quit mode; OOEnforceStandards() is true from "enforce" up, and the OXP verifier mode is
	"warn" from then on, when the defaults are no longer read. The tests share that state, so they
	run in order. These expectations were written against the Objective-C file and run on it first.

	The game controller would bring the whole game into the link, so it is this file's stand-in
	(proposed ADR-0056, amendment oo-z1s4 item 4): it answers +sharedController and records the
	contexts it is asked to exit with. The defaults are set in memory (setObject; nothing is
	written without synchronize()). Run: bash tools/check-core-tests.sh test_OODebugStandards
*/

#import "OODebugStandards.h"

#include "oofnd/Defaults.hpp"
#include "oo_test.hpp"

#include <string>
#include <vector>


namespace {

std::vector<std::string> sExitContexts;

}	// namespace


@interface GameController: OOObject
+ (GameController *) sharedController;
- (void) cxx_exitAppWithContext:(const std::string &)context;
@end

@implementation GameController

+ (GameController *) sharedController
{
	static GameController *controller = nil;
	if (controller == nil)  controller = [[GameController alloc] init];
	return controller;
}


- (void) cxx_exitAppWithContext:(const std::string &)context
{
	sExitContexts.push_back(context);
}

@end


// First: an out-of-range setting (7) is clamped to quit mode, which enforces, logs and asks the
// game to exit with the message class as its context.
OO_TEST(quitModeFromAClampedSetting)
{
	oo::Defaults::standard().setObject("enforce-oxp-standards", oo::PList(7));

	OO_CHECK(OOEnforceStandards());
	OO_CHECK(sExitContexts.empty());

	cxx_OOStandardsDeprecated("a deprecated thing");
	OO_CHECK(sExitContexts.size() == 1 && sExitContexts[0] == "oxp-standards.deprecated");

	cxx_OOStandardsError("an OXP error");
	OO_CHECK(sExitContexts.size() == 2 && sExitContexts[1] == "oxp-standards.error");
}


// The setting is read on every check (OOStandardsSetup never marks it read; kept): each level in
// turn, and a negative one clamped to off.
OO_TEST(theSettingIsReadOnEveryCheck)
{
	oo::Defaults::standard().setObject("enforce-oxp-standards", oo::PList(0));
	OO_CHECK(!OOEnforceStandards());
	cxx_OOStandardsError("off: nothing happens");
	OO_CHECK(sExitContexts.size() == 2);

	oo::Defaults::standard().setObject("enforce-oxp-standards", oo::PList(-3));
	OO_CHECK(!OOEnforceStandards());

	oo::Defaults::standard().setObject("enforce-oxp-standards", oo::PList(1));
	OO_CHECK(!OOEnforceStandards());
	cxx_OOStandardsDeprecated("warn: only logged");
	OO_CHECK(sExitContexts.size() == 2);

	oo::Defaults::standard().setObject("enforce-oxp-standards", oo::PList(2));
	OO_CHECK(OOEnforceStandards());
	cxx_OOStandardsError("enforce: only logged");
	OO_CHECK(sExitContexts.size() == 2);

	oo::Defaults::standard().setObject("enforce-oxp-standards", oo::PList(3));
	OO_CHECK(OOEnforceStandards());
	cxx_OOStandardsError("quit again");
	OO_CHECK(sExitContexts.size() == 3 && sExitContexts[2] == "oxp-standards.error");
}


// The OXP verifier runs in warn mode: nothing is enforced and nothing exits.
OO_TEST(verifierModeWarns)
{
	OOSetStandardsForOXPVerifierMode();
	OO_CHECK(!OOEnforceStandards());

	const size_t before = sExitContexts.size();
	cxx_OOStandardsDeprecated("only logged");
	cxx_OOStandardsError("only logged");
	OO_CHECK(sExitContexts.size() == before);

	// The verifier mode marks the setting read: the defaults stay ignored.
	oo::Defaults::standard().setObject("enforce-oxp-standards", oo::PList(3));
	OO_CHECK(!OOEnforceStandards());
}


OO_TEST_MAIN()
