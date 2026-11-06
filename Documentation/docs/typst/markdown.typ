// Renders one of the Markdown pages in docs/ as a PDF, so the PDFs and the
// ReadTheDocs site share the same source. Compile with the docs/ folder as root:
//   typst compile --root docs --input src=index.md docs/typst/markdown.typ out.pdf
#import "vendor/cmarker/lib.typ" as cmarker

#let src = sys.inputs.at("src")

// mkdocs attr_list image widths, ![](img.png){ width="30%" }, become <img> tags.
// A line straight after a one-line <div></div> would be swallowed into the HTML
// block (mkdocs's md_in_html copes with it, CommonMark doesn't), so add a blank line.
#let markdown = (
  read("/" + src)
    .replace(
      regex("!\[([^\]]*)\]\(([^)]+)\)\{\s*width=\"([^\"]+)\"\s*\}"),
      m => "<img src=\"" + m.captures.at(1) + "\" alt=\"" + m.captures.at(0) + "\" width=\"" + m.captures.at(2) + "\">",
    )
    .replace(regex("(?m)^(<div[^>]*></div>)\n"), m => m.captures.at(0) + "\n\n")
)

#set document(title: src)
#set page(paper: "a4", margin: (x: 1.8cm, y: 1.8cm), numbering: "1")
#set text(font: "Libertinus Serif", size: 10.5pt)
#set par(justify: false)
#show heading.where(level: 1): set text(size: 17pt)
#show heading.where(level: 2): set text(size: 14pt)
#show heading.where(level: 3): set text(size: 12pt)
#show heading: set block(above: 1.4em, below: 0.8em)
#show link: set text(fill: rgb("1a5fb4"))

#set table(
  inset: 4pt,
  stroke: (x, y) => (bottom: 0.4pt + rgb("cccccc")),
  fill: (x, y) => if y == 0 { rgb("eeeeee") },
)
#show table: set text(size: 8.5pt)
#show table.cell.where(y: 0): strong

#let kbd(attrs, body) = box(
  fill: rgb("f4f4f4"),
  stroke: 0.5pt + rgb("aaaaaa"),
  radius: 2pt,
  inset: (x: 2.5pt),
  outset: (y: 2pt),
  text(font: "DejaVu Sans Mono", size: 0.85em, body),
)

// Only the classes used in docs/css/extra.css mean anything in print
#let div(attrs, body) = {
  let classes = attrs.at("class", default: "").split(" ")
  if "no-print" in classes {
    none
  } else if "page-break" in classes {
    pagebreak(weak: true)
  } else {
    body
  }
}

#cmarker.render(
  markdown,
  html: (kbd: kbd, div: div),
  scope: (image: (source, ..args) => image("/" + source.trim("./", at: start), ..args)),
)
