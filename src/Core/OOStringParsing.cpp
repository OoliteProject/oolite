/*

OOStringParsing.cpp

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#include "OOStringParsing.h"

#include <array>
#include <format>
#include <string_view>

#include "HeadUpDisplay.h"
#include "OOFunctionAttributes.h"
#include "OOJSEngineTimeManagement.h"
#include "OOJavaScriptEngine.h"
#include "OOLogging.h"
#include "PlayerEntity.h"
#include "PlayerEntityLegacyScriptEngine.h"
#include "ResourceManager.h"
#include "Universe.h"
#include "legacy_random.h"
#include "oofnd/Scanner.hpp"
#include "oofnd/String.hpp"

bool ScanVectorFromString(const std::optional<std::string>& xyzString,
                          Vector* outVector) {
  GLfloat xyz[] = {0.0, 0.0, 0.0};
  int i = 0;
  std::string_view error;

  assert(outVector != nullptr);
  if (!xyzString.has_value()) return false;

  oo::str::Scanner scanner(*xyzString);
  while (!scanner.isAtEnd() && i < 3 && error.empty()) {
    if (!scanner.scanFloat(&xyz[i++])) error = "could not scan a float value.";
  }

  if (error.empty() && i < 3) error = "found less than three float values.";

  if (error.empty()) {
    *outVector = make_vector(xyz[0], xyz[1], xyz[2]);
    return true;
  } else {
    OO_LOG_ERR("strings.conversion.vector", "cannot make vector from '{}': {}",
               *xyzString, error);
    return false;
  }
}

bool ScanHPVectorFromString(const std::optional<std::string>& xyzString,
                            HPVector* outVector) {
  Vector scanVector;
  assert(outVector != nullptr);
  bool result = ScanVectorFromString(xyzString, &scanVector);
  if (!result) {
    return false;
  }
  *outVector = vectorToHPVector(scanVector);
  return true;
}

bool ScanQuaternionFromString(const std::optional<std::string>& wxyzString,
                              Quaternion* outQuaternion) {
  GLfloat wxyz[] = {1.0, 0.0, 0.0, 0.0};
  int i = 0;
  std::string_view error;

  assert(outQuaternion != nullptr);
  if (!wxyzString.has_value()) return false;

  oo::str::Scanner scanner(*wxyzString);
  while (!scanner.isAtEnd() && i < 4 && error.empty()) {
    if (!scanner.scanFloat(&wxyz[i++])) error = "could not scan a float value.";
  }

  if (error.empty() && i < 4) error = "found less than four float values.";

  if (error.empty()) {
    outQuaternion->w = wxyz[0];
    outQuaternion->x = wxyz[1];
    outQuaternion->y = wxyz[2];
    outQuaternion->z = wxyz[3];
    quaternion_normalize(outQuaternion);
    return true;
  } else {
    OO_LOG_ERR("strings.conversion.quaternion",
               "cannot make quaternion from '{}': {}", *wxyzString, error);
    return false;
  }
}

bool ScanVectorAndQuaternionFromString(
    const std::optional<std::string>& xyzwxyzString, Vector* outVector,
    Quaternion* outQuaternion) {
  GLfloat xyzwxyz[] = {0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0};
  int i = 0;
  std::string_view error;

  assert(outVector != nullptr && outQuaternion != nullptr);
  if (!xyzwxyzString.has_value()) return false;

  oo::str::Scanner scanner(*xyzwxyzString);
  while (!scanner.isAtEnd() && i < 7 && error.empty()) {
    if (!scanner.scanFloat(&xyzwxyz[i++]))
      error = "Could not scan a float value.";
  }

  if (error.empty() && i < 7) error = "Found less than seven float values.";

  if (!error.empty()) {
    OO_LOG_ERR("strings.conversion.quaternion",
               "cannot make vector and quaternion from '{}': {}",
               *xyzwxyzString, error);
    return false;
  }

  outVector->x = xyzwxyz[0];
  outVector->y = xyzwxyz[1];
  outVector->z = xyzwxyz[2];
  outQuaternion->w = xyzwxyz[3];
  outQuaternion->x = xyzwxyz[4];
  outQuaternion->y = xyzwxyz[5];
  outQuaternion->z = xyzwxyz[6];

  return true;
}

Vector VectorFromString(const std::optional<std::string>& xyzString,
                        Vector defaultValue) {
  Vector result;
  if (!ScanVectorFromString(xyzString, &result)) result = defaultValue;
  return result;
}

Quaternion QuaternionFromString(const std::optional<std::string>& wxyzString,
                                Quaternion defaultValue) {
  Quaternion result;
  if (!ScanQuaternionFromString(wxyzString, &result)) result = defaultValue;
  return result;
}

std::string StringFromPoint(NSPoint point) {
  return std::format("{:f} {:f}", point.x, point.y);
}

NSPoint PointFromString(const std::string& xyString) {
  const std::vector<std::string> tokens = oo::str::tokens(xyString);
  NSPoint result = NSZeroPoint;

  if (tokens.size() == 2) {
    result.x = oo::str::doubleValue(tokens[0]);
    result.y = oo::str::doubleValue(tokens[1]);
  }
  return result;
}

Random_Seed RandomSeedFromString(
    const std::optional<std::string>& abcdefString) {
  Random_Seed result;
  int abcdef[] = {0, 0, 0, 0, 0, 0};
  int i = 0;
  std::string_view error;
  oo::str::Scanner scanner(
      abcdefString.value_or(""));  // a nil string scans as an empty one

  while (!scanner.isAtEnd() && i < 6 && error.empty()) {
    if (!scanner.scanInt(&abcdef[i++])) error = "could not scan a int value.";
  }

  if (error.empty() && i < 6) error = "found less than six int values.";

  if (error.empty()) {
    result.a = abcdef[0];
    result.b = abcdef[1];
    result.c = abcdef[2];
    result.d = abcdef[3];
    result.e = abcdef[4];
    result.f = abcdef[5];
  } else {
    OO_LOG_ERR("strings.conversion.randomSeed",
               "cannot make Random_Seed from '{}': {}",
               abcdefString.value_or("(null)"), error);
    result = kNilRandomSeed;
  }

  return result;
}

std::string StringFromRandomSeed(Random_Seed seed) {
  return std::format("{} {} {} {} {} {}", static_cast<int8_t>(seed.a),
                     static_cast<int8_t>(seed.b), static_cast<int8_t>(seed.c),
                     static_cast<int8_t>(seed.d), static_cast<int8_t>(seed.e),
                     static_cast<int8_t>(seed.f));
}

std::string OOPadStringToEms(const std::string& string, float padEms) {
  std::string result = string;
  float numEms = padEms - OOStringWidthInEm(result);
  if (numEms > 0) {
    numEms /= OOStringWidthInEm(" ");  // start with wide space
    result = std::string(static_cast<std::size_t>(numEms), ' ') + result;
  }
  // most of the way there, so switch to narrow space
  numEms = padEms - OOStringWidthInEm(result);
  if (numEms > 0) {
    numEms /= OOStringWidthInEm("\037");  // 037 is narrow space
    result = std::string(static_cast<std::size_t>(numEms), '\037') + result;
  }
  return result;
}

std::string OOStringFromDeciCredits(OOCreditsQuantity tenthsOfCredits,
                                    bool includeDecimal, bool includeSymbol) {
  JSContext* context = OOJSAcquireContext();
  JSValueConst global = OOJavaScriptEngine::sharedEngine()->globalObject();
  JSValue exception = JS_UNDEFINED;
  std::optional<std::string> result;
  bool hadException;

  /*	Because the |cr etc. formatting operators call this, and the
          implementation may use string expansion, we need to ensure recursion
          can't happen.
  */
  static bool reentrancyLock;
  if (reentrancyLock) return std::format("{:0.1f}", tenthsOfCredits * 0.1);

  reentrancyLock = true;

  hadException = JS_HasException(context);
  if (hadException) exception = JS_GetException(context);  // Clears it.

  JSValue method = JS_GetProperty(context, global, OOJSID("formatCredits"));
  if (!JS_IsException(method)) {
    JSValue args[3] = {JS_NewNumber(context, tenthsOfCredits * 0.1),
                       OOJSValueFromBOOL(includeDecimal),
                       OOJSValueFromBOOL(includeSymbol)};

    OOJSStartTimeLimiter();
    JSValue rval = JS_Call(context, method, global, 3, args);
    OOJSStopTimeLimiter();

    if (JS_IsException(rval))
      OOJSReportPendingException(context);
    else
      // nullopt (was nil) for null or undefined
      result = OOStringFromJSValue(context, rval);
    JS_FreeValue(context, rval);
  } else {
    OOJSReportPendingException(context);
  }
  JS_FreeValue(context, method);

  if (hadException) JS_Throw(context, exception);  // Takes ownership.

  OOJSRelinquishContext(context);

  if (EXPECT_NOT(!result.has_value()))
    result = std::format("{}", static_cast<long>(tenthsOfCredits) / 10);

  reentrancyLock = false;

  return *result;
}

std::vector<unsigned> ComponentsFromVersionString(const std::string& string) {
  return oo::str::versionComponents(string);
}

OOComparisonResult CompareVersions(const std::vector<unsigned>& version1,
                                   const std::vector<unsigned>& version2) {
  const int order = oo::str::compareVersions(version1, version2);
  if (order < 0) return OOComparisonResult::kAscending;
  if (order > 0) return OOComparisonResult::kDescending;
  return OOComparisonResult::kSame;
}

std::string ClockToString(double clock, bool adjusting) {
  int days, hrs, mins, secs;
  std::string format;

  days = floor(clock / 86400.0);
  secs = floor(clock - days * 86400.0);
  hrs = floor(secs / 3600.0);
  secs %= 3600;
  mins = floor(secs / 60.0);
  secs %= 60;

  // DESC() (Universe) is unmigrated: convert at the call. The format is read at
  // run time.
  if (adjusting)
    format = OO_DESC("clock-format-adjusting");
  else
    format = OO_DESC("clock-format");

  return oo::str::formatRuntime(format, {days, hrs, mins, secs});
}

#if DEBUG_GRAPHVIZ

std::string EscapedGraphVizString(const std::string& string) {
  static constexpr std::array<std::string_view, 6> srcStrings = {
      // Note: backslash must be first.
      "\\", "\"", "\'", "\r", "\n", "\t"};
  static constexpr std::array<std::string_view, 6> subStrings = {
      // Note: must be same order.
      "\\\\", "\\\"", "\\\'", "\\r", "\\n", "\\t"};

  std::string result = string;

  for (std::size_t i = 0; i < srcStrings.size(); ++i) {
    // -replaceOccurrencesOfString:withString:options:0 range:(the whole string)
    result = oo::str::replaceOccurrences(result, srcStrings[i], subStrings[i]);
  }

  return result;
}

namespace {

// The GraphViz keywords, matched case-insensitively (-lowercaseString).
constexpr std::string_view kGraphVizKeywords[] = {
    "node", "edge", "graph", "digraph", "subgraph", "strict"};

bool NameIsTaken(const std::string& name,
                 const std::set<std::string>* uniqueSet) {
  if (uniqueSet != nullptr && uniqueSet->contains(name)) return true;

  const std::string lowercaseName = oo::str::lowercase(name);
  for (std::string_view keyword : kGraphVizKeywords) {
    if (lowercaseName == keyword) return true;
  }
  return false;
}

}  // namespace

std::string GraphVizTokenString(const std::string& string,
                                std::set<std::string>* uniqueSet) {
  std::string token;
  bool lastWasUnderscore = false;
  // UTF-16 units, as -characterAtIndex: read them
  const std::u16string units = oo::utf8ToUtf16(string);
  std::size_t i, length = units.size();
  std::u16string result;
  result.reserve(length);

  if (length > 0) {
    // Special case for first char - can't be digit.
    char16_t c = units[0];
    if (!isalpha(c)) {
      c = '_';
      lastWasUnderscore = true;
    }
    result.push_back(c);

    for (i = 1; i < length; i++) {
      c = units[i];
      if (!isalnum(c)) {
        if (lastWasUnderscore) continue;
        c = '_';
        lastWasUnderscore = true;
      } else {
        lastWasUnderscore = false;
      }

      result.push_back(c);
    }

    token = oo::utf16ToUtf8(result);
  } else {
    token = "_";
  }

  if (NameIsTaken(token, uniqueSet)) {
    if (!lastWasUnderscore) token += "_";
    std::string uniqueToken;
    unsigned uniqueID = 2;

    for (;;) {
      uniqueToken = std::format("{}{}", token, uniqueID);
      if (!NameIsTaken(uniqueToken, uniqueSet)) break;
    }
    token = uniqueToken;
  }
  if (uniqueSet != nullptr) uniqueSet->insert(token);

  return token;
}

#endif  // DEBUG_GRAPHVIZ
