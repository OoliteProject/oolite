

How to run Oolite
-----------------

A folder has been created in Start -> Program Files called Oolite. This
folder has icons for running the game, the reference sheet, this file,
and an uninstall program.

To run the game, choose the Oolite icon in the Oolite folder.


The user preferences defaults file .GNUstepDefaults
-----------------------------------------------------------------------

The file <installation dir>/oolite.app/GNUstep/Defaults/.GNUstepDefaults
contains the current settings for fullscreen mode and display resolutions,
together with the user preference settings for sound volume, reduced
detail (Yes/No), wireframe graphics display (Yes/No) and the shader
effects level (Off, Simple, Full), in case your system supports shaders.
All these can be changed by either running the game and navigating to the
Game Options... menu ('F2' or '2' key, then select Game Options...), or
by directly editing the .GNUstepDefaults file. The recommended way to
change settings is to use the in-game menu. See below for examples of
editing the preferences file. Note that .GNUstepDefaults will not be
present after the game's installation. You will need to run Oolite at
least once to have it generated.


Switching between full screen and windowed mode, or changing resolution
-----------------------------------------------------------------------

This should work significantly better than in previous versions of Oolite
for Windows.

There are still some problems with models and their textures, but for the
most part all the textures get reinitialised and keep working.

If in doubt, delete .GNUstepDefaults and restart the game. That will start
you in windowed mode.

Do not try to resize the window in windowed mode. The settings are not
saved under Windows and the game will restart in an 800x600 widow.

To change the full screen mode resolution, you can use the Game Options...
menu or alternatively edit the .GNUstepDefaults file by changing the
display_width and display_height values, and ensuring the fullscreen
property has a value of <*BY>.


.GNUstepDefaults Editing Examples
-----------------------------------------------------------------------

These settings will give a full screen display of 800x600, about one
third sound volume, reduced detail set to No, wireframe graphics set
to Yes and shader effects set to Simple:

{
    NSGlobalDomain = {
    };
    oolite.exe = {
    display_width = <*I800>;
    display_height = <*I600>;
    fullscreen = <*BY>;
    "reduced-detail-graphics" = <*BN>;
    "shader-effects-level" = <*I2>;
    volume_control = <*R0.26>;
    "wireframe-graphics" = <*BY>;
    };
}

And these settings will give a full screen display of 1400x1050,
full sound volume, reduced detail set to No, wireframe graphics
set to No and shader effects set to Full:

{
    NSGlobalDomain = {
    };
    oolite.exe = {
    display_width = <*I1400>;
    display_height = <*I1050>;
    fullscreen = <*BY>;
    "reduced-detail-graphics" = <*BN>;
    "shader-effects-level" = <*I3>;
    volume_control = <*R1>;
    "wireframe-graphics" = <*BN>;
    };
}


Tips
----

* Read the installed "Oolite reference sheet" PDF for the controls

* Use Shift+Escape to quit the game

* Read the tutorial before you begin! ( http://oolite.aegidian.org/tutorial )


Links
-----
Oolite Message board at: http://www.aegidian.org/bb

Browse the Oolite wiki at: http://wiki.alioth.net/index.php/Oolite_Main_Page

Get OXPs at: 	http://wiki.alioth.net/index.php/OXP
		http://oosat.alioth.net/
