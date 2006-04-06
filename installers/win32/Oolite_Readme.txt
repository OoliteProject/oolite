

How to run Oolite
-----------------

A folder has been created in Start -> Program Files called Oolite. This
folder has icons for running the game, the reference sheet, this file,
and an uninstall program.

To run the game, choose the Oolite icon in the Oolite folder.


Switching between full screen and windowed mode, or changing resolution
-----------------------------------------------------------------------

The Windows version of Oolite loses the OpenGL texture information when you
switch between full-screen and windowed mode, or change resolution.

You must quit the game using Shift-Escape and restart to get use the
new mode or resolution.

The file <installation dir>/oolite.app/GNUstep/Defaults/.GNUstepDefaults
contains the current settings for fullscreen mode and display resolutions.

If in doubt, delete this file and restart the game. That will start you
in windowed mode.

Do not try to resize the window in windowed mode. The settings are not
saved under Windows and the game will restart in an 800x600 widow.

To change the full screen mode resolution, change the display_width and
display_height values, and ensure the fullscreen property has a value of
<*BY>.

These settings will give a full screen display of 800x600:

{
    NSGlobalDomain = {
    };
    oolite.exe = {
    display_width = <*I800>;
    display_height = <*I600>;
	fullscreen = <*BY>;
	volume_control = <*R1>;
    };
}

And these settings will give a full screen display of 1400x1050:

{
    NSGlobalDomain = {
    };
    oolite.exe = {
    display_width = <*I1400>;
    display_height = <*I1050>;
	fullscreen = <*BY>;
	volume_control = <*R1>;
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

Get OXPs at: http://oosat.alioth.net/

