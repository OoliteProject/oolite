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

#include "GameController.h"

#if OOLITE_SDL

#include "MyOpenGLView.h"
#include "OOFullScreenController.h"
#include "Universe.h"
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

// The former FullScreen category of GameController (bead oo-qinv): members of GameController,
// defined here (ADR-0056 amendment oo-o89 item 4). Their callers call them (the façade that forwarded
// the category's selectors went with bead oo-9ht.164).

void GameController::setUpDisplayModes()
{
    // The screen's mode dictionaries, in its order (Foundation sweep, proposed ADR-0043).
    const std::vector<oo::PList> modes = (_gameView != nullptr ? _gameView->getScreenSizeArray() : std::vector<oo::PList>());
    unsigned int modeWidth, modeHeight;

    displayModes.clear();
    for (const oo::PList& mode : modes) {
        modeWidth = mode.get<int>(std::string(kOODisplayWidth));
        modeHeight = mode.get<int>(std::string(kOODisplayHeight));

        if (modeWidth < DISPLAY_MIN_WIDTH || modeWidth > DISPLAY_MAX_WIDTH || modeHeight < DISPLAY_MIN_HEIGHT || modeHeight > DISPLAY_MAX_HEIGHT)
            continue;
        displayModes.push_back(mode);
    }

    const oo::PList currentMode = (_gameView != nullptr ? _gameView->currentScreenMode() : oo::PList());
    if (currentMode) {
        width = currentMode.get<int>(std::string(kOODisplayWidth));
        height = currentMode.get<int>(std::string(kOODisplayHeight));
        refresh = currentMode.get<int>(std::string(kOODisplayRefreshRate));
    } else {
        NSSize fsmSize = (_gameView != nullptr ? _gameView->currentScreenSize() : NSSize { });
        width = fsmSize.width;
        height = fsmSize.height;
    }
}

void GameController::setFullScreenMode(bool fsm)
{
    fullscreen = fsm;
}

void GameController::exitFullScreenMode()
{
    oo::Defaults::standard().setBool("fullscreen", false);
    stayInFullScreenMode = false;
}

bool GameController::inFullScreenMode()
{
    return (_gameView != nullptr ? _gameView->inFullScreenMode() : false);
}

bool GameController::setDisplayWidth(unsigned int d_width, unsigned int d_height, unsigned int d_refresh)
{
    const oo::PList* d_mode = FindDisplayMode(displayModes, d_width, d_height, d_refresh);
    if (d_mode != nullptr) {
        width = d_width;
        height = d_height;
        refresh = d_refresh;
        fullscreenDisplayMode = *d_mode;

        oo::Defaults& userDefaults = oo::Defaults::standard();

        userDefaults.setInteger("display_width", width);
        userDefaults.setInteger("display_height", height);
        userDefaults.setInteger("display_refresh", refresh);

        // Manual synchronization is required for SDL And doesn't hurt much for OS X.
        userDefaults.synchronize();

        return true;
    }
    return false;
}

oo::PList GameController::findDisplayModeForWidth(unsigned int d_width, unsigned int d_height, unsigned int d_refresh)
{
    const oo::PList* mode = FindDisplayMode(displayModes, d_width, d_height, d_refresh);
    return (mode != nullptr) ? *mode : oo::PList(); // a mode dictionary; null: none
}

oo::PList GameController::getDisplayModes()
{
    return oo::PList(displayModes); // an array of mode dictionaries
}

NSUInteger GameController::indexOfCurrentDisplayMode()
{
    const oo::PList* mode = FindDisplayMode(displayModes, width, height, refresh);
    if (mode == nullptr)
        return NSNotFound;
    else
        return (NSUInteger)(mode - displayModes.data()); // the first match, as -indexOfObject: found

    return NSNotFound;
}

void GameController::pauseFullScreenModeToPerform(const char* selectorName, oo::RefCounted* target)
{
    pauseSelector = selectorName != nullptr ? selectorName : ""; // by name since bead oo-xu228.3
    pauseTarget = target;
    stayInFullScreenMode = false;
}

#endif
