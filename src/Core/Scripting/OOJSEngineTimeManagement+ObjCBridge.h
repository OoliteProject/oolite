/*

OOJSEngineTimeManagement+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-cn4o): the Objective-C OOTimeProfile and
OOTimeProfileEntry, facades over the C++ cxx::OOTimeProfile and cxx::OOTimeProfileEntry
(OOJSEngineTimeManagement.h), for what is not converted yet: the debug console, which holds the
profile OOJSEndProfiling() returns (+1) and describes it or converts it to JavaScript, and the
engine, which converts a profile and each entry in its "profiles" list through
-oo_jsValueInContext:. Their interfaces are the ones OOJSEngineTimeManagement.h declared before the
conversion, copied exactly (same selectors and types; the ivar is the C++ object), plus the two
OOObject overrides they had (-cxx_description, -oo_jsValueInContext:). Imported as the last line
of OOJSEngineTimeManagement.h; do not import it directly.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  -------------------------
        still Objective-C                      OOTimeProfile(Entry) *          nothing: messages as before
        converted (C++)                        oo::Ref<cxx::OOTimeProfile(Entry)>
          handing one to Objective-C                                            oo::ToObjC(profile)
          taking one from Objective-C                                           oo::ToCxx(objcProfile)

oo::ToObjC gives an object's one live facade (oo::ObjCPeers), or a new one. Never add to this file;
converted code does not message the facades. Deleted by its deletion bead once the debug console
and the engine's object conversion are C++.


Copyright (C) 2010-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#ifndef OOJSENGINETIMEMANAGEMENT_OBJCBRIDGE_H
#define OOJSENGINETIMEMANAGEMENT_OBJCBRIDGE_H

#if OOJS_PROFILE

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@interface OOTimeProfile : OOObject {
@private
    oo::Ref<cxx::OOTimeProfile> _cxxProfile;
}

- (double)totalTime;
- (double)javaScriptTime;
- (double)nativeTime;
- (double)extensionTime;
- (double)nonExtensionTime;
- (double)profilerOverhead;

- (std::vector<oo::ObjCRef<OOTimeProfileEntry*>>)profileEntries; // sorted by self time, longest first

@end

@interface OOTimeProfileEntry : OOObject {
@private
    oo::Ref<cxx::OOTimeProfileEntry> _cxxEntry;
}

- (std::optional<std::string>)cxx_description;

- (std::optional<std::string>)cxx_function; // nullopt: none (bead oo-3rb.291.3)
- (NSUInteger)hitCount;
- (double)totalTimeSum;
- (double)selfTimeSum;
- (double)totalTimeAverage;
- (double)selfTimeAverage;
- (double)totalTimeMax;
- (double)selfTimeMax;
- (BOOL)isJavaScriptFrame;

- (OOComparisonResult)compareByTotalTime:(OOTimeProfileEntry*)other;
- (OOComparisonResult)compareByTotalTimeReverse:(OOTimeProfileEntry*)other;
- (OOComparisonResult)compareBySelfTime:(OOTimeProfileEntry*)other;
- (OOComparisonResult)compareBySelfTimeReverse:(OOTimeProfileEntry*)other;

@end

namespace oo {

// An object's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
::OOTimeProfile* ToObjC(cxx::OOTimeProfile* profile);
::OOTimeProfileEntry* ToObjC(cxx::OOTimeProfileEntry* entry);

// The C++ object behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOTimeProfile* ToCxx(::OOTimeProfile* profile);
cxx::OOTimeProfileEntry* ToCxx(::OOTimeProfileEntry* entry);

} // namespace oo

#endif // OOJS_PROFILE

#endif // OOJSENGINETIMEMANAGEMENT_OBJCBRIDGE_H
