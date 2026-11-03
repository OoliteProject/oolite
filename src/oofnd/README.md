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
| `src/oofnd/Ref.hpp` | `oo::RefCounted`, `oo::Ref<T>`, `oo::WeakRef<T>`, `oo::AutoreleaseScope`: ObjC retain/release/autorelease and `OOWeakReference` 1:1 ([ADR-0003](../../../../docs/decisions/0003-intrusive-refcount.md), [ADR-0026](../../../../docs/decisions/0026-oofnd-ref-semantics.md)); the banner maps each ObjC idiom |
| `src/oofnd/WeakSet.hpp` | `oo::WeakSet<T>`: `OOWeakSet` |
| `src/oofnd/PList.hpp` | `oo::PList`: the property-list value (null/bool/integer/real/string/data/date/array/dict) replacing the Foundation plist object graph; UTF-16 <-> UTF-8 helpers ([ADR-0027](../../../../docs/decisions/0027-oofnd-plist-fidelity.md)) |
| `src/oofnd/PListOldStyle.hpp` | `oo::parseOldStylePList`: GNUstep's old-style (OpenStep) scanner, `parsePlItem`, ported quirk-for-quirk |
| `src/oofnd/PListXML.hpp` | `oo::parseXMLPList` (GNUstep's GSXMLPListParser over GSSloppyXMLParser) and `oo::changeDTDIfApplicable` (OOPListParsing.m), ported quirk-for-quirk |
| `src/oofnd/PListWriting.hpp` | `oo::writeOldStylePList` (OldSchoolPropertyListWriting.m) and `oo::writeXMLPList` (GNUstep's XML writer), byte-identical output |
| `src/oofnd/PListParsing.hpp` | `oo::parsePropertyList`: OOPropertyListFromData's DTD change + format detection + dispatch to the two readers |
| `src/oofnd/PListGet.hpp` | `oo::PList::get<T>(key, fallback)` / `at<T>(index, fallback)`: OOCollectionExtractors' `oo_*ForKey:` / `oo_*AtIndex:` with GNUstep's exact conversions ([ADR-0031](../../../../docs/decisions/0031-plist-get-and-the-foundation-bridge.md)); included by `PList.hpp` |
| `src/Core/OOPListView.h` (game side) | `oo::PListView`: the same `get<T>`/`at<T>` over a Foundation collection, for sweeping `oo_*ForKey` before the containers are `PList`; see below |
| `src/oofnd/Data.hpp` | `oo::Data`: `NSData` / `NSMutableData` as a value type ([ADR-0028](../../../../docs/decisions/0028-oofnd-filesystem-paths-data.md)) |
| `src/oofnd/FileSystem.hpp` | `oo::fs`: `NSFileManager` + its OOExtensions category + NSData file I/O, on `std::filesystem` with GNUstep semantics |
| `src/oofnd/ResourcePaths.hpp` | `oo::ResourcePaths`: the game's Resources/AddOns/saves/logs/caches locations, exactly as computed today on Windows and Linux |
| `src/oofnd/Process.hpp` | `oo::process` + `oo::env`: `NSProcessInfo` (arguments captured in `main`, `hasArgument`, `processName`, `processorCount`, `operatingSystemVersionString`) with GNUstep's measured semantics |
| `src/oofnd/Thread.hpp` | `oo::thread`: `NSThread` on `std::thread`: `detach`, `isMainThread` (id captured at static init), `setCurrentName`, `setCurrentPriority` (GNUstep's measured Windows mapping) |
| `src/oofnd/Defaults.hpp` | `oo::Defaults`: `NSUserDefaults` with `NSUserDefaults+Override`/`NSBundle+Override` as the game runs them: same `GNUstep/Defaults/oolite.plist`, same search list and coercions, `oo::writeOpenStepPList` (GNUstep's OpenStep writer, byte-identical) ([ADR-0032](../../../../docs/decisions/0032-oofnd-defaults.md)) |
| `src/oofnd/objc/OOObject.h`, `.mm` | `OOObject`: the Foundation-free Objective-C root class on libobjc2's own refcount and pool; `OOObjCInstallFloor()` ([ADR-0029](../../../../docs/decisions/0029-objc-floor-without-foundation.md)). Objective-C++, not linked into the game until the reroot bead |
| `src/oofnd/objc/OOObject.h`, `.mm` | `OOObject`: the Foundation-free Objective-C root class on libobjc2's own refcount and pool; `OOObjCInstallFloor()` ([ADR-0029](../../../../docs/decisions/0029-objc-floor-without-foundation.md)). Objective-C++; linked into the game by bead oo-3rb.2 (exemplar reroot: `Core/OORoleSet`), but `OOObjCInstallFloor()` is not called until the constant-string flip |
| `src/oofnd/objc/OOConstantString.h`, `.mm` | `OOConstantString`/`OOTinyString`: the classes behind `@"..."` under `-fconstant-string-class=OOConstantString` (ADR-0029) |
| `src/oofnd/objc/OORuntime.h` | `OOClassFromName`/`OOClassName`/`OOSelectorFromName`/`OOSelectorName`/`OOSelectorsEqual`: `NSClassFromString` & co. on the libobjc2 calls GNUstep makes, UTF-8 in and out; header-only |
| `src/oofnd/objc/OOException.h`, `.mm` | `OOException`: `NSException` without Foundation; `@try`/`@catch` stay Objective-C (ADR-0029 Decision 4). `+raise:format:` is printf-style; `OOInvalidArgumentException` & co. are `const char *` with Foundation's text |
| `src/oofnd/objc/OOFoundationTypes.h` | Foundation's C types (`NSInteger`/`NSUInteger`, `NSRange`, `NSNotFound`, `NSPoint`/`NSSize`/`NSRect`, `NSMake*`, `NSEqual*`, `NSTimeInterval`, `CGFloat`) with GNUstep's exact definitions and names (ADR-0029 Decision 5); refuses to compile beside Foundation, so OOCocoa.h includes it only from oo-qps. Pinned by `tests/unit/oofnd/test_foundation_types.cpp` |
| `src/oofnd/meson.build` | `oofnd_dep` (include path `src/`, so consumers write `#include "oofnd/X.hpp"`) |
| `tests/unit/oofnd/test_*.cpp` | one executable per component, plain C++20 |
| `tests/unit/oofnd/oo_test.hpp` | the whole test harness: `OO_TEST`, `OO_CHECK`, `OO_CHECK_EQ`, `OO_TEST_MAIN` |
| `tests/unit/oofnd/plist_dump.hpp` | canonical one-line dump of a `PList`, the format the PList tests' GNUstep-captured expectations are written in |
| `tests/unit/oofnd/test_*.mm` | Objective-C++ tests of `src/oofnd/objc`, linked against libobjc2 alone; `tools/check-oofnd-objc.sh` builds them and proves the import table has no gnustep-base |
| `tests/unit/oofnd/meson.build` | registers each test in `meson test --suite oofnd` |

## Migrating oo_*ForKey

The recipe for every `sweep:extractors` bead ("Retire oo_*ForKey in <file>"). Proposed
[ADR-0031](../../../../docs/decisions/0031-plist-get-and-the-foundation-bridge.md); exemplar
`src/Core/Entities/OOWaypointEntity.mm` (bead oo-u77) - open it and do what it does.

The file keeps its Foundation collections. Each call goes through `oo::PListView`
(`src/Core/OOPListView.h`), a zero-copy view with `oo::PList`'s `get<T>`/`at<T>` API that performs
the same lookup and calls the same conversion function as the category method it replaces, so the
change is behaviour-preserving by construction. Do exactly this, nothing else:

1. **Import.** Replace `#import "OOCollectionExtractors.h"` with `#import "OOPListView.h"` (the view
   imports it, so nothing is lost). If the file has no such import, add `#import "OOPListView.h"`
   after its last `#import`.
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
