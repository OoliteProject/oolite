/*

OOJSTimer.h

JavaScript timer class.

C++20 since bead oo-kdyh (proposed ADR-0056; amendment oo-ppc for the binding), converted with
its superclass OOScriptTimer. OOJSTimer has no caller outside OOJSTimer.mm, and since bead
oo-6symp a Timer's private slot holds it (OOJSPrivateObject.h). Its own facade was deleted by bead
oo-9ht.37 (ADR-0056 amendment oo-9ht.37): the timer queue and Objective-C code hold the root's
OOScriptTimer facade, which answers the JS glue selectors (-oo_jsValueInContext:,
-cxx_oo_jsClassName) for it and describes it as "<OOJSTimer 0x...>" (className()).


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

#ifndef OOJSTIMER_H
#define OOJSTIMER_H

#include "OOScriptTimer.h"
#include "ooscript/JSEngine.hpp"
#include "OOJSPrivateObject.h"

class OOJSScript;


// A Timer JS object's private slot holds the timer (proposed ADR-0056 amendment oo-6symp).
class OOJSTimer : public OOScriptTimer, public ::OOJSPrivateObject
{
public:
	// [[OOJSTimer alloc] initWithDelay:interval:context:function:this:], for the Timer
	// constructor: null where the initialiser answered nil.
	static oo::Ref<OOJSTimer> timerWithDelay(OOTimeAbsolute delay, OOTimeDelta interval, ooscript::Context context, ooscript::Value function, ooscript::Object jsThis);

	~OOJSTimer() override;

	std::optional<std::string> descriptionComponents() const override;
	std::string className() const override	{ return "OOJSTimer"; }
	std::optional<std::string> oo_jsClassName() override;

	void timerFired() override;

	// The JS glue (OOJSPrivateObject): the Timer object, made by the initialiser; forgetting it
	// when it is finalized, with a warning if the timer still runs; "[Timer <components>]".
	ooscript::Value jsValueInContext(ooscript::Context context) override;
	void clearJSSelf(ooscript::Object selfVal) override;
	std::optional<std::string> jsDescription() override;

private:
	OOJSTimer() = default;

	bool initWithDelay(OOTimeAbsolute delay, OOTimeDelta interval, ooscript::Context context, ooscript::Value function, ooscript::Object jsThis);
	void deleteJSPointers();

	ooscript::Value				_function = {};
	ooscript::Object _jsThis = {};	// The object that is 'this' in the function call.

	oo::WeakRef<OOJSScript>		_owningScript;	// a weak reference (was the facade's weak reference proxy)

	ooscript::Object _jsSelf = {};	// The JS Timer object proxy for this OOJSTimer.
};


#ifdef __cplusplus
extern "C" {
#endif

void InitOOJSTimer(ooscript::Context context, ooscript::Object global);

#ifdef __cplusplus
}
#endif

#endif	// OOJSTIMER_H
