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
#import "OOFoundationBridge.h"
#import "OOFullScreenController.h"
#import "Universe.h"

@implementation GameController (FullScreen)

- (void)setUpDisplayModes
{
    // The screen's mode dictionaries, in its order (Foundation sweep, proposed ADR-0043).
    const std::vector<oo::ObjCRef<id>> modes = oo::ObjCRefsFrom<id>(oo::ObjectFromPList(oo::PList(oo::PList::Array([gameView getScreenSizeArray]))));
    std::vector<oo::ObjCRef<id>> usableModes;
    unsigned int modeWidth, modeHeight;

    for (const oo::ObjCRef<id>& mode : modes) {
        modeWidth = [[mode.get() objectForKey:kOODisplayWidth] intValue];
        modeHeight = [[mode.get() objectForKey:kOODisplayHeight] intValue];

        if (modeWidth < DISPLAY_MIN_WIDTH || modeWidth > DISPLAY_MAX_WIDTH || modeHeight < DISPLAY_MIN_HEIGHT || modeHeight > DISPLAY_MAX_HEIGHT)
            continue;
        usableModes.push_back(mode);
    }
    displayModes = [oo::NSArrayFromObjects(usableModes) mutableCopy]; // owned (+1), as the ivar was

    const oo::PList currentMode = [gameView currentScreenMode];
    if (currentMode) {
        width = currentMode.get<int>(oo::StdString(kOODisplayWidth));
        height = currentMode.get<int>(oo::StdString(kOODisplayHeight));
        refresh = currentMode.get<int>(oo::StdString(kOODisplayRefreshRate));
    } else {
        NSSize fsmSize = [gameView currentScreenSize];
        width = fsmSize.width;
        height = fsmSize.height;
    }
}

- (void)setFullScreenMode:(BOOL)fsm
{
    fullscreen = fsm;
}

- (void)exitFullScreenMode
{
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"fullscreen"];
    stayInFullScreenMode = NO;
}

- (BOOL)inFullScreenMode
{
    return [gameView inFullScreenMode];
}

- (BOOL)setDisplayWidth:(unsigned int)d_width Height:(unsigned int)d_height Refresh:(unsigned int)d_refresh
{
    id d_mode = [self findDisplayModeForWidth:d_width Height:d_height Refresh:d_refresh]; // shared selector's result
    if (d_mode) {
        width = d_width;
        height = d_height;
        refresh = d_refresh;
        fullscreenDisplayMode = d_mode;

        NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];

        [userDefaults setInteger:width forKey:@"display_width"];
        [userDefaults setInteger:height forKey:@"display_height"];
        [userDefaults setInteger:refresh forKey:@"display_refresh"];

        // Manual synchronization is required for SDL And doesn't hurt much for OS X.
        [userDefaults synchronize];

        return YES;
    }
    return NO;
}

- (id)findDisplayModeForWidth:(unsigned int)d_width Height:(unsigned int)d_height Refresh:(unsigned int)d_refresh // shared selector (proposed ADR-0043)
{
    unsigned int modeWidth, modeHeight, modeRefresh;

    for (const oo::ObjCRef<id>& mode : oo::ObjCRefsFrom<id>(displayModes)) {
        modeWidth = [[mode.get() objectForKey:kOODisplayWidth] intValue];
        modeHeight = [[mode.get() objectForKey:kOODisplayHeight] intValue];
        modeRefresh = [[mode.get() objectForKey:kOODisplayRefreshRate] intValue];
        if ((modeWidth == d_width) && (modeHeight == d_height) && (modeRefresh == d_refresh)) {
            return mode.get();
        }
    }
    return nil;
}

- (id)displayModes // shared selector (proposed ADR-0043)
{
    return [[displayModes copy] autorelease]; // an immutable copy, as +arrayWithArray: gave
}

- (NSUInteger)indexOfCurrentDisplayMode
{
    id mode; // the shared selector's result

    mode = [self findDisplayModeForWidth:width Height:height Refresh:refresh];
    if (mode == nil)
        return NSNotFound;
    else
        return [displayModes indexOfObject:mode];

    return NSNotFound;
}

- (void)pauseFullScreenModeToPerform:(SEL)selector onTarget:(id)target
{
    pauseSelector = selector;
    pauseTarget = target;
    stayInFullScreenMode = NO;
}

@end

#endif
