/*

PlayerEntityContracts.h

Methods relating to passenger and cargo contract handling.

For Oolite
Copyright (C) 2004  Giles C Williams

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
#import "PlayerEntityScripting.h"

#define PASSENGER_KEY_NAME				@"name"
#define PASSENGER_KEY_DESTINATION_NAME	@"destination_name"
#define PASSENGER_KEY_START				@"start"
#define PASSENGER_KEY_DESTINATION		@"destination"
#define PASSENGER_KEY_LONG_DESCRIPTION	@"long_description"
#define PASSENGER_KEY_DEPARTURE_TIME	@"departure_time"
#define PASSENGER_KEY_ARRIVAL_TIME		@"arrival_time"
#define PASSENGER_KEY_FEE				@"fee"
#define PASSENGER_KEY_PREMIUM			@"premium"

#define CONTRACT_KEY_ID					@"id"
#define CONTRACT_KEY_START				@"start"
#define CONTRACT_KEY_DESTINATION		@"destination"
#define CONTRACT_KEY_DESTINATION_NAME	@"destination_name"
#define CONTRACT_KEY_CARGO_TYPE			@"co_type"
#define CONTRACT_KEY_CARGO_AMOUNT		@"co_amount"
#define CONTRACT_KEY_CARGO_DESCRIPTION	@"cargo_description"
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

@interface PlayerEntity (Contracts)

- (NSString*) processEscapePods; // removes pods from cargo bay and treats categories of characters carried
- (NSString *) checkPassengerContracts;	// returns messages from any passengers whose status have changed

- (NSDictionary*) reputation;

- (int) passengerReputation;
- (void) increasePassengerReputation;
- (void) decreasePassengerReputation;

- (int) contractReputation;
- (void) increaseContractReputation;
- (void) decreaseContractReputation;

- (void) erodeReputation;

- (void) setGuiToContractsScreen;
- (BOOL) pickFromGuiContractsScreen;
- (void) highlightSystemFromGuiContractsScreen;

- (NSArray*) passengerList;
- (NSArray*) contractList;
- (void) setGuiToManifestScreen;

- (void) setGuiToDeliveryReportScreenWithText:(NSString*) report;
- (void) setGuiToDockingReportScreen;

// ---------------------------------------------------------------------- //

- (void) setGuiToShipyardScreen:(int) skip;

- (void) showShipyardInfoForSelection;

- (void) showShipyardModel: (NSDictionary *)shipDict;

- (int) yourTradeInValue;

- (BOOL) buySelectedShip;

@end
