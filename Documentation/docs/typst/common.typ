// Create a dynamic state for the page-specific header title
#let header-text = state("header-text", "")

// Global Setup Function
#let setup-page(
  body,
  body-size: 9.3pt,
  header-size: 9.4pt,
) = {
  // 1. Page Geometry & Header
  set page(
    paper: "a4",
    flipped: true,
    margin: (x: 0.5cm, top: 0.9cm, bottom: 0.5cm),
    numbering: none,
    header: context {
      text(size: header-size, fill: rgb("444444"))[
        #grid(
          columns: (1fr, 1fr, 1fr),
          align(left)[],
          align(center)[*Oolite Reference Sheet*],
          align(right)[#text(fill: rgb("666666"), weight: "bold")[#header-text.get()]]
        )
      ]
      v(-0.5em)
      line(length: 100%, stroke: 0.4pt + rgb("cccccc"))
      v(-0.3em)
    }
  )

  // 2. Base Typography
  set text(
    font: ("Libertinus Serif"),
    size: body-size,
    stretch: 90%,
    hyphenate: false
  )
  set par(leading: 0.38em, justify: false)

  // Return body (Required!)
  body
}

#let apply-table-styles(
  body,
  columns: auto,
  align: (left, left),
) = {
  // 1. Configure cell properties globally
  set table(
    inset: 2.8pt,
    stroke: (x, y) => if y == 0 { none } else { (bottom: 0.3pt + rgb("dddddd")) },
    columns: columns,
    align: align
  )

  // 2. Clean layout wrapper (fill grid cells completely)
  show table: it => block(width: 100%, it)

  body
}

// Helper functions with their own direct defaults (overrideable on call)

// Styled header helper for our reference sections - centered text
#let section-header(title, colspan: 2) = table.cell(colspan: colspan, fill: rgb("eeeeee"))[*#title*]

// Styled helper for subheadings (Services, Crimes, Bounty Hunting, etc.)
#let sub-header(title, colspan: 2) = table.cell(
  colspan: colspan,
  fill: rgb("f4f4f4"),
  align: center,
  inset: 2.8pt
)[
  #text(size: 8.5pt, weight: "semibold", fill: rgb("333333"))[#title]
]

// Spacer cell helper to create clean white space inside tables
#let table-gap(colspan: 2, height: 0.4em) = table.cell(colspan: colspan, stroke: none, inset: 0pt)[#v(height)]

// Helper function to format clickable URLs cleanly
#let url-link(url) = link(url)[#underline(text(fill: rgb("0056b3"))[#url])]

// Main ship table generator following your exact layout requirements
#let ship-card(
  name, size, img,
  speed, charge,
  rp, mounts,
  cargo, hyper,
  tech, price,
  equip, desc
) = table(
  columns: (23fr, 26fr, 13fr, 24fr, 10fr), // Col 1 widest, then 2, 4, 3, 5
  align: (x, y) => if x == 0 { left + horizon } else { left + horizon },
  stroke: (x, y) => if y == 6 { none } else { (bottom: 0.3pt + rgb("dddddd")) },
  inset: (x: 2pt, y: 4pt),

  // Row 1: Ship Name & Dimensions
  table.cell(colspan: 3)[#text(size: 9pt)[*#name*]],
  table.cell(colspan: 2, align: right)[#size],

  // Row 2-5: Col 1 Picture spanning 4 rows (Rows 2 to 5)
  table.cell(rowspan: 4, align: center + horizon)[
    #image(img, width: 100%, height: 1.7cm, fit: "contain")
  ],

  // Row 2: Speed / Banks
  [*Speed/Thrust (lm)*], [#speed], [*Banks & Charge*], [#charge],

  // Row 3: Roll & Pitch / Weapon Mounts
  [*Roll & Pitch*], [#rp], [*Weapon Mounts*], [#mounts],

  // Row 4: Cargo Space / Hyperspace
  [*Cargo Space (t)*], [#cargo], [*Hyperspace*], [#hyper],

  // Row 5: Sold at Tech Level / Base Price
  [*Sold at Tech Level*], [#tech], [*Base Price (cr)*], [#price],

  // Row 6: Base Equipment (Cols 3-5 combined into 1 spanned cell)
  [], [*Base Equipment*], table.cell(colspan: 3)[#equip],

  // Row 7: One-line description spanning all 5 columns with top spacing
  table.cell(colspan: 5)[
    #v(0.3em)
    #text(size: 7.5pt, style: "italic")[#desc]
    #v(0.1em)
  ]
)

