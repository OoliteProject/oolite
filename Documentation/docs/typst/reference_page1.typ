#import "common.typ": *

#header-text.update("Keyboard Guide")

#show: setup-page.with(header-size: 9.7pt, body-size: 9.6pt)

#show: apply-table-styles.with(columns: (auto, 1fr, auto, 1fr), align: (center, left, center, left))

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
      [F1], [Forward (front) view], [V], [External views#super[2];],
      [F2], [Aft (rear) view], [Z], [Cycle IFF Scanner zoom#super[3];],
      [F3], [Port (left) view], [⇫+Z], [Reset IFF Scanner zoom],
      [F4], [Starboard (right) view], [\\], [Select next Space Compass target #super[4] #super[†]],
      [↑], [Pitch down (dive) / up (climb)], [|], [Select previous Space Compass target #super[4];],
      [←], [Roll clockwise / anticlockwise], [⇫+L], [Contact Station Traffic Control#super[5];],
      [,], [Yaw (turn) left / right], [C], [Activate Docking Computer #super[†]],
      [Ctrl], [Fine control of pitch, roll and yaw], [⇫+C], [Activate Fast Docking Computer#super[6] #super[†]],
      [W / S], [Speed increase / decrease], [S], [Turn off the music while auto-docking #super[†]],
      [I], [Witchspace Fuel Injectors], [⇫+D], [Dump one cargo canister#super[7] #super[†]],
      [J], [Engage Jump (torus) drive], [⇫+R], [Rotate through the manifest#super[7] #super[†]],
      [H], [Hyperspace jump], [\`], [Show the communication log],
      [G], [Galactic Hyperspace jump#super[1];], [Esc Esc], [Launch Escape Pod],
      [;], [Cycle current MFD #super[8];], [:], [Select next MFD #super[8];],
      [Ctrl+;], [Cycle current MFD in reverse #super[8];], [Ctrl+:], [Select previous MFD #super[8];]
    )

    #table(
      section-header("Combat Controls", colspan: 4),
      [A], [Fire laser], [\+ / \-], [Cycle to next / previous target],
      [T], [Missile target seek], [R], [Activate ID recognition],
      [M], [Fire missile (if locked)], [E], [Activate ECM system],
      [U], [Unlock missile target], [\_], [Toggle weapon lockdown],
      [Y], [Cycle through available missiles#super[†;]], [⇫+T], [Target nearest incoming missile]
    )

    #table(
      section-header("Commodities Market Controls", colspan: 4),
      [F8], [Commodities Market], [F7], [Data on Planet],
      [F8 F8], [Commodity Details], [Home], [Select current system],
      [Enter], [Buy / sell maximum amount], [End], [Select current destination system],
      [↑ / ↓], [Move cursor up / down the list], [← / →], [Select previous / next system on course],
      [← / →], [Sell / buy one unit of commodity], [], [],
      [\/ / ?], [Change commodity list sort / filter], [], []
    )
    #text(size: 7.5pt, style: "italic")[Note: holding shift while buying or selling will also buy or sell the maximum amount.]
  ],

  // ==========================================
  // COLUMN 2: Systems, Nav & UI
  // ==========================================
  stack(spacing: 0.5em)[
    #table(
      section-header("Ship, Systems & Status Controls", colspan: 4),
      [F1], [Launch the ship], [F2], [Game Menu],
      [F3], [Ship Outfitting#super[‡;]], [F3 F3], [Ships For Sale#super[‡;]],
      [F5], [Commander's Profile], [F5 F5], [Ship's Manifest],
      [↑ / ↓], [Move cursor up / down the list], [⇫+N], [Prime next special equipment],
      [Enter], [Select the highlighted entry], [Ctrl+⇫+N], [Prime previous special equipment],
      [Tab / 0], [Fast-activate special equipment], [N / B], [Activate special equipment#super[9];]
    )

    #table(
      section-header("Navigation Controls", colspan: 4),
      [F6 F6], [Galactic Chart], [Arrows], [Move cursor around the charts],
      [F6], [Short Range Chart], [Pg Up], [Zoom chart in],
      [I], [Toggle name/system information view], [Pg Dn], [Zoom chart out],
      [?], [Cycle highlight mode], [Home], [Return cursor to current system],
      [^], [Advanced navigation -- cycle route mode], [], []
    )
    #text(size: 7.5pt)[#underline[*Navigation Chart Note:*] Typing a planet's name while in the Galactic Chart will automatically move the cursor to the world matching the text. When more than one planet matches the text, use shift-arrow keys to move the cursor to the next highlighted world. Use Alt + left / right arrow keys to select the system for which information will be displayed in the F7 system data screen.]

    #table(
      section-header("Ship-Station Interfaces Controls", colspan: 4),
      [F4], [List available interfaces #super[‡;]], [↑ / ↓], [Move cursor up / down the list],
      [Enter], [Activate selected interface], [← / →], [Move between pages on list]
    )

    #table(
      section-header("Other Controls -- All Systems", colspan: 4),
      [P], [Pause the game], [O], [Turn the HUD off / on while paused],
      [⇫+F], [Toggle the game frame rate display], [\*], [Take a screenshot],
      [⇫+M], [Toggle mouse flight control in full screen mode (roll on x-axis)], [Ctrl+⇫+M], [Toggle mouse flight control in full screen mode (yaw on x-axis)],
      [Caps], [Toggle free-look camera in ext. view], [F12], [Toggle window / full screen mode],
      [⇫+Esc], [Quit the game], [], []
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
      [X X], [Tap this key twice],
      [F2], [Function key],
      [⇫], [Shift key],
      [Ctrl], [Ctrl key],
      [X], [Key only available when equipment installed],
      [X], [Key only available with mod pack equipment]
    )

    #block(stroke: 0.3pt + rgb("cccccc"), inset: 5pt, radius: 2pt, fill: rgb("fafafa"))[
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

        #v(0.3em)
        This reference sheet makes several references to mod packs. The 1000+ Oolite eXpansion Packs (OXP's) can add extra missions, equipment, ships or change the game mechanics. These mods are not part of the default installation of the game and will not be covered by this sheet. For more information on them and how to install them, visit the Oolite Wiki or consult the in-game *Expansions Pack Manager* (see *page 5* for more information).

        #v(0.3em)
        *Attention non-US/UK keyboard users:* \
        Some keys may vary from the ones listed here. All keys are alterable via the keyboard configuration screen, accessed from the F2 Game options menu, which is available when docked or paused.
      ]
    ]
  ]
)

#pagebreak()
#header-text.update("Heads Up Display")
