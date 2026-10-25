/*

OOJSFunction.h

Object encapsulating a runnable JavaScript function.

C++20 since bead oo-3smy (proposed ADR-0056, the OOColor house style). Bead oo-9ht.41 deleted the
Objective-C facade once ShipEntityAI and OORegExpMatcher held the C++ object, and moved the class
out of namespace cxx.


JavaScript support for Oolite
Copyright (C) 2007-2013 David Taylor and Jens Ayton.

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

#ifndef OOJSFUNCTION_H
#define OOJSFUNCTION_H

#include "OOCocoa.h"
#include "ooscript/JSEngine.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/Ref.hpp"

#include <optional>
#include <string>
#include <vector>


class OOJSFunction : public oo::RefCounted
{
public:
	// The initialisers' factories (proposed ADR-0056 amendment oo-novu): null where the
	// initialiser answered nil (a NULL function; no code, missing argument names, or a compile
	// error).
	static oo::Ref<OOJSFunction> initWithFunction(ooscript::Function function, ooscript::Context context);
	static oo::Ref<OOJSFunction> initWithName(const std::optional<std::string> &name,
											  ooscript::Object scope,		// may be NULL, in which case global object is used.
											  const std::optional<std::string> &code,		// full JS code for function, including function declaration.
											  NSUInteger argCount,
											  const char **argNames,
											  const std::optional<std::string> &fileName,
											  NSUInteger lineNumber,
											  ooscript::Context context);	// may be NULL. If not null, must be in a request.

	~OOJSFunction() override;

	std::optional<std::string> descriptionComponents() const;

	std::optional<std::string> name();	// nullopt: anonymous (bead oo-3rb.289.7)
	ooscript::Function function();
	ooscript::Value functionValue();

	// Raw evaluation. Context may not be NULL and must be in a request.
	bool evaluateWithContext(ooscript::Context context,
							 ooscript::Object jsThis,
							 unsigned argc,
							 ooscript::Value *argv,
							 ooscript::Value *result);

	// (The object-wrapper evaluations, which converted Objective-C arguments and scope -
	// evaluatePredicateWithContext() and its evaluateWithContext() - had no game caller and went
	// with OOJSValueFromNativeObject(), bead oo-4aq6a.6.2.)

private:
	// The part of -initWithFunction:context: that cannot fail.
	OOJSFunction(ooscript::Function function, ooscript::Context context);

	void deleteJSValue();

	ooscript::Function _function = {};
	std::optional<std::string>	_name;	// nullopt for an anonymous function (was nil)
};

#endif	// OOJSFUNCTION_H
