![](./assets/oolite-logo.png){: width="30%" }

# Oolite

## Installation

See the [README](https://github.com/OoliteProject/oolite/blob/master/README.md#installing-oolite).

## Start Menu

When starting Oolite, a menu with six options will be displayed.

### Start New Commander

Start a new commander. Three starting scenarios are available by default, though expansion packs may add more. New 
players may wish to start with the Tutorial scenario which introduces the basics of flight and combat. A commander 
started with the Strict Mode option will never have any expansion packs affecting the game-play, even if these are 
installed at a later stage.

### Load Commander

Load an existing commander file.

### View Ship Library

View the specifications and descriptions of the ships and other common space objects.

### Game Options

Opens the Game Options screen to allow for game settings to be viewed and changed (See Game Options below for more 
details).

### Manage Expansion Packs

Install and remove expansions packs (OXPs). Not all mod packs can be installed and removed by this method – others, 
especially older ones, can be found at [https://wiki.alioth.net/index.php/OXP_List](https://wiki.alioth.net/index.php/OXP_List).

### Exit Game

Exit the game.

## Controls and Commands

The current keyboard configuration can be edited by selecting “Keyboard Configuration” from the “Game Options” menu.

Oolite can be controlled using the keyboard, mouse and/or game controller.

The list below describes the default key settings.

### In Dock Commands

| Key                           | Menu / Action         | Sub-Item / Control    | Interaction & Details                                                                                                                        |
|:------------------------------|:----------------------|:----------------------|:---------------------------------------------------------------------------------------------------------------------------------------------|
| <kbd>1</kbd> or <kbd>F1</kbd> | **Launch**            | —                     | Propels your spacecraft from docked station.                                                                                                 |
| <kbd>2</kbd> or <kbd>F2</kbd> | **Quick-Save / Load** | **File Selection**    | Use <kbd>↑</kbd> and <kbd>↓</kbd> to select, <kbd>Enter</kbd> to choose.                                                                     |
|                               | **Game Options**      | **Autosave**          | <kbd>←</kbd> <kbd>→</kbd> to toggle. When enabled, creates a save every time you launch from a planetary station.                            |
|                               |                       | **Docking Clearance** | <kbd>←</kbd> <kbd>→</kbd> to toggle. If enabled, docking without clearance at Galcop/OXP stations results in a fine.                         |
|                               |                       | **Audio Settings**    | <kbd>←</kbd> <kbd>→</kbd> to adjust **Source Volume** or toggle **Music** (Mac users also have "iTunes" option).                             |
|                               |                       | **Spoken Messages**   | <kbd>←</kbd> <kbd>→</kbd> or <kbd>Enter</kbd> to toggle. Uses selectable voice.                                                              |
|                               |                       | **Display Mode**      | <kbd>←</kbd> <kbd>→</kbd> to select screen size/refresh rate. <kbd>Enter</kbd> to toggle Window/Full Screen (or use <kbd>F12</kbd> anytime). |
|                               |                       | **HDR Brightness**    | <kbd>←</kbd> <kbd>→</kbd> to adjust **Max Brightness** and **Paper White** levels (for HDR-capable systems only).                            |
|                               |                       | **Graphics / Gamma**  | <kbd>←</kbd> <kbd>→</kbd> to toggle **Wireframe** mode, **Gamma** correction, or **Graphics Detail** (Minimal, Normal, Shaders, Extra).      |
|                               |                       | **Field Of View**     | <kbd>←</kbd> <kbd>→</kbd> to adjust (30°–80°). Lower values make objects appear larger; higher values increase peripheral vision.            |
|                               |                       | **Colorblind Mode**   | <kbd>←</kbd> <kbd>→</kbd> to select: None, Protanopia, Deuteranopia, or Tritanopia.                                                          |
|                               |                       | **Config Screens**    | Press <kbd>Enter</kbd> on **Joystick** or **Keyboard** configuration to view/change assignments.                                             |
|                               | **System**            | **End / Exit**        | Press <kbd>Enter</kbd> to **End Game** (return to menu) or **Exit Game** (quit to desktop).                                                  |
| <kbd>3</kbd> or <kbd>F3</kbd> | **Shipyard**          | **Outfitting**        | <kbd>↑</kbd> <kbd>↓</kbd> to select, <kbd>Enter</kbd> to purchase. <kbd>←</kbd> <kbd>→</kbd> to move between pages.                          |
| <kbd>4</kbd> or <kbd>F4</kbd> | **Interfaces**        | **Station/Ship**      | <kbd>↑</kbd> <kbd>↓</kbd> to select, <kbd>Enter</kbd> to open. <kbd>←</kbd> <kbd>→</kbd> for pages.                                          |
| <kbd>5</kbd> or <kbd>F5</kbd> | **Manifest**          | **Status/Cargo**      | Toggles views. Use <kbd>←</kbd> and <kbd>→</kbd> to move between pages.                                                                      |
| <kbd>6</kbd> or <kbd>F6</kbd> | **Galactic Chart**    | **Navigation**        | **Mouse Drag** to pan; **Wheel** or <kbd>PgUp</kbd>/<kbd>PgDn</kbd> to Zoom.                                                                 |
|                               |                       | **Selection**         | <kbd>Click</kbd> or **Cursors** to select. **Double-Click** for System Data.                                                                 |
|                               |                       | **Home**              | <kbd>Home</kbd> selects current system.                                                                                                      |
|                               |                       | **Routing**           | <kbd>^</kbd> plots route (Fewest Jumps/Time). *Requires advanced navigational array.*                                                        |
|                               |                       | **Filters**           | <kbd>?</kbd> highlights by economy, government, tech level, or sun color. *Requires advanced navigational array.*                            |
|                               |                       | **Info History**      | <kbd>Alt</kbd> + <kbd>←</kbd> / <kbd>→</kbd> to cycle previous system info screens for the F7 display.                                       |
|                               |                       | **Search / Info**     | **Type Name** to find (Entire Chart); <kbd>i</kbd> for tech info (Zoomed).                                                                   |
| <kbd>7</kbd> or <kbd>F7</kbd> | **Database**          | **System Info**       | Shows detailed planetary database for the system selected on the Chart.                                                                      |
| <kbd>8</kbd> or <kbd>F8</kbd> | **Market**            | **Selection**         | Use <kbd>↑</kbd> and <kbd>↓</kbd> to select commodity.                                                                                       |
|                               |                       | **Buying**            | <kbd>→</kbd> buys 1 unit. <kbd>Shift</kbd> + <kbd>→</kbd> buys maximum possible.                                                             |
|                               |                       | **Selling**           | <kbd>←</kbd> sells 1 unit. <kbd>Shift</kbd> + <kbd>←</kbd> sells maximum possible.                                                           |
|                               |                       | **Smart Trade**       | <kbd>Enter</kbd>: If holding item, sells all. If empty, buys maximum possible.                                                               |
|                               |                       | **Filters**           | <kbd>?</kbd> cycles: All goods, Carried in stock, Carried, In stock, No transport restrictions, Transport restrictions.                      |
|                               |                       | **Sorting**           | <kbd>/</kbd> cycles: Default, Alphabetical, Price, Quantity in stock, Quantity in hold, Unit mass.                                           |

### Flight Key Commands

### Movement & Attitude

| Key                         | Action             | Notes                                                           |
|:----------------------------|:-------------------|:----------------------------------------------------------------|
| <kbd>↑</kbd> <kbd>↓</kbd>   | **Pitch**          | Nose up and down.                                               |
| <kbd>←</kbd> <kbd>→</kbd>   | **Roll**           | Rotate ship along the longitudinal axis.                        |
| <kbd>,</kbd> <kbd>.</kbd>   | **Yaw**            | Turn nose left and right.                                       |
| <kbd>Ctrl</kbd>             | **Precision Mode** | Hold while turning to move more slowly/precisely.               |
| <kbd>w</kbd> / <kbd>s</kbd> | **Speed Control**  | <kbd>w</kbd> to Increase Speed; <kbd>s</kbd> to Decrease Speed. |

### Propulsion & Travel

| Key          | Action                  | Notes                                                                        |
|:-------------|:------------------------|:-----------------------------------------------------------------------------|
| <kbd>j</kbd> | **Torus Jump Drive**    | Toggle in-system hyperspeed. Disabled by nearby mass/gravity.                |
| <kbd>h</kbd> | **Hyperdrive**          | Activate Witchspace jump. Requires a target selected on <kbd>F6</kbd> chart. |
| <kbd>g</kbd> | **Galactic Hyperdrive** | Activate the inter-galactic jump drive (if installed).                       |
| <kbd>i</kbd> | **Fuel Injection**      | Activate afterburners/Witchdrive injectors (if installed).                   |

### Weaponry & Combat

| Key          | Action               | Notes                                                                                                                                   |
|:-------------|:---------------------|:----------------------------------------------------------------------------------------------------------------------------------------|
| <kbd>a</kbd> | **Fire Laser**       | Fire main weapon for the current view facing.                                                                                           |
| <kbd>_</kbd> | **Weapons Lockdown** | Toggle safety lockdown on/off.                                                                                                          |
| <kbd>e</kbd> | **ECM**              | Activate Electronic Counter-Measures to destroy incoming missiles.                                                                      |
| <kbd>p</kbd> | **Pause**            | **Pause/Un-pause.** While paused, press <kbd>2</kbd> or <kbd>F2</kbd> to access Options, or <kbd>o</kbd> to toggle HUD for screenshots. |

### Missiles & Pylon Equipment

| Key                           | Action              | Notes                                                                |
|:------------------------------|:--------------------|:---------------------------------------------------------------------|
| <kbd>r</kbd>                  | **Identify Target** | Activate ID system (deactivates missile/mine system).                |
| <kbd>t</kbd>                  | **Target/Arm**      | Enable missile targeting or arm mine. Locks missile if ID is active. |
| <kbd>y</kbd>                  | **Cycle Missiles**  | Switch to next available pylon. *Requires Multi-Targeting System.*   |
| <kbd>Shift</kbd>+<kbd>t</kbd> | **Target Missile**  | Immediately target the nearest incoming enemy missile.               |
| <kbd>u</kbd>                  | **Unarm / Safety**  | Deactivate ID or put missiles into safety mode.                      |
| <kbd>m</kbd>                  | **Launch/Drop**     | Fire locked missile or drop armed mine.                              |

### Selectable Equipment & MFDs

| Key                                                                           | Action              | Notes                                                                             |
|:------------------------------------------------------------------------------|:--------------------|:----------------------------------------------------------------------------------|
| <kbd>n</kbd>                                                                  | **Activate**        | Activate currently selected equipment.                                            |
| <kbd>Shift</kbd>+<kbd>n</kbd> / <kbd>Shift</kbd>+<kbd>Ctrl</kbd>+<kbd>n</kbd> | **Cycle Equipment** | Select Next or Previous equipment in your inventory.                              |
| <kbd>b</kbd>                                                                  | **Mode Change**     | Change mode for the selected equipment (if applicable).                           |
| <kbd>Tab</kbd> / <kbd>0</kbd>                                                 | **Fast Slots**      | Activate equipment in Fast Slot 1 (<kbd>Tab</kbd>) or Slot 2 (<kbd>0</kbd>).      |
| <kbd>;</kbd> / <kbd>:</kbd>                                                   | **MFD Controls**    | <kbd>;</kbd> to rotate current display; <kbd>:</kbd> to select next display area. |
| <kbd>+</kbd> / <kbd>-</kbd>                                                   | **Target Memory**   | Lock on to next/previous target in memory expansion (if installed).               |

### Sensors & Navigation

| Key                                          | Action              | Notes                                                                               |
|:---------------------------------------------|:--------------------|:------------------------------------------------------------------------------------|
| <kbd>z</kbd> / <kbd>Shift</kbd>+<kbd>z</kbd> | **Scanner Zoom**    | <kbd>z</kbd> cycles zoom (1:1 to 5:1); <kbd>Shift</kbd>+<kbd>z</kbd> resets to 1:1. |
| <kbd>\\</kbd>                                | **Compass Mode**    | Cycle targets (Planet, Station, Sun, Target, Beacons).                              |
| <kbd>\|</kbd>                                | **Compass Reverse** | Reverse cycle the Compass Mode.                                                     |
| <kbd>`</kbd> (Backtick)                      | **Comms Log**       | View recent ship-to-ship message history.                                           |

### Docking & Utility

| Key                           | Action            | Notes                                                           |
|:------------------------------|:------------------|:----------------------------------------------------------------|
| <kbd>c</kbd>                  | **Autodock**      | Begin/Abandon docking sequence. *Requires Docking Computer.*    |
| <kbd>Shift</kbd>+<kbd>c</kbd> | **Instant Dock**  | Fast docking without the sequence. Advances game clock 20 mins. |
| <kbd>Shift</kbd>+<kbd>l</kbd> | **Docking Clear** | Request, cancel, or renew docking clearance with a station.     |
| <kbd>s</kbd>                  | **Docking Music** | Toggle music during the automated docking sequence.             |
| <kbd>Shift</kbd>+<kbd>d</kbd> | **Eject Cargo**   | Jettisons one cargo pod into space.                             |
| <kbd>Shift</kbd>+<kbd>r</kbd> | **Rotate Cargo**  | Choose which cargo type is at the "front" of the eject queue.   |
| <kbd>Esc</kbd> <kbd>Esc</kbd> | **Escape Pod**    | Quickly double-tap to abandon ship (if installed).              |

### Viewscreens & Systems

| Key                                                 | Action                 | Notes                                                                |
|:----------------------------------------------------|:-----------------------|:---------------------------------------------------------------------|
| <kbd>1</kbd> or <kbd>F1</kbd>                       | **Forward View**       | Look out the front of the ship.                                      |
| <kbd>2</kbd> or <kbd>F2</kbd>                       | **Aft View**           | Look out the back of the ship.                                       |
| <kbd>3</kbd> or <kbd>F3</kbd>                       | **Port View**          | Look out the left side of the ship.                                  |
| <kbd>4</kbd> or <kbd>F4</kbd>                       | **Starboard View**     | Look out the right side of the ship.                                 |
| <kbd>5</kbd> or <kbd>F5</kbd>                       | **Status/Manifest**    | Toggles between Ship Status and Cargo Manifest.                      |
| <kbd>6</kbd> or <kbd>F6</kbd>                       | **Galactic Chart**     | Toggles between Zoomed and Entire range charts.                      |
| <kbd>7</kbd> or <kbd>F7</kbd>                       | **System Data**        | Shows the Planetary Database for the selected system.                |
| <kbd>8</kbd> or <kbd>F8</kbd>                       | **Market**             | Access the Commodity Market.                                         |
| <kbd>v</kbd>                                        | **External View**      | Toggle between external free-look views.                             |
| <kbd>↑</kbd> <kbd>↓</kbd> <kbd>←</kbd> <kbd>→</kbd> | **External Camera**    | Use arrow keys to rotate the camera in external view.                |
| <kbd>Caps Lock</kbd> + **Mouse**                    | **External Free-look** | Move the mouse while Caps Lock is on for free-look in external view. || <kbd>*</kbd> (Asterisk) | **Screenshot** | Saves a .png to your `oolite-saves` folder. |
| <kbd>Shift</kbd>+<kbd>f</kbd>                       | **FPS Toggle**         | Show/hide the frames-per-second counter.                             |
| <kbd>F12</kbd>                                      | **Screen Mode**        | Toggle between Full Screen and Windowed mode.                        |
| <kbd>Shift</kbd>+<kbd>Esc</kbd>                     | **Quit**               | Immediate exit to desktop.                                           |

---

### Mouse Flight Controls

To enable mouse flight (available in Full Screen mode only), use the following toggles:

| Key Combination                                   | Action                                   |
|:--------------------------------------------------|:-----------------------------------------|
| <kbd>Shift</kbd> + <kbd>M</kbd>                   | Toggle mouse control (X-axis = **Roll**) |
| <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>M</kbd> | Toggle mouse control (X-axis = **Yaw**)  |

* <kbd>Shift</kbd> + <kbd>M</kbd>: Toggle mouse control (X-axis = **Roll**)
* <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>M</kbd>: Toggle mouse control (X-axis = **Yaw**)

**Active Mouse Commands:**

| Input                      | Action                                           |
|:---------------------------|:-------------------------------------------------|
| **Mouse Left/Right**       | Roll or Yaw (depending on toggle mode)           |
| **Mouse Forward/Back**     | Pitch                                            |
| **Primary Mouse Button**   | Fire main weapon                                 |
| **Secondary Mouse Button** | Center all controls (cancels roll/yaw and pitch) |
| **Mouse Wheel Up/Down**    | Increase or Decrease speed                       |

## Game Data

Game data such as your saved games and expansion packs are stored in certain locations depending upon the setup:

| OS      | Type     | Default Game Data Folder                  |
|:--------|:---------|:------------------------------------------|
| Windows | NSIS     | `<Oolite installation folder>/oolite.app` |
| Linux   | AppImage | `<AppImage folder>/GameData`              |
| Linux   | Flatpak  | `$HOME/.var/app/space.oolite.Oolite`      |

### Linux

The AppImage can be configured to use alternative locations by setting various environment variables:

| Variable   | Value  | Game Folder                    |
|:-----------|:-------|:-------------------------------|
| OO_DIRTYPE | xdg    | `$HOME/.local/share/Oolite`    |
| OO_DIRTYPE | legacy | `$HOME` (old folder structure) |

Using legacy is not recommended.

More intricate setups are possible by specifying individual environment variables for different folders:

| Environment Variable      | Description                              | Default Path (if unset)                  |
|:--------------------------|:-----------------------------------------|:-----------------------------------------|
| `OO_SAVEDIR`              | Directory for saved games                | `$GAME_DATA/SavedGames`                  |
| `OO_SNAPSHOTSDIR`         | Directory for screenshots/snapshots      | `$GAME_DATA/Snapshots`                   |
| `OO_LOGSDIR`              | Directory for game log files             | `$GAME_DATA/.logs`                       |
| `OO_MANAGEDADDONSDIR`     | Directory for OXPs managed by the game   | `$GAME_DATA/.ManagedAddOns`              |
| `OO_USERADDONSDIR`        | User-specified directory for OXPs        | `$GAME_DATA/AddOns`                      |
| `OO_ADDONSEXTRACTDIR`     | Directory for extracted OXPs             | `${OO_USERADDONSDIR:-$GAME_DATA/AddOns}` |
| `OO_ADDITIONALADDONSDIRS` | List of extra addon search paths         |                                          |
| `OO_GNUSTEPDIR`           | GNUstep directory                        | `$GAME_DATA/.GNUstep`                    |
| `OO_GNUSTEPDEFAULTSDIR`   | User prefereences defaults file location | `$GAME_DATA`                             |

## Changing user preferences

The user preferences defaults file OoliteDefaults.plist contains the current settings for vaerious 'Game Options...' menu entries:

* Autosave (Off/On)
* Sound Volume (Mute to 100% in increments of 5%)
* Music mode (Off/On)
* Full Screen Mode and Display Resolutions
* Wireframe Graphics (Off/On)
* Graphics Detail (Minimum, Normal, Shaders Enabled, Extra)
* Gamma correction (0.02 to 4.0 in increments of 0.02)
* Field Of View (30° to 80° in 20 increments)
* Javascript Runtime (in mib)

The file is created after Oolite first execution. It is located 

Windows: `*\<Oolite installation folder\>*/oolite.app/GNUstep/Defaults/`

Linux AppImage: `*\<AppImage folder\>*/GameData` (or can be configured to use `~/.local/share/Oolite`)
Linux Flatpak

The recommended way to change these settings is to use the in-game options menu. Troubleshooting or the need to experiment with more advanced options, may lead to directly editing the file. For the changes to take effect, the file must be edited and saved before executing Oolite. 

For more information please refer to [https://wiki.alioth.net/index.php/Hidden\_Settings\_in\_Oolite](http://wiki.alioth.net/index.php/Hidden_Settings_in_Oolite) .

## Test Builds

Starting with Oolite 1.77 there are two different versions of the game. A normal version without debugging tools and a slightly slower version with debugging options that can be used with the console. This test build version will be useful for oxp developers.

The test builds have the following extra features:

* When pressing <kbd>Shift</kbd>+<kbd>F</kbd>, the FPS display will show additional info, including a TAF indicator.
* A console can be used, to type in JavaScript commands, interfacing directly with the Oolite universe and its entities.

The following debugging options are accessible while paused:

| Key                           | Action                                                                 |
|:------------------------------|:-----------------------------------------------------------------------|
| <kbd>0</kbd>                  | Dump a list of all entities in the log-file.                           |
| <kbd>b</kbd>                  | Enable collision test debugging.                                       |
| <kbd>c</kbd>                  | Enables octree debugging.                                              |
| <kbd>d</kbd>                  | Enables all debug flags.                                               |
| <kbd>s</kbd>                  | Enables shader debug messages.                                         |
| <kbd>x</kbd>                  | Enables drawing of bounding boxes around all entities.                 |
| <kbd>n</kbd>                  | Disables all debug flags and displays HUD again.                       |
| <kbd>←</kbd> and <kbd>→</kbd> | **Time Acceleration:** Halves or Doubles the Time Acceleration Factor. |

## Helpful Information

For more information on playing Oolite visit [https://www.oolite.space](http://www.oolite.org/).

Browse the Oolite Wiki at [https://wiki.alioth.net/index.php/Oolite\_Main\_Page](http://wiki.alioth.net/index.php/Oolite_Main_Page) .

Check the Frequently Asked Questions at [https://wiki.alioth.net/index.php/Oolite\_FAQ](http://wiki.alioth.net/index.php/Oolite_FAQ) .

Most Oolite mods, often referred to as OXP’s (Oolite eXpansion Packs) are available at [https://wiki.alioth.net/index.php/OXP](http://wiki.alioth.net/index.php/OXP) , or from the Expansion Manager in the game.

The Oolite Development Project Page is located at <https://github.com/OoliteProject/oolite> .

For answers to questions about playing Oolite, customizing Oolite and anything else Oolite related, post to the Oolite Bulletin Boards at [https://bb.oolite.space](https://bb.oolite.space/) .

Oolite is making use of various external open source libraries, some of them modified to fit certain requirements of the game. For more information about where to find the source code of those libraries, as well as information about the modifications required to make them build for Oolite, please refer to the file *ExternalLibrariesSourceCodeChanges.txt*, found inside the Doc folder of the game’s source code distribution.

Military laser sound courtesy of user “notyermom”, sourced from <https://freesound.org/people/notyermom/sounds/434834/> under license: <https://creativecommons.org/publicdomain/zero/1.0/>

Mining laser sound courtesy of user “bubaproducer”, sourced from <https://freesound.org/people/bubaproducer/sounds/151022/> under license: <https://creativecommons.org/licenses/by/3.0/>

Beam laser sound courtesy of user “jobro”, sourced from <https://freesound.org/people/jobro/sounds/35677/> under license: <https://creativecommons.org/licenses/by/3.0/>

Your feedback is essential to keep improving Oolite.

A lot of effort has been put in making Oolite stable. In the, nowadays rare, event Oolite crashes, it will be highly appreciated if you let us know by raising an issue at <https://github.com/OoliteProject/oolite/issues> or by creating a topic in trhe “Testing and Bug reports” section of the Oolite Bulletin Board, found here: <https://bb.oolite.space/viewforum.php?f=3>. In both cases, attaching the crash log can be very helpful in solving problems. It is located at

Windows: *\<Oolite installation folder\>*/oolite.app/Logs/Latest.log

Linux: ~/.Oolite/Logs/Latest.log

Be encouraged to drop by the Oolite Bulletin Board at <https://bb.oolite.space> to give feedback and chat about the game. It’s the friendliest place this side of Riedquat!

**We are immensely grateful to all the people who have been testing Oolite and tediously bringing it towards perfection.**

**Thank you all!**

## License

Copyright © 2004-2026 Giles C Williams, Jens Ayton and contributors.

This work is licensed under the GNU General Public License version 2.

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.

Additionally, all artwork – 3D models, images and sounds – included in the work, as well as configuration files, are also licensed under the Commons Creative Attribution-Non Commercial-Share Alike License version 3.0. This means that these files may be distributed under either license at your discretion.

To view a copy of Attribution-Non Commercial-Share Alike license, visit <http://creativecommons.org/licenses/by-nc-sa/3.0/> or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

* to Share — to copy, distribute and transmit the work
* to Remix — to adapt the work

under the following conditions:

* Attribution. You must attribute the work in the manner specified by the author or licensor (but not in any way that suggests that they endorse you or your use of the work).
* Noncommercial. You may not use this work for commercial purposes.
* Share Alike. If you alter, transform, or build upon this work, you may distribute the resulting work only under the same or similar license to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of the above conditions can be waived if you get permission from the copyright holder.

Apart from the remix rights granted under this license, nothing in this license impairs or restricts the author’s moral rights

Your fair dealing and other rights are in no way affected by the above.

This is a human-readable summary of the Legal Code (the full license).

The source code distribution and the Mac OS X version of Oolite contain parts subject to the following license:

VirtualRingBuffer

Copyright © 2002, Kurt Revis. All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
* Neither the name of Snoize nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS “AS IS” AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

The MiniZip code used is subject to the following license.

License

----------------------------------------------------------

Condition of use and distribution are the same than zlib :

This software is provided 'as-is', without any express or implied warranty. In no event will the authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose, including commercial applications, and to alter it and redistribute it freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim that you wrote the original software. If you use this software in a product, an acknowledgment in the product documentation would be appreciated but is not required.
2. Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
3. This notice may not be removed or altered from any source distribution.

----------------------------------------------------------
