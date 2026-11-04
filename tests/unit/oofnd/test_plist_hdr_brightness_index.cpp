/*	test_plist_hdr_brightness_index.cpp
        Pins today's (upstream's) behaviour for an HDR max
   brightness that is not in descriptions.plist's hdr_maxBrightness_array.
   Decision: keep upstream behaviour (Jon may overrule).

        The two game sites are PlayerEntity.mm (the game-options screen's
   HDRMAXBRIGHTNESS row) and PlayerEntityControls.mm (the left/right arrow on
   that row). Both run only when OOLITE_WINDOWS and the game view's hdrOutput()
   is true, from a full PlayerEntity with a Universe, a GUI and key state; no
   core test has a stand-in for that, and one would be far beyond this test's
   size. So this test pins the behaviour at helper level instead: each site's
   index arithmetic is copied below verbatim (minus the log and the GUI calls)
   and run on the oofnd pieces it depends on, the int narrowing of NSNotFound
   and oo::PList::at<int> out of range.

        What it pins, for an unmatched brightness:
          * static_cast<int>(NSNotFound) is -1 and widening it back never equals
   NSNotFound, so the "not found -> index 0" fallback never runs (as in
   upstream's Objective-C);
          * options screen: at<int>(static_cast<std::size_t>(-1)) is out of
   range and answers the fallback 0 (upstream: -oo_intAtIndex: answered 0) - the
   row shows the 0-nit label;
          * arrow keys: -1 + 1 = 0 (the first entry, 400) and -1 - 1 = -2,
   wrapped to count - 1 (the last entry, 1000); both in range. meson test
   --suite oofnd-plist
*/

#include <cstddef>
#include <cstdint>
#include <string>

#include "oo_test.hpp"
#include "oofnd/PListGet.hpp"
#include "oofnd/PListOldStyle.hpp"
#include "oofnd/objc/OOFoundationTypes.h"

namespace {

// descriptions.plist, hdr_maxBrightness_array, as shipped. Unquoted old-style
// tokens are strings.
oo::PList shippedBrightnesses() {
  auto parsed = oo::parseOldStylePList("( 400, 500, 600, 800, 1000 )");
  return parsed.has_value() ? *parsed : oo::PList();
}

// PlayerEntity.mm, the options screen row: the index lookup and the value read.
int optionsScreenBrightnessValue(const oo::PList& brightnesses,
                                 int currentMaxBrightness, bool* fallbackRan) {
  const std::string currentBrightness = std::to_string(currentMaxBrightness);
  int brightnessIdx = static_cast<int>(NSNotFound);
  for (std::size_t i = 0; i < brightnesses.count(); i++) {
    const oo::PList* element = brightnesses.at(i);
    if (element->isString() &&
        *element->getIf<std::string>() == currentBrightness) {
      brightnessIdx = static_cast<int>(i);
      break;
    }
  }

  *fallbackRan = false;
  if (static_cast<NSInteger>(brightnessIdx) == NSNotFound) {
    *fallbackRan = true;
    brightnessIdx = 0;
  }

  return brightnesses.at<int>(static_cast<std::size_t>(brightnessIdx));
}

// PlayerEntityControls.mm, the arrow keys on that row: the new index and the
// value it selects.
int controlsBrightnessValue(const oo::PList& brightnesses,
                            int currentMaxBrightness, int direction,
                            bool* fallbackRan) {
  const std::string currentBrightness = std::to_string(currentMaxBrightness);
  int brightnessIdx = static_cast<int>(NSNotFound);
  for (std::size_t i = 0; i < brightnesses.count(); i++) {
    const oo::PList* element = brightnesses.at(i);
    if (element->isString() &&
        *element->getIf<std::string>() == currentBrightness) {
      brightnessIdx = static_cast<int>(i);
      break;
    }
  }

  *fallbackRan = false;
  if (static_cast<NSInteger>(brightnessIdx) == NSNotFound) {
    *fallbackRan = true;
    brightnessIdx = 0;
  }

  brightnessIdx += direction;
  int count = static_cast<int>(brightnesses.count());
  if (brightnessIdx < 0) brightnessIdx = count - 1;
  if (brightnessIdx >= count) brightnessIdx = 0;

  return brightnesses.at<int>(static_cast<std::size_t>(brightnessIdx));
}

void notFoundNarrowsToMinusOneAndNeverComparesEqual() {
  const int narrowed = static_cast<int>(NSNotFound);
  OO_CHECK_EQ(narrowed, -1);
  OO_CHECK(static_cast<NSInteger>(narrowed) != NSNotFound);
  OO_CHECK_EQ(static_cast<std::size_t>(narrowed), SIZE_MAX);
}

void atIntOutOfRangeAnswersTheFallback() {
  const oo::PList brightnesses = shippedBrightnesses();
  OO_CHECK(brightnesses.isArray());
  OO_CHECK_EQ(brightnesses.count(), std::size_t{5});
  OO_CHECK(brightnesses.at(SIZE_MAX) == nullptr);
  OO_CHECK_EQ(brightnesses.at<int>(SIZE_MAX), 0);
  OO_CHECK_EQ(brightnesses.at<int>(brightnesses.count()), 0);
  OO_CHECK_EQ(brightnesses.at<int>(SIZE_MAX, 77), 77);
  OO_CHECK_EQ(brightnesses.at<int>(0), 400);
  OO_CHECK_EQ(brightnesses.at<int>(4), 1000);
}

void optionsScreenMatchedBrightnessShowsItsOwnValue() {
  const oo::PList brightnesses = shippedBrightnesses();
  bool fallbackRan = true;
  OO_CHECK_EQ(optionsScreenBrightnessValue(brightnesses, 600, &fallbackRan),
              600);
  OO_CHECK(!fallbackRan);
}

void optionsScreenUnmatchedBrightnessReadsSizeMaxAndShowsZero() {
  const oo::PList brightnesses = shippedBrightnesses();
  bool fallbackRan = true;
  OO_CHECK_EQ(optionsScreenBrightnessValue(brightnesses, 750, &fallbackRan), 0);
  OO_CHECK(
      !fallbackRan);  // upstream behaviour: the 400-nit fallback never runs
}

void optionsScreenMissingArrayShowsZero() {
  bool fallbackRan = true;
  OO_CHECK_EQ(optionsScreenBrightnessValue(oo::PList(), 750, &fallbackRan), 0);
  OO_CHECK(!fallbackRan);
}

void controlsMatchedBrightnessStepsAndWraps() {
  const oo::PList brightnesses = shippedBrightnesses();
  bool fallbackRan = true;
  OO_CHECK_EQ(controlsBrightnessValue(brightnesses, 600, 1, &fallbackRan), 800);
  OO_CHECK(!fallbackRan);
  OO_CHECK_EQ(controlsBrightnessValue(brightnesses, 600, -1, &fallbackRan),
              500);
  OO_CHECK_EQ(controlsBrightnessValue(brightnesses, 1000, 1, &fallbackRan),
              400);
  OO_CHECK_EQ(controlsBrightnessValue(brightnesses, 400, -1, &fallbackRan),
              1000);
}

void controlsUnmatchedBrightnessRightGoesToFirstLeftWrapsToLast() {
  const oo::PList brightnesses = shippedBrightnesses();
  bool fallbackRan = true;
  OO_CHECK_EQ(controlsBrightnessValue(brightnesses, 750, 1, &fallbackRan), 400);
  OO_CHECK(!fallbackRan);
  fallbackRan = true;
  OO_CHECK_EQ(controlsBrightnessValue(brightnesses, 750, -1, &fallbackRan),
              1000);
  OO_CHECK(!fallbackRan);
}

}  // namespace

// Registered here rather than with OO_TEST: the macro's static registrars and
// static functions are clang-tidy findings
// (bugprone-throwing-static-initialization, misc-use-anonymous-namespace) in a
// new file under tools/tier-a.sh. Same registry, same runner, same summary
// line.
int main() {
  ::oo_test::registry().push_back(
      ::oo_test::Case{"notFoundNarrowsToMinusOneAndNeverComparesEqual",
                      &notFoundNarrowsToMinusOneAndNeverComparesEqual});
  ::oo_test::registry().push_back(::oo_test::Case{
      "atIntOutOfRangeAnswersTheFallback", &atIntOutOfRangeAnswersTheFallback});
  ::oo_test::registry().push_back(
      ::oo_test::Case{"optionsScreenMatchedBrightnessShowsItsOwnValue",
                      &optionsScreenMatchedBrightnessShowsItsOwnValue});
  ::oo_test::registry().push_back(::oo_test::Case{
      "optionsScreenUnmatchedBrightnessReadsSizeMaxAndShowsZero",
      &optionsScreenUnmatchedBrightnessReadsSizeMaxAndShowsZero});
  ::oo_test::registry().push_back(
      ::oo_test::Case{"optionsScreenMissingArrayShowsZero",
                      &optionsScreenMissingArrayShowsZero});
  ::oo_test::registry().push_back(
      ::oo_test::Case{"controlsMatchedBrightnessStepsAndWraps",
                      &controlsMatchedBrightnessStepsAndWraps});
  ::oo_test::registry().push_back(::oo_test::Case{
      "controlsUnmatchedBrightnessRightGoesToFirstLeftWrapsToLast",
      &controlsUnmatchedBrightnessRightGoesToFirstLeftWrapsToLast});
  return ::oo_test::runAll(__FILE__);
}
