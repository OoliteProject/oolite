#import "common.typ": *

#header-text.update("Commander’s Log")

#show: setup-page.with(body-size: 8pt)

#let log-entry = table(
  columns: (0.9fr, 0.9fr, 0.9fr, 0.9fr, 1.6fr, 0.5fr, 0.6fr, 0.3fr, 0.6fr, 0.3fr),
  stroke: 0.5pt + rgb("000000"),
  align: (left,left,left,left,left,left,left,left,left,left),
  table.hline(stroke: 1pt),
  table.cell(colspan: 2)[*Solar System -- Galaxy*], table.cell(colspan: 2)[*Commander Status*], table.cell(colspan: 6, align: center)[*Manifest*],
  table.cell(colspan: 2)[GCW MT], table.cell(colspan: 2)[Ship], [Commodity], [Quantity], table.cell(colspan: 2, align: center)[Buy Price], table.cell(colspan: 2, align: center)[Sell Price],
  table.cell(rowspan: 2)[Present System], table.cell(rowspan: 2)[Destination System], table.cell(rowspan: 2)[Credits], table.cell(rowspan: 2)[Cargo Capacity], [~], [], [], [], [], [],
  [~], [], [], [], [], [],
  table.cell(rowspan: 2)[Government], table.cell(rowspan: 2)[Government], table.cell(rowspan: 2)[Legal Status:], table.cell(rowspan: 2)[Combat Rating:], [~], [], [], [], [], [],
  [~], [], [], [], [], [],
  table.cell(rowspan: 2)[Economy], table.cell(rowspan: 2)[Economy], table.cell(colspan: 2, rowspan: 3)[Outstanding Contracts], [~], [], [], [], [], [],
  [~], [], [], [], [], [],
  [Tech Level], [Tech Level], [~], [], [], [], [], [],
  table.cell(colspan: 4, rowspan: 7)[Notes], [~], [], [], [], [], [],
  [~], [], [], [], [], [],
  [~], [], [], [], [], [],
  [~], [], [], [], [], [],
  [~], [], [], [], [], [],
  [~], [], [], [], [], [],
  [~], [], [], [], [], [],
)

#grid(
  columns: (1fr),
  gutter: 0.5cm,

  stack()[
    #figure(
      align(center)[
        #log-entry
        #log-entry
      ]
    )
  ],
)
