/*

PlayerEntityControls.h

Input management methods.

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

#include "PlayerEntity.h"

@interface PlayerEntity (Controls)

- (void)initControls;
- (void)initKeyConfigSettings;

- (void)pollControls:(double)delta_t;
- (BOOL)handleGUIUpDownArrowKeys;
- (void)clearPlanetSearchString;
- (void)targetNewSystem:(int)direction;
- (void)switchToMainView;
- (void)noteSwitchToView:(OOViewID)toView fromView:(OOViewID)fromView;
- (void)beginWitchspaceCountdown:(int)spin_time;
- (void)beginWitchspaceCountdown;
- (void)cancelWitchspaceCountdown;
- (oo::PList)cxx_processKeyCode:(const oo::PList&)key_def; // an Array of key-definition Dicts, each fully expanded
- (BOOL)checkNavKeyPress:(const oo::PList&)key_def;
- (BOOL)checkKeyPress:(const oo::PList&)key_def;
- (BOOL)checkKeyPress:(const oo::PList&)key_def fKey_only:(BOOL)fKey_only;
- (BOOL)checkKeyPress:(const oo::PList&)key_def ignore_ctrl:(BOOL)ignore_ctrl;
- (BOOL)checkKeyPress:(const oo::PList&)key_def fKey_only:(BOOL)fKey_only ignore_ctrl:(BOOL)ignore_ctrl;
- (int)getFirstKeyCode:(const oo::PList&)key_def;

@end
