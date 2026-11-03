/*

GuiDisplayGen+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, beads oo-2g51, oo-6dvw, oo-bcz4, oo-v3ao): the Objective-C
GuiDisplayGen, a facade over the C++ cxx::GuiDisplayGen (GuiDisplayGen.h), for the code that is not
converted yet: the universe, which makes the GUIs with +alloc and -init / -cxx_initWithPixelSize:...
and draws them, the player, the HUD, the OXZ manager and the scripting bindings, which message them.
Its interface is the one GuiDisplayGen.h declared before the conversion, copied exactly (same
selectors, same types), less the ivars, which are the C++ class's members. Each method forwards to
its C++ member. Imported as the last line of GuiDisplayGen.h; do not import it directly.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  ----------------------------
        still Objective-C                      GuiDisplayGen * (this facade)   nothing: messages as before
        converted (C++)                        oo::Ref<cxx::GuiDisplayGen>
          handing a GUI to Objective-C                                         oo::ToObjC(gui)
          taking one from Objective-C                                          oo::ToCxx(objcGui)

oo::ToObjC gives the GUI's one live facade (oo::ObjCPeers), so identity survives a round trip
(the universe compares a GUI with its own: self == [UNIVERSE gui]). Never add to this file;
converted code does not message the facade. Deleted by its deletion bead once no file outside
GuiDisplayGen.* names the Objective-C class.

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#ifndef GUIDISPLAYGEN_OBJCBRIDGE_H
#define GUIDISPLAYGEN_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@interface GuiDisplayGen : OOObject {
@private
    oo::Ref<cxx::GuiDisplayGen> _cxxGui;
}

- (id)init;
/*	Foundation sweep (proposed ADR-0043, chunk 1 of oo-ol63: bead oo-3rb.92): titles, row texts and
        row keys are UTF-8 std::strings, std::optional where the old code accepted or returned nil.
*/
- (id)cxx_initWithPixelSize:(NSSize)gui_size
                    columns:(int)gui_cols
                       rows:(int)gui_rows
                  rowHeight:(int)gui_row_height
                   rowStart:(int)gui_row_start
                      title:(const std::optional<std::string>&)gui_title OO_RETURNS_RETAINED;

- (void)cxx_resizeWithPixelSize:(NSSize)gui_size
                        columns:(int)gui_cols
                           rows:(int)gui_rows
                      rowHeight:(int)gui_row_height
                       rowStart:(int)gui_row_start
                          title:(const std::optional<std::string>&)gui_title;
- (void)cxx_resizeTo:(NSSize)gui_size
     characterHeight:(int)csize
               title:(const std::optional<std::string>&)gui_title;
- (NSSize)size;
- (unsigned)columns;
- (unsigned)rows;
- (unsigned)rowHeight;
- (int)rowStart;

- (std::optional<std::string>)cxx_title; // nullopt: no title (bead oo-3rb.290)
- (void)cxx_setTitle:(const std::optional<std::string>&)str; // empty string means no title (bead oo-3rb.290)

- (void)dealloc;

- (void)setDrawPosition:(Vector)vector;
- (Vector)drawPosition;

- (oo::PList)cxx_userSettings; // gui-settings.plist, with any colours set by -cxx_setGuiColorSettingFromKey:color:

- (void)fadeOutFromTime:(OOTimeAbsolute)now_time overDuration:(OOTimeDelta)duration;
- (void)stopFadeOuts;

- (GLfloat)alpha;
- (void)setAlpha:(GLfloat)an_alpha;
- (void)setMaxAlpha:(GLfloat)an_alpha;

- (void)setBackgroundColor:(OOColor*)color;

- (OOColor*)textColor;
- (void)setTextColor:(OOColor*)color;
- (OOColor*)textCommsColor;
- (void)setTextCommsColor:(OOColor*)color;
- (OOColor*)cxx_colorFromSetting:(const std::optional<std::string>&)setting defaultValue:(OOColor*)def;
- (void)cxx_setGLColorFromSetting:(const std::optional<std::string>&)setting defaultValue:(OOColor*)def alpha:(GLfloat)alpha;
- (void)cxx_setGuiColorSettingFromKey:(const std::string&)key color:(OOColor*)col;

- (void)setCharacterSize:(NSSize)character_size;

- (void)setShowAdvancedNavArray:(BOOL)inFlag;

- (void)setColor:(OOColor*)color forRow:(OOGUIRow)row;

- (oo::PList)objectForRow:(OOGUIRow)row; // a string, or an array of column strings; null out of range
- (std::optional<std::string>)cxx_keyForRow:(OOGUIRow)row;
- (OOGUIRow)cxx_rowForKey:(const std::optional<std::string>&)key;
- (OOGUIRow)selectedRow;
- (BOOL)setSelectedRow:(OOGUIRow)row;
- (BOOL)setNextRow:(int)direction;
- (BOOL)setFirstSelectableRow;
- (BOOL)setLastSelectableRow;
- (void)setNoSelectedRow;
- (std::optional<std::string>)cxx_selectedRowText;
- (std::optional<std::string>)cxx_selectedRowKey;
- (void)reportSelectedRow:(int)row;

- (void)setShowTextCursor:(BOOL)yesno;
- (void)setCurrentRow:(OOGUIRow)value;

- (NSRange)selectableRange;
- (void)setSelectableRange:(NSRange)range;

- (void)setTabStops:(OOGUITabSettings)stops;
- (void)cxx_overrideTabs:(OOGUITabSettings)stops from:(const std::string&)setting length:(NSUInteger)len;

- (void)clear;
- (void)clearAndKeepBackground:(BOOL)keepBackground;

- (void)cxx_setKey:(const std::string&)str forRow:(OOGUIRow)row;
- (void)cxx_setText:(const std::string&)str forRow:(OOGUIRow)row;
- (void)cxx_setText:(const std::optional<std::string>&)str forRow:(OOGUIRow)row align:(OOGUIAlignment)alignment; // nullopt: no change

// The row under a virtual-joystick (pointer) position: the row -drawGUI:drawCursor:YES returns for
// that position, without rendering. A click uses it so that it activates the row under the pointer
// NOW, not the row of the last render (bead oo-3rb.348).
- (int)rowAtVirtualJoystickPosition:(NSPoint)vjpos;

// Chunk 2 (oo-3rb.93): a nil text or key is std::nullopt (nothing printed / no key set, as before);
// text_array, when not nullptr, receives each line printed.
- (std::optional<std::string>)cxx_reflowTextForMFD:(const std::optional<std::string>&)input;
- (OOGUIRow)cxx_addLongText:(const std::optional<std::string>&)str
              startingAtRow:(OOGUIRow)row
                      align:(OOGUIAlignment)alignment;
- (void)cxx_printLongText:(const std::optional<std::string>&)str
                    align:(OOGUIAlignment)alignment
                    color:(OOColor*)text_color
                 fadeTime:(float)text_fade
                      key:(const std::optional<std::string>&)text_key
               addToArray:(std::vector<std::string>*)text_array;
- (void)cxx_printLineNoScroll:(const std::optional<std::string>&)str
                        align:(OOGUIAlignment)alignment
                        color:(OOColor*)text_color
                     fadeTime:(float)text_fade
                          key:(const std::optional<std::string>&)text_key
                   addToArray:(std::vector<std::string>*)text_array;

- (void)cxx_setArray:(const std::vector<std::string>&)arr forRow:(OOGUIRow)row; // one string per column

// items: an array of row texts (a string, or an array of column strings); item_keys: null or an
// array of the same length.
- (void)cxx_insertItemsFromArray:(const oo::PList&)items
                        withKeys:(const oo::PList&)item_keys
                         intoRow:(OOGUIRow)row
                           color:(OOColor*)text_color;

- (void)scrollUp:(int)how_much;

/* allows the use of special dynamic backgrounds */
- (void)setBackgroundTextureSpecial:(OOGUIBackgroundSpecial)spec withBackground:(BOOL)withBackground;

/*
        A background/foreground texture descriptor is a dictionary with a string
        property keyed "name" and optional number properties keyed "width" and
        "height". Chunk 4 (oo-3rb.94..95): descriptors are oo::PList (null = nil).
*/

- (BOOL)cxx_setBackgroundTextureDescriptor:(const oo::PList&)descriptor;
- (BOOL)cxx_setForegroundTextureDescriptor:(const oo::PList&)descriptor;
- (BOOL)cxx_setBackgroundTextureKey:(const std::optional<std::string>&)key;
- (BOOL)cxx_setForegroundTextureKey:(const std::optional<std::string>&)key;

- (BOOL)cxx_preloadGUITexture:(const oo::PList&)descriptor;

/*
        Interpret a JavaScript value as a texture descriptor for
        -[GUIDisplayGen cxx_set{Background|Foreground}TextureDescriptor:]. Also starts
        preloading the texture. Null: no such texture.

        callerDescription is a string describing the context in which this was
        called, generally a method name (like "mission.runScreen()") for warning
        generation.

        Requires a request on context.
*/
- (oo::PList)cxx_textureDescriptorFromJSValue:(JSValue)value inContext:(JSContext*)context callerDescription:(const std::optional<std::string>&)callerDescription;

- (void)clearBackground;

- (void)leaveLastLine;
- (oo::PList)cxx_getLastLines; // text, colour, fade time (x 2); null with no rows
- (void)setStatusPage:(NSInteger)pageNum;
- (NSUInteger)statusPage;
- (void)cxx_drawEquipmentList:(const oo::PList&)eqptList z:(GLfloat)z;

- (int)drawGUI:(GLfloat)alpha drawCursor:(BOOL)drawCursor;
- (void)drawGUIBackground;
- (void)refreshStarChart;
- (void)setStarChartTitle;

- (OOSystemID)targetNextFoundSystem:(int)direction;

@end

// Slice 3's facade forwarder for the system markers (ADR-0056 amendment oo-bwjb item 2). Slice 4
// no longer sends it, but test_GuiDisplayGen cxxSlice3API pins that the facade answers it (bead
// oo-iro0g); deleted with the facade.
@interface GuiDisplayGen (OOGuiDisplayGenInternalForwarded)

- (void)drawSystemMarkers:(const oo::PList&)marker atX:(GLfloat)x andY:(GLfloat)y andZ:(GLfloat)z withAlpha:(GLfloat)alpha andScale:(GLfloat)scale;

@end

// One-line bridges (ADR-0056 amendment oo-9ht.139 item 3) for the file-scope helpers of
// GuiDisplayGen.mm, which may not message the universe themselves. Deleted with the universe's
// conversion.
bool GuiDisplayGenUniverseUseShaders();

namespace oo {

// The GUI's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
GuiDisplayGen* ToObjC(cxx::GuiDisplayGen* gui);
inline GuiDisplayGen* ToObjC(const Ref<cxx::GuiDisplayGen>& gui) { return ToObjC(gui.get()); }
// The C++ GUI behind a facade, borrowed (the facade retains it); null for nil.
cxx::GuiDisplayGen* ToCxx(GuiDisplayGen* gui);

} // namespace oo

#endif // GUIDISPLAYGEN_OBJCBRIDGE_H
