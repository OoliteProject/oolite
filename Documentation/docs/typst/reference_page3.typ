#import "common.typ": *

#header-text.update("Equipment and Trade")

#show: setup-page.with(header-size: 9.7pt, body-size: 9.6pt)

#show: apply-table-styles

// ==========================================
// PAGE 3: EQUIPMENT AND TRADE
// ==========================================

#grid(
  columns: (1fr, 1fr, 1fr, 1fr),
  gutter: 0.6cm,

  // ------------------------------------------
  // COLUMN 1: Equipment Guide
  // ------------------------------------------
  stack(spacing: 0.5em)[
    #table(
      columns: (1fr, auto, auto),
      align: (left, center, right),
      section-header("Equipment Guide", colspan: 3),
      [*Item*], [*TL*], [*Cost ₢*],
      [Advanced Navigational Array (ANA)], [7], [2250],
      [Advanced Space Compass (ASC)], [8], [650],
      [Beam Laser], [5], [1000],
      [Docking Computers (DC)], [10], [1500],
      [ECM Hardened Missile], [10], [350],
      [ECM System (ECM)], [3], [600],
      [Escape Pod (EP)], [7], [1000],
      [External Heat Shielding (HS)], [5], [1500],
      [Extra Energy Unit (EU)], [9], [1500],
      [Fuel], [All], [Varies],
      [Fuel Scoop (FS)], [6], [525],
      [Galactic Hyperdrive (GH)], [11], [5000],
      [Integrated Targeting System (ITS)], [12], [1500],
      [Large Cargo Bay (LCB)], [2], [400],
      [Maintenance Overhaul], [7], [Varies],
      [Military Laser], [11], [6000],
      [Military Shield Enhancement (MSE)], [14], [47550],
      [Mining Laser], [11], [800],
      [Missile], [2], [30],
      [Multi-Targeting System (MTS)], [6], [325],
      [Passenger Berth], [6], [825],
      [Pulse Laser], [4], [400],
      [Quirium Cascade Mine], [7], [2500],
      [Remove Passenger Berth], [2], [100],
      [Scanner Targeting Enhancement (STE)], [12], [450],
      [Shield Boosters (SB)], [11], [14750],
      [Target System Memory Expansion (TSME)], [9], [1250],
      [Unmount and sell all pylon-mounted weapons], [2], [20],
      [Witchdrive Fuel Injectors (FI)], [11], [600],
      [Wormhole Scanner (WS)], [10], [2395]
    )
    #v(-0.6em)
    #text(size: 7.5pt, style: "italic")[
      Equipment damage can only be repaired in systems of that Tech Level or one lower. The listed prices apply only to GCW station shipyards. Prices may vary in other anchorages. Additional equipment can be obtained by installing mods. See the individual mod documentation for more information on their cost, availability and use.
    ]
  ],

  // ------------------------------------------
  // COLUMN 2: Commodities Guide, Combat Rank
  // ------------------------------------------
  stack(spacing: 0.5em)[
    #table(
      columns: (1fr, auto, auto, auto, auto),
      align: (left, right, right, right, center),
      section-header("Commodities Guide", colspan: 5),
      table.cell(colspan: 1)[*Commodities*], table.cell(colspan: 3, align: center)[*Price ₢*], table.cell(colspan: 1, align: center)[*per*],
      [], [*Min*], [*Avg*], [*Max*], [],
      [Food], [2.0], [4.8], [7.9], [t],
      [Textiles], [5.2], [7.0], [9.0], [t],
      [Radioactives], [17.3], [22.8], [28.8], [t],
      [Slaves †], [2.4], [14.7], [27.9], [t],
      [Liquor/Wines], [20.7], [28.6], [37.4], [t],
      [Luxuries], [78.4], [90.8], [101.9], [t],
      [Narcotics †], [0.5], [50.9], [101.4], [t],
      [Computers], [61.3], [83.0], [102.2], [t],
      [Machinery], [46.5], [56.4], [65.5], [t],
      [Alloys], [31.6], [38.8], [45.6], [t],
      [Firearms †], [49.8], [70.3], [88.5], [t],
      [Furs], [45.4], [69.7], [95.2], [t],
      [Minerals], [10.0], [11.9], [13.9], [t],
      [Gold], [35.3], [38.7], [42.2], [kg],
      [Platinum], [62.6], [71.6], [81.0], [kg],
      [Gem-stones], [15.3], [19.5], [23.8], [g],
      [Alien Items], [21.3], [44.8], [65.7], [t]
    )
    #v(-0.6em)
    #text(size: 7.5pt, style: "italic")[
      [†] Trafficking in these commodities is illegal in all GCW member systems.
    ]
    #v(-0.3em)
    #text(size: 7.5pt, style: "italic")[
      Note: These prices are indicative only. GalCop regulations expressly forbids the broadcasting of actual prices beyond the current system. Prices may also vary widely at non-GCW stations.
    ]

    #table(
      columns: (1fr, auto),
      align: (left, right),
      section-header("Combat Rank"),
      [*Rank*], [*Kills*],
      [Harmless], [0],
      [Mostly Harmless], [8],
      [Poor], [16],
      [Average], [32],
      [Above Average], [64],
      [Competent], [128],
      [Dangerous], [512],
      [Deadly], [2560],
      [Elite], [6400]
    )
  ],

  // ------------------------------------------
  // COLUMN 3: Government Guide, Economy Guide
  // ------------------------------------------
  stack(spacing: 0.5em)[
    #table(
      columns: (auto, auto, 1fr),
      align: (center, center, left),
      section-header("Government Guide", colspan: 3),
      [*Risk*], [*Icon*], [*Type*],
      [Negligible], [#box(image("./assets/Pictures/1000000100000051000000759760F827.png", height: 0.4cm, width: 0.27cm))], [Corporate State],
      [▲ \ Low \ ▼], [#box(image("./assets/Pictures/10000001000000620000007491CB753A.png", height: 0.4cm, width: 0.34cm))], [Democracy],
      [], [#box(image("./assets/Pictures/10000001000000480000007DA945B054.png", height: 0.4cm, width: 0.229cm))], [Confederacy],
      [▲ \ Medium \ ▼], [#box(image("./assets/Pictures/10000001000000710000007122FFE589.png", height: 0.4cm, width: 0.4cm))], [Communist],
      [], [#box(image("./assets/Pictures/10000001000000740000007BD09C1539.png", height: 0.4cm, width: 0.379cm))], [Dictatorship],
      [▲ \ High \ ▼], [#box(image("./assets/Pictures/100000010000007400000074792CD40E.png", height: 0.4cm, width: 0.4cm))], [Multi-Government],
      [], [#box(image("./assets/Pictures/10000001000000620000007407B6C1A1.png", height: 0.4cm, width: 0.34cm))], [Feudal],
      [Extreme], [#box(image("./assets/Pictures/100000010000007400000083C7C5AE78.png", height: 0.4cm, width: 0.349cm))], [Anarchy]
    )

    #table(
      columns: (1fr, auto, 1fr),
      align: (left, center, left),
      section-header("Economy Guide", colspan: 3),
      [*Produces*], [*Icon*], [*Type*],
      [Advanced technology], [#box(image("./assets/Pictures/100000010000008300000077963A92E0.png", height: 0.4cm, width: 0.439cm))], [Rich Industrial],
      [▲ \ Basic technology and Advance Materials \ ▼], [#box(image("./assets/Pictures/100000010000007100000078FA85F0DF.png", height: 0.4cm, width: 0.379cm))], [Average Industrial],
      [], [#box(image("./assets/Pictures/1000000100000048000000788DA803FC.png", height: 0.4cm, width: 0.24cm))], [Poor Industrial],
      [▲ \ Mixture of both \ ▼], [#box(image("./assets/Pictures/100000010000004D00000083607D4C06.png", height: 0.4cm, width: 0.229cm))], [Mainly Industrial],
      [], [#box(image("./assets/Pictures/10000001000000510000007AFDBB9150.png", height: 0.4cm, width: 0.259cm))], [Mainly Agricultural],
      [▲ \ Advanced organics and Refined Materials \ ▼], [#box(image("./assets/Pictures/100000010000005F00000087EAEB72C4.png", height: 0.4cm, width: 0.28cm))], [Rich Agricultural],
      [], [#box(image("./assets/Pictures/10000001000000580000008CA29FCABF.png", height: 0.4cm, width: 0.25cm))], [Average Agricultural],
      [Basic organics and Raw Materials], [#box(image("./assets/Pictures/100000010000003D0000007ED4693E48.png", height: 0.4cm, width: 0.191cm))], [Poor Agricultural]
    )
    #v(-0.6em)
    #text(size: 7.5pt)[
      On the *F6* chart screen, press the "?" key to cycle the highlighted information between:
      #v(-0.3em)
      #list(
        tight: true,
        [Sun color],
        [Economy type],
        [Government type],
        [Tech level]
      )
    ]
  ],

  // ------------------------------------------
  // COLUMN 4: Legal Status, GCW Orbital Laws
  // ------------------------------------------
  stack(spacing: 0.5em)[
    #table(
      columns: (auto, 1fr),
      align: (left, left),
      section-header("Legal Status"),
      [*Status*], [*The commander can expect*],
      [Clean \ ▼], [Free travel and access to GCW Stations. Full protection by GalCop Vipers.],
      [Offender \ ▼], [Free travel and access to GCW Stations. Limited protection by GalCop Vipers, but could also be targeted at law enforcer's discretion. Small bounty on the commander.],
      [Fugitive], [Limited travel and access to GCW Stations. Actively targeted by GalCop Vipers. Large bounty on the commander.]
    )
    #v(-0.6em)
    #text(size: 7.5pt)[
      All commanders start as Clean, with any criminal acts reducing their legal standing. Performing services for the GCW will repair their reputation.
    ]

    #table(
      columns: (1fr),
      align: (left),
      section-header("GCW Orbital Laws", colspan: 1),

      table-gap(colspan: 1),
      sub-header("Services", colspan: 1),
      [*Defence Of GCW Space* \ Providing assistance to the Galactic Navy by the destruction of Thargoid Invasion Fleet craft.],
      [*Space Lane Hazard Clearance* \ Destruction of navigation hazards from the space lanes, i.e. asteroids and wreckage.],
      [*Termination Of Criminals* \ Providing assistance to GalCop by the destruction of Offender and Fugitive rated craft.],

      table-gap(colspan: 1),
      sub-header("Crimes", colspan: 1),
      [*Murder* \ The destruction of any law-abiding vessel with the resulting loss of life.],
      [*Piracy* \ Attacking any law-abiding craft to force them to discharge cargo.],
      [*Property Destruction* \ Attacking a Galactic Cooperative of Worlds Station, Rock Hermitage or other anchorages.],
      [*Trafficking* \ Leaving a GCW station with any of the following commodities on-board: Slaves, Narcotics or Firearms.]
    )
  ]
)
