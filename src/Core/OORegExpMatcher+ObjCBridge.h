/*

OORegExpMatcher+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-ct7c): the Objective-C OORegExpMatcher, a facade over
the C++ cxx::OORegExpMatcher (OORegExpMatcher.h), for callers that are not converted yet (today
OOOpenGLExtensionManager.mm). Its interface is the one OORegExpMatcher.h declared before the
conversion, copied exactly (same selectors, same types), so those callers compile and behave
unchanged; each method forwards to its C++ member. Imported as the last line of
OORegExpMatcher.h; do not import it directly.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  ----------------------------
        still Objective-C                      OORegExpMatcher * (this facade) nothing: messages as before
        converted (C++)                        oo::Ref<cxx::OORegExpMatcher>
          handing a matcher to Objective-C                                      oo::ToObjC(matcher)
          taking one from Objective-C                                           oo::ToCxx(objcMatcher)

oo::ToObjC gives the matcher's one live facade (oo::ObjCPeers), so identity survives a round
trip. The facade +regExpMatcher returns is autoreleased and retains the C++ matcher, so the
matcher lives until the autorelease pool drains, as the autoreleased Objective-C instance did:
the pseudo-singleton keeps its lifetime. Never add to this file; converted code does not message
the facade. Deleted by its deletion bead once no file outside OORegExpMatcher.* names the
Objective-C OORegExpMatcher.


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

#ifndef OOREGEXPMATCHER_OBJCBRIDGE_H
#define OOREGEXPMATCHER_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@interface OORegExpMatcher : OOObject {
@private
    oo::Ref<cxx::OORegExpMatcher> _cxxMatcher;
}

+ (instancetype)regExpMatcher;

// Strings are UTF-8 (Foundation sweep, proposed ADR-0043). The Objective-C string category
// -oo_matchesRegularExpression: was [[OORegExpMatcher regExpMatcher] string:self matchesExpression:regExp];
// its callers now send that message themselves.
- (BOOL)string:(const std::string&)string matchesExpression:(const std::string&)regExp;
- (BOOL)string:(const std::string&)string matchesExpression:(const std::string&)regExp flags:(NSUInteger)flags;

@end

namespace oo {

// The matcher's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OORegExpMatcher* ToObjC(cxx::OORegExpMatcher* matcher);
inline OORegExpMatcher* ToObjC(const Ref<cxx::OORegExpMatcher>& matcher) { return ToObjC(matcher.get()); }

// The C++ matcher behind a facade, borrowed (the facade retains it); null for nil.
cxx::OORegExpMatcher* ToCxx(OORegExpMatcher* matcher);

} // namespace oo

#endif // OOREGEXPMATCHER_OBJCBRIDGE_H
