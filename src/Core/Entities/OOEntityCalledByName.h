/*

OOEntityCalledByName.h

The entities' methods called by name, as a C++ table (bead oo-9ht.39.7.1, ADR-0056 amendment
oo-9ht.39.7.1): the rows tools/gen-entity-by-name-table.py generates from the facade's by-name
categories (OOEntityCalledByNameTable.h), one per method, with the categories' names exactly.
The callers use oo::CallEntityByName and oo::EntityRespondsToName (OOCallByName.h); the rows are
here for them and for the test that proves them equal to the facade's selectors.

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

#ifndef OOENTITYCALLEDBYNAME_H
#define OOENTITYCALLEDBYNAME_H

#include "OOMaths.h"
#include "oofnd/objc/OOObject.h"
#include "oofnd/PList.hpp"
#include <cstdint>
#include <span>
#include <string>

class Entity;
class OOColor;


// The name sets the root facade's -respondsToSelector: read: a row applies to an entity whose C++ part is
// of a class one of its flags names (a proxy's flag with the player's: the proxy's dials).
enum: unsigned
{
	kOOByNameShip		= 1u << 0,
	kOOByNamePlayer		= 1u << 1,
	kOOByNameProxy		= 1u << 2,
	kOOByNameStation	= 1u << 3,
	kOOByNameDock		= 1u << 4,
	kOOByNameEffect		= 1u << 5,
};

enum class OOEntityByNameArgument: std::uint8_t
{
	None,		// - (T) name
	String,		// - (T) name:(const std::string &)
	PList		// - (T) name:(const oo::PList &)
};

// A typed call's result (bead oo-9ht.39.7.2), kept by its type: an integer, enum or BOOL result
// as a long long (as OOCallIntegerMethod() converted it), a float or double as a double, a vector,
// a quaternion, an entity, a colour, a property list. callObjC() reads the member its row's type
// names. (An Objective-C object result, which no row answers, went with bead oo-4aq6a.5.)
struct OOEntityByNameValue
{
	long long	integer = 0;
	double		real = 0;
	Vector		vector{};
	Quaternion	quaternion{};
	Entity	*entity = nullptr;	// an entity result, borrowed: the C++ entity (bead oo-9ht.39.24; its object, in object, before)
	OOColor		*color = nullptr;	// a colour result, borrowed (fogUniform; bead oo-9ht.39.8.25)
	oo::PList	plist;
};

struct OOEntityByNameRow
{
	const char				*name;		// the selector's name
	unsigned				flags;		// kOOByName...
	const char				*result;	// @encode() of the declared result type
	OOEntityByNameArgument	argument;
	// The method's body on the entity, given the argument its kind takes; a PList result, else null.
	oo::PList				(*call)(Entity *entity, const std::string *string, const oo::PList *plist);
	// A method with no argument: its body on the entity, its result kept by type; else null.
	void					(*typed)(Entity *entity, OOEntityByNameValue &value);
};


/*	The root facade's own selectors that callObjC() lists (OOJSCallEntityMethods.h) and the by-name
	table does not (bead oo-9ht.39.8.25, ADR-0056 amendment oo-9ht.39.8.25): a row per name, its
	answer (null: every entity, as the root facade's -respondsToSelector: answered the facade's methods; the
	planet's and the beacon's selectors for the parts it answered them for) and, for a name callObjC()
	can call, the facade method's body on the C++ entity, its result kept by type.
*/
struct OOEntityFacadeRow
{
	const char				*name;
	bool					(*answers)(Entity *entity);
	void					(*typed)(Entity *entity, OOEntityByNameValue &value);
};


/*	Every name a C++ entity's Objective-C object (the root's facade) answered outside the by-name
	table (bead oo-9ht.39.9, ADR-0056 amendment oo-9ht.39.9): its own methods, its categories' and
	its root classes' (the weak-reference root, OOObject and their categories), measured on the facade by the
	selector path OOCallByName took (OOEntityObjectNamesTable.h). oo::EntityRespondsToName answers
	each for the entities the object answered it for, and oo::CallEntityByName no longer asks the
	object: a facade row's method with no argument that OOCallByName could call is the row's body;
	any other is logged as the call logged it (the method's type encoding, as the object's method had
	it), and a root-class or lifetime method that the call could call (init, dealloc, retain,
	release, ...) is answered but never called.
*/
enum OOEntityObjectNameKind: std::uint8_t
{
	kOOEntityObjectSignature,	// no signature a by-name call can use: logged
	kOOEntityObjectCalled,		// a facade row's method with no argument: the row's body, called
	kOOEntityObjectLifetime		// a root-class or lifetime method: answered, logged, never called
};

struct OOEntityObjectName
{
	const char				*name;
	bool					(*answers)(Entity *entity);	// null: every entity
	OOEntityObjectNameKind	kind;
	const char				*encoding;	// the object's method's type encoding
};


namespace oo {

std::span<const OOEntityObjectName> EntityObjectNames();
const OOEntityObjectName *EntityObjectNameNamed(const std::string &name);	// null if the object did not answer it

std::span<const OOEntityFacadeRow> EntityFacadeRows();
const OOEntityFacadeRow *EntityFacadeRowNamed(const std::string &name);	// null if not a facade row

std::span<const OOEntityByNameRow> EntityByNameRows();
const OOEntityByNameRow *EntityByNameRowNamed(const std::string &name);	// null if not tabled
bool EntityByNameRowApplies(const OOEntityByNameRow &row, Entity *entity);

// The tabled method with no argument that applies to the entity, called, its result kept by type
// in value (bead oo-9ht.39.7.2), or the facade row's (bead oo-9ht.39.8.25); false (nothing called)
// for any other name.
bool CallEntityByNameTyped(Entity *entity, const std::string &name, OOEntityByNameValue &value);

}	// namespace oo

#endif	// OOENTITYCALLEDBYNAME_H
