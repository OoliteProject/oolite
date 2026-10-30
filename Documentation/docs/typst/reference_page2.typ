#import "common.typ": *

#header-text.update("Heads Up Display")

#show: setup-page

#show: apply-table-styles

// ==========================================
// PAGE 2: HEADS UP DISPLAY
// ==========================================

#grid(
  columns: (1fr, 1fr, 1fr, 1fr),
  gutter: 0.6cm,

  // ------------------------------------------
  // COLUMN 1: Items 1 to 8
  // ------------------------------------------
  stack(spacing: 0.5em)[
    #table(
      columns: (1fr, 1fr),
      section-header("1 Speed"),
      table.cell(colspan: 2, align: left)[This is a percentage gauge showing how fast the ship is travelling relative to its maximum speed.]
    )

    #table(
      columns: (1fr, 1fr),
      section-header("2 Roll and Pitch"),
      table.cell(colspan: 2, align: left)[
        The diamonds show how much the ship is anti/clockwise rolling and climbing/diving relative to its maximum turn rate.
        #v(-0.6em)
        #text(size: 7.5pt, style: "italic")[Some ships and HUDs may also feature a Yaw indicator. It functions exactly the same way as the Roll and Pitch units.]
      ]
    )

    #table(
      columns: (1fr, 1fr),
      section-header("3 Energy Banks"),
      table.cell(colspan: 2, align: left)[The multiple meters of the Energy Banks show how much energy you have available for ship systems. Recharging your shields, firing your lasers or ECM and direct hits to the ship's hull will drain the banks. If completely drained, the collapse of the energy banks destroys the ship. The number and size of energy banks installed is dependent on the model of ship being flown.]
    )

    #table(
      columns: (1fr, 1fr),
      section-header("4 Shields"),
      table.cell(colspan: 2, align: left)[The front (FWD) and rear (AFT) shields, where the bar length equals the shield strength. As the shields weaken, the risk of weapons fire penetrating the shield increases. Any penetration will result in energy drain, along with the risk of equipment damage and the destruction of cargo.]
    )

    #table(
      columns: (1fr, 1fr),
      section-header("5 Fuel"),
      table.cell(colspan: 2, align: left)[A gauge displaying how much witchspace fuel is available. If a destination has been selected for a hyperspace jump, a marker line will show how much you need to activate the drive.]
    )

    #table(
      columns: (1fr, 1fr),
      section-header("6 Cabin Temperature"),
      table.cell(colspan: 2, align: left)[This gauge shows the ship's life support temperature. Exposure to excessive amounts of heat will overload the life support resulting in the crew's death.]
    )

    #table(
      columns: (1fr, 1fr),
      section-header("7 Laser Temperature"),
      table.cell(colspan: 2, align: left)[Displays the heat level of the active laser. Continuous fire raises the laser temperature. An overheated laser will shut down, requiring a cool-down period before it will fire again.]
    )

    #table(
      columns: (1fr, 1fr),
      section-header("8 Altitude"),
      table.cell(colspan: 2, align: left)[Shows the proximity of a nearby planet or sun. Exposure to excessive atmospheric and gravitational pressures of such bodies will destroy the ship.]
    )
  ],

  // ------------------------------------------
  // COLUMNS 2 & 3 CONTAINER (For the image span)
  // ------------------------------------------
  grid.cell(colspan: 2)[
    #grid(
      columns: (1fr, 1fr),
      gutter: 0.6cm,

      // Column 2 Content
      stack(spacing: 0.5em)[
        #table(
          columns: (auto, 1fr),
          section-header("9 Missiles"),
          table.cell(colspan: 2, align: left)[These icons show what types of, and how many, missiles or other pylon-mounted devices you are carrying, and which one is active (yellow border). When a weapon has been locked on to the target, its icon turns red.],
          [#box(image("./assets/Pictures/1000000000000022000000281FCBE9BB.png", height: 0.4cm, width: 0.33cm))], [Empty pylon],
          [#box(image("./assets/Pictures/100000000000002200000028D4D07A4C.png", height: 0.4cm, width: 0.319cm))], [Active standard missile ],
          [#box(image("./assets/Pictures/10000000000000200000002E7CBB0BAA.png", height: 0.4cm, width: 0.319cm))], [ECM hardened missile target locked],
          [#box(image("./assets/Pictures/100000000000001200000021B10E8A7A.png", height: 0.4cm, width: 0.25cm))], [Quirium cascade mine target locked],
          table.cell(colspan: 2, align: left)[
            Should you see a green square replacing the missile information, this means that you have used ID Recognition without a missile being active. #v(0.3em) #box(image("./assets/Pictures/1000000000000163000000398104FD70.png", height: 0.76cm, width: 4.734cm)) \ Installing additional equipment will allow you to keep a target lock with one missile while target seeking with another.
            #v(-0.6em)
            #text(size: 7.5pt, style: "italic")[Mods may add additional pylon-based equipment for purchase. See the mod documentation for more information.]
          ]
        )

        #table(
          columns: (1fr, 1fr),
          section-header("10 Fuel Scoop"),
          table.cell(colspan: 2, align: left)[The Fuel Scoop icon will be added to the HUD when one is fitted to the ship. When the fuel scoop is active, the icon strobes. If the tail of the icon becomes red, then your cargo bay is full and any new object scooped will be destroyed.]
        )

        #table(
          columns: (1fr, 1fr),
          section-header("11 Station Aegis"),
          table.cell(colspan: 2, align: left)[The Station Aegis is the area of space around a GCW station where its Vipers will provide protection to your ship should you come under attack.]
        )

        #table(
          columns: (1fr, 1fr),
          section-header("12 Primed Equipment"),
          table.cell(colspan: 2, align: left)[Displays currently primed OXP equipment, which can be activated with the “b” and “n” keys. See page 6 “MFDs and Primable Equipment” for more information.]
        )
      ],

      // Column 3 Content
      stack(spacing: 0.5em)[
        #table(
          columns: (1fr, 1fr),
          section-header("13 Threat Indicator"),
          table.cell(colspan: 2, align: left)[This is an indicator showing the current level of risk to your ship. When green, there are no other ships within scanner range. Yellow indicates that there are objects within scanner range. When the indicator turns red, other ships have targeted you.]
        )

        #table(
          columns: (1fr, 1fr),
          section-header("14 Date and Time"),
          table.cell(colspan: 2, align: left)[The current date and time, set to Galactic Cooperative of Worlds Mean Time.]
        )

        #table(
          columns: (1fr, 1fr),
          section-header("15 Scanner Zoom"),
          table.cell(colspan: 2, align: left)[The zoom ratio displays the current magnification setting of the IFF scanner.]
        )

        #table(
          columns: (auto, 1fr, auto),
          align: (center, left, center),
          table.cell(colspan: 3, fill: rgb("eeeeee"), align: center)[*16 Space Compass*],
          table.cell(colspan: 3, align: left)[The Space Compass shows the direction of the target relative to the direction of the ship. The default target of the space compass is the planet. When inside the GCW Station Aegis, the compass will target the station.],
          // Centered text elements using table.cell
          table.cell(align: center)[Fore], table.cell(align: center)[Target position relative to the ship], table.cell(align: center)[Aft],
          [#box(image("./assets/Pictures/100000000000001A0000001BDAF5F305.png", height: 0.499cm, width: 0.48cm))], table.cell(align: center)[Planet], [#box(image("./assets/Pictures/100000000000001A0000001B2F958552.png", height: 0.499cm, width: 0.48cm))],
          [#box(image("./assets/Pictures/100000000000001A0000001BD7300663.png", height: 0.499cm, width: 0.48cm))], table.cell(align: center)[Sun †], [#box(image("./assets/Pictures/100000000000001A0000001B58669CF2.png", height: 0.499cm, width: 0.48cm))],
          [#box(image("./assets/Pictures/100000000000001A0000001BCA6AC27F.png", height: 0.499cm, width: 0.48cm))], table.cell(align: center)[GCW Stations †], [#box(image("./assets/Pictures/100000000000001A0000001BE62838D0.png", height: 0.499cm, width: 0.48cm))],
          [#box(image("./assets/Pictures/10000001000000200000001B5CCDDEA4.png", height: 0.499cm, width: 0.589cm))], table.cell(align: center)[Navigation beacon †], [#box(image("./assets/Pictures/10000001000000200000001B4A583528.png", height: 0.499cm, width: 0.589cm))],
          [#box(image("./assets/Pictures/10000000000000250000001BF70A17D2.png", height: 0.499cm, width: 0.681cm))], table.cell(align: center)[Witchspace beacon †], [#box(image("./assets/Pictures/10000000000000250000001BF44F930B.png", height: 0.499cm, width: 0.681cm))],
          [#box(image("./assets/Pictures/100000000000001B0000001BE51ACE22.png", height: 0.499cm, width: 0.499cm))], table.cell(align: center)[Active target †], [#box(image("./assets/Pictures/100000000000001B0000001BE57F8F9A.png", height: 0.499cm, width: 0.499cm))]
        )
        #v(-0.6em)
        #text(size: 7.5pt)[
          _Additional compass targets may become available with the installation of mods. Refer to the individual mod documentation for more information._
        ]
        #v(-0.3em)
        #text(size: 7.5pt)[
          _[†] In order for stations to become manually selectable the Advanced Space Compass equipment is required to be installed._
        ]
      ]
    )

    // Wide layout image placed cleanly beneath Columns 2 and 3
    #v(0.5em)
    #align(center)[
      #image("./assets/Pictures/10000000000004FD000000F6FBD54C2B.png", width: 100%)
    ]
  ],

  // ------------------------------------------
  // COLUMN 4: Item 17 Onwards
  // ------------------------------------------
  stack(spacing: 0.5em)[
    #table(
      columns: (auto, 1fr),
      align: (center, left),
      table.cell(colspan: 2, fill: rgb("eeeeee"), align: center)[*17 IFF Scanner*],
      table.cell(colspan: 2, align: left)[The IFF Scanner Grid shows the relative positions of all objects within scanner range of the ship. The V lines show which direction you are currently viewing. The rule lines show the scale the scanner is working in.],
      [#box(image("./assets/Pictures/10000000000000FF000000563F8646EA.png", height: 0.75cm, width: 2.221cm))], [#box(image("./assets/Pictures/10000000000000FF0000005AFB8D923A.png", height: 0.75cm, width: 2.12cm))],
      table.cell(align: center)[Forward (front) View], table.cell(align: center)[Aft (rear) View],
      [#box(image("./assets/Pictures/100000000000010100000056BE214D26.png", height: 0.75cm, width: 2.24cm))], [#box(image("./assets/Pictures/1000000000000101000000579099A9EE.png", height: 0.75cm, width: 2.21cm))],
      table.cell(align: center)[Port (left) View], table.cell(align: center)[Starboard (right) View],
      table.cell(colspan: 2, align: left)[Each object is represented by a colour-coded flag and pole. The length and position of the flag pole represents the object's direction and distance from your ship. The flag's position on the pole indicates whether the object is above or below your ship.],
      [#box(image("./assets/Pictures/10000000000000160000001DFAF65A99.png", height: 0.4cm, width: 0.3cm))], [Non-powered objects #super[1];],
      [#box(image("./assets/Pictures/10000000000000150000001C4FDF0A1D.png", height: 0.4cm, width: 0.3cm))], [Civilian craft],
      [#box(image("./assets/Pictures/10000000000000150000001CF558530D.png", height: 0.4cm, width: 0.3cm))], [Hostile craft],
      [#box(image("./assets/Pictures/10000000000000150000001CF1E62719.png", height: 0.4cm, width: 0.3cm))], [Police/Government craft],
      [#box(image("./assets/Pictures/10000000000000150000001CE7AD75FC.png", height: 0.4cm, width: 0.3cm))], [Police/Government craft on intercept],
      [#box(image("./assets/Pictures/10000000000000150000001CC4692DC0.png", height: 0.4cm, width: 0.3cm))], [Thargoid craft],
      [#box(image("./assets/Pictures/10000000000000150000001C05BD88D4.png", height: 0.4cm, width: 0.3cm))], [Missile #super[2];],
      [#box(image("./assets/Pictures/10000000000000150000001CF51053F8.png", height: 0.4cm, width: 0.3cm))], [Mine about to detonate #super[2];],
      [#box(image("./assets/Pictures/10000000000000150000001C18B01FE9.png", height: 0.4cm, width: 0.3cm))], [Space stations and other anchorages],
      [#box(image("./assets/Pictures/10000000000000150000001C51CE1B0C.png", height: 0.4cm, width: 0.3cm))], [Navigation and witchpoint beacons],
      [#box(image("./assets/Pictures/10000000000000150000001C53E46C30.png", height: 0.4cm, width: 0.3cm))], [Witchspace cloud],
      [1], [Non-powered objects include asteroids, cargo pods, escape pods, and abandoned craft.],
      [2], [Certain OXPs will add extra types of munitions to Oolite. The game will use the missile or mine IFF flag to show them.]
    )
    #text(size: 7.5pt, style: "italic")[The twin colour flags are the colours that those IFF flags cycle through.]
    #v(-0.3em)
    #text(size: 7.5pt)[#underline[*Note:*] The layout shown here is for the Faulcon deLacy Cobra Mk III which you are issued with at the start of the game. Other vessels may have alternative instrument configurations.]
  ]
)
