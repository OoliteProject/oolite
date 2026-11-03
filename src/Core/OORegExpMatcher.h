/*

OORegExpMatcher.h

Regular expression utility built on top of JavaScript regexp objects in lieu
of Objective-C regexp support. Not thread-safe.

If we had a performance-critical need for regexps, I'd want a real library,
but this will do for light usage.

C++20 since bead oo-ct7c (proposed ADR-0056). The class is cxx::OORegExpMatcher while
OORegExpMatcher+ObjCBridge.h, imported at the end of this header, keeps the Objective-C
OORegExpMatcher its unconverted caller (OOOpenGLExtensionManager.mm) messages; the bridge's
deletion bead moves it out of namespace cxx.


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

#ifndef OOREGEXPMATCHER_H
#define OOREGEXPMATCHER_H

#import "OOFoundation.h"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

@class OOJSFunction, OOJSValue;

// Same values as SpiderMonkey's JSREG_FOLD and JSREG_MULTILINE.
enum {
    kOORegExpCaseInsensitive = 0x01,
    kOORegExpMultiLine = 0x04
};

namespace cxx {

class OORegExpMatcher : public oo::RefCounted {
public:
    /*	Pseudo-singleton: a single instance exists at a given time, but can be released. While
            one is alive (held by a Ref, or by its facade until the autorelease pool drains, as the
            autoreleased Objective-C instance was) this returns it; otherwise a new one. Null if the
            tester function could not be compiled.
    */
    static oo::Ref<OORegExpMatcher> regExpMatcher();

    // Strings are UTF-8 (Foundation sweep, proposed ADR-0043). The Objective-C string category
    // -oo_matchesRegularExpression: was [[OORegExpMatcher regExpMatcher] string:self matchesExpression:regExp];
    // its callers now send that message themselves.
    bool string(const std::string& string, const std::string& regExp);
    bool string(const std::string& string, const std::string& regExp, NSUInteger flags);

    ~OORegExpMatcher() override;

private:
    // The old -init, which could fail (proposed ADR-0056 amendment oo-r7m0 item 2): regExpMatcher()
    // calls it right after making the object, and drops the object when it returns false.
    bool init();

    ::OOJSFunction* _tester = { }; // the facade (ADR-0056 amendment oo-rmd7 item 3)
    std::optional<std::string> _cachedRegExpString = { }; // UTF-8; nullopt: nothing cached (proposed ADR-0043)
    OOJSValue* _cachedRegExpObject = { };
    NSUInteger _cachedFlags = { };
};

} // namespace cxx

// Transitional: the Objective-C OORegExpMatcher, for callers not yet converted. Deleted, with
// namespace cxx above, by the bridge's deletion bead.
#import "OORegExpMatcher+ObjCBridge.h"

#endif // OOREGEXPMATCHER_H
