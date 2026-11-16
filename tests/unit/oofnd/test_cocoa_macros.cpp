/*	test_cocoa_macros.cpp
	Regression test for bead oo-i9q: the oofnd headers Objective-C++ game code includes must
	compile after Oolite's OOCocoa.h, which does `#define true 1` / `#define false 0`, and must
	hand those macros back unchanged (game code keeps its int-typed true/false; proposed ADR-0028).
	Here the macros are defined exactly as OOCocoa.h defines them, BEFORE any standard header, so
	every standard header the oofnd headers pull in is first parsed inside their macro guard.
*/

#define true						1
#define false						0

#include "oofnd/ResourcePaths.hpp"   // and so FileSystem.hpp, Data.hpp, Expected.hpp

#include <type_traits>

// The macros are back, as the game expects them after the include.
static_assert(std::is_same_v<decltype(true), int>, "oofnd must restore OOCocoa.h's true macro");
static_assert(std::is_same_v<decltype(false), int>, "oofnd must restore OOCocoa.h's false macro");
static constexpr int kTrueAfter = true;
static constexpr int kFalseAfter = false;

#undef true
#undef false

#include "oo_test.hpp"

OO_TEST(macrosAreRestoredWithTheirValues)
{
	OO_CHECK_EQ(kTrueAfter, 1);
	OO_CHECK_EQ(kFalseAfter, 0);
}

OO_TEST(headersIncludedUnderTheMacrosWork)
{
	const oo::Data d = oo::Data::fromString("ok");
	OO_CHECK_EQ(d.length(), 2u);
	OO_CHECK_EQ(oo::fs::utf8String(oo::fs::pathFromUTF8("a/b")), std::string("a/b"));
	oo::PathEnvironment env;
	env.platform = oo::PathEnvironment::Platform::posix;
	env.getenv = [](const std::string&) -> std::optional<std::string> { return std::string("/home/x"); };
	OO_CHECK_EQ(oo::fs::utf8String(oo::ResourcePaths(env).homeDirectory()), std::string("/home/x"));
}

OO_TEST_MAIN()
