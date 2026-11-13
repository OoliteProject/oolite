/*

OOEntityCalledByName.h

The entities' methods called by name, as a C++ table: the rows
(OOEntityCalledByNameTable.h), one per method. The callers use
oo::CallEntityByName and oo::EntityRespondsToName (OOCallByName.h); the rows are
here for them.

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

#pragma once

#include <cstdint>
#include <span>
#include <string>

#include "OOEnumFlags.h"
#include "OOMaths.h"
#include "oofnd/PList.hpp"
#include "oofnd/objc/OOObject.h"

class Entity;
class OOColor;

// The name sets: a row applies to an entity whose C++ part is
// of a class one of its flags names (a proxy's flag with the player's: the
// proxy's dials).
enum class OOByName : unsigned {
  kNone = 0,
  kShip = 1u << 0,
  kPlayer = 1u << 1,
  kProxy = 1u << 2,
  kStation = 1u << 3,
  kDock = 1u << 4,
  kEffect = 1u << 5,
};
constexpr std::true_type OOEnableFlagOperators(OOByName);

enum class OOEntityByNameArgument : std::uint8_t {
  kNone,    // T name()
  kString,  // T name(const std::string &)
  kPList    // T name(const oo::PList &)
};

// A typed call's result, kept by its type: an integer, enum or BOOL result
// as a long long (as OOCallIntegerMethod() converted it), a float or double as
// a double, a vector, a quaternion, an entity, a colour, a property list.
// callObjC() reads the member its row's type names. (An object result, which no
// row answers, is not kept.)
struct OOEntityByNameValue {
  long long integer = 0;
  double real = 0;
  Vector vector{};
  Quaternion quaternion{};
  Entity* entity = nullptr;  // an entity result, borrowed: the C++ entity
  OOColor* color = nullptr;  // a colour result, borrowed (fogUniform)
  oo::PList plist;
};

struct OOEntityByNameRow {
  const char* name;  // the selector's name
  OOByName flags;
  const char* result;  // @encode() of the declared result type
  OOEntityByNameArgument argument;
  // The method's body on the entity, given the argument its kind takes; a PList
  // result, else null.
  oo::PList (*call)(Entity* entity, const std::string* string,
                    const oo::PList* plist);
  // A method with no argument: its body on the entity, its result kept by type;
  // else null.
  void (*typed)(Entity* entity, OOEntityByNameValue& value);
};

/*	The root entity's own names that callObjC() lists
   (OOJSCallEntityMethods.h) and the by-name table does not: a row per name, its
        answer (null: every entity; the planet's and the beacon's names for
   the parts that answer them) and, for a name callObjC() can call, the
   method's body on the C++ entity, its result kept by type.
*/
struct OOEntityFacadeRow {
  const char* name;
  bool (*answers)(Entity* entity);
  void (*typed)(Entity* entity, OOEntityByNameValue& value);
};

/*	Every name a C++ entity answers outside the by-name table: its own
   methods, categories' and root classes' (OOEntityObjectNamesTable.h).
   oo::EntityRespondsToName answers each for the entities that answer it: a
   root-entity row's method with no argument that OOCallByName could call is the
   row's body; any other is logged (the method's type encoding), and a
   root-class or lifetime method that the call could call (init, dealloc,
   retain, release,
   ...) is answered but never called.
*/
enum class OOEntityObjectNameKind : std::uint8_t {
  kSignature,  // no signature a by-name call can use: logged
  kCalled,     // a root-entity row's method with no argument: the row's body,
               // called
  kLifetime  // a root-class or lifetime method: answered, logged, never called
};

struct OOEntityObjectName {
  const char* name;
  bool (*answers)(Entity* entity);  // null: every entity
  OOEntityObjectNameKind kind;
  const char* encoding;  // the object's method's type encoding
};

namespace oo {

std::span<const OOEntityObjectName> EntityObjectNames();
const OOEntityObjectName* EntityObjectNameNamed(
    const std::string& name);  // null if the object did not answer it

std::span<const OOEntityFacadeRow> EntityFacadeRows();
const OOEntityFacadeRow* EntityFacadeRowNamed(
    const std::string& name);  // null if not a root-entity row

std::span<const OOEntityByNameRow> EntityByNameRows();
const OOEntityByNameRow* EntityByNameRowNamed(
    const std::string& name);  // null if not tabled
bool EntityByNameRowApplies(const OOEntityByNameRow& row, Entity* entity);

// The tabled method with no argument that applies to the entity, called, its
// result kept by type in value, or the root-entity row's; false (nothing
// called) for any other name.
bool CallEntityByNameTyped(Entity* entity, const std::string& name,
                           OOEntityByNameValue& value);

}  // namespace oo
