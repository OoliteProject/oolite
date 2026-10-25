/*

OOCharacter.h

Represents an NPC person (as opposed to an NPC ship).

C++20 since bead oo-8kx7 (Phase 3, proposed ADR-0056). Its Objective-C facade was deleted by bead
oo-9ht.10 (batch E): ships' crews and the character pool hold oo::Ref<OOCharacter>, and a
character is its own PList::Object payload (oo::PListForeign) for its script's "character".

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

#ifndef OOCHARACTER_H
#define OOCHARACTER_H

#include "ooscript/JSEngine.hpp"
#include "OOTypes.h"
#include "legacy_random.h"
#include "OOJSPropID.h"

#include "oofnd/StdLib.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/PList.hpp"

#include "OOScript.h"	// oo::Ref<OOScript> members and results (bead oo-9ht.133)


class OOCharacter : public oo::PListForeign
{
public:
	OOCharacter() = default;	// [[OOCharacter alloc] init]: every field zero
	OOCharacter(const std::string &role, OOSystemID s);

	static oo::Ref<OOCharacter> characterWithRole(const std::string &c_role, OOSystemID s);
	static oo::Ref<OOCharacter> randomCharacterWithRole(const std::string &c_role, OOSystemID s);
	static oo::Ref<OOCharacter> characterWithDictionary(const oo::PList &c_dict);	// a dictionary (JS crew definitions may hold any object, as an Object node)

	std::optional<std::string> planetOfOrigin();
	OOSystemID planetIDOfOrigin();
	std::optional<std::string> species();

	void basicSetUp();
	bool castInRole(const std::string &role);

	std::optional<std::string> name();	// nullopt: none (bead oo-3rb.289.9)
	void setName(const std::optional<std::string> &value);

	std::optional<std::string> shortDescription();
	void setShortDescription(const std::optional<std::string> &value);	// nullopt: none (bead oo-qps.51)

	int legalStatus();
	void setLegalStatus(int value);

	OOCreditsQuantity insuranceCredits();
	void setInsuranceCredits(OOCreditsQuantity value);

	oo::PList legacyScript();	// an array of script actions; null: none
	void setLegacyScript(const oo::PList &scriptActions);
	::OOScript *script();
	void setCharacterScript(const std::string &scriptName);
	void doScriptEvent(ooscript::PropertyId message);

	oo::PList infoForScripting();	// a dictionary

	// What "%@" prints between the braces of <OOCharacter 0x...>{...} (OODescription.h).
	std::optional<std::string> descriptionComponents() const;
	// The JavaScript class the character's Objective-C object answered (-oo_jsClassName).
	std::optional<std::string> oo_jsClassName();

	// oo::PListForeign: what the facade answered (its class, and "%@" as <OOCharacter 0x...>{...}).
	std::string className() const override;
	std::string description() const override;

private:
	OOCharacter(Random_Seed characterSeed, OOSystemID systemSeed);	// -initWithGenSeed:andOriginalSystem:
	void setCharacterFromDictionary(const oo::PList &dict);

	void setOriginSystem(OOSystemID value);
	Random_Seed genSeed();
	void setGenSeed(Random_Seed value);

	std::optional<std::string>	_name;
	std::optional<std::string>	_shortDescription;
	OOSystemID			_originSystem = {};
	Random_Seed			_genSeed = {};
	int					_legalStatus = {};
	OOCreditsQuantity	_insuranceCredits = {};
	oo::PList			_scriptActions;	// an array; null: none
	oo::Ref<OOScript>	_script;
};



#endif	// OOCHARACTER_H
