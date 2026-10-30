#import "common.typ": *

#header-text.update("Settings and Flight Controls")

#show: setup-page

#show: apply-table-styles

// ==========================================
// PAGE 4: SETTINGS AND FLIGHT CONTROLS
// ==========================================

#grid(
  columns: (1fr, 1fr, 1fr, 1fr),
  gutter: 0.6cm,

  // ------------------------------------------
  // COLUMN 1: Game Settings
  // ------------------------------------------
  stack(spacing: 0.5em)[
    #table(
      columns: (1fr),
      section-header("Game Settings", colspan: 1),
      [*Autosave* -- _on / off_ \ Automatically saves your game as ‘autosave' before you leave a GCW Station.],
      [*Docking Clearance Protocol* -- _on / off_ \ Enables docking clearance requests for GCW stations (and some OXP stations).],
      [*Music* -- _off / on_ \ Turns the in-game music on and off.],
      [*Sound Volume* -- _sliding scale_ \ Volume slider controls both in-game music and sound effects.],
      [*Spoken Messages* -- _off / on_ \ Makes the computer read all messages (if "on", Voice and Gender options are available).],
      [*Full Screen Mode* -- _width x height_ \ Rotate through screen resolutions choices for full screen mode.],
      [*Play in Window / Full Screen* \ Toggle between playing the game in full screen or a window.],
      [*HDR Max Brightness (nits)* -- _value_ \ HDR Mode only. Max brightness monitor is able to produce.],
      [*HDR Paper White Brightness (nits)* -- _sliding scale_ \ HDR mode only. Controls how bright a paper white surface should be.],
      [*Wireframe Graphics* -- _on / off_ \ Play Oolite with visuals reminiscent of the original Elite. This visual style does not alter game speed.],
      [*Graphics Detail* -- _minimum / normal / shaders / extra_ \ Changes the levels of in-game graphics detail. Higher settings may be unavailable on old hardware, and use more processing power.],
      [*Gamma* -- _sliding scale_ \ Adjust gamma setting for Oolite to suit your display hardware.],
      [*Field Of View* -- _sliding scale, in degrees_ \ Adjust field of view of your viewscreen, value range 30-80.],
      [*Colorblind Mode* -- _None / Protanopia / Deuteranopia / Tritanopia_ \ Available when "Graphics Detail" set to "Shaders" or "Extra detail". Adjusts the colors of the game to help colorblind players see things more clearly.],
      [*Joystick Configuration* \ Assign most game actions to your joystick.],
      [*Keyboard Configuration* \ Reassign any game actions to keys on your keyboard.]
    )
  ],

  // ------------------------------------------
  // COLUMN 2: Joystick Flight Controls - Propulsion & Navigation
  // ------------------------------------------
  stack(spacing: 0.5em)[
    #table(
      columns: (1fr),
      section-header("Joystick Flight Controls", colspan: 1),
      table-gap(colspan: 1),
      sub-header("Propulsion", colspan: 1),
      [*Roll* \ Direction axis for roll anti/clockwise.],
      [*Pitch* \ Direction axis for dive/climb.],
      [*Yaw* \ Direction axis for turn left/right.],
      [*Increase / Decrease thrust* \ Buttons or direction axis to fly faster or slower.],
      [*Fuel injection* \ Button to activate the Witchspace Fuel Injectors.],
      [*Torus drive* \ Button to activate the Torus drive hyperspeed system.],
      [*Witchspace jump* \ Button to initiate a witchspace jump.],
      [*Galactic jump* \ Button to initiate a galactic jump.],
      [*Roll/pitch precision toggle* \ Button to toggle the degree of thrust relative to angle of the joystick.]
    )

    #table(
      columns: (1fr),
      sub-header("Navigation", colspan: 1),
      [*Next / Previous compass target* \ Buttons to select the next/previous space compass target.],
      [*Zoom scanner* \ Button to zoom out the scanner.],
      [*Unzoom scanner* \ Button to reset the scanner zoom factor.],
      [*Forward / aft / port / starboard view* \ Buttons or axes to change the view screen direction.],
      [*Cycle external views* \ Button to cycle the available external views.],
      [*Ident system* \ Button to activate the ID Recognition System.],
      [*Request docking clearance* \ Button to request docking clearance from a station.],
      [*Docking computer* \ Button to activate/deactivate the docking computer.],
      [*Fast docking* \ Button to activate the fast docking computer.],
      [*Toggle docking music on/off* \ Button to turn on/off the docking music.]
    )
  ],

  // ------------------------------------------
  // COLUMN 3: Joystick Flight Controls - Offensive, Defensive, Special Equipment
  // ------------------------------------------
  stack(spacing: 0.5em)[
    #table(
      columns: (1fr),
      section-header("Joystick Flight Controls", colspan: 1),
      table-gap(colspan: 1),
      sub-header("Offensive", colspan: 1),
      [*Weapons toggle* \ Button to toggle weapons online/offline.],
      [*Fire laser* \ Button to fire the energy weapon.],
      [*Fire missile/bomb* \ Button to fire currently active pylon-mounted weapon or equipment.],
      [*Arm missile/bomb* \ Button to activate / target seek currently highlighted pylon-mounted weapon or equipment.],
      [*Disarm missile/bomb* \ Button to deactivate highlighted pylon-mounted weapon or equipment.],
      [*Target incoming missile* \ Button to automatically target the incoming missile nearest to the player ship.],
      [*Select next missile/bomb* \ Button to rotate through the available range of pylon-mounted weapons or equipment.],
      [*Next / Previous target* \ Buttons to cycle to next/previous target.]
    )

    #table(
      columns: (1fr),
      sub-header("Defensive", colspan: 1),
      [*ECM* \ Button to activate the Electronic Counter-Measure Systems.],
      [*Dump cargo* \ Button to dump one cargo canister.],
      [*Rotate cargo* \ Button to rotate through the manifest.],
      [*Escape pod* \ Button to activate the Escape Pod, if installed. Requires fast double press.]
    )

    #table(
      columns: (1fr),
      sub-header("Special Equipment", colspan: 1),
      [*Select next / previous MFD* \ Buttons to select the next/previous MFD.],
      [*Cycle next / previous MFD* \ Buttons to cycle to the next/previous MFD display.],
      [*Prime next / previous equipment* \ Buttons to cycle through selectable equipment.],
      [*Activate equipment* \ Button to activate primed selectable equipment.],
      [*Set equipment mode* \ Button to change the mode of the primed equipment.]
    )
  ],

  // ------------------------------------------
  // COLUMN 4: Fast-Activate, Miscellaneous, Mouse Controls
  // ------------------------------------------
  stack(spacing: 0.5em)[
    #table(
      columns: (1fr),
      section-header("Joystick Flight Controls", colspan: 1),
      table-gap(colspan: 1),
      sub-header("Fast-Activate Equipment", colspan: 1),
      [*Fast-activate first equipment item* \ Button to fast-activate the first equipment item.],
      [*Fast-activate second equipment item* \ Button to fast-activate the second equipment item.]
    )

    #table(
      columns: (1fr),
      sub-header("Miscellaneous", colspan: 1),
      [*Take Snapshot* \ Button to capture a screen shot.],
      [*Pause* \ Button to pause the game.],
      [*Toggle HUD* \ Button to toggle the HUD on/off.],
      [*Comms log* \ Button to view the comms log.]
    )

    #table(
      columns: (1fr),
      section-header("Mouse Flight Controls", colspan: 1),
      table.cell(inset: (top: 8pt, bottom: 4pt, x: 2.8pt))[
        #text(size: 7.5pt)[
          Fly by mouse control is only available when the game is in Full Screen mode.
        ]
      ],
      [*Move Mouse Up and Down* \ Ship dives and climbs.],
      [*Move Mouse Left and Right* \ Roll anticlockwise and clockwise.],
      [*Left Mouse Button* \ Fire primary weapon.],
      [*Right Mouse Button* \ Zero flight roll and pitch.],
      [*Mouse Wheel Up* \ Increase speed.],
      [*Mouse Wheel Down* \ Decrease speed.],
    )

    #table(
      columns: (1fr),
      sub-header("External View", colspan: 1),
      table.cell(inset: (top: 8pt, bottom: 4pt, x: 2.8pt))[
        #text(size: 7.5pt)[
          With Caps Lock active & Left Mouse Button down:
        ]
      ],
      [*Move Mouse Up and Down* \ External Camera rotates Up / Down.],
      [*Move Mouse Left and Right* \ External Camera rotates Left / Right.],
      table.cell(inset: (top: 8pt, bottom: 4pt, x: 2.8pt))[
        #text(size: 7.5pt)[
          With Caps Lock active:
        ]
      ],
      [*Mouse Wheel Up* \ Zoom View In.],
      [*Mouse Wheel Down* \ Zoom View Out.]
    )
  ]
)
