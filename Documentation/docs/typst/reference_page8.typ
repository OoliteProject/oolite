#import "common.typ": *

#header-text.update("Observer’s Guide")

#show: setup-page.with(body-size: 8pt)

#show: apply-table-styles

// ==========================================
// PAGE 8: OBSERVER'S GUIDE (3 EQUAL COLUMNS)
// ==========================================

#grid(
  columns: (1fr, 1fr, 1fr),
  gutter: 0.5cm,

  // ------------------------------------------
  // COLUMN 1: Orbital Shuttle to Thargoid Robotic Fighter inclusive
  // ------------------------------------------
  stack(spacing: 0.4em)[
    #ship-card(
      [Orbital Shuttle #super[†]], "20w x 20h x 35l m", "./assets/Pictures/100000000000020600000205F1255681.png",
      "0.08/0.016", "D10", "JD", "N/A", "30", "no", "N/A", "N/A",
      "None",
      "Often unmanned, this ship is the GCW's primary in-system heavy cargo hauler."
    )

    #ship-card(
      "Python", "80w x 40h x 130l m", "./assets/Pictures/10000000000001B1000001B17B569ADA.png",
      "0.20/0.020", "N25", "JD", "All M2", "100 (+15)", "yes", "5", "200000",
      "Pulse Laser, 1 Missile",
      "An ageing design that's still popular with commanders needing a simple robust freighter."
    )

    #ship-card(
      [Sidewinder Scout Ship #super[†]], "65w x 15h x 35l m", "./assets/Pictures/10000000000001EC000001ECC595B883.png",
      "0.37/0.037", "H25", "NH", "F M0", "N/A", "no", "N/A", "N/A",
      "Pulse Laser",
      "A tough compact fighter popular with racers, freighter escorts and pirates alike."
    )

    #ship-card(
      [Thargoid Warship #super[†]], "180w x 40h x 180l m", "./assets/Pictures/10000000000002510000025171CDF272.png",
      "0.50/0.050", "S40", "JE", "All M5", "N/A", "yes", "N/A", "N/A",
      "Thargoid Laser, ECM, 5 Robotic fighters",
      "The primary vessel of the Thargoid Invasion Fleet. Deadly and fights without fear."
    )

    #ship-card(
      [Thargoid Robotic Fighter #super[†]], "38w x 9h x 36l m", "./assets/Pictures/10000000000001F0000001F1D4B783D7.png",
      "0.45/0.040", "E30", "JE", "F M0", "N/A", "no", "N/A", "N/A",
      "Pulse Laser",
      "Small remote-controlled fighters designed to swarm their victims."
    )
  ],

  // ------------------------------------------
  // COLUMN 2: Transporter to Worm inclusive & Stations
  // ------------------------------------------
  stack(spacing: 0.4em)[
    #ship-card(
      [Transporter #super[†]], "30w x 10h x 35l m", "./assets/Pictures/10000000000001CE000001CE9AA2BC17.png",
      "0.10/0.020", "E30", "JE", "All M0", "12", "no", "N/A", "N/A",
      "None",
      "Predating the GCW, this ship serves as shuttle, cargo hauler and industrial platform."
    )

    #ship-card(
      [Viper #super[†]], "50w x 16h x 55l m", "./assets/Pictures/100000000000020400000204B5CE487B.png",
      "0.32/0.032", "F40", "NI", "F M1", "N/A", "no", "N/A", "N/A",
      "Beam Laser, ECM, 1 Missile, EP",
      "GalCop's mainstay patrol vessel, capable of dealing with the most deadly threat."
    )

    #ship-card(
      [Viper Interceptor #super[†]], "50w x 16h x 55l m", "./assets/Pictures/10000000000001F5000001F57CEA1A18.png",
      "0.52/0.050", "I60", "UJ", "F M3", "N/A", "yes", "N/A", "N/A",
      "Military Laser, ECM, 3 Missiles, EP",
      "GalCop's best pilots fly these ships to fight threats of an interstellar scale."
    )

    #ship-card(
      [Worm #super[†]], "35w x 12h x 35l m", "./assets/Pictures/10000000000001BF000001BFC7AE7144.png",
      "0.11/0.012", "C20", "JE", "F M0", "2", "no", "N/A", "N/A",
      "None",
      "A simple support craft, often seen as a ship's launch, lifeboat or miner."
    )

    #v(1.2em)
    #block(width: 100%)[
      #align(center)[*Stations and Other Anchorages*]
      #v(0.3em)
      #grid(
        columns: (1fr, 1fr, 1fr, 1fr),
        gutter: 0.2cm,
        align: center + horizon,
        image("./assets/Pictures/100000000000021F0000021F6251BA5B.png", height: 1.5cm, fit: "contain"),
        image("./assets/Pictures/100000000000020D0000020DF901DFA4.png", height: 1.5cm, fit: "contain"),
        image("./assets/Pictures/10000000000001EC000001EC11F34CC1.png", height: 1.5cm, fit: "contain"),
        image("./assets/Pictures/100000000000023600000235FD1968EA.png", height: 1.5cm, fit: "contain"),
        [#text(size: 7.5pt)[Coriolis Station]],
        [#text(size: 7.5pt)[Dodecahedron Station]],
        [#text(size: 7.5pt)[Icosahedron Station]],
        [#text(size: 7.5pt)[Rock Hermit]],
      )
    ]
  ],

  // ------------------------------------------
  // COLUMN 3: Notes, Other Objects Grid, & Credits Box
  // ------------------------------------------
  stack(spacing: 0.4em)[
    #block(width: 100%)[
      #text(weight: "bold")[Notes]
      #v(0.2em)
      #text(size: 7.5pt)[
        *†* Ships which are unavailable for purchase at the GCW station shipyards for the following reasons:
        #list(
          indent: 1em,
          [GCW shipyards specialise in currently manufactured models fitted with hyperspace drives.],
          [GCW shipyards will not deal in craft from unlicensed manufacturers.],
          [It is illegal for civilians to own Local Government, Galactic Navy and GalCop ships. It is also illegal for civilians to be in possession of craft constructed outside of the Galactic Cooperative of Worlds.],
        )
        #list(
          [Speed is measured against _Light Mach_, which is the maximum velocity a ship can reach before suffering relativistic effects.],
          [The ships' banks and charge rate are graded on the _KeZecky_ scale. The higher letter (_A_ being the lowest) and number value, the larger and faster charging the energy bank is.],
          [A vessel's agility is measured using the _Holdstock_ method. The higher value of each letter (_A_ being the lowest) the better the performance.],
          [Ships have laser mounts in the _Forward_, _Aft_, or _All_ view screen directions. The number of pylons is shown by the _M_ value.],
          [Cargo space is measured in GCW standardised 1 TC cargo canisters.],
          [The base price is calculated for craft with the base equipment fitted. Ships available for sale may be fitted with extra equipment, with a corresponding increase in price.],
          [Images shown here are not to scale and measurements are listed in metres.],
        )
      ]
    ]

    #v(1.2em)
    #block(width: 100%)[
      #align(center)[*Other Objects*]
      #v(0.3em)
      #grid(
        columns: (1fr, 1fr, 1fr),
        gutter: 0.2cm,
        align: center + horizon,

        image("./assets/Pictures/10000000000002530000025325D15D12.png", height: 1.3cm, fit: "contain"),
        image("./assets/Pictures/10000000000001AF000001AFC99D1065.png", height: 1.3cm, fit: "contain"),
        image("./assets/Pictures/100000000000006400000060E96C64EB.png", height: 1.3cm, fit: "contain"),
        [#text(size: 7.5pt)[Cargo Canister]],
        [#text(size: 7.5pt)[Missile]],
        [#text(size: 7.5pt)[Quirium Cascade Mine]],

        image("./assets/Pictures/10000001000000C8000000C3F906FB25.png", height: 1.3cm, fit: "contain"),
        image("./assets/Pictures/10000000000002560000025678643601.png", height: 1.3cm, fit: "contain"),
        image("./assets/Pictures/10000000000001DC000001DCF65B6051.png", height: 1.3cm, fit: "contain"),
        [#text(size: 7.5pt)[Beacon]],
        [#text(size: 7.5pt)[Asteroid]],
        [#text(size: 7.5pt)[Boulder]],

        image("./assets/Pictures/10000000000001F5000001F53D288C22.png", height: 1.3cm, fit: "contain"),
        image("./assets/Pictures/1000000000000252000002529E9BFB84.png", height: 1.3cm, fit: "contain"),
        image("./assets/Pictures/10000000000000ED000000EADE86F00A.png", height: 1.3cm, fit: "contain"),
        [#text(size: 7.5pt)[Splinter]],
        [#text(size: 7.5pt)[Metal Fragment]],
        [#text(size: 7.5pt)[Witchcloud]],
      )
    ]

    #v(1.2em)
    #rect(
      width: 100%,
      inset: 4pt,
      radius: 2pt,
      stroke: 0.4pt + rgb("cccccc"),
      fill: rgb("fafafa"),
    )[
      #set text(size: 5.8pt)
      #set par(leading: 0.35em)
      *Oolite* created by Giles Williams, Jens Ayton and contributors © 2003–2026 \

      #v(0.1em)
      #grid(
        columns: (auto, 1fr),
        column-gutter: 0.4em,
        row-gutter: 0.3em,
        [*Documentation:*], url-link("https://oolite.readthedocs.io/"),
        [*Website:*], url-link("https://www.oolite.space"),
        [*Wiki:*], url-link("https://wiki.alioth.net/index.php/Oolite"),
        [*BBS:*], url-link("https://bb.oolite.space"),
      )

      #v(0.1em)
      Oolite is inspired by the Elite computer game series, originally created by Ian Bell and David Braben. \
      GNU General Public License V2 & Creative Commons License: BY - NC - SA 3.0

      #v(0.1em)
      *Oolite Reference Sheet* by KZ9999, updated and expanded by phkb, ported to Typst by mcarans. \
      Inspired by the OoliteRS by Darkbee / another_commander / Commander McLane. \

      *Checked by* Disembodied, \_ds\_, Kaks, Commander McLane, Ahruman, Micha, another_commander, Cholmondely and others.
    ]
  ]
)
