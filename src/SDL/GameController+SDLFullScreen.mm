/*

GameController+SDLFullScreen.m

Full-screen rendering support for SDL targets.


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

#import "GameController.h"

#if OOLITE_SDL

#import "MyOpenGLView.h"
#import "OOFullScreenController.h"
#import "Universe.h"
#include "oofnd/Defaults.hpp"

namespace {
// The first of modes with this size and refresh rate, or nullptr (modes are mode dictionaries).
const oo::PList* FindDisplayMode(const oo::PList::Array& modes, unsigned int d_width, unsigned int d_height, unsigned int d_refresh)
{
    unsigned int modeWidth, modeHeight, modeRefresh;

    for (const oo::PList& mode : modes) {
        modeWidth = mode.get<int>(std::string(kOODisplayWidth));
        modeHeight = mode.get<int>(std::string(kOODisplayHeight));
        modeRefresh = mode.get<int>(std::string(kOODisplayRefreshRate));
        if ((modeWidth == d_width) && (modeHeight == d_height) && (modeRefresh == d_refresh)) {
            return &mode;
        }
    }
    return nullptr;
}
}

@implementation GameController (FullScreen)

- (void)setUpDisplayModes
{
    // The screen's mode dictionaries, in its order (Foundation sweep, proposed ADR-0043).
    const std::vector<oo::PList> modes = [_cxxController->_gameView getScreenSizeArray];
    unsigned int modeWidth, modeHeight;

    _cxxController->displayModes.clear();
    for (const oo::PList& mode : modes) {
        modeWidth = mode.get<int>(std::string(kOODisplayWidth));
        modeHeight = mode.get<int>(std::string(kOODisplayHeight));

        if (modeWidth < DISPLAY_MIN_WIDTH || modeWidth > DISPLAY_MAX_WIDTH || modeHeight < DISPLAY_MIN_HEIGHT || modeHeight > DISPLAY_MAX_HEIGHT)
            continue;
        _cxxController->displayModes.push_back(mode);
    }

    const oo::PList currentMode = [_cxxController->_gameView currentScreenMode];
    if (currentMode) {
        _cxxController->width = currentMode.get<int>(std::string(kOODisplayWidth));
        _cxxController->height = currentMode.get<int>(std::string(kOODisplayHeight));
        _cxxController->refresh = currentMode.get<int>(std::string(kOODisplayRefreshRate));
    } else {
        NSSize fsmSize = [_cxxController->_gameView currentScreenSize];
        _cxxController->width = fsmSize.width;
        _cxxController->height = fsmSize.height;
    }
}

- (void)setFullScreenMode:(BOOL)fsm
{
    _cxxController->fullscreen = fsm;
}

- (void)exitFullScreenMode
{
    oo::Defaults::standard().setBool("fullscreen", false);
    _cxxController->stayInFullScreenMode = NO;
}

- (BOOL)inFullScreenMode
{
    return [_cxxController->_gameView inFullScreenMode];
}

- (BOOL)setDisplayWidth:(unsigned int)d_width Height:(unsigned int)d_height Refresh:(unsigned int)d_refresh
{
    const oo::PList* d_mode = FindDisplayMode(_cxxController->displayModes, d_width, d_height, d_refresh);
    if (d_mode != nullptr) {
        _cxxController->width = d_width;
        _cxxController->height = d_height;
        _cxxController->refresh = d_refresh;
        _cxxController->fullscreenDisplayMode = *d_mode;

        oo::Defaults& userDefaults = oo::Defaults::standard();

        userDefaults.setInteger("display_width", _cxxController->width);
        userDefaults.setInteger("display_height", _cxxController->height);
        userDefaults.setInteger("display_refresh", _cxxController->refresh);

        // Manual synchronization is required for SDL And doesn't hurt much for OS X.
        userDefaults.synchronize();

        return YES;
    }
    return NO;
}

- (oo::PList)findDisplayModeForWidth:(unsigned int)d_width Height:(unsigned int)d_height Refresh:(unsigned int)d_refresh
{
    const oo::PList* mode = FindDisplayMode(_cxxController->displayModes, d_width, d_height, d_refresh);
    return (mode != nullptr) ? *mode : oo::PList(); // a mode dictionary; null: none
}

- (oo::PList)displayModes
{
    return oo::PList(_cxxController->displayModes); // an array of mode dictionaries
}

- (NSUInteger)indexOfCurrentDisplayMode
{
    const oo::PList* mode = FindDisplayMode(_cxxController->displayModes, _cxxController->width, _cxxController->height, _cxxController->refresh);
    if (mode == nullptr)
        return NSNotFound;
    else
        return (NSUInteger)(mode - _cxxController->displayModes.data()); // the first match, as -indexOfObject: found

    return NSNotFound;
}

- (void)pauseFullScreenModeToPerform:(SEL)selector onTarget:(id)target
{
    _cxxController->pauseSelector = selector;
    _cxxController->pauseTarget = target;
    _cxxController->stayInFullScreenMode = NO;
}

@end

#endif
