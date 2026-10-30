#import "common.typ": *

#header-text.update("Observer’s Guide")

#show: setup-page.with(body-size: 8pt)

#show: apply-table-styles

// ==========================================
// PAGE 7: OBSERVER'S GUIDE (3 EQUAL COLUMNS)
// ==========================================

#grid(
  columns: (1fr, 1fr, 1fr),
  gutter: 0.5cm,

  // ------------------------------------------
  // COLUMN 1: Adder to Boa Cruiser inclusive
  // ------------------------------------------
  stack(spacing: 0.4em)[
    #ship-card(
      "Adder", "30w x 8h x 45l m", "./assets/Pictures/10000000000001F5000001F56C366291.png",
      "0.24/0.030", "C20", "NJ", "F M1", "2", "yes", "5", "65000",
      "Pulse Laser, 1 Missile, HS",
      "An agile compact ship favoured by couriers, customisers and professional racers."
    )

    #ship-card(
      "Anaconda", "75w x 60h x 170l m", "./assets/Pictures/10000000000001D4000001D4A7A4711C.png",
      "0.14/0.014", "P30", "DB", "All M7", "750", "yes", "9", "650000",
      "Pulse Laser, 3 Missiles",
      "The biggest mass produced freighter available, built like an asteroid and steers like one."
    )

    #ship-card(
      "Asp Mk II", "65w x 20h x 70l m", "./assets/Pictures/10000000000001ED000001EE6077E5C0.png",
      "0.40/0.050", "P30", "JE", "FA M1", "N/A", "yes", "11", "375000",
      "Pulse Laser, 1 Missile",
      "The civilian version of the Galactic Navy's premier long range scouting / commando craft."
    )

    #ship-card(
      "Boa", "65w x 60h x 115l m", "./assets/Pictures/10000000000001DA000001DAE98C5EA8.png",
      "0.24/0.036", "P30", "NE", "All M4", "125", "yes", "7", "450000",
      "Pulse Laser, 3 Missiles",
      "The replacement for the ageing Python, with better performance and capacity."
    )

    #ship-card(
      "Boa Cruiser / Mk II", "65w x 60h x 115l m", "./assets/Pictures/10000000000001FA000001FA5D6E4AD9.png",
      "0.31/0.040", "P32", "LE", "All M5", "175", "yes", "8", "495000",
      "Beam Laser, 5 Missiles",
      "The long haul version of the Boa, trading some agility for more capacity and speed."
    )
  ],

  // ------------------------------------------
  // COLUMN 2: Cobra Mk1 to Fer-de-lance inclusive
  // ------------------------------------------
  stack(spacing: 0.4em)[
    #ship-card(
      "Cobra Mk I", "70w x 15h x 55l m", "./assets/Pictures/100000000000021300000213D03D3F2A.png",
      "0.26/0.025", "E25", "JF", "FA M1", "10", "yes", "5", "100000",
      "Pulse Laser, 1 Missile",
      "The first truly effective solo fighter/trader ship, but now superseded by the Mk III."
    )

    #ship-card(
      "Cobra Mk III", "130w x 30h x 65l m", "./assets/Pictures/10000000000001DA000001DA544F3181.png",
      "0.35/0.032", "H40", "JE", "All M4", "20 (+15)", "yes", "7", "150000",
      "Pulse Laser, 3 Missiles",
      "The most successful medium size ship ever built and an excellent fighter/trader."
    )

    #ship-card(
      [Constrictor #super[†]], "54w x 10h x 60l m", "./assets/Pictures/10000000000001DD000001DD5F3CFDBB.png",
      "Unknown", "?", "Unknown", "?", "Unknown", "yes", "N/A", "N/A",
      "Unknown",
      "Currently under test by the Galactic Navy, the rumours say it's extremely deadly."
    )

    #ship-card(
      "Escape Pod", "7w x 6h x 6l m", "./assets/Pictures/10000000000001AD000001B2ABDD0914.png",
      "0.05/0.005", "P30", "AA", "N/A", "N/A", "no", "7", "1000",
      "N/A",
      "Only technically a ship, the Escape Pod is the primary lifeboat system of GCW ships."
    )

    #ship-card(
      "Fer-de-Lance", "45w x 20h x 85l m", "./assets/Pictures/10000000000001880000018733605447.png",
      "0.30/0.036", "H45", "RE", "All M2", "12", "yes", "9", "485000",
      "Beam Laser, 2 Missiles, 2 Passenger Berths, MTS, STE, ECM, ASC, FI, FS, DC, SB, EP",
      "An agile and deadly assault class ship favoured by bounty hunters and the well-to-do."
    )
  ],

  // ------------------------------------------
  // COLUMN 3: Gecko to Moray Medical Boat inclusive
  // ------------------------------------------
  stack(spacing: 0.4em)[
    #ship-card(
      [Gecko #super[†]], "65w x 12h x 40l m", "./assets/Pictures/10000000000002010000020158BBFC18.png",
      "0.30/0.045", "H40", "OG", "F M1", "3", "no", "N/A", "N/A",
      "Beam Laser, 1 Missile",
      "Produced in unlicensed shipyards, this fighter is a favourite of pirates and assassins."
    )

    #ship-card(
      [Krait #super[†]], "90w x 20h x 80l m", "./assets/Pictures/100000010000024300000243411D4F1F.png",
      "0.30/0.035", "H25", "MG", "F M0", "2", "no", "N/A", "N/A",
      "Beam Laser",
      "A discontinued fighter design finding a new life in the professional racing circuit."
    )

    #ship-card(
      [Mamba #super[†]], "65w x 12h x 55l m", "./assets/Pictures/10000000000001C9000001C9B36345D5.png",
      "0.32/0.032", "H30", "JG", "F M0", "4", "no", "N/A", "N/A",
      "Beam Laser",
      "Originally used in professional racing, this fighter is used by pirates and escorts alike."
    )

    #ship-card(
      "Moray Star Boat", "60w x 25h x 65l m", "./assets/Pictures/10000000000001EA000001EAF9566E8E.png",
      "0.30/0.032", "H30", "JG", "All M2", "7", "yes", "6", "125000",
      "Pulse Laser, 2 Missiles, HS",
      "A multi-role ship, often seen as a medical or tourist craft. It's popular with pirates too."
    )

    #ship-card(
      "Moray Medical Boat", "60w x 25h x 65l m", "./assets/Pictures/10000001000001E1000001E1C71A26B2.png",
      "0.30/0.032", "H30", "JG", "F M2", "7 (+15)", "yes", "6", "145000",
      "HS",
      "Largely used for medical applications, standard model comes with no offensive capabilities."
    )
  ]
)
