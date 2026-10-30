#import "common.typ": *

#header-text.update("General Information and FAQ")

#show: setup-page

#show: apply-table-styles

// ==========================================
// PAGE 5: GENERAL INFORMATION AND FAQ
// ==========================================

#grid(
  columns: (1fr, 1fr, 1fr, 1fr),
  gutter: 0.6cm,

  // ------------------------------------------
  // COLUMN 1: Career Choices
  // ------------------------------------------
  stack(spacing: 0.5em)[
    #table(
      columns: (1fr, 1fr),
      section-header("Career Choices"),

      table-gap(colspan: 2),
      sub-header("Bounty Hunting"),
      table.cell(colspan: 2)[Collect bounties for pirate/fugitive craft destroyed. Bounties are also paid if you capture/rescue the escape pods of the criminals/victims. #v(-0.61em) _No additional equipment required. Recommend minimum of: Beam Laser, ECM, Fuel Scoop and Shield Booster be fitted before attempting this profession._],

      table-gap(colspan: 2),
      sub-header("Carrier Service"),
      table.cell(colspan: 2)[With a big enough ship you can get paid for moving someone else's bulk goods from A to B. Contracts are available through the Interfaces screen. #v(-0.61em) _Requires a ship with larger cargo bays. Recommend an Advanced Navigation Array be fitted._],

      table-gap(colspan: 2),
      sub-header("Mining"),
      table.cell(colspan: 2)[Blast asteroids, scoop up the fragments and sell the minerals on the commodities market. #v(-0.61em) _Requires a Fuel Scoop and Mining Laser. Recommend a Cargo Bay Expansion be fitted._],

      table-gap(colspan: 2),
      sub-header("Passenger or Courier Service"),
      table.cell(colspan: 2)[With a passenger berth fitted, you take a traveller from point A to point B for profit. Small packages may also be carried without requiring extra equipment. Contracts are available through the Interfaces screen. #v(-0.61em) _May require a Passenger Berth. Recommend an Advanced Navigation Array be fitted._],

      table-gap(colspan: 2),
      sub-header("Piracy"),
      table.cell(colspan: 2)[Attack other ships and steal their cargo, which will make you a fugitive very quickly. You will then have GalCop, bounty hunters and opportunist commanders after you. #v(-0.61em) _Requires a Fuel Scoop and upgraded combat systems. Recommend fitting an Escape Pod._],

      table-gap(colspan: 2),
      sub-header("Trading"),
      table.cell(colspan: 2)[Buy low-priced commodities on one world and sell at a higher price on another. #v(-0.61em) _No additional equipment required. Recommend a Cargo Bay Expansion be fitted._],

      table-gap(colspan: 2),
      sub-header("Trafficking In Illegal Goods"),
      table.cell(colspan: 2)[Illegal goods can be traded for massive profit. Doing so will eventually make you a fugitive and limit the systems you can trade in. #v(-0.61em) _No additional equipment required. Recommend a Cargo Bay Expansion and upgraded combat systems be fitted._],

      table.cell(colspan: 2, align: left)[
        #text(size: 7.5pt, style: "italic")[Additional careers can be added by installing mods. Refer to the Oolite Wiki for more details.]
      ]
    )
  ],

  // ------------------------------------------
  // COLUMN 2: Expansion Pack Manager
  // ------------------------------------------
  stack(spacing: 0.5em)[
    #table(
      columns: (auto, 1fr),
      section-header("Expansion Pack Manager"),
      table.cell(colspan: 2)[The Expansion Pack Manager is accessed from the main game menu, and provides easy access to hundreds of Oolite mods that have been created by community members over a number of years. However, please note that these mods are not endorsed or vetted by the Oolite development team. They are provided “as-is”, with no warranty or guarantee whatsoever. Care should be taken to read all the documentation for each mod to fully understand the changes it will make to the game and your playing experience.],

      table-gap(colspan: 2),
      sub-header("Guide to colors"),
      table.cell(colspan: 2)[The color of the various expansions in the list is used to indicate the following:],
      [#text(fill: rgb("d4a000"), weight: "bold")[Yellow]], [Ready to download and install],
      [#text(fill: rgb("333333"), weight: "bold")[White]], [Installed and at the current version],
      [#text(fill: rgb("0097a7"), weight: "bold")[Cyan]], [Installed; updated mod available for download.],
      [#text(fill: rgb("e65100"), weight: "bold")[Orange]], [Ready to download, but Oolite will also download extra mods to make it work.],
      [#text(fill: rgb("5d4037"), weight: "bold")[Brown]], [Conflicts with an already installed mod.],
      [#text(fill: rgb("616161"), weight: "bold")[Gray]], [Incompatible with this version of Oolite.],
      [#text(fill: rgb("c62828"), weight: "bold")[Red]], [Manually installed: cannot also be installed automatically (eg. a tweaked mod in the AddOns folder)],
      [#text(fill: rgb("1565c0"), weight: "bold")[Blue]], [Installed but no longer available for download.],

      table-gap(colspan: 2),
      sub-header("Special key controls"),
      table.cell(colspan: 2)[The following keys perform special functions within the Expansion Pack Manager:],
      [#strong[F]], [Filter sets. Allows custom filter to be applied to list.],
      [#strong[I]], [Display information about the mod. Additionally, copies the URL to the clipboard so it can be pasted into a browser.],
      [#strong[X]], [Extracts mod content to the AddOns folder. Folder will initially have an extension of “.off”. Change this to “.oxp” to enable it.]
    )
  ],

  // ------------------------------------------
  // COLUMNS 3 & 4: Frequently Asked Questions
  // ------------------------------------------
  grid.cell(colspan: 2)[
    #grid(
      columns: (1fr, 1fr),
      gutter: 0.6cm,

      // Column 3 Content
      stack(spacing: 0.5em)[
        #table(
          columns: (1fr, 1fr),
          section-header("Frequently Asked Questions"),

          table.cell(colspan: 2)[#v(0.8em)*Q: Where is my game data (saved games, expansion packs etc.)?*],
          table.cell(colspan: 2)[#strong[A:] Game data such as your saved games and expansion packs are stored in certain locations depending on your operating system. For information, see this guide: \
          #url-link("https://oolite.readthedocs.io/en/latest/#game-data")
          .],

          table.cell(colspan: 2)[#v(0.8em)*Q: Where is my log file?*],
          table.cell(colspan: 2)[
            #strong[A:] While Oolite runs, various diagnostic information is written to a file called _Latest.log_. That file is typically located in your game data folder. See question above and also this guide: \
          #url-link("https://oolite.readthedocs.io/en/latest/#helpful-information")
          ],

          table.cell(colspan: 2)[#v(0.8em)*Q: Why do none of the mods I have installed appear to work in the game?*],
          table.cell(colspan: 2)[#strong[A:] Check you do not have Oolite in “Strict Play” mode. Also, make sure any mods you have added manually to the AddOns folder have an extension of “.oxp”.],

          table.cell(colspan: 2)[#v(0.8em)*Q: I made a tweak to one of the expansions I added, but the tweak hasn't been applied in game?*],
          table.cell(colspan: 2)[#strong[A:] After making a change to an expansion pack, make sure to hold down the right shift key when starting the game, and hold it until you see the spinning Cobra. This will force Oolite to rebuild its game cache, thus applying your change to the game files.]
        )
      ],

      // Column 4 Content
      stack(spacing: 0.5em)[
        #table(
          columns: (1fr, 1fr),
          section-header("Frequently Asked Questions (cont.)"),

          table.cell(colspan: 2)[#v(0.8em)*Q: I am getting destroyed by pirates everywhere I go!*],
          table.cell(colspan: 2)[
            #strong[A:] Make sure to avoid dangerous systems if you aren't prepared for them. Pirates will generally demand some cargo from you, so always keep some cheap cargo on hand which you can eject when asked. #v(-0.61em) \
            Watch out for parcel or passenger contracts that have a higher than normal payout as they might attract unwanted attention. They might also require you to travel through dangerous systems. #v(-0.61em) \
            For more detailed information on combat tactics and dealing with pirates, visit this wiki page: \
            #url-link("https://wiki.alioth.net/index.php/Oolite_Tactics")
          ],

          table.cell(colspan: 2)[#v(0.8em)*Q: I keep crashing when trying to dock!*],
          table.cell(colspan: 2)[
            #strong[A:] Make sure to use the navigation beacon in front of the docking port to help with lining up your ship. Keep the docking port centred in your front view, and the navigation beacon centred in your rear view. Match the rotation of the station and accelerate slowly towards the dock. When you enter the dock, keep moving forwards towards the back wall of the dock until the docking animation appears. #v(-0.61em) \
            For more detailed discussions on docking methods, please visit the wiki, and in particular, this page: \
            #url-link("https://wiki.alioth.net/index.php/How_to_Dock")
          ],

          table.cell(colspan: 2)[#v(0.8em)*Q: It takes a long time to travel to the station after arriving in a new system!*],
          table.cell(colspan: 2)[
            #strong[A:] Yes it does. However, if there are no powered ships in scanner range, you can make use of the torus drive, which can be activated by pressing the “#strong[J]” key. The system will speed up the flight time considerably, but will auto-disengage whenever another ship comes inside scanner range. Which will occur frequently because most ships are travelling along the direct route from the witchpoint beacon to the planet and main station. But that doesn't mean you have to. Flying at right angles a short distance away from the main route will put you out of the way of most ships and allow your torus drive to operate for longer periods without interruption.
          ]
        )
      ]
    )
  ]
)
