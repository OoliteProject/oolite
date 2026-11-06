# oofnd — the Foundation replacement

`oofnd` is the C++20 library that replaces GNUstep Foundation (`libgnustep-base`) during the
migration ([architecture §3.4](../../../docs/architecture.md)). It is built bottom-up,
one component per seam, each with its own unit tests. Namespace `oo`.

Rules that hold for every component:

- **C++20 only** for now. Where C++23 has the thing (`std::expected`), oofnd provides a
  same-API polyfill so the upgrade to C++23 is a rename.
- **No exceptions across oofnd APIs.** Fallible operations return `oo::Expected<T, E>`.
  Headers must compile with `-fno-exceptions` (the canary checks it).
- **Header-first.** A component is a header in this directory until it needs a `.cpp`; then
  `meson.build` here grows an `oofnd` static library (the recipe is in that file).
- **No Foundation, no `JS_*`** (the deny-list); no third-party code without a recorded decision.

## Layout

| Path | What |
|---|---|
| `src/oofnd/Expected.hpp` | `oo::Expected<T, E>`, `oo::Unexpected<E>`, `oo::unexpect`, `oo::BadExpectedAccess<E>`: `std::expected`'s C++23 API |
| `src/oofnd/Ref.hpp` | `oo::RefCounted`, `oo::Ref<T>`, `oo::WeakRef<T>`, `oo::AutoreleaseScope`: ObjC retain/release/autorelease and `OOWeakReference` 1:1; the banner maps each ObjC idiom |
| `src/oofnd/WeakSet.hpp` | `oo::WeakSet<T>`: `OOWeakSet` |
| `src/oofnd/PList.hpp` | `oo::PList`: the property-list value (null/bool/integer/real/string/data/date/array/dict) replacing the Foundation plist object graph; UTF-16 <-> UTF-8 helpers |
| `src/oofnd/PListOldStyle.hpp` | `oo::parseOldStylePList`: GNUstep's old-style (OpenStep) scanner, `parsePlItem`, ported quirk-for-quirk |
| `src/oofnd/PListXML.hpp` | `oo::parseXMLPList` (GNUstep's GSXMLPListParser over GSSloppyXMLParser) and `oo::changeDTDIfApplicable` (OOPListParsing.m), ported quirk-for-quirk |
| `src/oofnd/PListWriting.hpp` | `oo::writeOldStylePList` (OldSchoolPropertyListWriting.m) and `oo::writeXMLPList` (GNUstep's XML writer), byte-identical output |
| `src/oofnd/PListParsing.hpp` | `oo::parsePropertyList`: OOPropertyListFromData's DTD change + format detection + dispatch to the two readers |
| `src/oofnd/PListDescription.hpp` | `oo::describe(plist)`: gnustep-base's `-description` of the Foundation form of a `PList` (what `%@` printed for `ObjectFromPList(plist)`), byte for byte; pinned by rows captured with `tools/captures/plist-description/capture.sh`. Game code calls `oo::DescriptionOf(plist)` |
| `src/oofnd/PListGet.hpp` | `oo::PList::get<T>(key, fallback)` / `at<T>(index, fallback)`: OOCollectionExtractors' `oo_*ForKey:` / `oo_*AtIndex:` with GNUstep's exact conversions; included by `PList.hpp` |
| `src/oofnd/Data.hpp` | `oo::Data`: `NSData` / `NSMutableData` as a value type |
| `src/oofnd/FileSystem.hpp` | `oo::fs`: `NSFileManager` + its OOExtensions category + NSData file I/O, on `std::filesystem` with GNUstep semantics |
| `src/oofnd/ResourcePaths.hpp` | `oo::ResourcePaths`: the game's Resources/AddOns/saves/logs/caches locations, exactly as computed today on Windows and Linux |
| `src/oofnd/Notification.hpp` | `oo::NotificationCenter`, `oo::Notification`: `NSNotificationCenter` / `NSNotification` (named, synchronous, registration order) |
| `src/oofnd/Date.hpp` | `oo::date`: `NSDate` on `std::chrono`: the reference-date (2001) wall clock, a monotonic clock for intervals, NSDate's `-description` |
| `src/oofnd/StdLib.hpp` | the standard containers and clocks game code uses instead of Foundation collections, `NSValue` boxes and `NSDate`, included under the OOFoundation.h `true`/`false` guard; game code includes it rather than `<vector>` etc. |
| `src/oofnd/Process.hpp` | `oo::process` + `oo::env`: `NSProcessInfo` (arguments captured in `main`, `hasArgument`, `processName`, `processorCount`, `operatingSystemVersionString`) with GNUstep's measured semantics |
| `src/oofnd/Thread.hpp` | `oo::thread`: `NSThread` on `std::thread`: `detach`, `isMainThread` (id captured at static init), `setCurrentName`, `setCurrentPriority` (GNUstep's measured Windows mapping) |
| `src/oofnd/String.hpp` | `oo::str`: the `NSString` methods and Oolite `NSString` categories the game uses (`NSStringOOExtensions`, `OOStringParsing`'s `NSString (OOUtilities)`, `ScanTokensFromString`, the version helpers) over UTF-8 `std::string`, GNUstep 1.31.1's answers exactly: case tables, whitespace set, composed-sequence rules, `-pathExtension`, `-replaceOccurrencesOfString:`, `-hasPrefix:`, `-stringWithFormat:` without `%@` |
| `src/oofnd/Scanner.hpp` | `oo::str::CharacterSet` / `oo::str::Scanner` and `trim` / `findFirstOf` / `findLastOf` / `splitByCharacters`: `NSCharacterSet` (the named sets as GNUstep 1.31.1 tables, custom, inverted), `NSScanner` (skipping, case-insensitive matching, failure locations, `scanInt`/`scanDouble`) and `NSScannerOOExtensions`, exactly |
| `src/oofnd/Encoding.hpp` | `oo::str::Encoding` / `encodeLossy` / `convertForFont`: `OOEncodingConverter`'s conversion to the five Windows code pages, including libiconv's transliterations as GNUstep runs them; `stringWithContentsOfUnicodeFile` / `decodeUnicodeText`: `+[NSString stringWithContentsOfUnicodeFile:]` (UTF-16 by BOM, else UTF-8, else Latin-1; plain files, captured) |
| `src/oofnd/Log.hpp` | `oo::log`: OOLogging without Foundation: message-class switches (inheritance, `$metaclasses`, `_default`/`_override`), per-thread indentation, the exact Latest.log line layout, OOLogging's own diagnostics, and the `OO_LOG("cls", "{}", ...)` std::format front end. `src/Core/OOLogging.mm` is its Objective-C shell |
| `src/oofnd/LogFile.hpp` | `oo::log::FileWriter`, `logFileBytes`, `consoleBytes`, `rotateToPrevious`: the Latest.log writer (OOLogOutputHandler's OOAsyncLogger) without Foundation, byte for byte: CRLF, lone-surrogate lines dropped, 1 GiB saturation, Previous.log rotation |
| `src/oofnd/Http.hpp` | `oo::http::Download`, `parseUrl`: the OXZ manager's `NSURLConnection` without Foundation: one GET on its own thread (WinHTTP on Windows), its response/data/finish/failure callbacks taken in order on the main thread; every status delivers its body, Content-Length or -1, no cookies, redirects followed, file: URLs read from disk |
| `src/oofnd/Defaults.hpp` | `oo::Defaults`: preferences store matching former `NSUserDefaults`+Override/`NSBundle+Override` behaviour: same `GNUstep/Defaults/oolite.plist`, same search list and coercions, `oo::writeOpenStepPList` (GNUstep's OpenStep writer, byte-identical) |
| `src/oofnd/objc/OOObject.h`, `OOException.h` | forwarding headers: the Objective-C runtime's types (`id`, `Class`, `SEL`, `BOOL`) and `oofnd/Exception.hpp` |
| `src/oofnd/objc/OOFoundationTypes.h` | Foundation's C types (`NSInteger`/`NSUInteger`, `NSRange`, `NSNotFound`, `NSPoint`/`NSSize`/`NSRect`, `NSMake*`, `NSEqual*`, `NSTimeInterval`, `CGFloat`) with GNUstep's exact definitions and names; refuses to compile beside Foundation, so OOFoundation.h includes it only when the Foundation import is removed. Pinned by `tests/unit/oofnd/test_foundation_types.cpp` |
| `src/oofnd/meson.build` | `oofnd_dep` (include path `src/`, so consumers write `#include "oofnd/X.hpp"`) |
| `tests/unit/oofnd/test_*.cpp` | one executable per component, plain C++20 |
| `tests/unit/oofnd/oo_test.hpp` | the whole test harness: `OO_TEST`, `OO_CHECK`, `OO_CHECK_EQ`, `OO_TEST_MAIN` |
| `tests/unit/oofnd/plist_dump.hpp` | canonical one-line dump of a `PList`, the format the PList tests' GNUstep-captured expectations are written in |
| `tests/unit/oofnd/meson.build` | registers each test in `meson test --suite oofnd` |


## Conventions

- **Floats written to disk** (savegames, caches, defaults): build them with `oo::PList::singleReal(f)`, never `oo::PList(double(f))`; the writers then print `%0.7g` as GNUstep did. The saved game is written with `oo::writeXMLPList`.
- **A format string that is data** (a `DESC(...)` entry, a plist template) goes through `oo::str::formatRuntime(fmt, {args...})`, each argument an `oo::str::FormatArg`: an object's `oo::DescriptionOf(obj)` for `%@`, `FormatArg::null()` for nil, `FormatArg::pointer(p)` for `%p`, numbers as themselves (`FormatArg::single(f)` for a float). Only a literal format uses `oo::str::format`.

## The Foundation-free boundaries

The seams the game uses in place of gnustep-base's helpers. Each is Foundation-free.

### Describing an object: `Core/OODescription.h`

Imported by `OOFoundation.h`, so no file includes it. A class describes itself by overriding **one**
method on the `OOObject` root; the printers wrap it:

| Override | Printed by | As |
|---|---|---|
| `- (std::optional<std::string>) cxx_descriptionComponents` | `-cxx_description`, `oo::DescriptionOf(x)`, `-cxx_oo_jsDescription` | `<ClassName 0xnnnnnnnn>{components}`; JS `[jsClassName components]` |
| `- (std::optional<std::string>) cxx_shortDescriptionComponents` | `-cxx_shortDescription`, `oo::ShortDescriptionOf(x)` | `<ClassName 0xnnnnnnnn>{components}` |
| `- (std::optional<std::string>) cxx_description` (rare: the whole text) | `oo::DescriptionOf(x)` | whatever it returns |

nullopt means no components (`<ClassName 0xnnnnnnnn>`). A subclass extends its superclass's text with
`[super cxx_descriptionComponents].value_or("(null)")`. Exemplar: `src/Core/OORoleSet.mm`
(`-cxx_descriptionComponents`). `%@` of an object is `oo::DescriptionOf(obj)` (`(null)` for nil, a class's name for a class object, the text of a string
literal). `oo::DescriptionOf([x shortDescription])` is `oo::ShortDescriptionOf(x)`.

The root has no description category: the four methods are the `@optional` protocol
`OODescription`, and an object whose class has no method of its own gets the root's default from the
C++ functions `oo::ObjectDescription`, `oo::ObjectShortDescription`, `oo::ObjectDescriptionComponents`
and `oo::ObjectShortDescriptionComponents` (what the deleted category answered; nullopt for nil).
Send none of the four to an object directly; ask those functions. `tests/unit/oofnd/test_objc_plist.mm`
links `OODescription.mm` against libobjc2 alone.

### Describing a property list: `oo::DescriptionOf(const oo::PList &)`

`oo::DescriptionOf(oo::ObjectFromPList(v))` is `oo::DescriptionOf(v)`: the `OODescription.h` overload
forwards to `oo::describe` (`oofnd/PListDescription.hpp`), which prints what gnustep-base's
`-description` printed (`(a, "two words", 1)`, `{key = value; }`, keys by `-compare:`, strings
quoted and escaped as GNUstep did). Exemplar: `src/Core/Entities/OOVisualEffectEntity.mm`
(`setUpOneStandardSubentity:`). The text is pinned by `tests/unit/oofnd/test_plist_description.cpp`
against `plist_description_captured.inc`, captured from GNUstep base 1.31.1; to add a case, add a
line to `tools/captures/plist-description/cases.txt` and rerun
`bash tools/captures/plist-description/capture.sh` (needs gnustep-base installed; `--check`
compares without writing). Dates print in the local time zone, as NSDate did
(`oo::date::description`); the capture runs with TZ=UTC and the test describes at offset 0.

### Calling a method by name: `Core/OOCallByName.h`

A dispatcher that runs a method named in data (an AI action, a legacy-script action or query, a
HUD dial, a deferred call) calls `OOCallByName(target, selector [, argument])` instead of
`-performSelector:withObject:`, and the method it names has one of the dispatcher's C++ signatures:
`- (void|oo::PList) sel`, `- (void|oo::PList) sel:(const std::string &)s`, or
`- (void) sel:(const oo::PList &)p` (the table is in the header). Exemplar: `src/Core/AI.mm`
(`-cxx_takeAction:`, the `interpretAIMessage:` message, the deferred-call trampoline and its
`-deferredSetState:(const std::string &)`). To flip a called-by-name method, give it one of those
signatures in every declaring class at once (the family rule). The entity call
(`OOEntityCalledByName.mm`) keeps the signatures.

## Testing

From the repo root, in the MSYS2 UCRT64 shell:

```bash
bash tools/check-oofnd.sh      # no build dir needed; ~10 s.
```

It compiles every header alone and together (the canary TU, also under `-fno-exceptions`), then
builds and runs every `tests/unit/oofnd/test_*.cpp` at `-std=c++20 -Wall -Wextra -Werror`, then
again under AddressSanitizer. It fails on zero tests and on a test file missing from
`tests/unit/oofnd/meson.build`.

Inside a game build directory the same tests run through meson:

```bash
cd oolite-dev && ./mk.sh build test
meson test -C build/meson_test --suite oofnd
```

Game code builds as `c++20` and sees OOFoundation.h's `#define true 1` / `#define false 0`:
a header that game code includes must suspend them with `#pragma push_macro`/`pop_macro` as
`Data.hpp` does (`tests/unit/oofnd/test_cocoa_macros.cpp` checks it).

Adding a component: put `Foo.hpp` here, write `tests/unit/oofnd/test_foo.cpp` ending in
`OO_TEST_MAIN()`, and add `'test_foo'` to `tests/unit/oofnd/meson.build`.
