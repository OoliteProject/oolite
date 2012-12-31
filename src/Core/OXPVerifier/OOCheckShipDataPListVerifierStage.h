/*

OOCheckShipDataPListVerifierStage.h

OOOXPVerifierStage which checks shipdata.plist.


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

#import "OOTextureVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

@class OOPListSchemaVerifier, OOAIStateMachineVerifierStage;

@interface OOCheckShipDataPListVerifierStage: OOTextureHandlingStage
{
@private
	NSDictionary				*_shipdataPList;
	NSSet						*_ooliteShipNames;
	NSSet						*_basicKeys,
								*_stationKeys,
								*_playerKeys,
								*_allKeys;
	OOPListSchemaVerifier		*_schemaVerifier;
	OOAIStateMachineVerifierStage *_aiVerifierStage;
	
	// Info about ship currently being checked.
	NSString					*_name;
	NSDictionary				*_info;
	NSSet						*_roles;
	uint32_t					_isStation: 1,
								_isPlayer: 1,
								_havePrintedMessage: 1;
}
@end

#endif
