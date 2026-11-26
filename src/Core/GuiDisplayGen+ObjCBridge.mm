/*

GuiDisplayGen+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, beads oo-2g51 to oo-v3ao): the Objective-C GuiDisplayGen facade.
Every method forwards to cxx::GuiDisplayGen in one line. See GuiDisplayGen+ObjCBridge.h.

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

#import "GuiDisplayGen.h"
#import "OOColor.h"
#import "Universe.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface GuiDisplayGen (OOObjCBridgePrivate)

- (id)initWithCxxGui:(cxx::GuiDisplayGen*)gui;
- (id)initWithNewCxxGui:(const oo::Ref<cxx::GuiDisplayGen>&)gui;

@end

@implementation GuiDisplayGen

// Inside the @implementation for the private ivar.
GuiDisplayGen* oo::ToObjC(cxx::GuiDisplayGen* gui)
{
    return Peers().peerFor(gui, [gui] { return [[GuiDisplayGen alloc] initWithCxxGui:gui]; });
}

cxx::GuiDisplayGen* oo::ToCxx(GuiDisplayGen* gui)
{
    if (gui == nil)
        return nullptr;
    return gui->_cxxGui.get();
}

- (id)initWithCxxGui:(cxx::GuiDisplayGen*)gui
{
    self = [super init];
    if (self != nil)
        _cxxGui = oo::Ref<cxx::GuiDisplayGen>(gui);
    return self;
}

// An initialiser's C++ GUI, made before the facade: the facade is its peer.
- (id)initWithNewCxxGui:(const oo::Ref<cxx::GuiDisplayGen>&)gui
{
    self = [self initWithCxxGui:gui.get()];
    if (self != nil) {
        @autoreleasepool {
            Peers().peerFor(gui.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

- (id)init
{
    return [self initWithNewCxxGui:oo::makeRef<cxx::GuiDisplayGen>()];
}

- (id)cxx_initWithPixelSize:(NSSize)gui_size
                    columns:(int)gui_cols
                       rows:(int)gui_rows
                  rowHeight:(int)gui_row_height
                   rowStart:(int)gui_row_start
                      title:(const std::optional<std::string>&)gui_title
{
    return [self initWithNewCxxGui:oo::makeRef<cxx::GuiDisplayGen>(gui_size, gui_cols, gui_rows, gui_row_height, gui_row_start, gui_title)];
}

- (void)dealloc
{
    Peers().forget(_cxxGui.get());
    [super dealloc];
}

- (void)cxx_resizeWithPixelSize:(NSSize)gui_size
                        columns:(int)gui_cols
                           rows:(int)gui_rows
                      rowHeight:(int)gui_row_height
                       rowStart:(int)gui_row_start
                          title:(const std::optional<std::string>&)gui_title
{
    _cxxGui->resizeWithPixelSize(gui_size, gui_cols, gui_rows, gui_row_height, gui_row_start, gui_title);
}

- (void)cxx_resizeTo:(NSSize)gui_size
     characterHeight:(int)csize
               title:(const std::optional<std::string>&)gui_title
{
    _cxxGui->resizeTo(gui_size, csize, gui_title);
}

- (NSSize)size
{
    return _cxxGui->size();
}

- (unsigned)columns
{
    return _cxxGui->columns();
}

- (unsigned)rows
{
    return _cxxGui->rows();
}

- (unsigned)rowHeight
{
    return _cxxGui->rowHeight();
}

- (int)rowStart
{
    return _cxxGui->rowStart();
}

- (std::optional<std::string>)cxx_title
{
    return _cxxGui->getTitle();
}

- (void)cxx_setTitle:(const std::optional<std::string>&)str
{
    _cxxGui->setTitle(str);
}

- (void)setDrawPosition:(Vector)vector
{
    _cxxGui->setDrawPosition(vector);
}

- (Vector)drawPosition
{
    return _cxxGui->getDrawPosition();
}

- (oo::PList)cxx_userSettings
{
    return _cxxGui->userSettings();
}

- (void)fadeOutFromTime:(OOTimeAbsolute)now_time overDuration:(OOTimeDelta)duration
{
    _cxxGui->fadeOutFromTime(now_time, duration);
}

- (void)stopFadeOuts
{
    _cxxGui->stopFadeOuts();
}

- (GLfloat)alpha
{
    return _cxxGui->alpha();
}

- (void)setAlpha:(GLfloat)an_alpha
{
    _cxxGui->setAlpha(an_alpha);
}

- (void)setMaxAlpha:(GLfloat)an_alpha
{
    _cxxGui->setMaxAlpha(an_alpha);
}

- (void)setBackgroundColor:(OOColor*)color
{
    _cxxGui->setBackgroundColor(color);
}

- (OOColor*)textColor
{
    return _cxxGui->getTextColor();
}

- (void)setTextColor:(OOColor*)color
{
    _cxxGui->setTextColor(color);
}

- (OOColor*)textCommsColor
{
    return _cxxGui->getTextCommsColor();
}

- (void)setTextCommsColor:(OOColor*)color
{
    _cxxGui->setTextCommsColor(color);
}

- (OOColor*)cxx_colorFromSetting:(const std::optional<std::string>&)setting defaultValue:(OOColor*)def
{
    return _cxxGui->colorFromSetting(setting, def);
}

- (void)cxx_setGLColorFromSetting:(const std::optional<std::string>&)setting defaultValue:(OOColor*)def alpha:(GLfloat)alpha
{
    _cxxGui->setGLColorFromSetting(setting, def, alpha);
}

- (void)cxx_setGuiColorSettingFromKey:(const std::string&)key color:(OOColor*)col
{
    _cxxGui->setGuiColorSettingFromKey(key, col);
}

- (void)setCharacterSize:(NSSize)character_size
{
    _cxxGui->setCharacterSize(character_size);
}

- (void)setShowAdvancedNavArray:(BOOL)inFlag
{
    _cxxGui->setShowAdvancedNavArray(inFlag);
}

- (void)setColor:(OOColor*)color forRow:(OOGUIRow)row
{
    _cxxGui->setColor(color, row);
}

- (oo::PList)objectForRow:(OOGUIRow)row
{
    return _cxxGui->objectForRow(row);
}

- (std::optional<std::string>)cxx_keyForRow:(OOGUIRow)row
{
    return _cxxGui->keyForRow(row);
}

- (OOGUIRow)cxx_rowForKey:(const std::optional<std::string>&)key
{
    return _cxxGui->rowForKey(key);
}

- (OOGUIRow)selectedRow
{
    return _cxxGui->getSelectedRow();
}

- (BOOL)setSelectedRow:(OOGUIRow)row
{
    return _cxxGui->setSelectedRow(row);
}

- (BOOL)setNextRow:(int)direction
{
    return _cxxGui->setNextRow(direction);
}

- (BOOL)setFirstSelectableRow
{
    return _cxxGui->setFirstSelectableRow();
}

- (BOOL)setLastSelectableRow
{
    return _cxxGui->setLastSelectableRow();
}

- (void)setNoSelectedRow
{
    _cxxGui->setNoSelectedRow();
}

- (std::optional<std::string>)cxx_selectedRowText
{
    return _cxxGui->selectedRowText();
}

- (std::optional<std::string>)cxx_selectedRowKey
{
    return _cxxGui->selectedRowKey();
}

- (void)reportSelectedRow:(int)row
{
    _cxxGui->reportSelectedRow(row);
}

- (void)setShowTextCursor:(BOOL)yesno
{
    _cxxGui->setShowTextCursor(yesno);
}

- (void)setCurrentRow:(OOGUIRow)value
{
    _cxxGui->setCurrentRow(value);
}

- (NSRange)selectableRange
{
    return _cxxGui->getSelectableRange();
}

- (void)setSelectableRange:(NSRange)range
{
    _cxxGui->setSelectableRange(range);
}

- (void)setTabStops:(OOGUITabSettings)stops
{
    _cxxGui->setTabStops(stops);
}

- (void)cxx_overrideTabs:(OOGUITabSettings)stops from:(const std::string&)setting length:(NSUInteger)len
{
    _cxxGui->overrideTabs(stops, setting, len);
}

- (void)clear
{
    _cxxGui->clear();
}

- (void)clearAndKeepBackground:(BOOL)keepBackground
{
    _cxxGui->clearAndKeepBackground(keepBackground);
}

- (void)cxx_setKey:(const std::string&)str forRow:(OOGUIRow)row
{
    _cxxGui->setKey(str, row);
}

- (void)cxx_setText:(const std::string&)str forRow:(OOGUIRow)row
{
    _cxxGui->setText(str, row);
}

- (void)cxx_setText:(const std::optional<std::string>&)str forRow:(OOGUIRow)row align:(OOGUIAlignment)alignment
{
    _cxxGui->setText(str, row, alignment);
}

- (int)rowAtVirtualJoystickPosition:(NSPoint)vjpos
{
    return _cxxGui->rowAtVirtualJoystickPosition(vjpos);
}

- (std::optional<std::string>)cxx_reflowTextForMFD:(const std::optional<std::string>&)input
{
    return _cxxGui->reflowTextForMFD(input);
}

- (OOGUIRow)cxx_addLongText:(const std::optional<std::string>&)str
              startingAtRow:(OOGUIRow)row
                      align:(OOGUIAlignment)alignment
{
    return _cxxGui->addLongText(str, row, alignment);
}

- (void)cxx_printLongText:(const std::optional<std::string>&)str
                    align:(OOGUIAlignment)alignment
                    color:(OOColor*)text_color
                 fadeTime:(float)text_fade
                      key:(const std::optional<std::string>&)text_key
               addToArray:(std::vector<std::string>*)text_array
{
    _cxxGui->printLongText(str, alignment, text_color, text_fade, text_key, text_array);
}

- (void)cxx_printLineNoScroll:(const std::optional<std::string>&)str
                        align:(OOGUIAlignment)alignment
                        color:(OOColor*)text_color
                     fadeTime:(float)text_fade
                          key:(const std::optional<std::string>&)text_key
                   addToArray:(std::vector<std::string>*)text_array
{
    _cxxGui->printLineNoScroll(str, alignment, text_color, text_fade, text_key, text_array);
}

- (void)cxx_setArray:(const std::vector<std::string>&)arr forRow:(OOGUIRow)row
{
    _cxxGui->setArray(arr, row);
}

- (void)cxx_insertItemsFromArray:(const oo::PList&)items
                        withKeys:(const oo::PList&)item_keys
                         intoRow:(OOGUIRow)row
                           color:(OOColor*)text_color
{
    _cxxGui->insertItemsFromArray(items, item_keys, row, text_color);
}

- (void)scrollUp:(int)how_much
{
    _cxxGui->scrollUp(how_much);
}

- (void)setBackgroundTextureSpecial:(OOGUIBackgroundSpecial)spec withBackground:(BOOL)withBackground
{
    _cxxGui->setBackgroundTextureSpecial(spec, withBackground);
}

- (BOOL)cxx_setBackgroundTextureDescriptor:(const oo::PList&)descriptor
{
    return _cxxGui->setBackgroundTextureDescriptor(descriptor);
}

- (BOOL)cxx_setForegroundTextureDescriptor:(const oo::PList&)descriptor
{
    return _cxxGui->setForegroundTextureDescriptor(descriptor);
}

- (BOOL)cxx_setBackgroundTextureKey:(const std::optional<std::string>&)key
{
    return _cxxGui->setBackgroundTextureKey(key);
}

- (BOOL)cxx_setForegroundTextureKey:(const std::optional<std::string>&)key
{
    return _cxxGui->setForegroundTextureKey(key);
}

- (BOOL)cxx_preloadGUITexture:(const oo::PList&)descriptor
{
    return _cxxGui->preloadGUITexture(descriptor);
}

- (oo::PList)cxx_textureDescriptorFromJSValue:(JSValue)value inContext:(JSContext*)context callerDescription:(const std::optional<std::string>&)callerDescription
{
    return _cxxGui->textureDescriptorFromJSValue(value, context, callerDescription);
}

- (void)clearBackground
{
    _cxxGui->clearBackground();
}

- (void)leaveLastLine
{
    _cxxGui->leaveLastLine();
}

- (oo::PList)cxx_getLastLines
{
    return _cxxGui->getLastLines();
}

- (void)setStatusPage:(NSInteger)pageNum
{
    _cxxGui->setStatusPage(pageNum);
}

- (NSUInteger)statusPage
{
    return _cxxGui->getStatusPage();
}

- (void)cxx_drawEquipmentList:(const oo::PList&)eqptList z:(GLfloat)z
{
    _cxxGui->drawEquipmentList(eqptList, z);
}

- (int)drawGUI:(GLfloat)alpha drawCursor:(BOOL)drawCursor
{
    return _cxxGui->drawGUI(alpha, drawCursor);
}

- (void)drawGUIBackground
{
    _cxxGui->drawGUIBackground();
}

- (void)refreshStarChart
{
    _cxxGui->refreshStarChart();
}

- (void)setStarChartTitle
{
    _cxxGui->setStarChartTitle();
}

- (OOSystemID)targetNextFoundSystem:(int)direction
{
    return _cxxGui->targetNextFoundSystem(direction);
}

- (void)drawSystemMarkers:(const oo::PList&)marker atX:(GLfloat)x andY:(GLfloat)y andZ:(GLfloat)z withAlpha:(GLfloat)alpha andScale:(GLfloat)scale
{
    _cxxGui->drawSystemMarkers(marker, x, y, z, alpha, scale);
}

@end

bool GuiDisplayGenUniverseUseShaders()
{
    return [UNIVERSE useShaders];
}
