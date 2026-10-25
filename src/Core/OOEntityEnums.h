/*

OOEntityEnums.h

The entity enumerations that used to live inside Objective-C class headers: OOEntityStatus and
OOScanClass (Entities/Entity.h), OOGUIScreenID and OOGalacticHyperspaceBehaviour
(Entities/PlayerEntity.h), OOShipDamageType (Entities/ShipEntity.h). Moved here unchanged (bead
oo-9ht.64) so a plain C or C++ translation unit (OOConstToJSString) can name them without parsing
an @interface. Those headers include this one back, so no caller changes.


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

#ifndef INCLUDED_OOENTITYENUMS_h
#define INCLUDED_OOENTITYENUMS_h


// From Entities/Entity.h.

#define ENTRY(label, value) label = value,

typedef enum OOEntityStatus
{
	#include "OOEntityStatus.tbl"
} OOEntityStatus;


#ifndef OO_SCANCLASS_TYPE
#define OO_SCANCLASS_TYPE
#ifndef __cplusplus
/* ISO C++ forbids a forward reference to an unscoped enum with no fixed underlying
   type (this used to compile only because this file was Objective-C, not Objective-C++;
   ADR-0001). The full definition is three lines below in this same file, so C++
   translation units never need the forward tag at all. */
typedef enum OOScanClass OOScanClass;
#endif
#endif

enum OOScanClass
{
	#include "OOScanClass.tbl"
};

#undef ENTRY


enum
{
	// Values used for unknown strings.
	kOOEntityStatusDefault		= STATUS_INACTIVE,
	kOOScanClassDefault			= CLASS_NOT_SET
};


// From Entities/PlayerEntity.h.

#define ENTRY(label, value) label,

typedef enum
{
	#include "OOGUIScreenID.tbl"
} OOGUIScreenID;

#define GALACTIC_HYPERSPACE_ENTRY(label, value) GALACTIC_HYPERSPACE_##label = value,

typedef enum
{
	#include "OOGalacticHyperspaceBehaviour.tbl"

	GALACTIC_HYPERSPACE_MAX					= GALACTIC_HYPERSPACE_BEHAVIOUR_FIXED_COORDINATES
} OOGalacticHyperspaceBehaviour;

#undef ENTRY
#undef GALACTIC_HYPERSPACE_ENTRY


enum
{
	// Values used for unknown strings.
	kOOGUIScreenIDDefault					= GUI_SCREEN_MAIN,
	kOOGalacticHyperspaceBehaviourDefault	= GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN
};


// From Entities/ShipEntity.h.

typedef enum
{
#define DIFF_STRING_ENTRY(label, string) label,
#include "OOShipDamageType.tbl"
#undef DIFF_STRING_ENTRY

	kOOShipDamageTypeDefault = kOODamageTypeEnergy
} OOShipDamageType;


#endif	// INCLUDED_OOENTITYENUMS_h
