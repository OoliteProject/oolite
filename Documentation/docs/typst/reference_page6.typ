#import "common.typ": *

#header-text.update("MFDs and Primable Equipment")

#show: setup-page

#show: apply-table-styles

// ==========================================
// PAGE 6: MFDS AND PRIMABLE EQUIPMENT
// ==========================================

#grid(
  columns: (1fr, 1fr, 1fr, 1fr),
  gutter: 0.6cm,

  // ------------------------------------------
  // COLUMN 1: MFDs Part 1
  // ------------------------------------------
  stack(spacing: 0.5em)[
    #table(
      columns: (1fr, 1fr),
      section-header("MFDs"),
      table.cell(colspan: 2, align: left)[
        MFDs, or Multi-function displays, are a part of the HUD that can show additional information to the player. Mods are the primary way MFDs are used, and each mod will use them in different ways - you will need to check the documentation for each mod to learn about what information will be displayed.

        Each HUD can define multiple MFD positions or slots, and the content of each MFD can be cycled through the available options. For the default HUD, there are 2 MFD slots defined: slot 1 being located in the top left of the screen, and slot 2 in the top right of the screen.

        #v(0.3em)
        #align(center)[#image("./assets/Pictures/10000000000004E000000438D03D351A.png", width: 100%)]
        #v(0.3em)

        Each MFD slot can be made active in turn, but only one MFD slot can be active at any time.

        To activate an MFD slot, use the *":" key*. Press the key multiple times to move through all the MFD positions. As each position is activated, a console message will appear on your HUD indicating which MFD slot has just become active.

        #v(0.3em)
        #align(center)[#image("./assets/Pictures/100000000000025C0000013812D8115F.png", width: 100%)]
        #v(0.3em)

        To move in reverse order through the MFD slots, use the *Ctrl + ":"* key combination.
      ]
    )
  ],

  // ------------------------------------------
  // COLUMN 2: Rest of MFDs & Primable Equipment
  // ------------------------------------------
  stack(spacing: 0.5em)[
    #table(
      columns: (1fr, 1fr),
      section-header("MFDs (cont.)"),
      table.cell(colspan: 2, align: left)[
        To cycle through the available content for an MFD slot, press *";"*, or press *Ctrl + ";"* to cycle in reverse order. The initial display of any MFD slot is blank. As you cycle through the content options, eventually you will return to the blank item. The available content is defined by the installed mods and equipment purchased.
      ]
    )

    #table(
      columns: (1fr, 1fr),
      section-header("Primable Equipment"),
      table.cell(colspan: 2, align: left)[
        Some mods give the player custom equipment that can be activated and used in flight. If the activation of the equipment is not automatic (based on some condition or situation) then it is likely that the primable equipment that has been installed must be manually activated.

        On the default HUD, the currently primed equipment is displayed on the bottom right of the screen, below the energy banks. If there is no primable equipment installed, nothing will be displayed in this position. If some are available, the text "Primed: None" will initially be shown.

        #v(0.3em)
        #align(center)[#image("./assets/Pictures/10000000000001690000002AF07E3454.png", width: 100%)]
        #v(0.3em)

        To "prime" a piece of equipment, press *Shift + "N"*. If there are several pieces of equipment installed, you may have to press multiple times until the desired equipment item is primed. As each piece of equipment is primed, a console message will appear on your HUD, and the currently primed equipment will be displayed at the bottom of the screen.

        #v(0.3em)
        #align(center)[#image("./assets/Pictures/10000000000002D000000138672A921C.png", width: 100%)]
        #v(0.3em)

        To move in reverse order through the primable equipment, press *Ctrl + Shift + "N"*.

        To call the "mode" function for a primed piece of equipment, press the *"b" key*. To call the "activate" function, press the *"n"* key. What these functions do varies for each equipment item and can be determined by reading the documentation.
      ]
    )
  ],

  // ------------------------------------------
  // COLUMN 3: Fast Activation Part 1
  // ------------------------------------------
  stack(spacing: 0.5em)[
    #table(
      columns: (1fr, 1fr),
      section-header("Fast Activation"),
      table.cell(colspan: 2, align: left)[
        Along with the standard priming and activation methods described above, 2 keys have been allocated to directly execute the activation function of a particular piece of primable equipment. The first is the *"0" key*, the second is the *"Tab" key*. In essence, once configured, these keys allow the player to bypass the need to prime an equipment item individually in order to activate it.

        To set up what equipment is assigned to each key, you will need to be docked at a station and then go to the *F4 "Available Interfaces"* screen, and select the "Manage primable equipment" option.

        #v(0.3em)
        #align(center)[#image("./assets/Pictures/10000000000004EC00000438F01BADF5.png", width: 100%)]
        #v(0.3em)

        When selected, you will be asked what equipment should be allocated to the *"0" key.*

        #v(0.3em)
        #align(center)[#image("./assets/Pictures/10000000000005190000043835D9093B.png", width: 100%)]
      ]
    )
  ],

  // ------------------------------------------
  // COLUMN 4: Rest of Fast Activation & Custom Keys
  // ------------------------------------------
  stack(spacing: 0.5em)[
    #table(
      columns: (1fr, 1fr),
      section-header("Fast Activation (cont.)"),
      table.cell(colspan: 2, align: left)[
        This will be followed by what equipment should be allocated to the *"Tab" key*.

        #v(0.3em)
        #align(center)[#image("./assets/Pictures/10000000000004F400000436D4E346DC.png", width: 100%)]
        #v(0.3em)

        After both equipment items have been selected, the new arrangement will be displayed as confirmation.

        #v(0.3em)
        #align(center)[#image("./assets/Pictures/10000000000005080000043891731C27.png", width: 100%)]
      ]
    )

    #table(
      columns: (1fr, 1fr),
      section-header("Custom Keys for Mod Equipment"),
      table.cell(colspan: 2, align: left)[
        To avoid the need to prime individual equipment items to make use of its functions, after you have purchased a new piece of primable equipment, you can go to the Keyboard configuration screen in the Game options menu, and allocate individual keys to the “mode” and “activate” functions of the equipment.
      ]
    )
  ]
)
