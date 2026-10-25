/*

OORegExpMatcher.h

Regular expression utility built on top of JavaScript regexp objects in lieu
of Objective-C regexp support. Not thread-safe.

If we had a performance-critical need for regexps, I'd want a real library,
but this will do for light usage.

C++20 since bead oo-ct7c (proposed ADR-0056). Its Objective-C facade was deleted by bead
oo-9ht.12 (ADR-0056 amendment "deleting a facade"): the class is global, and a caller that wants
one matcher across several matches holds the Ref (amendment oo-ct7c item 3).


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

#include "OOCocoa.h"
#include "oofnd/Ref.hpp"
#include "ooscript/JSEngine.hpp"
#include "oofnd/StdLib.hpp"
#include "OOJSFunction.h"
#include "OOJSEngineCore.h"	// OOJSValue, which the matcher holds


enum
{
	kOORegExpCaseInsensitive	= ooscript::RegExpFoldCase,
	kOORegExpMultiLine			= ooscript::RegExpMultiline
};


class OORegExpMatcher : public oo::RefCounted
{
public:
	/*	Pseudo-singleton: a single instance exists at a given time, but can be released. While
		one is alive (held by a Ref) this returns it; otherwise a new one. Null if the tester
		function could not be compiled.
	*/
	static oo::Ref<OORegExpMatcher> regExpMatcher();

	// Strings are UTF-8 (Foundation sweep, proposed ADR-0043). The Objective-C string category
	// -oo_matchesRegularExpression: was [[OORegExpMatcher regExpMatcher] string:self matchesExpression:regExp];
	// its callers now send that message themselves.
	bool string(const std::string &string, const std::string &regExp);
	bool string(const std::string &string, const std::string &regExp, NSUInteger flags);

	~OORegExpMatcher() override;

private:
	// The old -init, which could fail (proposed ADR-0056 amendment oo-r7m0 item 2): regExpMatcher()
	// calls it right after making the object, and drops the object when it returns false.
	bool init();

	oo::Ref<OOJSFunction>	_tester = {};
	std::optional<std::string>	_cachedRegExpString = {};	// UTF-8; nullopt: nothing cached (proposed ADR-0043)
	oo::Ref<OOJSValue>		_cachedRegExpObject = {};
	NSUInteger				_cachedFlags = {};
};

#endif	// OOREGEXPMATCHER_H
