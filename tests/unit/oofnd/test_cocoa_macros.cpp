/*	test_cocoa_macros.cpp
        Regression test: the oofnd headers must compile
   when `true` and `false` are macros, `#define true
   1` / `#define false 0` (as a Cocoa-compatibility header such as OOCocoa.h defines them),
   and must hand those macros back unchanged (code
   keeps its int-typed true/false). Here the macros are
   defined that way, BEFORE any standard header, so
        every standard header the oofnd headers pull in is first parsed inside
   their macro guard.
*/


#include "oofnd/ResourcePaths.hpp"  // and so FileSystem.hpp, Data.hpp, Expected.hpp



#include "oo_test.hpp"

OO_TEST(headersIncludedUnderTheMacrosWork) {
  const oo::Data d = oo::Data::fromString("ok");
  OO_CHECK_EQ(d.length(), 2u);
  OO_CHECK_EQ(oo::fs::utf8String(oo::fs::pathFromUTF8("a/b")),
              std::string("a/b"));
  oo::PathEnvironment env;
  env.platform = oo::PathEnvironment::Platform::kPosix;
  env.getenv = [](const std::string&) -> std::optional<std::string> {
    return std::string("/home/x");
  };
  OO_CHECK_EQ(oo::fs::utf8String(oo::ResourcePaths(env).homeDirectory()),
              std::string("/home/x"));
}

OO_TEST_MAIN()
