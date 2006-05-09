//
//  PlayerEntity (contracts).m
/*
 *
 *  Oolite
 *
 *  Created by Giles Williams on Sat Apr 03 2004.
 *  Copyright (c) 2004 for aegidian.org. All rights reserved.
 *

Copyright (c) 2004, Giles C Williams
All rights reserved.

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Noncommercial. You may not use this work for commercial purposes.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/

#import "PlayerEntity.h"
#import "PlayerEntity Additions.h"

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

// ---------------------------------------------------------------------- //

- (void) setGuiToShipyardScreen:(int) skip;

- (void) showShipyardInfoForSelection;

- (void) showShipyardModel: (NSDictionary *)shipDict;

- (int) yourTradeInValue;

- (BOOL) buySelectedShip;

@end
