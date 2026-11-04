/*

PlayerEntityContracts.h

Methods relating to passenger and cargo contract handling.

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

#include "PlayerEntity.h"

/* The category PlayerEntity (Contracts) is members of PlayerEntity, declared
 * in PlayerEntity.h. This header stays for the files that include it.
 */
#include <string_view>

#include "GuiDisplayGen.h"
#include "PlayerEntityLegacyScriptEngine.h"

inline constexpr std::string_view PASSENGER_KEY_NAME = "name";

inline constexpr std::string_view CARGO_KEY_ID = "id";
inline constexpr std::string_view CARGO_KEY_TYPE = "co_type";
inline constexpr std::string_view CARGO_KEY_AMOUNT = "co_amount";
inline constexpr std::string_view CARGO_KEY_DESCRIPTION = "cargo_description";

inline constexpr std::string_view CONTRACT_KEY_START = "start";
inline constexpr std::string_view CONTRACT_KEY_DESTINATION = "destination";
#define CONTRACT_KEY_DESTINATION_NAME "destination_name"
#define CONTRACT_KEY_LONG_DESCRIPTION "long_description"
inline constexpr std::string_view CONTRACT_KEY_DEPARTURE_TIME =
    "departure_time";
inline constexpr std::string_view CONTRACT_KEY_ARRIVAL_TIME = "arrival_time";
inline constexpr std::string_view CONTRACT_KEY_FEE = "fee";
inline constexpr std::string_view CONTRACT_KEY_PREMIUM = "premium";
inline constexpr std::string_view CONTRACT_KEY_RISK = "risk";

#define MAX_CONTRACT_REP 70

#define GUI_ROW_PASSENGERS_LABELS 1
#define GUI_ROW_PASSENGERS_START 2
#define GUI_ROW_CARGO_LABELS 8
#define GUI_ROW_CARGO_START 9
#define GUI_ROW_CONTRACT_INFO_START 15

#define GUI_ROW_SHIPYARD_LABELS 1
#define GUI_ROW_SHIPYARD_START 2
#define GUI_ROW_SHIPYARD_INFO_START 15
#define GUI_ROW_NO_SHIPS 10

#define MAX_ROWS_SHIPS_FOR_SALE 12
