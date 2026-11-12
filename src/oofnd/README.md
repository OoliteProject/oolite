# oofnd — the Foundation replacement

`oofnd` is the C++23 library that replaced GNUstep Foundation (`libgnustep-base`): one
component per seam the game used, each with its own unit tests. Namespace `oo`.

Rules that hold for every component:

- **C++23.** Where the standard library has the thing, game code uses it directly and the
  `oofnd` copy goes (spec 009); a component stays only where the standard has no equivalent or
  gives different answers.
- **No exceptions across oofnd APIs.** Fallible operations return `std::expected<T, E>`. The game
  itself does throw (`OORaiseException`, `oo::Exception`), so nothing is built with
  `-fno-exceptions`.
- **Header-first.** A component is a header in this directory until it needs a `.cpp`; then
  `meson.build` here grows an `oofnd` static library (the recipe is in that file).
- **No Foundation, no `JS_*`** (the deny-list); no third-party code without a recorded decision.

## Layout

| Path | What |
|---|---|
| `src/oofnd/Ref.hpp` | `oo::RefCounted`, `oo::Ref<T>`, `oo::WeakRef<T>`, `oo::AutoreleaseScope`: ObjC retain/release/autorelease and `OOWeakReference` 1:1; the banner maps each ObjC idiom |
| `src/oofnd/WeakSet.hpp` | `oo::WeakSet<T>`: `OOWeakSet` |
| `src/oofnd/PList.hpp` | `oo::PList`: the property-list value (null/bool/integer/real/string/data/date/array/dict) replacing the Foundation plist object graph; UTF-16 <-> UTF-8 helpers |
| `src/oofnd/PListOldStyle.hpp` | `oo::parseOldStylePList`: GNUstep's old-style (OpenStep) scanner, `parsePlItem`, ported quirk-for-quirk |
| `src/oofnd/PListXML.hpp` | `oo::parseXMLPList` (GNUstep's GSXMLPListParser over GSSloppyXMLParser) and `oo::changeDTDIfApplicable` (OOPListParsing.m), ported quirk-for-quirk |
| `src/oofnd/PListWriting.hpp` | `oo::writeOldStylePList` (OldSchoolPropertyListWriting.m) and `oo::writeXMLPList` (GNUstep's XML writer), byte-identical output |
| `src/oofnd/PListParsing.hpp` | `oo::parsePropertyList`: OOPropertyListFromData's DTD change + format detection + dispatch to the two readers |
| `src/oofnd/PListDescription.hpp` | `oo::describe(plist)`: gnustep-base's `-description` of the Foundation form of a `PList` (what `%@` printed for `ObjectFromPList(plist)`), byte for byte; pinned by rows captured from gnustep-base 1.31.1 (`tests/unit/oofnd/plist_description_captured.inc`). Game code calls `oo::DescriptionOf(plist)` |
| `src/oofnd/PListGet.hpp` | `oo::PList::get<T>(key, fallback)` / `at<T>(index, fallback)`: OOCollectionExtractors' `oo_*ForKey:` / `oo_*AtIndex:` with GNUstep's exact conversions; included by `PList.hpp` |
| `src/oofnd/Data.hpp` | `oo::Data`: `NSData` / `NSMutableData` as a value type |
| `src/oofnd/FileSystem.hpp` | `oo::fs`: `NSFileManager` + its OOExtensions category + NSData file I/O, on `std::filesystem` with GNUstep semantics |
| `src/oofnd/ResourcePaths.hpp` | `oo::ResourcePaths`: the game's Resources/AddOns/saves/logs/caches locations, exactly as computed today on Windows and Linux |
| `src/oofnd/Notification.hpp` | `oo::NotificationCenter`, `oo::Notification`: `NSNotificationCenter` / `NSNotification` (named, synchronous, registration order) |
| `src/oofnd/Date.hpp` | `oo::date`: `NSDate` on `std::chrono`: the reference-date (2001) wall clock, a monotonic clock for intervals, NSDate's `-description` |
| `src/oofnd/StdLib.hpp` | no longer used by game code, which includes the standard headers it uses (spec 009 T031); kept only for `tests/unit/oofnd/test_stdlib.cpp` until Jon decides whether that test is retired |
| `src/oofnd/Process.hpp` | `oo::process` + `oo::env`: `NSProcessInfo` (arguments captured in `main`, `hasArgument`, `processName`, `processorCount`, `operatingSystemVersionString`) with GNUstep's measured semantics |
| `src/oofnd/Thread.hpp` | `oo::thread`: what `std::thread` cannot do: `setCurrentName`, `setCurrentPriority` (GNUstep's measured Windows mapping), and `isMainThread()` (against the id captured at static init, `kMainThreadId`) |
| `src/oofnd/String.hpp` | `oo::str`: the `NSString` methods and Oolite `NSString` categories the game uses (`NSStringOOExtensions`, `OOStringParsing`'s `NSString (OOUtilities)`, `ScanTokensFromString`, the version helpers) over UTF-8 `std::string`, GNUstep 1.31.1's answers exactly: case tables, whitespace set, composed-sequence rules, `-pathExtension`, `-replaceOccurrencesOfString:`, `-hasPrefix:`, `-stringWithFormat:` without `%@` |
| `src/oofnd/Scanner.hpp` | `oo::str::CharacterSet` / `oo::str::Scanner` and `trim` / `findFirstOf` / `findLastOf` / `splitByCharacters`: `NSCharacterSet` (the named sets as GNUstep 1.31.1 tables, custom, inverted), `NSScanner` (skipping, case-insensitive matching, failure locations, `scanInt`/`scanDouble`) and `NSScannerOOExtensions`, exactly |
| `src/oofnd/Encoding.hpp` | `oo::str::Encoding` / `encodeLossy` / `convertForFont`: `OOEncodingConverter`'s conversion to the five Windows code pages, including libiconv's transliterations as GNUstep runs them; `stringWithContentsOfUnicodeFile` / `decodeUnicodeText`: `+[NSString stringWithContentsOfUnicodeFile:]` (UTF-16 by BOM, else UTF-8, else Latin-1; plain files, captured) |
| `src/oofnd/Log.hpp` | `oo::log`: OOLogging without Foundation: message-class switches (inheritance, `$metaclasses`, `_default`/`_override`), per-thread indentation, the exact Latest.log line layout, OOLogging's own diagnostics, and the `OO_LOG("cls", "{}", ...)` std::format front end. `src/Core/OOLogging.cpp` is the game-side shell |
| `src/oofnd/LogFile.hpp` | `oo::log::FileWriter`, `logFileBytes`, `consoleBytes`, `rotateToPrevious`: the Latest.log writer (OOLogOutputHandler's OOAsyncLogger) without Foundation, byte for byte: CRLF, lone-surrogate lines dropped, 1 GiB saturation, Previous.log rotation |
| `src/oofnd/Http.hpp` | `oo::http::Download`, `parseUrl`: the OXZ manager's `NSURLConnection` without Foundation: one GET on its own thread (libcurl), its response/data/finish/failure callbacks taken in order on the main thread; every status delivers its body, Content-Length or -1, no cookies, redirects followed, file: URLs read from disk |
| `src/oofnd/Defaults.hpp` | `oo::Defaults`: preferences store matching former `NSUserDefaults`+Override/`NSBundle+Override` behaviour: same `GNUstep/Defaults/oolite.plist`, same search list and coercions, `oo::writeOpenStepPList` (GNUstep's OpenStep writer, byte-identical) |
| `src/oofnd/objc/OOObject.h` | `OOZone`, the opaque zone type (always null) that OOMesh's copy members take |
| `src/oofnd/objc/OOException.h` | forwards to `oofnd/Exception.hpp` (`oo::Exception`, `OORaiseException`) |
| `src/oofnd/objc/OOAssert.h` | `OOCAssert` / `OOCParameterAssert`: gnustep-base's assertion semantics, live in every flavour |
| `src/oofnd/objc/OOFoundationTypes.h` | Foundation's C types (`std::ptrdiff_t`/`std::size_t`, `NSRange`, `oo::kNotFound`, `NSPoint`/`NSSize`/`NSRect`, `NSMake*`, `NSEqual*`, `double`, `double`) with GNUstep's exact definitions and names; refuses to compile beside a Foundation header. Pinned by `tests/unit/oofnd/test_foundation_types.cpp` |
| `src/oofnd/meson.build` | `oofnd_dep` (include path `src/`, so consumers write `#include "oofnd/X.hpp"`) |
| `tests/unit/oofnd/test_*.cpp` | one executable per component, plain C++23 |
| `tests/unit/oofnd/oo_test.hpp` | the whole test harness: `OO_TEST`, `OO_CHECK`, `OO_CHECK_EQ`, `OO_TEST_MAIN` |
| `tests/unit/oofnd/plist_dump.hpp` | canonical one-line dump of a `PList`, the format the PList tests' GNUstep-captured expectations are written in |
| `tests/unit/oofnd/meson.build` | registers each test in `meson test --suite oofnd` |


## Conventions

- **Floats written to disk** (savegames, caches, defaults): build them with `oo::PList::singleReal(f)`, never `oo::PList(double(f))`; the writers then print `%0.7g` as GNUstep did. The saved game is written with `oo::writeXMLPList`.
- **A format string that is data** (a `DESC(...)` entry, a plist template) goes through `oo::str::formatRuntime(fmt, {args...})`, each argument an `oo::str::FormatArg`: an object's `oo::DescriptionOf(obj)` for `%@`, `FormatArg::null()` for nil, `FormatArg::pointer(p)` for `%p`, numbers as themselves (`FormatArg::single(f)` for a float). Only a literal format uses `oo::str::format`.

## The Foundation-free boundaries

The seams the game uses in place of gnustep-base's helpers. Each is Foundation-free.

### Describing an object

A class describes itself by overriding `virtual std::optional<std::string> descriptionComponents()
const`; the text is `<ClassName 0xnnnnnnnn>{components}`, or `<ClassName 0xnnnnnnnn>` for nullopt
(the pointer is `oo::str::pointerDescription`'s, GNUstep's `%p`: the low 32 bits). A subclass extends
its base's components by calling the base and appending. Exemplar: `OORoleSet::descriptionComponents`
in `src/Core/OORoleSet.cpp`.

### Describing a property list: `oo::DescriptionOf(const oo::PList &)`

`oo::DescriptionOf(oo::ObjectFromPList(v))` is `oo::DescriptionOf(v)`: the `OODescription.h` overload
forwards to `oo::describe` (`oofnd/PListDescription.hpp`), which prints what gnustep-base's
`-description` printed (`(a, "two words", 1)`, `{key = value; }`, keys by `-compare:`, strings
quoted and escaped as GNUstep did). The text is pinned by
`tests/unit/oofnd/test_plist_description.cpp` against `plist_description_captured.inc`, captured
from GNUstep base 1.31.1. Dates print in the local time zone, as NSDate did
(`oo::date::description`); the capture runs with TZ=UTC and the test describes at offset 0.

### Calling a method by name: `Core/OOCallByName.h`

A dispatcher that runs a method named in data (an AI action, a legacy-script action or query, a
string-expander `[selector]` key, `ship.call()`, a deferred call) calls
`oo::CallEntityByName(entity, name [, argument])`, which looks the name up in the generated table
`Core/Entities/OOEntityCalledByNameTable.h`. The forms it can call, and what it logs for the rest,
are in the header.

## Testing

The tests run through meson, from `oolite-dev` in the MSYS2 UCRT64 shell:

```bash
./mk.sh build test
meson test -C build/meson_test --suite oofnd
```

The headers must also compile where `true` and `false` are macros (`#define true 1`, as old
Cocoa-compatibility headers had it) and hand them back unchanged, suspending them with
`#pragma push_macro`/`pop_macro` as `Data.hpp` does (`tests/unit/oofnd/test_cocoa_macros.cpp`
checks it).

Adding a component: put `Foo.hpp` here, write `tests/unit/oofnd/test_foo.cpp` ending in
`OO_TEST_MAIN()`, and add `'test_foo'` to `tests/unit/oofnd/meson.build`.
