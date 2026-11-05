#import "common.typ": *

#header-text.update("Keyboard Guide")

#show: setup-page.with(header-size: 9.7pt, body-size: 8.89pt)

#show: apply-table-styles.with(columns: (auto, 1fr, auto, 1fr), align: (center, left, center, left))

#let color_green = rgb("90EE90")
#let color_blue = rgb("AFEEEE")

#let keybox_wide(clr, txt) = box(
  width: 25pt,
  height: 10pt,
  stroke: 0.5pt + rgb("000000"),
  fill: clr,
  inset: 1pt,
  txt
)

#let keybox_mid(clr, txt) = box(
  width: 19pt,
  height: 10pt,
  stroke: 0.5pt + rgb("000000"),
  fill: clr,
  inset: 1pt,
  txt
)

#let keybox(clr, txt) = box(
  width: 12pt,
  height: 10pt,
  stroke: 0.5pt + rgb("000000"),
  fill: clr,
  inset: 1pt,
  txt
)

#let keybox_slim(clr, txt) = box(
  width: 6pt,
  height: 10pt,
  stroke: 0.5pt + rgb("000000"),
  fill: clr,
  inset: 1pt,
  txt
)

// 3-Column Page Layout Container
#grid(
  columns: (1.1fr, 1.1fr, 0.85fr),
  gutter: 0.6cm,

  // ==========================================
  // COLUMN 1: Flight, Combat, & Commodities
  // ==========================================
  stack(spacing: 0.5em)[
    #table(
      section-header("Flight Controls", colspan: 4),
      [#keybox(none, "F1") #keybox(none, "1")], [Forward (front) view], [#keybox(none, "V")], [External views#super[2];],
      [#keybox(none, "F2") #keybox(none, "2")], [Aft (rear) view], [#keybox(none, "Z")], [Cycle IFF Scanner zoom#super[3];],
      [#keybox(none, "F3") #keybox(none, "3")], [Port (left) view], [#keybox(none, "⇫")#keybox(none, "Z")], [Reset IFF Scanner zoom],
      [#keybox(none, "F4") #keybox(none, "4")], [Starboard (right) view], [#keybox(color_green, "\\")], [Select next Space Compass target #super[4]],
      [#keybox(none, "↑") #keybox(none, "↓")], [Pitch down (dive) / up (climb)], [#keybox(color_green, text(size: 8pt)[|])], [Select previous Space Compass target #super[4];],
      [#keybox(none, "←") #keybox(none, "→")], [Roll clockwise / anticlockwise], [#keybox(none, "⇫")#keybox(none, "L")], [Contact Station Traffic Control#super[5];],
      [#keybox(none, ",") #keybox(none, ".")], [Yaw (turn) left / right], [#keybox(color_green, "C")], [Activate Docking Computer],
      [#keybox_wide(none, "Ctrl")], [Fine control of pitch, roll and yaw], [#keybox(color_green, "⇫")#keybox(color_green, "C")], [Activate Fast Docking Computer#super[6]],
      [#keybox(none, "W") #keybox(none, "S")], [Speed increase / decrease], [#keybox(color_green, "S")], [Turn off the music while auto-docking],
      [#keybox(color_green, "I")], [Witchspace Fuel Injectors], [#keybox(none, "⇫")#keybox(none, "D")], [Dump one cargo canister#super[7]],
      [#keybox(none, "J")], [Engage Jump (torus) drive], [#keybox(none, "⇫")#keybox(none, "R")], [Rotate through the manifest#super[7]],
      [#keybox(none, "H")], [Hyperspace jump], [#keybox(none, "`")], [Show the communication log],
      [#keybox(color_green, "G")], [Galactic Hyperspace jump#super[1];], [#keybox(color_green, text(size: 7.5pt)[Esc])#keybox(color_green, text(size: 7.5pt)[Esc])], [Launch Escape Pod],
      [#keybox(color_blue, ";")], [Cycle current MFD #super[8];], [#keybox(color_blue, ":")], [Select next MFD #super[8];],
      [#keybox_mid(color_blue, text(size: 8pt)[Ctrl])#keybox_slim(color_blue, ";")], [Cycle current MFD in reverse #super[8];], [#keybox_mid(color_blue, text(size: 8pt)[Ctrl])#keybox_slim(color_blue, ":")], [Select previous MFD #super[8];]
    )

    #table(
      section-header("Combat Controls", colspan: 4),
      [#keybox(none, "A")], [Fire laser], [#keybox(color_green, "+") #keybox(color_green, "-")], [Cycle to next / previous target],
      [#keybox(none, "T")], [Missile target seek], [#keybox(none, "R")], [Activate ID recognition],
      [#keybox(none, "M")], [Fire missile (if locked)], [#keybox(color_green, "E")], [Activate ECM system],
      [#keybox(none, "U")], [Unlock missile target], [#keybox(none, "_")], [Toggle weapon lockdown],
      [#keybox(none, "Y")], [Cycle through available missiles#super[†;]], [#keybox(none, "⇫")#keybox(none, "T")], [Target nearest incoming missile]
    )

    #table(
      section-header("Commodities Market Controls", colspan: 4),
      [#keybox(none, "F8")], [Commodities Market], [#keybox(none, "F7")], [Data on Planet],
      [#keybox(none, "F8")#keybox(none, "F8")], [Commodity Details], [#keybox_wide(none, "Home")], [Select current system],
      [#keybox_wide(none, "Enter")], [Buy / sell maximum amount], [#keybox_wide(none, "End")], [Select current destination system],
      [#keybox(none, "↑") #keybox(none, "↓")], [Move cursor up / down the list], [#keybox(none, "←") #keybox(none, "→")], [Select previous / next system on course],
      [#keybox(none, "←") #keybox(none, "→")], [Sell / buy one unit of commodity], [], [],
      [#keybox(none, "/") #keybox(none, "?")], [Change commodity list sort / filter], [], []
    )
    #block(stroke: 0.3pt + rgb("cccccc"), inset: 5pt, radius: 2pt, fill: rgb("fafafa"), width: 100%)[
      #text(size: 7.5pt, style: "italic")[Note: holding shift while buying or selling will also buy or sell the maximum amount.]
    ]
  ],

  // ==========================================
  // COLUMN 2: Systems, Nav & UI
  // ==========================================
  stack(spacing: 0.5em)[
    #table(
      section-header("Ship, Systems & Status Controls", colspan: 4),
      [#keybox(none, "F1") #keybox(none, "1")], [Launch the ship], [#keybox(none, "F2") #keybox(none, "2")], [Game Menu],
      [#keybox(none, "F3") #keybox(none, "3")], [Ship Outfitting#super[‡;]], [#keybox(none, "F3")#keybox(none, "F3")], [Ships For Sale#super[‡;]],
      [#keybox(none, "F5") #keybox(none, "5")], [Commander's Profile], [#keybox(none, "F5")#keybox(none, "F5")], [Ship's Manifest],
      [#keybox(none, "↑") #keybox(none, "↓")], [Move cursor up / down the list], [#keybox(color_blue, "⇫")#keybox(color_blue, "N")], [Prime next special equipment],
      [#keybox_wide(none, "Enter")], [Select the highlighted entry], [#keybox_mid(color_blue, text(size:8pt)[Ctrl])#keybox_slim(color_blue, "⇫")#keybox(color_blue, "N")], [Prime previous special equipment],
      [#keybox_mid(color_blue, "Tab") #keybox(color_blue, "0")], [Fast-activate special equipment], [#keybox(color_blue, "N") #keybox(color_blue, "B")], [Activate special equipment#super[9];]
    )

    #table(
      section-header("Navigation Controls", colspan: 4),
      [#keybox(none, "F6")#keybox(none, "F6") #keybox(none, "6")#keybox(none, "6")], [Galactic Chart], [#keybox_wide(none, text(size:8pt)[Arrows])], [Move cursor around the charts],
      [#keybox(none, "F6") #keybox(none, "6")], [Short Range Chart], [#keybox_wide(none, "Pg Up")], [Zoom chart in],
      [#keybox(none, "I")], [Toggle name/system information view], [#keybox_wide(none, "Pg Dn")], [Zoom chart out],
      [#keybox(none, "?")], [Cycle highlight mode], [#keybox_wide(none, "Home")], [Return cursor to current system],
      [#keybox(color_green, "^")], [Advanced navigation -- cycle route mode], [], []
    )

    #block(stroke: 0.3pt + rgb("cccccc"), inset: 5pt, radius: 2pt, fill: rgb("fafafa"), width: 100%)[
      #text(size: 7.5pt)[#underline[*Navigation Chart Note:*] Typing a planet's name while in the Galactic Chart will automatically move the cursor to the world matching the text. When more than one planet matches the text, use shift-arrow keys to move the cursor to the next highlighted world. Use Alt + left / right arrow keys to select the system for which information will be displayed in the F7 system data screen.]
    ]
    
    #table(
      section-header("Ship-Station Interfaces Controls", colspan: 4),
      [#keybox(none, "F4") #keybox(none, "4")], [List available interfaces #super[‡;]], [#keybox(none, "↑") #keybox(none, "↓")], [Move cursor up / down the list],
      [#keybox_wide(none, "Enter")], [Activate selected interface], [#keybox(none, "←") #keybox(none, "→")], [Move between pages on list]
    )

    #table(
      section-header("Other Controls -- All Systems", colspan: 4),
      [#keybox(none, "P")], [Pause the game], [#keybox(none, "O")], [Turn the HUD off / on while paused],
      [#keybox(none, "⇫")#keybox(none, "F")], [Toggle the game frame rate display], [#keybox(none, "*")], [Take a screenshot],
      [#keybox(none, "⇫")#keybox(none, "M")], [Toggle mouse flight control in full screen mode (roll on x-axis)], [#keybox_mid(none, text(size:8pt)[Ctrl])#keybox_slim(none, "⇫")#keybox(none, "M")], [Toggle mouse flight control in full screen mode (yaw on x-axis)],
      [#keybox_wide(none, "Caps")], [Toggle free-look camera in ext. view], [#keybox_mid(none, "F12")], [Toggle window / full screen mode],
      [#keybox(none, "⇫")#keybox_mid(none, "Esc")], [Quit the game], [], []
    )
  ],

  // ==========================================
  // COLUMN 3: Legend & Footnotes
  // ==========================================
  stack(spacing: 0.5em)[
    #table(
      columns: (1fr, 4fr),
      align: (center, left),
      section-header("Notes"),
      [#keybox(none, "X")#keybox(none, "X")], [Tap this key twice],
      keybox(none, [F2]), [Function key],
      keybox(none, [⇫]), [Shift key],
      keybox_mid(none, text(size: 8pt)[Ctrl]), [Ctrl key],
      keybox(color_green, [X]), [Key only available when equipment installed],
      keybox(color_blue, [X]), [Key only available with mod pack equipment]
    )

    #block(stroke: 0.3pt + rgb("cccccc"), inset: 5pt, radius: 2pt, fill: rgb("fafafa"), width: 100%)[
      #text(size: 7.5pt)[
        #set par(leading: 0.28em)
        [‡] Only GCW (Galactic Cooperative of Worlds) Stations support all of these functions. Other anchorages may only carry a limited range.

        [1] Galactic Hyperdrives are one time use only. To jump again another drive must be bought.

        [2] The key cycles through the available external views of your craft. Ships featured in OXPs may not have external views available.

        [3] The key cycles through the five magnification setting of the IFF Scanner.

        [4] See the Space Compass section on the next page for more information.

        [5] The key requests a docking window from station launch control. Use the same key to cancel or renew a request.

        [6] Usually allowed at GCW Stations only.

        [7] Unless cargo is selected by the commander, dumping cargo will dump one unit from the first commodity listed in your manifest.

        [8] MFDs are multi-function displays which can be configured to show information from various equipped items. Different HUDs will have different numbers of MFDs available. See *page 6* for more information on MFD's.

        [9] Function of N and B keys varies with equipment. Not all equipment will define functions for both keys. See specific mod documentation for more information.
      ]
    ]
    #block(stroke: 0.3pt + rgb("cccccc"), inset: 5pt, radius: 2pt, fill: color_blue, width: 100%)[
      #text(size: 7.5pt)[
        #v(0.3em)
        This reference sheet makes several references to mod packs. The 1000+ Oolite eXpansion Packs (OXP's) can add extra missions, equipment, ships or change the game mechanics. These mods are not part of the default installation of the game and will not be covered by this sheet. For more information on them and how to install them, visit the Oolite Wiki or consult the in-game *Expansions Pack Manager* (see *page 5* for more information).
      ]
    ]
    #block(stroke: 0.3pt + rgb("cccccc"), inset: 5pt, radius: 2pt, fill: rgb("fafafa"), width: 100%)[
      #text(size: 7.5pt)[
        #set par(leading: 0.28em)
        #v(0.3em)
        *Attention non-US/UK keyboard users:* \
        Some keys may vary from the ones listed here. All keys are alterable via the keyboard configuration screen, accessed from the F2 Game options menu, which is available when docked or paused.
      ]
    ]
  ]
)

#pagebreak()
#header-text.update("Heads Up Display")
