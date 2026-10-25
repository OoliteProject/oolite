/*

OOJSCall.h

Basic JavaScript-to-ObjC bridge implementation.

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

#ifndef NDEBUG


#include "OOJSCall.h"
#include "OOColor.h"	// a colour result (kMethodTypeColorVoid)
#include "OOJavaScriptEngine.h"
#include "OOCallByName.h"

#include "OOFunctionAttributes.h"
#include "ShipEntity.h"
#include "PlayerEntity.h"	// the statistics members of callObjC's name table
#include "OOShaderUniformMethodType.h"
#include "OOJSVector.h"
#include "OOJSQuaternion.h"
#include "OOJSCallEntityMethods.h"	// callObjC()'s names for an entity (generated; bead oo-9ht.44)
#include "OOEntityCalledByName.h"	// the entities' by-name methods, on the C++ entity (bead oo-9ht.39.7.2)
#include "EntityPListForeign.h"	// oo::EntityObjectNode, oo::EntityShortDescription
#include "oofnd/PListGet.hpp"
#include "oofnd/String.hpp"


typedef enum
{
	kMethodTypeInvalid				= kOOShaderUniformTypeInvalid,
	
	kMethodTypeCharVoid				= kOOShaderUniformTypeChar,
	kMethodTypeUnsignedCharVoid		= kOOShaderUniformTypeUnsignedChar,
	kMethodTypeShortVoid			= kOOShaderUniformTypeShort,
	kMethodTypeUnsignedShortVoid	= kOOShaderUniformTypeUnsignedShort,
	kMethodTypeIntVoid				= kOOShaderUniformTypeInt,
	kMethodTypeUnsignedIntVoid		= kOOShaderUniformTypeUnsignedInt,
	kMethodTypeLongVoid				= kOOShaderUniformTypeLong,
	kMethodTypeUnsignedLongVoid		= kOOShaderUniformTypeUnsignedLong,
	kMethodTypeFloatVoid			= kOOShaderUniformTypeFloat,
	kMethodTypeDoubleVoid			= kOOShaderUniformTypeDouble,
	kMethodTypeVectorVoid			= kOOShaderUniformTypeVector,
	kMethodTypeQuaternionVoid		= kOOShaderUniformTypeQuaternion,
	kMethodTypeMatrixVoid			= kOOShaderUniformTypeMatrix,
	kMethodTypePointVoid			= kOOShaderUniformTypePoint,
	kMethodTypeColorVoid			= kOOShaderUniformTypeColor,	// a colour (OOColor *) since bead oo-9ht.1

	kMethodTypeObjectVoid			= kOOShaderUniformTypeObject,
	kMethodTypeObjectObject,
	kMethodTypeVoidVoid,
	kMethodTypeVoidObject,
	kMethodTypePListVoid
} MethodType;


namespace {
OOINLINE bool MethodExpectsParameter(MethodType type)	{ return type == kMethodTypeVoidObject || type == kMethodTypeObjectObject; }


#if OO_DEBUG
/*	callObjC()'s names that are C++ members (ADR-0056 amendment oo-9ht.15): exactly the selectors
	of the deleted categories PlayerEntity (JSVectorStatistics) and (JSQuaternionStatistics), with
	the signatures they had (a property-list result, or void), answered by the player only.
*/
struct CxxMethod
{
	const char		*name;
	oo::PList		(*pListVoid)();		// a -(oo::PList)name method, else null
	void			(*voidVoid)();		// a -(void)name method
};

const CxxMethod kPlayerMethods[] =
{
	{ "reportJSVectorStatistics",		&PlayerEntity::reportJSVectorStatistics,		nullptr },
	{ "clearJSVectorStatistics",		nullptr,	&PlayerEntity::clearJSVectorStatistics },
	{ "reportJSQuaternionStatistics",	&PlayerEntity::reportJSQuaternionStatistics,	nullptr },
	{ "clearJSQuaternionStatistics",	nullptr,	&PlayerEntity::clearJSQuaternionStatistics },
};


// The table's entry for name when the callee is the player (it answered the categories), else null.
// The player is C++ since bead oo-9ht.177: the callee is the C++ entity (an object whose C++ part
// was the player, bead oo-9ht.39.8.25, went with the root facade, bead oo-dpyk8).
const CxxMethod *CxxMethodNamed(Entity *entity, const std::optional<std::string> &name)
{
	Entity *callee = entity;
	if (!name.has_value() || PLAYER == nullptr || callee != PLAYER)  return nullptr;
	for (const CxxMethod &method : kPlayerMethods)
	{
		if (*name == method.name)  return &method;
	}
	return nullptr;
}
#endif
} // namespace


namespace {
// The table's row for name (bead oo-9ht.44); null for a name it does not list.
const OOJSCallEntityMethodRow *EntityMethodNamed(const std::optional<std::string> &name)
{
	if (!name.has_value())  return nullptr;
	for (const OOJSCallEntityMethodRow &row : kOOJSCallEntityMethods)
	{
		if (*name == row.name)  return &row;
	}
	return nullptr;
}


// The row's signature, as GetMethodType() classified the method it was generated from.
MethodType MethodTypeOfRow(const OOJSCallEntityMethodRow &row)
{
	switch (row.form)
	{
		case OOJSCallEntityMethodForm::VoidVoid:	return kMethodTypeVoidVoid;
		case OOJSCallEntityMethodForm::VoidString:	return kMethodTypeVoidObject;
		case OOJSCallEntityMethodForm::PListString:	return kMethodTypeObjectObject;
		case OOJSCallEntityMethodForm::PListVoid:	return kMethodTypePListVoid;
		case OOJSCallEntityMethodForm::Typed:		return (MethodType)OOShaderUniformTypeFromEncoding(row.encoding);
	}
	return kMethodTypeInvalid;
}


/*	The call of an entity by the entity table: a name the table does not list does not respond, and
	a listed one is called with the table's signature. An entity's by-name methods (the generated
	table OOEntityCalledByNameTable.h) are asked of and called on its C++ part (bead oo-9ht.39.7.2),
	as the facade answered and called them, and so are the facade's own methods the table lists (its
	rows in OOEntityCalledByName.mm, bead oo-9ht.39.8.25). Its "does not respond" error still names
	the entity's object, whose address the text holds. (The call of any Objective-C object by its
	method's signature, OOJSCallObjCObjectMethod, went with bead oo-4aq6a.5: the debug console's
	callObjC() had no such object to call since every `this` it is given is an entity or a monitor.)
*/
bool CallMethod(ooscript::Context context, const std::string &oo_jsClassName, unsigned argc, ooscript::Value *argv, ooscript::Value *outResult, Entity *entity)
{
	OOJS_PROFILE_ENTER
	
	std::optional<std::string>	selectorString;
	std::optional<std::string>	paramString;
	MethodType				type;
	bool					haveParameter = false,
							error = false;
	oo::PList				result;		// null for none
	
	if (argc == 0)
	{
		cxx_OOJSReportError(context, "%s.callObjC(): no selector specified.", oo_jsClassName.c_str());
		return false;
	}
	
	ShipEntity *ship = (entity != nullptr) ? oo::ToShip(entity) : nullptr;	// the C++ entity's (bead oo-9ht.39.8.25); no other object is a ship (bead oo-dpyk8)
	if (ship != nullptr)
	{
		if (PLAYER != nullptr)  PLAYER->PlayerEntity::setScriptTarget(ship);	// qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it
	}
	
	selectorString = cxx_OOStringFromJSValue(context, argv[0]);
	
	// Join all parameters together with spaces.
	if (1 < argc && selectorString.has_value() && oo::str::hasSuffix(*selectorString, ":"))
	{
		haveParameter = true;
		// As +concatenationOfStringsFromJavaScriptValues:count:separator:@" " joined them.
		std::string joined;
		for (unsigned i = 1; i < argc; i++)
		{
			if (i > 1)  joined += " ";
			joined += cxx_OOStringFromJSValueEvenIfNull(context, argv[i]).value_or(std::string());
		}
		paramString = joined;
	}
	
#if OO_DEBUG
	if (const CxxMethod *cxxMethod = CxxMethodNamed(entity, selectorString))
	{
		// As the category's method was called: a property-list result as kMethodTypePListVoid's
		// (no name in the table ends in "_bool"), a void method leaves the result alone.
		if (cxxMethod->pListVoid != nullptr)  result = cxxMethod->pListVoid();
		else  cxxMethod->voidVoid();
		if (!result.isNull())  *outResult = OOJSValueFromPList(context, result);
	}
	else
#endif
	if (const OOJSCallEntityMethodRow *row = EntityMethodNamed(selectorString); row != nullptr && entity != nullptr && oo::EntityRespondsToName(entity, *selectorString))
	{
		// Validate signature: the table's (bead oo-9ht.44).
		type = MethodTypeOfRow(*row);
		
		if (MethodExpectsParameter(type) && !haveParameter)
		{
			cxx_OOJSReportError(context, "%s.callObjC(): method %s requires a parameter.", oo_jsClassName.c_str(), (selectorString ? selectorString->c_str() : "(null)"));
			error = true;
		}
		else
		{
			// An entity's method with a numeric, vector, quaternion, colour or object result is called
			// on its C++ part (beads oo-9ht.39.7.2, oo-9ht.39.8.25), its result read as the method's was.
			OOEntityByNameValue typed;
			switch (type)
			{
				case kMethodTypeCharVoid:
				case kMethodTypeUnsignedCharVoid:
				case kMethodTypeShortVoid:
				case kMethodTypeUnsignedShortVoid:
				case kMethodTypeIntVoid:
				case kMethodTypeUnsignedIntVoid:
				case kMethodTypeLongVoid:
				case kMethodTypeUnsignedLongVoid:
				case kMethodTypeFloatVoid:
				case kMethodTypeDoubleVoid:
				case kMethodTypeVectorVoid:
				case kMethodTypeQuaternionVoid:
				case kMethodTypeColorVoid:
				case kMethodTypeObjectVoid:
					// An entity's typed call: the table holds every name callObjC() lists for an entity
					// (bead oo-9ht.39.8.25); one it cannot call leaves the zero values.
					oo::CallEntityByNameTyped(entity, *selectorString, typed);
					break;
				default:
					break;
			}
			switch (type)
			{
				case kMethodTypeVoidObject:
				case kMethodTypeObjectObject:
					// Called by name with the joined string (ADR-0055 item 5); a void method gives null.
					result = oo::CallEntityByName(entity, *selectorString, *paramString);
					break;
					
				case kMethodTypeColorVoid:
					// A colour result is its PList::Object node, as the colour's facade's was (bead oo-9ht.1).
					result = OOColorObjectNode(typed.color);
					if (selectorString.has_value() && oo::str::hasSuffix(*selectorString, "_bool"))  result = oo::PList(false);	// a colour answered neither -boolValue nor -intValue
					break;

				case kMethodTypeObjectVoid:
				case kMethodTypePListVoid:
					if (type == kMethodTypePListVoid)  result = oo::CallEntityByName(entity, *selectorString);
					// An entity result is its entity's Object node (bead oo-9ht.39.24): the same object, class name,
					// description and JS value as the object's node. No entity method answers any other object
					// (the by-name rows' object results are entities), so no result is null, as nil's node was
					// (bead oo-4aq6a.5 deleted the Objective-C object's node).
					else if (typed.entity != nullptr)  result = oo::EntityObjectNode(typed.entity);
					if (selectorString.has_value() && oo::str::hasSuffix(*selectorString, "_bool"))
					{
						// OOBooleanFromObject(result, false): a string or number reads as oo::plist_get::boolFrom
						// does (bead oo-2764); an entity's node answered neither -boolValue nor -intValue (the
						// object path's -boolValue/-intValue of another object went with bead oo-4aq6a.5).
						bool boolResult = false;
						if (result.type() != oo::PList::Type::Object)  boolResult = oo::plist_get::boolFrom(!result.isNull() ? &result : nullptr, false);
						result = oo::PList(boolResult);
					}
					break;
					
				case kMethodTypeVoidVoid:
					oo::CallEntityByName(entity, *selectorString);
					break;
					
				case kMethodTypeCharVoid:
				case kMethodTypeUnsignedCharVoid:
				case kMethodTypeShortVoid:
				case kMethodTypeUnsignedShortVoid:
				case kMethodTypeIntVoid:
				case kMethodTypeUnsignedIntVoid:
				case kMethodTypeLongVoid:
					result = oo::PList::signedInteger(typed.integer);
					break;
					
				case kMethodTypeUnsignedLongVoid:
					result = oo::PList::unsignedInteger(typed.integer);
					break;
					
				case kMethodTypeFloatVoid:
				case kMethodTypeDoubleVoid:
					result = oo::PList(static_cast<double>(typed.real));
					break;
					
				case kMethodTypeVectorVoid:
				{
					Vector v = typed.vector;
					*outResult = ooscript::objectValue(JSVectorWithVector(context, v));
					break;
				}
					
				case kMethodTypeQuaternionVoid:
				{
					Quaternion q = typed.quaternion;
					*outResult = ooscript::objectValue(JSQuaternionWithQuaternion(context, q));
					break;
				}
					
				case kMethodTypeMatrixVoid:
				case kMethodTypePointVoid:
				case kMethodTypeInvalid:
					cxx_OOJSReportError(context, "%s.callObjC(): method %s cannot be called from JavaScript.", oo_jsClassName.c_str(), (selectorString ? selectorString->c_str() : "(null)"));
					error = true;
					break;
			}
			if (!result.isNull())
			{
				*outResult = OOJSValueFromPList(context, result);	// a Foundation result's PList form, as OOJSValueFromNativeObject gave it (ADR-0051)
			}
		}
	}
	else
	{
		// An entity's text names its object, whose address it holds (ADR-0056 amendment oo-9ht.39.8.25).
		// The entity's object's text comes from the facade (bead oo-9ht.39.24), byte for byte; no
		// entity is described as nil was (the console never calls without one).
		std::string described = (entity != nullptr) ? oo::EntityShortDescription(entity) : std::string("(null)");
		cxx_OOJSReportError(context, "%s.callObjC(): %s does not respond to method %s.", oo_jsClassName.c_str(), described.c_str(), (selectorString ? selectorString->c_str() : "(null)"));
		error = true;
	}
	
	return !error;
	
	OOJS_PROFILE_EXIT
}
} // namespace


bool OOJSCallEntityMethod(ooscript::Context context, Entity *entity, const std::string &oo_jsClassName, unsigned argc, ooscript::Value *argv, ooscript::Value *outResult)
{
	return CallMethod(context, oo_jsClassName, argc, argv, outResult, entity);	// the C++ entity only (bead oo-9ht.39.8.25)
}




#endif
