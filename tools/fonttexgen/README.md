# fonttexgen source assets

These files are the inputs that produced the game's font texture,
`Resources/Textures/oolite-font.png`, and its metrics, `Resources/Config/oolite-font.plist`:

- `template.plist`: the layout and substitutions that `oolite-font.plist` is made from;
- `toprows.png`, `toprows-big.png`: the hand-drawn special glyphs in the texture's top rows;
- `oolite-gov-symbols.pdf`: the government symbols.

The generator was a Cocoa (AppKit) application. It has been removed along with the rest of the
Objective-C. The texture and the plist are checked in and do not change in the build. Regenerating
them needs a new tool that renders the glyphs and writes the per-glyph `widths` into a copy of
`template.plist`.
