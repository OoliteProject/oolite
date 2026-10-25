/*

OOJSSpecialFunctions.m


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

#define OO_PLAIN_CPP_UNIT 1	// a plain C++ unit: the shared headers' game-unit parts stay out of it (bead oo-dbz)
#include "OOJSSpecialFunctions.h"
#include "OOJSEngineCore.h"	// OOJSValue
#include "oofnd/Ref.hpp"
#include "ooscript/JSEngine.hpp"	// ooscript::Context, ooscript::Object (InitOOJSSpecialFunctions)


static bool SpecialJSWarning(ooscript::Context context, ooscript::CallArgs &oojsArgs);
#ifndef NDEBUG
static bool SpecialMarkConsoleEntryPoint(ooscript::Context context, ooscript::CallArgs &oojsArgs);
#endif


static ooscript::FunctionSpec sSpecialFunctionsMethods[] =
{
	// JS name					Function						min args
	{ "jsWarning",				SpecialJSWarning,				1 },
#ifndef NDEBUG
	{ "markConsoleEntryPoint",	SpecialMarkConsoleEntryPoint,	0 },
#endif
	{ 0 }
};


void InitOOJSSpecialFunctions(ooscript::Context /*context*/, ooscript::Object /*global*/)
{
}


oo::Ref<OOJSValue> JSSpecialFunctionsObjectWrapper(ooscript::Context context)
{
	/*
		Special object is created on the fly so it can be GCed (the debug
		console script keeps a reference to its copy, but the prefix script
		doesn't) and so we don't need to clean up a root on JS engine reset.
		-- Ahruman 2011-03-30
	*/
	
	ooscript::Object special = NULL;
	OOJSAddGCObjectRoot(context, &special, "OOJSSpecialFunctions");
	
	special = ooscript::newObject(context, NULL, NULL, NULL);
	ooscript::defineFunctions(context, special, sSpecialFunctionsMethods);
	ooscript::freezeObject(context, special);
	
	oo::Ref<OOJSValue> result = OOJSValue::valueWithJSObject(special, context);
	
	ooscript::removeObjectRoot(context, &special);
	
	return result;
}


static bool SpecialJSWarning(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER	// These functions are exception-safe
	
	if (EXPECT_NOT(oojsArgs.count() < 1))
	{
		cxx_OOJSReportBadArguments(context, "special", "jsWarning", oojsArgs.count(), OOJS_ARGV, std::nullopt, "string");
		return false;
	}
	
	OOJSSetWarningOrErrorStackSkip(1);
	cxx_OOJSReportWarning(context, "%s", cxx_OOStringFromJSValue(context, OOJS_ARGV[0]).value_or("(null)").c_str());
	OOJSSetWarningOrErrorStackSkip(0);
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


#ifndef NDEBUG
static bool SpecialMarkConsoleEntryPoint(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	// First stack frame will be in eval() in console.script.evaluate(), unless someone is playing silly buggers.
	
	ooscript::StackFrame frame = NULL;
	if (ooscript::frameIterator(context, &frame) != NULL)
	{
		OOJSMarkConsoleEvalLocation(context, frame);
	}
	
	OOJS_RETURN_VOID;
}
#endif
