/*

PlayerEntityContracts.h

Methods relating to passenger and cargo contract handling.

Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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

#import "PlayerEntity.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import "GuiDisplayGen.h"

#define PASSENGER_KEY_NAME				@"name"

#define CARGO_KEY_ID					@"id"
#define CARGO_KEY_TYPE					@"co_type"
#define CARGO_KEY_AMOUNT				@"co_amount"
#define CARGO_KEY_DESCRIPTION			@"cargo_description"

#define CONTRACT_KEY_START				@"start"
#define CONTRACT_KEY_DESTINATION		@"destination"
#define CONTRACT_KEY_DESTINATION_NAME	@"destination_name"
#define CONTRACT_KEY_LONG_DESCRIPTION	@"long_description"
#define CONTRACT_KEY_DEPARTURE_TIME		@"departure_time"
#define CONTRACT_KEY_ARRIVAL_TIME		@"arrival_time"
#define CONTRACT_KEY_FEE				@"fee"
#define CONTRACT_KEY_PREMIUM			@"premium"

#define GUI_ROW_PASSENGERS_LABELS	1
#define GUI_ROW_PASSENGERS_START	2
#define GUI_ROW_CARGO_LABELS		8
#define GUI_ROW_CARGO_START			9
#define GUI_ROW_CONTRACT_INFO_START	15

#define GUI_ROW_SHIPYARD_LABELS		1
#define GUI_ROW_SHIPYARD_START		2
#define GUI_ROW_SHIPYARD_INFO_START	15
#define GUI_ROW_NO_SHIPS			10

#define MAX_ROWS_SHIPS_FOR_SALE		12

// only use within setGuiToManifestScreen
#define SET_MANIFEST_ROW(obj,color,row) ([self setManifestScreenRow:obj inColor:[OOColor color] forRow:row ofRows:max_rows andOffset:page_offset inMultipage:multi_page])

@interface PlayerEntity (Contracts)

- (NSString *) processEscapePods;		// removes pods from cargo bay and treats categories of characters carried
- (NSString *) checkPassengerContracts;	// returns messages from any passengers whose status have changed

- (NSDictionary *) reputation;

- (int) passengerReputation;
- (void) increasePassengerReputation;
- (void) decreasePassengerReputation;

- (int) contractReputation;
- (void) increaseContractReputation;
- (void) decreaseContractReputation;

- (void) erodeReputation;

- (void) addMessageToReport:(NSString*) report;

- (void) setGuiToContractsScreen;
- (BOOL) pickFromGuiContractsScreen;
- (void) highlightSystemFromGuiContractsScreen;

- (BOOL) addPassenger:(NSString*)Name start:(unsigned)start destination:(unsigned)destination eta:(double)eta fee:(double)fee;	// for js scripting
- (BOOL) removePassenger:(NSString*)Name;	// for js scripting
- (BOOL) awardContract:(unsigned)qty commodity:(NSString*)commodity start:(unsigned)start destination:(unsigned)destination eta:(double)eta fee:(double)fee;	// for js scripting.
- (NSArray *) passengerList;
- (NSArray *) contractList;
- (void) setGuiToManifestScreen;
- (void) setManifestScreenRow:(id)object inColor:(OOColor*)color forRow:(OOGUIRow)row ofRows:(OOGUIRow)max_rows andOffset:(OOGUIRow)offset inMultipage:(BOOL)multi;


- (void) setGuiToDockingReportScreen;

// ---------------------------------------------------------------------- //

- (void) setGuiToShipyardScreen:(unsigned) skip;

- (void) showShipyardModel:(NSString *)shipKey shipData:(NSDictionary *)shipDict personality:(uint16_t)personality;
- (void) showShipyardInfoForSelection;
- (OOInteger) missingSubEntitiesAdjustment;
- (void) showTradeInInformationFooter;

- (BOOL) buySelectedShip;
- (BOOL) buyNamedShip:(NSString *)shipName;
- (void) newShipCommonSetup:(NSString *)shipKey yardInfo:(NSDictionary *)ship_info baseInfo:(NSDictionary *)ship_base_dict; 

@end
