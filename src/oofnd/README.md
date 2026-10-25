# oofnd — the Foundation replacement

`oofnd` is the C++20 library that replaces GNUstep Foundation (`libgnustep-base`) during the
migration (Phase 2, [architecture §3.4](../../../../docs/architecture.md)). It is built bottom-up,
one component per seam, each with its own unit tests, and adopted by Objective-C++ call sites
while the classes are still Objective-C. Namespace `oo`.

Rules that hold for every component:

- **C++20 only** until Phase 6 ([ADR-0011](../../../../docs/decisions/0011-cpp20-then-cpp23.md)).
  Where C++23 has the thing (`std::expected`), oofnd provides a same-API polyfill so the
  Phase 6 upgrade is a rename.
- **No exceptions across oofnd APIs.** Fallible operations return `oo::Expected<T, E>`.
  Headers must compile with `-fno-exceptions` (the canary checks it).
- **Header-first.** A component is a header in this directory until it needs a `.cpp`; then
  `meson.build` here grows an `oofnd` static library (the recipe is in that file).
- **No Foundation, no `JS_*`** (the deny-list); no third-party code unless an ADR says so.

## Layout

| Path | What |
|---|---|
| `src/oofnd/Expected.hpp` | `oo::Expected<T, E>`, `oo::Unexpected<E>`, `oo::unexpect`, `oo::BadExpectedAccess<E>`: `std::expected`'s C++23 API |
| `src/oofnd/Ref.hpp` | `oo::RefCounted`, `oo::Ref<T>`, `oo::WeakRef<T>`, `oo::AutoreleaseScope`: ObjC retain/release/autorelease and `OOWeakReference` 1:1 ([ADR-0003](../../../../docs/decisions/0003-intrusive-refcount.md), [ADR-0026](../../../../docs/decisions/0026-oofnd-ref-semantics.md), drain order [ADR-0045](../../../../docs/decisions/0045-autorelease-scope-drains-lifo.md)); the banner maps each ObjC idiom |
| `src/oofnd/WeakSet.hpp` | `oo::WeakSet<T>`: `OOWeakSet` |
| `src/oofnd/PList.hpp` | `oo::PList`: the property-list value (null/bool/integer/real/string/data/date/array/dict) replacing the Foundation plist object graph; UTF-16 <-> UTF-8 helpers ([ADR-0027](../../../../docs/decisions/0027-oofnd-plist-fidelity.md)) |
| `src/oofnd/PListOldStyle.hpp` | `oo::parseOldStylePList`: GNUstep's old-style (OpenStep) scanner, `parsePlItem`, ported quirk-for-quirk |
| `src/oofnd/PListXML.hpp` | `oo::parseXMLPList` (GNUstep's GSXMLPListParser over GSSloppyXMLParser) and `oo::changeDTDIfApplicable` (OOPListParsing.m), ported quirk-for-quirk |
| `src/oofnd/PListWriting.hpp` | `oo::writeOldStylePList` (OldSchoolPropertyListWriting.m) and `oo::writeXMLPList` (GNUstep's XML writer), byte-identical output |
| `src/oofnd/PListParsing.hpp` | `oo::parsePropertyList`: OOPropertyListFromData's DTD change + format detection + dispatch to the two readers |
| `src/oofnd/PListDescription.hpp` | `oo::describe(plist)`: gnustep-base's `-description` of the Foundation form of a `PList` (what `%@` printed for `ObjectFromPList(plist)`), byte for byte; pinned by rows captured with `tools/captures/plist-description/capture.sh` (ADR-0055 item 1). Game code calls `oo::DescriptionOf(plist)` |
| `src/oofnd/PListGet.hpp` | `oo::PList::get<T>(key, fallback)` / `at<T>(index, fallback)`: OOCollectionExtractors' `oo_*ForKey:` / `oo_*AtIndex:` with GNUstep's exact conversions ([ADR-0031](../../../../docs/decisions/0031-plist-get-and-the-foundation-bridge.md)); included by `PList.hpp` |
| `src/Core/OOPListView.h` (game side) | deleted by oo-snzn with `OOCollectionExtractors` (ADR-0055): it was `oo::PListView`, the same `get<T>`/`at<T>` over a Foundation collection; the recipe below is history |
| `src/oofnd/Data.hpp` | `oo::Data`: `NSData` / `NSMutableData` as a value type ([ADR-0028](../../../../docs/decisions/0028-oofnd-filesystem-paths-data.md)) |
| `src/oofnd/FileSystem.hpp` | `oo::fs`: `NSFileManager` + its OOExtensions category + NSData file I/O, on `std::filesystem` with GNUstep semantics |
| `src/oofnd/ResourcePaths.hpp` | `oo::ResourcePaths`: the game's Resources/AddOns/saves/logs/caches locations, exactly as computed today on Windows and Linux |
| `src/oofnd/Notification.hpp` | `oo::NotificationCenter`, `oo::Notification`: `NSNotificationCenter` / `NSNotification` (named, synchronous, registration order; bead oo-3rb.9, ADR-0029 Decision 5) |
| `src/oofnd/Date.hpp` | `oo::date`: `NSDate` on `std::chrono`: the reference-date (2001) wall clock, a monotonic clock for intervals, NSDate's `-description` (bead oo-3rb.11) |
| `src/oofnd/StdLib.hpp` | the standard containers and clocks game code uses instead of Foundation collections, `NSValue` boxes and `NSDate`, included under the OOCocoa.h `true`/`false` guard (bead oo-3rb.10); game code includes it rather than `<vector>` etc. |
| `src/oofnd/Process.hpp` | `oo::process` + `oo::env`: `NSProcessInfo` (arguments captured in `main`, `hasArgument`, `processName`, `processorCount`, `operatingSystemVersionString`) with GNUstep's measured semantics |
| `src/oofnd/Thread.hpp` | `oo::thread`: `NSThread` on `std::thread`: `detach`, `isMainThread` (id captured at static init), `setCurrentName`, `setCurrentPriority` (GNUstep's measured Windows mapping) |
| `src/oofnd/String.hpp` | `oo::str`: the `NSString` methods and Oolite `NSString` categories the game uses (`NSStringOOExtensions`, `OOStringParsing`'s `NSString (OOUtilities)`, `ScanTokensFromString`, the version helpers) over UTF-8 `std::string`, GNUstep 1.31.1's answers exactly: case tables, whitespace set, composed-sequence rules, `-pathExtension`, `-replaceOccurrencesOfString:`, `-hasPrefix:`, `-stringWithFormat:` without `%@` ([ADR-0034](../../../../docs/decisions/0034-oofnd-strings.md)) |
| `src/oofnd/Scanner.hpp` | `oo::str::CharacterSet` / `oo::str::Scanner` and `trim` / `findFirstOf` / `findLastOf` / `splitByCharacters`: `NSCharacterSet` (the named sets as GNUstep 1.31.1 tables, custom, inverted), `NSScanner` (skipping, case-insensitive matching, failure locations, `scanInt`/`scanDouble`) and `NSScannerOOExtensions`, exactly (bead oo-3rb.12, [ADR-0039](../../../../docs/decisions/0039-oofnd-scanner.md)) |
| `src/oofnd/Encoding.hpp` | `oo::str::Encoding` / `encodeLossy` / `convertForFont`: `OOEncodingConverter`'s conversion to the five Windows code pages, including libiconv's transliterations as GNUstep runs them; `stringWithContentsOfUnicodeFile` / `decodeUnicodeText`: `+[NSString stringWithContentsOfUnicodeFile:]` (UTF-16 by BOM, else UTF-8, else Latin-1; plain files, captured, oo-3rb.123) |
| `src/oofnd/Log.hpp` | `oo::log`: OOLogging without Foundation: message-class switches (inheritance, `$metaclasses`, `_default`/`_override`), per-thread indentation, the exact Latest.log line layout, OOLogging's own diagnostics, and the `OO_LOG("cls", "{}", ...)` std::format front end. `src/Core/OOLogging.mm` is its Objective-C shell ([ADR-0035](../../../../docs/decisions/0035-oofnd-logging.md)) |
| `src/oofnd/LogFile.hpp` | `oo::log::FileWriter`, `logFileBytes`, `consoleBytes`, `rotateToPrevious`: the Latest.log writer (OOLogOutputHandler's OOAsyncLogger) without Foundation, byte for byte: CRLF, lone-surrogate lines dropped, 1 GiB saturation, Previous.log rotation ([ADR-0042](../../../../docs/decisions/0042-oofnd-log-file-writer.md)) |
| `src/oofnd/Http.hpp` | `oo::http::Download`, `parseUrl`: the OXZ manager's `NSURLConnection` without Foundation: one GET on its own thread (WinHTTP on Windows), its response/data/finish/failure callbacks taken in order on the main thread; every status delivers its body, Content-Length or -1, no cookies, redirects followed, file: URLs read from disk ([ADR-0044](../../../../docs/decisions/0044-oofnd-http-client.md)) |
| `src/Core/OOStringBridge.h` (game side) | deleted by oo-qps.16 (ADR-0055): it was `oo::StdString` / `oo::NSStringFrom` / `oo::StringMap`, the `NSString` <-> `std::string` bridge; the Phase 5 Mac port restores what it needs from `git show <oo-qps.16>^` (ADR-0055 item 7) |
| ~~`src/oofnd/objc/OOObjCRef.h`~~ | deleted with libobjc2 (bead oo-dbz.2): `oo::ObjCRef<T *>`, a retaining reference to an Objective-C object, had no user left; its test `test_objc_ref.mm` retired with it |
| `src/Core/OOFoundationBridge.h` (game side) | deleted by oo-qps.16 (ADR-0055): it held the Foundation sweep's boundary helpers; Object nodes moved to `src/Core/OOObjCPList.h`, `%@` text to `src/Core/OODescription.h` |
| ~~`tools/check-selector-types.py`~~ | retired by bead oo-ebds4 (ADR-0043 Amendment 4): it found which of a header's Objective-C selectors were shared (keep `id`) and guarded selector families against disagreeing C++ types; with libobjc2 gone (oo-dbz.5) no selector is declared or sent, so it checked nothing. `git show oo-ebds4^:tools/check-selector-types.py` restores it |
| `src/oofnd/Defaults.hpp` | `oo::Defaults`: preferences store matching former `NSUserDefaults`+Override/`NSBundle+Override` behaviour: same `GNUstep/Defaults/oolite.plist`, same search list and coercions, `oo::writeOpenStepPList` (GNUstep's OpenStep writer, byte-identical) ([ADR-0032](../../../../docs/decisions/0032-oofnd-defaults.md)); shim deleted by oo-iobt |
| `src/oofnd/objc/OOObject.h`, `.mm` | `OOObject`: the Foundation-free Objective-C root class on libobjc2's own refcount and pool; `OOObjCInstallFloor()` ([ADR-0029](../../../../docs/decisions/0029-objc-floor-without-foundation.md)). Objective-C++, not linked into the game until the reroot bead. Deleted by bead oo-4aq6a.8 (OOObject.h stays as a forwarding header) |
| `src/oofnd/objc/OOObject.h`, `.mm` | `OOObject`: the Foundation-free Objective-C root class on libobjc2's own refcount and pool; `OOObjCInstallFloor()` ([ADR-0029](../../../../docs/decisions/0029-objc-floor-without-foundation.md)). Objective-C++; linked into the game by bead oo-3rb.2 (exemplar reroot: `Core/OORoleSet`), but `OOObjCInstallFloor()` is not called until the constant-string flip. Deleted by bead oo-4aq6a.8 (OOObject.h stays as a forwarding header) |
| `src/oofnd/objc/OOConstantString.h`, `.mm` | `OOConstantString`/`OOTinyString`: the classes behind `@"..."` under `-fconstant-string-class=OOConstantString` (ADR-0029). Deleted by bead oo-4aq6a.8 (OOObject.h stays as a forwarding header) |
| ~~`src/oofnd/objc/OORuntime.h`~~ | deleted with libobjc2 (bead oo-dbz.2): `OOClassFromName` & co., libobjc2's class and selector lookups, had no user left; its test `test_objc_runtime.mm` retired with it |
| `src/oofnd/objc/OOException.h`, `.mm` | `OOException`: `NSException` without Foundation; `@try`/`@catch` stay Objective-C (ADR-0029 Decision 4). `+raise:format:` is printf-style; `OOInvalidArgumentException` & co. are `const char *` with Foundation's text |
| `src/oofnd/objc/OOFoundationTypes.h` | Foundation's C types (`NSInteger`/`NSUInteger`, `NSRange`, `NSNotFound`, `NSPoint`/`NSSize`/`NSRect`, `NSMake*`, `NSEqual*`, `NSTimeInterval`, `CGFloat`) with GNUstep's exact definitions and names (ADR-0029 Decision 5); refuses to compile beside Foundation, so OOCocoa.h includes it only from oo-qps. Pinned by `tests/unit/oofnd/test_foundation_types.cpp` |
| `src/oofnd/meson.build` | `oofnd_dep` (include path `src/`, so consumers write `#include "oofnd/X.hpp"`) |
| `tests/unit/oofnd/test_*.cpp` | one executable per component, plain C++20 |
| `tests/unit/oofnd/oo_test.hpp` | the whole test harness: `OO_TEST`, `OO_CHECK`, `OO_CHECK_EQ`, `OO_TEST_MAIN` |
| `tests/unit/oofnd/plist_dump.hpp` | canonical one-line dump of a `PList`, the format the PList tests' GNUstep-captured expectations are written in |
| `tests/unit/oofnd/test_*.mm` | Objective-C++ tests of `src/oofnd/objc`, linked against libobjc2 alone; `tools/check-oofnd-objc.sh` builds them and proves the import table has no gnustep-base |
| `tests/unit/oofnd/meson.build` | registers each test in `meson test --suite oofnd` |

## Migrating oo_*ForKey

> **History (ADR-0055).** This recipe is kept as the record of what the sweep beads did. Its
> header, `src/Core/OOPListView.h`, was deleted by oo-snzn with `OOCollectionExtractors`; do not recreate it or import it. Code written today holds
> C++ values: `oo::PList`'s own `get<T>`/`at<T>` (`oofnd/PListGet.hpp`), and an Objective-C object in a
> property list goes through `Core/OOObjCPList.h`.

The recipe for every `sweep:extractors` bead ("Retire oo_*ForKey in <file>"). Proposed
[ADR-0031](../../../../docs/decisions/0031-plist-get-and-the-foundation-bridge.md); exemplar
`src/Core/Entities/OOWaypointEntity.mm` (bead oo-u77) - open it and do what it does.

The file keeps its Foundation collections. Each call goes through `oo::PListView`
(`src/Core/OOPListView.h`), a zero-copy view with `oo::PList`'s `get<T>`/`at<T>` API that performs
the same lookup and calls the same conversion function as the category method it replaces, so the
change is behaviour-preserving by construction. Do exactly this, nothing else:

1. **Import** (history). The bead swapped the file's `OOCollectionExtractors.h` import for the
   view's header, `OOPListView.h` (the view imported it, so nothing was lost), or added the view's
   header after the file's last import.
2. **Rewrite each call.** Receiver, key, index and fallback expressions move over **unchanged**
   (keep `@"..."`, `#define`d keys and `NSString *` constants as they are):

   | Objective-C | becomes |
   |---|---|
   | `[R oo_<type>ForKey:K defaultValue:D]` | `oo::PListView(R).get<T>(K, D)` |
   | `[R oo_<type>ForKey:K]` | `oo::PListView(R).get<T>(K)` |
   | `[R oo_<type>AtIndex:I defaultValue:D]` | `oo::PListView(R).at<T>(I, D)` |
   | `[R oo_<type>AtIndex:I]` | `oo::PListView(R).at<T>(I)` |

   where `<type>` → `T` is:

   | `<type>` | `T` | | `<type>` | `T` |
   |---|---|---|---|---|
   | `char` | `char` | | `bool` | `BOOL` |
   | `short` | `short` | | `fuzzyBoolean` | `oo::FuzzyBoolean` |
   | `int` | `int` | | `float` | `float` |
   | `long` | `long` | | `double` | `double` |
   | `longLong` | `long long` | | `nonNegativeFloat` | `oo::NonNegative<float>` |
   | `integer` | `NSInteger` | | `nonNegativeDouble` | `oo::NonNegative<double>` |
   | `unsignedChar` | `unsigned char` | | `object` | `id` |
   | `unsignedShort` | `unsigned short` | | `string` | `NSString *` |
   | `unsignedInt` | `unsigned int` | | `array` | `NSArray *` |
   | `unsignedLong` | `unsigned long` | | `dictionary` | `NSDictionary *` |
   | `unsignedLongLong` | `unsigned long long` | | `mutableDictionary` | `NSMutableDictionary *` |
   | `unsignedInteger` | `NSUInteger` | | `data` | `NSData *` |
   | `vector` | `Vector` | | `set` | `NSSet *` |
   | `hpvector` | `HPVector` | | `quaternion` | `Quaternion` |

   A receiver that is itself a message send is fine: `[[UNIVERSE descriptions] oo_arrayForKey:k]`
   becomes `oo::PListView([UNIVERSE descriptions]).get<NSArray *>(k)`. A nested call is rewritten
   inside out: `[[d oo_dictionaryForKey:a] oo_stringForKey:b]` becomes
   `oo::PListView(oo::PListView(d).get<NSDictionary *>(a)).get<NSString *>(b)`.
   `[R oo_textureSpecifierForKey:K defaultName:N]` (OOTexture.h) becomes
   `oo::PListView(R).get<oo::TextureSpecifier>(K, N)`.
   Convert the file's `oo_*AtIndex` calls too: they are the same seam, no other sweep covers them,
   and the phase exit retires OOCollectionExtractors as a whole.
3. **Leave alone:** the inserters (`oo_setFloat:forKey:`, `oo_addInteger:` ...), `oo_objectOfClass:`
   with a runtime `Class`, `oo_textureSpecifierAtIndex:defaultName:` (it raises past the end), the
   `OO<Type>FromObject()` functions, and every other line of the file. Do not change types, keys or fallbacks, and do not reformat.
4. **Check:** `! grep -nE 'oo_[a-zA-Z]+ForKey' <file>` prints nothing, then
   `tools/tier-a.sh <file>` passes. A comment that names an `oo_*ForKey` method is reworded to
   name the `get<T>` form. If a `T` does not compile, the call is not in the table: stop and
   report it rather than inventing a conversion.

Semantics worth knowing (all preserved, so nothing to do): a nil receiver returns zero / nil / NO
(not the fallback), exactly as messaging nil did; an index past the end gives the fallback.

Later, when the Foundation sweep turns a file's collections into `oo::PList`, `oo::PListView(x).`
becomes `x.` and the Objective-C types map to `std::string`, `PList::Array`, `PList::Dict`,
`oo::PList` (`oofnd/PListGet.hpp` has the C++ table and the full semantics).

## Migrating NSString category calls (oo::str)

> **History (ADR-0055).** This recipe is kept as the record of what the sweep beads did. Its
> header, `src/Core/OOStringBridge.h`, was deleted by oo-qps.16; do not recreate it or import it. Code written today holds
> C++ values: call `oo::str` on the `std::string` directly (the table in `String.hpp`'s banner),
> with no `oo::StdString` / `oo::StringMap` / `oo::NSStringFrom` around it.

The recipe for a file's `NSStringOOExtensions` / `NSString (OOUtilities)` calls (seam 2.5b, bead
oo-dps; proposed [ADR-0034](../../../../docs/decisions/0034-oofnd-strings.md)); exemplar
`src/Core/OOOXZManager.mm`. The file keeps its `NSString`s; each call goes through the bridge in
`src/Core/OOStringBridge.h`.

1. **Import** (history). The bead swapped the file's `NSStringOOExtensions.h` import for the
   string bridge header, `OOStringBridge.h`, or added the bridge header after its last import when
   the call came through `OOStringParsing.h` (kept if the file used anything else from it).
2. **Rewrite each call** (the table is in `String.hpp`'s banner):

   | Objective-C | becomes |
   |---|---|
   | `x = [s stringByTrimmingLeadingWhitespaceAndNewlineCharacters]` | `x = oo::StringMap(s, oo::str::trimLeadingWhitespaceAndNewlines)` |
   | `x = [s stringByTrimmingTrailingWhitespaceAndNewlineCharacters]` | `x = oo::StringMap(s, oo::str::trimTrailingWhitespaceAndNewlines)` |
   | `[s pathHasExtension:e]` (e ASCII) | `(s != nil && oo::str::pathHasExtension(oo::StdString(s), oo::StdString(e)))` |
   | `[s oo_hash]` | `(s != nil ? oo::str::ooHash(oo::StdString(s)) : 0)` |
   | `OOTabString(n)` | `oo::NSStringFrom(oo::str::tabString(n))` |

   **nil is the one trap.** Messaging nil answers nil / 0 / NO, but `oo::StdString(nil)` is `""`,
   and `oo::str` of `""` is not always zero (`ooHash("")` is 5381). `oo::StringMap` keeps nil for
   `NSString` -> `NSString` methods; for any other result, test the receiver as the table does.
3. **Leave alone:** everything else in the file, and methods not in the table (`%@` formatting
   waits for Logging, oo-qpb; `+stringWithContentsOfUnicodeFile:` is `oo::str::stringWithContentsOfUnicodeFile` in `Encoding.hpp`).
4. **Check:** the file no longer names a category method, `tools/tier-a.sh <file>` passes, and
   the goldens still verify.

When the Foundation sweep turns the file's strings into `std::string`, `oo::StringMap(s, f)`
becomes `f(s)` and the bridge header goes. Performance rule from the decision-4 benchmark
([2-string-benchmark.md](../../../../docs/phases/2-string-benchmark.md)): where Objective-C
retained a string, take `std::string_view` / `const std::string&` or move; copy only where it copied.

## Migrating NSScanner / NSCharacterSet calls (oo::str::Scanner)

> **History (ADR-0055).** This recipe is kept as the record of what the sweep beads did. Its
> header, `src/Core/OOStringBridge.h`, was deleted by oo-qps.16; do not recreate it or import it. Code written today holds
> C++ values: `#include "oofnd/Scanner.hpp"` and construct `oo::str::Scanner` from the
> `std::string` itself.

The recipe for the `NSScanner` / `NSCharacterSet` chunk beads (bead oo-3rb.12; proposed
[ADR-0039](../../../../docs/decisions/0039-oofnd-scanner.md)); exemplars `src/Core/OOColor.mm`,
`src/Core/OORoleSet.mm`, `src/Core/OOStringParsing.mm`. The file keeps its `NSString`s and bridges
per call (`OOStringBridge.h`).

1. **Include** (history) the string bridge header, `OOStringBridge.h`, and `#include "oofnd/Scanner.hpp"`
   after the last import. Today only the `Scanner.hpp` include remains.
2. **Rewrite each call** (the full table is in `Scanner.hpp`'s banner):

   | Objective-C | becomes |
   |---|---|
   | `NSScanner *sc = [NSScanner scannerWithString:s];` | `oo::str::Scanner sc(oo::StdString(s));` |
   | `[sc scanFloat:&f]` / `scanInt:` / `scanDouble:` / `isAtEnd` | `sc.scanFloat(&f)` / `scanInt` / `scanDouble` / `isAtEnd()` |
   | `[sc scanString:@"x" intoString:NULL]` | `sc.scanString("x")` |
   | `[sc scanUpToString:@"x" intoString:&r]` | `std::string t; if (sc.scanUpToString("x", &t)) r = oo::NSStringFrom(t);` |
   | `[NSCharacterSet whitespaceCharacterSet]` (and the other named sets) | `oo::str::CharacterSet::whitespace()` ... |
   | `[NSCharacterSet characterSetWithCharactersInString:@"ab"]` / `[set invertedSet]` | `oo::str::CharacterSet::fromCharacters("ab")` / `set.inverted()` |
   | `x = [s stringByTrimmingCharactersInSet:set]` | `x = oo::StringMap(s, [&](std::string_view v) { return oo::str::trim(v, set); })` |
   | `[s rangeOfCharacterFromSet:set].location == NSNotFound` | `oo::str::findFirstOf(oo::StdString(s), set) == std::string_view::npos` |
   | `[s rangeOfCharacterFromSet:set options:NSLiteralSearch range:r].location` (r to the end) | `oo::str::findFirstOf(oo::StdString(s), set, r.location)` |
   | `[set longCharacterIsMember:[s characterAtIndex:i]]` | `set.contains([s characterAtIndex:i])` |

   An `intoString:` target is assigned only when the scan succeeds, as before. A `static
   NSCharacterSet *` cache becomes a local `const oo::str::CharacterSet` (construction is cheap).
3. **nil:** `[NSScanner scannerWithString:nil]` scanned as an empty string (and GNUstep logged
   "Scanner initialised with nil string", which is not reproduced: ADR-0039); `oo::StdString(nil)`
   is `""`, so a scanner needs no nil test. A trim or find on a nil receiver still needs one
   (`StringMap` keeps nil; `findFirstOf` of `""` is npos where messaging nil gave location 0).
4. **Check:** the file no longer names `NSScanner`/`NSCharacterSet`, `tools/tier-a.sh <file>`
   passes, and the goldens verify.

## Migrating OOLog calls (oo::log)

The recipe for converting a file's `OOLog` family to the std::format front end (seam 2.8, bead
oo-qpb; proposed [ADR-0035](../../../../docs/decisions/0035-oofnd-logging.md)); exemplar
`src/SDL/OOSDLJoystickManager.mm`. Settings, indentation and line layout are shared with the
remaining `OOLog` calls, so a converted line reads exactly as it did.

1. **Include** `"oofnd/Log.hpp"` (replacing `#import "OOLogging.h"` if the file imports it).
2. **Rewrite each call:** `OOLog(@"cls", @"fmt", args)` -> `OO_LOG("cls", "fmt'", args')`, and
   `OOLogERR`/`OOLogWARN` -> `OO_LOG_ERR`/`OO_LOG_WARN`. The class is a string literal (a key
   constant is a `std::string_view` since ADR-0055 item 6, and passes as `std::string(kConstant)`).
   Conversions: `%d %i %ld %lld` -> `{}`; `%u %lu %llu %zu` -> `{}` and `%x` -> `{:x}`, **with the
   argument cast to the unsigned type the conversion read** if it is signed (`printf` reinterprets
   `-1` as `4294967295` / `ffffffff`; std::format prints the argument's own value); `%c` -> `{:c}`
   with a `char` argument; `%f` -> `{:f}`; `%.Nf` -> `{:.Nf}`; `%g` -> `{:g}`; `%s` -> `{}` (never
   with a null pointer: `%s` printed `(null)`); `%%` -> `%`; a literal `{` or `}` -> `{{` / `}}`;
   `%@` of an `NSString *` -> `{}` with `oo::StdString(x)`, **but only if x cannot be nil**
   (`%@` printed nil as `(null)`, `oo::StdString(nil)` is empty).
3. **Leave alone:** `%@` of anything but an `NSString` (its `-description` has no oo::log form
   yet), `OOLogWithArguments`, and every other line.
4. **Check:** `tools/tier-a.sh <file>` passes and the goldens verify.

## Migrating Foundation usage (sweep:foundation)

The recipe for every `sweep:foundation` bead ("Migrate Foundation usage to oofnd: <file>"). Proposed
[ADR-0043](../../../../docs/decisions/0043-foundation-sweep-recipe.md). Exemplars, one per early
module; open the one nearest your file and do what it does:

| Exemplar | Bead | Shows |
|---|---|---|
| `src/Core/OOVector.mm` / `.h` | oo-g7k5 | a C function returning a string; a header reached inside `extern "C"`; callers wrapped at the call |
| `src/Core/OORoleSet.mm` / `.h` | oo-hi38 | collections as std containers, `std::optional` results, unique and shared selectors, `-description` -> `-cxx_descriptionComponents` (OODescription.h), sorting, four callers adapted |
| `src/Core/Materials/OOBasicMaterial.mm` / `.h` | oo-ro7q | a class whose every NS-typed selector is shared: `id` at the boundary, a nil-able string ivar |
| `src/Core/Materials/OOMultiTextureMaterial.mm` / `.h` | oo-vpbt | a mixed configuration as `oo::PList`: read, copied minus two keys, handed on exactly |
| `src/Core/OOALSoundDecoder.mm` / `.h` | oo-oz2y | path components (`oo::str::pathComponents` & co.), a private dictionary as `std::optional<std::map>`, `-description` with a dictionary |

The class stays Objective-C. The file and its header end with no Foundation class name the
acceptance grep matches (comments included), the whole tree builds, and the game behaves the same.

### 0. Size it before you edit

1. `python3 tools/check-selector-types.py <file.h>` prints every method as `unique` or `shared`
   (declared by another class or protocol, in the tree or in Foundation). Only `unique` selectors
   and C functions change their types; `shared` ones keep an Objective-C object type (step 3).
2. For each `unique` selector and C function whose declaration names an NS type, find its direct
   callers: `grep -rn 'firstPartOfSelector:' upstream/oolite/src` (or the function name).
3. If your file, your header and those callers exceed 8 files: use a **transitional bridge**
   (step 6) instead of adapting the callers. If the file's own migration exceeds ~400 written
   lines even with a bridge, stop and report (the orchestrator splits it by selector group).
4. If the header declares a category on a Foundation class (`@interface NSString (OOExtensions)`),
   or a subclass of one (`: NSEnumerator`), this is not a sweep: step 7.

### 1. Types

Use `oofnd/StdLib.hpp` for standard containers (never `<vector>` directly: OOCocoa.h's
`true`/`false` macros), `oofnd/String.hpp` for `oo::str`, `oofnd/PList.hpp` for `oo::PList`,
`oofnd/objc/OOObjCRef.h` for `oo::ObjCRef`, a C++ `oo::PListForeign` for an object inside a
property list (the Objective-C object's node, `Core/OOObjCPList.h`'s `oo::PListObject` & co., went with
bead oo-4aq6a.5), and
`oo::DescriptionOf` (`Core/OODescription.h`, imported by `OOCocoa.h`) for `%@` text. The boundary
helpers this step used to name (`oo::StdString`, `oo::NSStringFrom`, `oo::NSStringOrNil`,
`oo::NSArrayFromStrings` & co.) lived in `OOFoundationBridge.h` / `OOStringBridge.h`, deleted by
oo-qps.16 (ADR-0055): where the tables below still name them they are history, and the forms that
replace them are in "The last Foundation boundaries (ADR-0055)".

| Foundation | inside the file (ivars, locals, statics) | parameter of a unique selector / C function | result of a unique **method** (receiver may be nil) | result of a C function |
|---|---|---|---|---|
| `NSString *` | `std::string`; `std::optional<std::string>` if nil and `@""` behave differently | `const std::string &` | `std::optional<std::string>` | `std::string` |
| `NSMutableString *` | `std::string` (`+=`, `oo::str::format`) | `std::string &` | as `NSString *` | as `NSString *` |
| `NSArray *` of strings / numbers | `std::vector<std::string>` / `std::vector<float>` ... | `const std::vector<...> &` | `std::vector<...>` | `std::vector<...>` |
| `NSArray *` of objects | `std::vector<oo::ObjCRef<OOFoo *>>` | `const std::vector<oo::ObjCRef<OOFoo *>> &` | `std::vector<oo::ObjCRef<OOFoo *>>` | same |
| `NSDictionary *` of plist data, or a configuration that also holds live objects (colours, textures, NSNull) or floats | `oo::PList` (a Dict; objects are `Object` nodes, floats single reals) | `const oo::PList &` | `oo::PList` (null = nil) | `oo::PList` |
| `NSDictionary *` string -> value | `std::map<std::string, V, std::less<>>` | `const std::map<...> &` | `std::optional<std::map<...>>` | `std::map<...>` |
| `NSDictionary *` string -> object | `std::map<std::string, oo::ObjCRef<OOFoo *>, std::less<>>` | as above | `std::optional<std::map<...>>` | `std::map<...>` |
| `NSSet *` of strings | `std::set<std::string>` or a sorted `std::vector<std::string>` | `const std::vector<std::string> &` | `std::vector<std::string>` (sorted) | same |
| `NSSet *` of objects (identity) | `std::vector<oo::ObjCRef<OOFoo *>>` + `std::find` | as `NSArray` | as `NSArray` | as `NSArray` |
| `NSNumber *` | the scalar it held (`float`, `int`, `BOOL`) | the scalar | the scalar | the scalar |
| `NSData *` | `oo::Data` | `const oo::Data &` | `oo::Data` (empty = nil) | `oo::Data` |

**Why methods differ from C functions.** A message to nil returns zero-filled storage. That is a
valid empty `std::vector`, a disengaged `std::optional`, a null `oo::ObjCRef` or `oo::PList`; it is
**not** a valid `std::string` (copying it crashes) or `std::map`. So a method never returns
`std::string`, `std::map`, `std::set` or a reference; it returns them inside `std::optional`.

| Foundation idiom | becomes |
|---|---|
| `foreach (x, array)`, `foreachkey (k, dict)`, `NSEnumerator`, `for (x in y)` | range-for: `for (const auto &x : v)`, `for (const auto &[k, v] : map)` |
| `[a count]`, `[a objectAtIndex:i]`, `[d objectForKey:k]`, `[d setObject:v forKey:k]` | `.size()`, `[i]`, `find`, `m[k] = v` |
| `[[d mutableCopy] autorelease]`, `[a copy]` | a value copy |
| `[a isEqual:b]` (two collections) / `[d hash]` | `a == b` / `d.size()` (GNUstep hashes a dictionary to its count) |
| `@"..."` that feeds a `std::string` | `"..."` |
| `[NSString stringWithFormat:f, ...]` / `-appendFormat:` without `%@` | `oo::str::format(f, ...)` / `s += oo::str::format(...)` |
| `%@` of a string you now hold as `std::string`, inside `oo::str::format` | `%s` with `s.c_str()` |
| `%@` of an object, inside `oo::str::format` | `%s` with `oo::DescriptionOf(obj).c_str()` (`(null)` for nil, as `%@` printed) |
| `OOLog(...)` argument that is now a `std::string` | keep `%@`, pass `oo::NSStringFrom(s)` (`oo::NSStringOrNil(opt)` if it can be nil). Converting to `OO_LOG` is the OOLog recipe's job, not this one's |
| `NSString` methods and categories | `oo::str` (the table in `String.hpp`), including `oo::str::compare` / `caseInsensitiveCompare` |
| `sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)` | `std::stable_sort(v.begin(), v.end(), [](auto &a, auto &b) { return oo::str::caseInsensitiveCompare(a, b) < 0; })` |
| `[x isKindOfClass:[NSString class]]` (& NSArray/NSDictionary/NSSet/NSNumber/NSData) | `oo::IsNSString(x)` (& co.) |
| `ScanTokensFromString(s)` | `oo::str::tokens(s)` |
| `NSScanner -scanFloat:` / `-scanDouble:` on a string you hold | `oo::plist_get::scanDouble(oo::utf8ToUtf16(s), &d)` (the NSScanner port; narrow for float) |
| `-pathComponents`, `+pathWithComponents:`, `-lastPathComponent`, `-stringByDeletingLastPathComponent`, `-stringByAppendingPathComponent:c` | `oo::str::pathComponents(s)`, `pathWithComponents(v)`, `lastPathComponent(s)`, `deletingLastPathComponent(s)`, `appendingPathComponent(s, c)` (GNUstep's Windows rules; `c` is one component) |
| `-stringByAppendingPathExtension:e` | `oo::str::appendingPathExtension(s, e)` (GNUstep's Windows rules: trailing `/` and `\` dropped; an empty or bare-root path — `/`, `C:`, `~` — comes back unchanged, without GNUstep's "cannot append extension" log line; pinned by `tests/unit/oofnd/test_string_path_extension.cpp`, bead oo-3rb.327). Never write a file-local copy |
| `%p` in a format string | `%s` with `oo::str::pointerDescription(p).c_str()` (GNUstep's text: low 32 bits, `(null)`) |
| `[s UTF8String]` to hand a path to a C API | `s.c_str()` |
| `OOCommodityType` (a typedef of `NSString *`) | `std::string`; never name the typedef in a migrated file (also `OOALStringRef` & co.) |

Leave alone: `NSInteger`/`NSUInteger`/`NSRange`/`NSNotFound` (they stay, ADR-0029), and the other
Foundation families (`NSScanner`, `NSNotification`, `NSDate`, `NSValue`, `NSException`...), which
have their own beads, unless one forces a matched NS name into your file.

### 2. Unique selectors and C functions

Change the declaration in the header and the definition in the `.mm` per the table, then adapt each
direct caller **at the call expression only**, in the same commit:

| the caller has | and calls your | write |
|---|---|---|
| `NSString *s` | `const std::string &` parameter | `oo::StdString(s)` (nil arrives as `""`) |
| `@"lit"` | `const std::string &` parameter | `"lit"` |
| use of the result as `NSString *` | `std::optional<std::string>` / `std::string` result | `oo::NSStringOrNil([x foo])` / `oo::NSStringFrom(Foo())` |
| use of the result as `NSArray *` of strings | `std::vector<std::string>` | `oo::NSArrayFromStrings(...)` |
| use of the result as a dictionary of numbers | `std::optional<std::map<std::string, float>>` | build it in the caller's own Foundation code: `for (const auto &[k, v] : *m) [d setObject:[NSNumber numberWithFloat:v] forKey:oo::NSStringFrom(k)];` (the exact NSNumber type the old code stored) |
| a nil receiver whose nil result mattered (e.g. handed to JavaScript, where nil is not `[]`) | any collection result | test the receiver: `r != nil ? oo::NSArrayFromStrings([r foo]) : nil` (`OOJSShip.mm`, `kShip_roles`) |

(History: the bead also added the bridge header, `OOFoundationBridge.h` or `OOStringBridge.h`, after
the caller's last import; both are deleted (ADR-0055), and a caller today holds C++ values.) Change
nothing else in the caller. A caller whose own bead has landed already holds C++ values: pass them
directly.

A header reached inside `extern "C"` (the `OOMaths.h` family) wraps its C++ declarations in
`extern "C++" { ... }`, as `OOVector.h` does; the same goes for an `#include` of a C++ header (an
oofnd `.hpp`, `oofnd/StdLib.hpp`) from such a header: `#ifdef __cplusplus` / `extern "C++" {
#include "..." }` / `#endif`, the idiom `OOCocoa.h` and `OOLogging.h` use.

### 3. Shared selectors

For each `shared` selector, every parameter or result that was an NS type becomes `id` and nothing
else about the selector changes: callers, subclasses and the other classes in the family are
untouched. Inside, convert with the bridge (`oo::StdString(x)`, `oo::OptionalString(x)`,
`oo::NSStringOrNil(opt)`, `oo::StringsFrom(set)`, `oo::NSSetFromObjects(refs)`,
`oo::ObjectFromPList(plist)` ...). Mark the declaration `// shared selector (proposed ADR-0043)`.
Root-class selectors are shared by construction: `-description`, `-descriptionComponents`,
`-shortDescriptionComponents`, `-copyWithZone:`, `-isEqual:`, `-hash`, the JavaScript glue.

- A `-description` whose format is exactly `@"<%@ %p>{%@}", [self class], self, X` is replaced by
  `- (id)descriptionComponents { return <X as an NSString via the bridge>; }`: the root class's
  `-description` prints the same text (`OORoleSet.mm`).
- `id` is for this and nothing else. Never `@[]`, `@{}`, `@()`, a typedef or a macro to keep a
  Foundation value out of the grep's sight. Where the old code built an empty Foundation collection
  for a callee (`[NSDictionary dictionary]`), build it with the bridge
  (`oo::ObjectFromPList(oo::PList(oo::PList::Dict{}))`, `OOBasicMaterial.mm`).

### 4. nil, order, and text

- **nil.** `oo::StdString(nil)` is `""`. Where the file tested a string against nil, returned nil,
  or stored nil, and `@""` would behave differently, carry `std::optional<std::string>`. An empty
  role, key or name may stand for nil only where the old code could never see an empty one (say so
  in the header comment, as `OORoleSet.h` does).
- **Order.** A dictionary or set used to enumerate in hash order; a `std::map` enumerates in byte
  order of the key, a vector in insertion order. Classify every loop over a former dictionary or
  set: order-insensitive (lookup, membership, integer sums, building another map) needs nothing;
  order-sensitive (first match wins, weighted random pick, float accumulation, text or log output,
  the order of random draws) is allowed, but name it in the commit message. The goldens decide.
- **Mixed configurations** (Amendment 2). `oo::PListFrom` keeps any non-plist object as a
  `PList::Object` node and a float as a single-precision real; `oo::ObjectFromPList` gives back the
  same objects and NSNumber types. So a configuration that holds colours, textures or
  placeholders is an `oo::PList` like any other: read it with `get<T>` / `find`, read an object
  with `oo::ObjectIn(*config.find("key"))`, copy it and `erase` keys for a keyed copy, and hand
  it to an unmigrated callee with `oo::ObjectFromPList`. Convert once per method, not per access;
  where two arguments were the same object, convert once and pass the one object twice
  (`OOMultiTextureMaterial.mm`). A float's text: `oo::plist_get::numberStringValue(v)` prints
  it as `%@` did.
- **Text.** Keep every formatted string byte-identical: same format string, same conversions.
  `oo::str::format` is `vsnprintf`, except `%p`: write `%s` with `oo::str::pointerDescription(p)`.
- **Typedefs.** A typedef of a Foundation type (`OOCommodityType`, `OOALStringRef`,
  `OOALDataRef`, `OOALMutableDataRef`, `OOALDictionaryRef`) is that Foundation type: the migrated
  file must not name it. `grep -nE '\b(OOCommodityType|OOAL(String|Data|MutableData|Dictionary)Ref)\b'`
  over your two files prints nothing. The typedef goes with the bead of its last user.

### 5. Check, commit, note

1. The acceptance grep prints nothing.
2. `python3 tools/check-selector-types.py --check` reports 0 families.
3. `tools/build-windows.sh test` succeeds, with no new warning in a file you touched (grep the build
   output for their names; `multiple methods named` anywhere is a stop).
4. `OOLITE_TIER_A_BUDGET=120 tools/tier-a.sh <file.mm>` and the same for every adapted caller.
5. `bash tools/guardrails.sh`.
6. `bash tools/tier-c.sh --only goldens` (after the build): `2 blessed verified`. Mandatory when you
   changed an iteration order or a formatted string.
7. Commit as `bead <id>: ...`, listing the shared selectors kept `id`, the order-sensitive loops, and
   the nil decisions. Put the same three lists in the bead's notes (`bd update <id> --notes`): the
   family beads and the callers' own beads read them.

### 6. Over budget: a transitional bridge

> **History (ADR-0055).** No bridge can be made now: every one was deleted (see "Transitional
> bridges" below), and so was the bridge header they imported. The steps record how they were built.

For a file `X` whose unique Foundation-typed API has too many direct callers (exemplar
`OOColor.mm`):

1. In `X.h` / `X.mm`, give each such method or C function a C++-typed twin named with a **`cxx_`
   prefix** (`+colorFromString:` -> `+cxx_colorFromString:(const std::string &)`,
   `OORGBAComponentsDescription()` -> `cxx_OORGBAComponentsDescription()`), with the types of
   step 1, and delete the old declaration and definition from `X.h` / `X.mm`. Migrate the body.
2. Create `X+FoundationBridge.h`: the banner of `OOColor+FoundationBridge.h` (say which bead made
   it), an include guard, no imports, and a category `@interface X (OOFoundationBridge)` holding
   the old declarations **copied exactly** (same selector names, same types) plus the old C
   function prototypes. Create `X+FoundationBridge.mm`: `#import "X.h"` and
   the boundary helper header, `OOFoundationBridge.h`, and implement each old method by forwarding to its `cxx_`
   twin and converting the result as the old code built it (the same NSNumber type, nil for nil,
   immutable collections).
3. Add `#import "X+FoundationBridge.h"` as the LAST line of `X.h`, under a comment saying it is
   transitional, and add `'X+FoundationBridge.mm'` after `'X.mm'` in the directory's `meson.build`.
4. Callers are untouched. Do not call the bridge from migrated code; never add to a bridge later.
5. Add a row to "Transitional bridges" below, and file its deletion bead:
   `bd create "Delete X+FoundationBridge" -t task -p 2 -l fleet,phase:2,sweep:foundation-bridge`
   with acceptance `! test -e <dir>/X+FoundationBridge.mm`, `! grep -n FoundationBridge <dir>/X.h
   <dir>/meson.build`, `tools/build-windows.sh test`, `bash tools/guardrails.sh`; then
   `bd dep add <deletion> <caller's sweep bead>` for every caller file's open sweep bead, and
   `bd dep add oo-qps <deletion>`.

A caller's own sweep bead replaces `[x foo:s]` with `[x cxx_foo:...]` (C++ values in, C++ values
out). The deletion bead, once `git grep` finds no use of a bridged name outside the bridge, deletes
the two files, the `meson.build` line and the import in `X.h`.

### 7. Categories on Foundation classes, and Foundation subclasses: retire, do not sweep

`@interface NSString (OOExtensions)` and its kind (`NSData`, `NSDictionary`, `NSMutableDictionary`,
`NSNumber`, `NSFileManager`, `OOCollectionExtractors`, `OODeepCopy`, OOCocoa.h's `NSEnumerator`
category) and subclasses of Foundation classes (`OOFilteringEnumerator`,
`OOExcludeObjectEnumerator`) cannot stop naming Foundation while they exist. Their beads wait on
the sweep beads of their callers (the dependency is recorded). The bead is ready when `git grep`
finds none of the category's selectors (or the subclass's name) outside its own files; it then
deletes its `.h` / `.mm`, their `meson.build` line and every `#import` of the header, and nothing
else. Until then, a caller's sweep bead moves off them with:

| retiring | replacement in the caller |
|---|---|
| `NSString (OOExtensions)`, `(OOUtilities)` | `oo::str` (tables above and in `String.hpp`) |
| `NSFileManager (OOExtensions)`, `NSData` file reading | `oo::fs` (`oofnd/FileSystem.hpp`) |
| `NSDictionary` / `NSMutableDictionary (OOExtensions)`, `OOCollectionExtractors` | `oo::PList` / std containers; `get<T>` (the `oo_*ForKey` recipe); `OO{Vector,HPVector,Quaternion}FromObject` / `OOPropertyListFrom*` / `OOFuzzyBooleanFromObject` -> `Core/OOPListGameTypes.h` (`get<Vector>(key, fallback)`, `OOVectorFromPList`, `OOPListFromVector`, `OOFuzzyBooleanFromPList`) |
| `NSNumber (OOExtensions)` | the scalar |
| `OODeepCopy(x)` | a value copy of the `oo::PList` / std container (already deep) |
| `[e objectEnumeratorFilteredWithSelector:@selector(isFoo)]` & co. | `for (const auto &r : v) { if (![r.get() isFoo]) continue; ... }` |
| `[e objectEnumeratorExcludingObject:x]` | `for (const auto &r : v) { if (r.get() == x) continue; ... }` |
| `foreach` / `foreachkey` / `-objectEnumerator` over a std container | range-for |
| `NSUserDefaults (Override)` | retired (oo-iobt): use `oo::Defaults` (ADR-0032) |

### 8. Materials order, chunk beads, C handles (Amendment 2)

- **Materials:** `OOMaterialSpecifier` (done) -> `OOTextureLoader` -> `OOTexture` -> `OOCombinedEmissionMapGenerator` -> the materials -> `OODefaultShaderSynthesizer` -> `OOShaderMaterial` -> `OOMaterialConvenienceCreators`. Specifiers and configurations are `const oo::PList &` in every `cxx_` twin; `cxx_OOMaterial*` (OOMaterialSpecifier.h) replace the `-oo_*Color` / `-oo_*MapSpecifier` category methods.
- **Chunk beads:** a file the orchestrator split (`sweep:foundation-chunk`) is done chunk by chunk, in order; each chunk touches only its listed selectors or body part and has its own acceptance; the parent bead's whole-file grep passes after the last chunk.
- **A C file behind an abstraction layer** keeps its API; the layer's handles become `struct OOALObject *` (ADR-0043 item 14), defined in C++ in the layer's `.mm`.

- **Floats written to disk** (savegames, caches, defaults): build them with `oo::PList::singleReal(f)`, never `oo::PList(double(f))`; the writers then print `%0.7g` as GNUstep did (ADR-0043 item 15). The saved game is written with `oo::writeXMLPList`.
- **An `NSEnumerator` subclass** is replaced by C++ iteration in the owner's bead: range-for over the backing container, or a nested C++ iterator class behind a `cxx_` accessor; a shared `-objectEnumerator` stays `id` and returns `[oo::NSArrayFromObjects(snapshot) objectEnumerator]` (item 16).
- **OOLog:** `OOLogging.h` keeps the `const char *` / `OO_LOG` API; the NSString API lives in `OOLogging+FoundationBridge.h` until every caller has moved (item 17). Do not touch it from a caller's bead; convert your own `OOLog` calls with "Migrating OOLog calls".

- **A format string that is data** (a `DESC(...)` entry, a plist template) goes through `oo::str::formatRuntime(fmt, {args...})`, each argument an `oo::str::FormatArg`: an object's `oo::DescriptionOf(obj)` for `%@`, `FormatArg::null()` for nil, `FormatArg::pointer(p)` for `%p`, numbers as themselves (`FormatArg::single(f)` for a float). Only a literal format uses `oo::str::format` (ADR-0043 item 19; exemplar OOOXPVerifier `-dumpDebugGraphviz`).
- **An error message or comment that names a Foundation class** and that no player, golden or script sees is reworded ("array", "string"), not kept (item 20).

- **Called by name** (item 21): a selector check-selector-types.py marks `called by name` keeps `id` like any shared selector; add a `cxx_` twin for C++ callers.
- **Live containers** (item 22): an accessor whose callers mutate the container becomes a `cxx_` accessor returning a pointer to the owned std container (`nullptr` for nil); never a snapshot.
- **Error/debug logs** (item 23): `%@` of a collection there may print via `oo::writeOldStylePList`; name the change in the commit.

### 9. Worktrees on the fleet machine

`.agents/skills/beads-worker/scripts/worktree.sh <id>` run from MSYS2 records MSYS paths (`/c/Users/...`) in `.git/worktrees/<id>/gitdir`. Git for Windows (and anything it runs, such as an automatic `git gc`) cannot find that path and **prunes the worktree's registration**, after which the checkout is no longer a repository. The durable fix, once per worktree, from MSYS2:

```bash
wt=.worktrees/<id>
cygpath -m "$PWD/$wt/.git" > "$(git rev-parse --git-common-dir)/worktrees/<id>/gitdir"
```

After it, `worktree.sh --remove <id>` run from MSYS2 no longer finds the worktree by its MSYS path: remove it with `git worktree remove` from Git for Windows (or give the `C:/` path). Never `git worktree prune` yourself.

### Transitional bridges

None remain. The last, `src/Core/OOLogOutputHandler+FoundationBridge.h/.mm` (gnustep-base's NSLog
hook, Amendment 2 item 18(a); made by oo-vjts), was deleted by oo-qps.28: whatever gnustep-base
itself NSLogs goes to stderr instead of Latest.log until oo-qps.18 unlinks it.

### Stop and report (do not stretch)

- The file's own migration exceeds ~400 written lines even with a bridge (step 0).
- A shared selector would have to change type (only its family bead may).
- A value you must change is a dictionary holding non-plist objects that a not-yet-migrated callee
  consumes: report the callee as a prerequisite.
- A method result has no zero-valid C++ form, even inside `std::optional`.
- Formatted text you cannot keep byte-identical.
- A Foundation operation with no oofnd equivalent in the tables: report it, name the method; a
  frontier bead adds the helper with captured tests (as `oo::str::pathComponents` was added).
- A golden differs, a test fails, `check-selector-types.py --check` fails, or the build warns about
  `multiple methods named`. Never re-bless, never sort to make a golden match, never edit a test.

When a family's last member has been swept, its **family bead** changes every `id` of that selector
to the C++ type in all declarations and callers at once; the bridges go with gnustep-base (oo-qps).

## The last Foundation boundaries (ADR-0055)

What replaces each bridge helper once gnustep-base leaves the link line. Each seam below is
Foundation-free and is what Phase 3 keeps (it drops the `cxx_` prefix as it converts each call).

### Describing an object: `Core/OODescription.h` (item 1, oo-qps.31)

Imported by `OOCocoa.h`, so no file includes it. A class describes itself by overriding **one**
method on the `OOObject` root; the printers wrap it:

| Override | Printed by | As |
|---|---|---|
| `- (std::optional<std::string>) cxx_descriptionComponents` | `-cxx_description`, `oo::DescriptionOf(x)`, `-cxx_oo_jsDescription` | `<ClassName 0xnnnnnnnn>{components}`; JS `[jsClassName components]` |
| `- (std::optional<std::string>) cxx_shortDescriptionComponents` | `-cxx_shortDescription`, `oo::ShortDescriptionOf(x)` | `<ClassName 0xnnnnnnnn>{components}` |
| `- (std::optional<std::string>) cxx_description` (rare: the whole text) | `oo::DescriptionOf(x)` | whatever it returns |

nullopt means no components (`<ClassName 0xnnnnnnnn>`). A subclass extends its superclass's text with
`[super cxx_descriptionComponents].value_or("(null)")`. Exemplar: `src/Core/OORoleSet.mm`
(`-cxx_descriptionComponents`); the idiom table's `%@ of an object` row is unchanged:
`oo::DescriptionOf(obj)` (`(null)` for nil, a class's name for a class object, the text of a string
literal). `oo::DescriptionOf([x shortDescription])` is `oo::ShortDescriptionOf(x)`.

Transitional, until oo-qps.43 flips the legacy family tree-wide in one codemod commit
(`python3 tools/codemods/description-family.py --fix upstream/oolite/src`, then `--check` for the
hand residue) and deletes the legacy root in `OOCocoa.h/.mm`: the root's `cxx_` defaults forward to a
legacy `- (id) descriptionComponents` (& co.) override while a class has one, and `oo::DescriptionOf`
of an object not rooted on `OOObject` asks its `-description` (oo-qps.72 deletes both). Do not flip
one class's override by hand before oo-qps.43: a converted superclass hides an unconverted
subclass's override (the exemplar has no subclass).

Since oo-8sql7 the root has no description category: the four methods are the `@optional` protocol
`OODescription`, and an object whose class has no method of its own gets the root's default from the
C++ functions `oo::ObjectDescription`, `oo::ObjectShortDescription`, `oo::ObjectDescriptionComponents`
and `oo::ObjectShortDescriptionComponents` (what the deleted category answered; nullopt for nil).
Send none of the four to an object directly; ask those functions. `tests/unit/oofnd/test_objc_plist.mm`
links `OODescription.mm` against libobjc2 alone.

### Describing a property list: `oo::DescriptionOf(const oo::PList &)` (item 1, oo-qps.32)

`oo::DescriptionOf(oo::ObjectFromPList(v))` is `oo::DescriptionOf(v)`: the `OODescription.h` overload
forwards to `oo::describe` (`oofnd/PListDescription.hpp`), which prints what gnustep-base's
`-description` printed (`(a, "two words", 1)`, `{key = value; }`, keys by `-compare:`, strings
quoted and escaped as GNUstep did). Exemplar: `src/Core/Entities/OOVisualEffectEntity.mm`
(`setUpOneStandardSubentity:`). The text is pinned by `tests/unit/oofnd/test_plist_description.cpp`
against `plist_description_captured.inc`, captured from GNUstep base 1.31.1; to add a case, add a
line to `tools/captures/plist-description/cases.txt` and rerun
`bash tools/captures/plist-description/capture.sh` (needs gnustep-base installed, also after
oo-qps.18; `--check` compares without writing). Dates print in the local time zone, as NSDate did
(`oo::date::description`); the capture runs with TZ=UTC and the test describes at offset 0.

### Calling a method by name: `Core/OOCallByName.h` (item 5, oo-qps.34)

A dispatcher that runs a method named in data (an AI action, a legacy-script action or query, a
HUD dial, a deferred call) calls `OOCallByName(target, selector [, argument])` instead of
`-performSelector:withObject:`, and the method it names has one of the dispatcher's C++ signatures:
`- (void|oo::PList) sel`, `- (void|oo::PList) sel:(const std::string &)s`, or
`- (void) sel:(const oo::PList &)p` (the table is in the header). Exemplar: `src/Core/AI.mm`
(`-cxx_takeAction:`, the `interpretAIMessage:` message, the deferred-call trampoline and its
`-deferredSetState:(const std::string &)`). To flip a called-by-name method, give it one of those
signatures in every declaring class at once (the family rule); `python3 tools/check-selector-types.py --check`
accepts exactly those and the transitional `id` form, and `--strict-called-by-name` (oo-qps.72)
rejects the `id` form. Until then OOCallByName bridges an `id`-typed method's argument and result,
so selectors flip file by file. `OOCallByName.mm` (the call on an Objective-C object) and its test,
`test_objc_call_by_name.mm`, were deleted by bead oo-6e1.2; the entity call (`OOEntityCalledByName.mm`) keeps
the signatures.

## Testing

From the repo root, in the MSYS2 UCRT64 shell:

```bash
bash tools/check-oofnd.sh      # no build dir needed; ~10 s. The bead acceptance.
```

It compiles every header alone and together (the canary TU, also under `-fno-exceptions`), then
builds and runs every `tests/unit/oofnd/test_*.cpp` at `-std=c++20 -Wall -Wextra -Werror`, then
again under AddressSanitizer. It fails on zero tests and on a test file missing from
`tests/unit/oofnd/meson.build`.

Inside a game build directory the same tests run through meson:

```bash
cd upstream/oolite && ./mk.sh build test
meson test -C build/meson_test --suite oofnd
```

Objective-C++ game code builds as `gnu++20` and sees OOCocoa.h's `#define true 1` / `#define false 0`:
a header that game code includes must suspend them with `#pragma push_macro`/`pop_macro` as
`Data.hpp` does (ADR-0028; `tests/unit/oofnd/test_cocoa_macros.cpp` checks it).

Adding a component: put `Foo.hpp` here, write `tests/unit/oofnd/test_foo.cpp` ending in
`OO_TEST_MAIN()`, and add `'test_foo'` to `tests/unit/oofnd/meson.build`.
