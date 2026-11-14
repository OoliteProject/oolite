/*

GuiDisplayGen.h

Class handling interface elements, primarily text, that are not part of the 3D
game world, together with GuiDisplayGen.

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

#import "OOFoundation.h"
#import "OOFunctionAttributes.h"
#import "OOMaths.h"
#import "OOTypes.h"
#import "oofnd/objc/OOObject.h"
#include <quickjs.h>

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"
#include <string_view>

#define GUI_DEFAULT_COLUMNS 6
#define GUI_DEFAULT_ROWS 30

#define GUI_MAX_ROWS 64
#define GUI_MAX_COLUMNS 40
#define MAIN_GUI_PIXEL_HEIGHT 480
#define MAIN_GUI_PIXEL_WIDTH 480
#define MAIN_GUI_ROW_HEIGHT 16
#define MAIN_GUI_ROW_WIDTH 16
#define MAIN_GUI_PIXEL_ROW_START 40

typedef enum {
    GUI_ALIGN_LEFT,
    GUI_ALIGN_RIGHT,
    GUI_ALIGN_CENTER
} OOGUIAlignment;

typedef enum {
    GUI_BACKGROUND_SPECIAL_NONE,
    GUI_BACKGROUND_SPECIAL_CUSTOM,
    GUI_BACKGROUND_SPECIAL_CUSTOM_ANA_SHORTEST,
    GUI_BACKGROUND_SPECIAL_CUSTOM_ANA_QUICKEST,
    GUI_BACKGROUND_SPECIAL_SHORT,
    GUI_BACKGROUND_SPECIAL_SHORT_ANA_SHORTEST,
    GUI_BACKGROUND_SPECIAL_SHORT_ANA_QUICKEST,
    GUI_BACKGROUND_SPECIAL_LONG,
    GUI_BACKGROUND_SPECIAL_LONG_ANA_SHORTEST,
    GUI_BACKGROUND_SPECIAL_LONG_ANA_QUICKEST
} OOGUIBackgroundSpecial;

inline constexpr std::string_view GUI_KEY_OK = "OK";
inline constexpr std::string_view GUI_KEY_SKIP = "SKIP-ROW";

// globals: the gui-settings.plist keys (Foundation sweep chunk 3, oo-3rb.94).
inline constexpr const char* cxx_kGuiDefaultTextColor = "default_text_color";
inline constexpr const char* cxx_kGuiScreenTitleColor = "screen_title_color";
inline constexpr const char* cxx_kGuiScreenDividerColor = "screen_divider_color";
inline constexpr const char* cxx_kGuiSelectedRowBackgroundColor = "selected_row_background_color";
inline constexpr const char* cxx_kGuiSelectedRowColor = "selected_row_color";
inline constexpr const char* cxx_kGuiTextInputCursorColor = "text_input_cursor_color";
// F3
inline constexpr const char* cxx_kGuiEquipmentCashColor = "equipment_cash_color";
inline constexpr const char* cxx_kGuiEquipmentUnavailableColor = "equipment_unavailable_color";
inline constexpr const char* cxx_kGuiEquipmentScrollColor = "equipment_scroll_color";
inline constexpr const char* cxx_kGuiEquipmentOptionColor = "equipment_option_color";
inline constexpr const char* cxx_kGuiEquipmentRepairColor = "equipment_repair_color";
inline constexpr const char* cxx_kGuiEquipmentDescriptionColor = "equipment_description_color";
inline constexpr const char* cxx_kGuiEquipmentLaserColor = "equipment_laser_color";
inline constexpr const char* cxx_kGuiEquipmentLaserFittedColor = "equipment_laser_fitted_color";
inline constexpr const char* cxx_kGuiEquipmentTabs = "equipment_tabs";
// F3 F3
inline constexpr const char* cxx_kGuiShipyardHeadingColor = "shipyard_heading_color";
inline constexpr const char* cxx_kGuiShipyardScrollColor = "shipyard_scroll_color";
inline constexpr const char* cxx_kGuiShipyardEntryColor = "shipyard_entry_color";
inline constexpr const char* cxx_kGuiShipyardNoshipColor = "shipyard_noship_color";
inline constexpr const char* cxx_kGuiShipyardTradeinColor = "shipyard_tradein_color";
inline constexpr const char* cxx_kGuiShipyardDescriptionColor = "shipyard_description_color";
inline constexpr const char* cxx_kGuiShipyardTabs = "shipyard_tabs";
// F4
inline constexpr const char* cxx_kGuiInterfaceHeadingColor = "interface_heading_color";
inline constexpr const char* cxx_kGuiInterfaceScrollColor = "interface_scroll_color";
inline constexpr const char* cxx_kGuiInterfaceEntryColor = "interface_entry_color";
inline constexpr const char* cxx_kGuiInterfaceDescriptionColor = "interface_description_color";
inline constexpr const char* cxx_kGuiInterfaceNoneColor = "interface_none_color";
inline constexpr const char* cxx_kGuiInterfaceTabs = "interface_tabs";
// F5
inline constexpr const char* cxx_kGuiStatusShipnameColor = "status_shipname_color";
inline constexpr const char* cxx_kGuiStatusDataColor = "status_data_color";
inline constexpr const char* cxx_kGuiStatusEquipmentHeadingColor = "status_equipment_heading_color";
inline constexpr const char* cxx_kGuiStatusEquipmentScrollColor = "status_equipment_scroll_color";
inline constexpr const char* cxx_kGuiStatusEquipmentOkColor = "status_equipment_ok_color";
inline constexpr const char* cxx_kGuiStatusEquipmentDamagedColor = "status_equipment_damaged_color";
inline constexpr const char* cxx_kGuiStatusTabs = "status_tabs";
inline constexpr const char* cxx_kGuiStatusPrioritiseDamaged = "status_prioritise_damaged";
// F5 F5
inline constexpr const char* cxx_kGuiManifestSubheadColor = "manifest_subhead_color";
inline constexpr const char* cxx_kGuiManifestEntryColor = "manifest_entry_color";
inline constexpr const char* cxx_kGuiManifestScrollColor = "manifest_scroll_color";
inline constexpr const char* cxx_kGuiManifestNoScrollColor = "manifest_no_scroll_color";
inline constexpr const char* cxx_kGuiManifestTabs = "manifest_tabs";
// F6
inline constexpr const char* cxx_kGuiChartLabelScale = "chart_label_scale";
inline constexpr const char* cxx_kGuiChartCircleScale = "chart_circle_scale";
inline constexpr const char* cxx_kGuiChartLabelColor = "chart_label_color";
inline constexpr const char* cxx_kGuiChartLabelReachableColor = "chart_labelreachable_color";
inline constexpr const char* cxx_kGuiChartRangeColor = "chart_range_color";
inline constexpr const char* cxx_kGuiChartCrosshairColor = "chart_crosshair_color";
inline constexpr const char* cxx_kGuiChartCursorColor = "chart_cursor_color";
inline constexpr const char* cxx_kGuiChartInfoMarkerColor = "chart_info_marker_color";
inline constexpr const char* cxx_kGuiChartMatchBoxColor = "chart_match_box_color";
inline constexpr const char* cxx_kGuiChartMatchLabelColor = "chart_match_label_color";
inline constexpr const char* cxx_kGuiChartConnectionColor = "chart_connection_color";
inline constexpr const char* cxx_kGuiChartCurrentJumpStartColor = "chart_currentjumpstart_color";
inline constexpr const char* cxx_kGuiChartCurrentJumpEndColor = "chart_currentjumpend_color";
inline constexpr const char* cxx_kGuiChartRouteShortColor = "chart_route_short_color";
inline constexpr const char* cxx_kGuiChartRouteQuickColor = "chart_route_quick_color";
inline constexpr const char* cxx_kGuiChartTraveltimeTabs = "chart_traveltime_tabs";

inline constexpr const char* cxx_kGuiChartEconomyUColor = "chart_economy_%zu_color";
inline constexpr const char* cxx_kGuiChartGovernmentUColor = "chart_government_%zu_color";
inline constexpr const char* cxx_kGuiChartTechColor = "chart_tech_color";
// F7
inline constexpr const char* cxx_kGuiSystemdataFactsColor = "systemdata_facts_color";
inline constexpr const char* cxx_kGuiSystemdataDescriptionColor = "systemdata_description_color";
inline constexpr const char* cxx_kGuiSystemdataTabs = "systemdata_tabs";
// F8
inline constexpr const char* cxx_kGuiMarketHeadingColor = "market_heading_color";
inline constexpr const char* cxx_kGuiMarketCommodityColor = "market_commodity_color";
inline constexpr const char* cxx_kGuiMarketScrollColor = "market_scroll_color";
inline constexpr const char* cxx_kGuiMarketFilteredAllColor = "market_filtered_all_color";
inline constexpr const char* cxx_kGuiMarketFilterInfoColor = "market_filter_info_color";
inline constexpr const char* cxx_kGuiMarketCashColor = "market_cash_color";
// F8 F8 extras
inline constexpr const char* cxx_kGuiMarketContractedColor = "market_contracted_color";
inline constexpr const char* cxx_kGuiMarketDescriptionColor = "market_description_color";
inline constexpr const char* cxx_kGuiMarketTabs = "market_tabs";
// Docking report
inline constexpr const char* cxx_kGuiDockingReportColor = "docking_report_color";
inline constexpr const char* cxx_kGuiDockingSummaryColor = "docking_summary_color";
inline constexpr const char* cxx_kGuiDockingContinueColor = "docking_continue_color";

@class OOSound, OOColor, OOTexture, OOTextureSprite, HeadUpDisplay;

typedef NSInteger OOGUIRow; // -1 for none
typedef NSInteger OOGUITabStop; // negative value = right align text
typedef OOGUITabStop OOGUITabSettings[GUI_MAX_COLUMNS];

@interface GuiDisplayGen : OOObject {
@private
    NSSize size_in_pixels;
    unsigned n_columns;
    unsigned n_rows;
    int pixel_row_center;
    unsigned pixel_row_height;
    int pixel_row_start;
    NSSize pixel_text_size;

    BOOL showAdvancedNavArray;

    NSSize pixel_title_size;

    OOColor* backgroundColor;
    OOColor* textColor;
    OOColor* textCommsColor;

    OOTextureSprite* backgroundSprite;
    OOTextureSprite* foregroundSprite;
    OOGUIBackgroundSpecial backgroundSpecial;

    std::optional<std::string> title; // none: no title bar

    std::vector<oo::PList> rowText; // each a string, or an array of column strings (chunk 5a, oo-3rb.165)
    std::vector<std::string> rowKey;
    std::vector<oo::ObjCRef<OOColor*>> rowColor;

    Vector drawPosition;

    NSPoint rowPosition[GUI_MAX_ROWS];
    OOGUIAlignment rowAlignment[GUI_MAX_ROWS];
    float rowFadeTime[GUI_MAX_ROWS];

    OOGUITabSettings tabStops;

    oo::PList guiUserSettings; // a mixed configuration: plist values and OOColors (Amendment 2)

    NSRange rowRange;

    OOGUIRow selectedRow;
    NSRange selectableRange;

    BOOL showTextCursor;
    OOGUIRow currentRow;

    GLfloat max_alpha; // main alpha setting
    GLfloat fade_alpha; // for fade-in / fade-out
    GLfloat fade_sign; //	-1.0 to 1.0
    NSUInteger statusPage; // status  screen: paging equipped items
    OOSystemID foundSystem;
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

/////////////////////////////////////////////////////

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

- (int)drawGUI:(GLfloat)alpha drawCursor:(BOOL)drawCursor;
// The row under a virtual-joystick (pointer) position: the row -drawGUI:drawCursor:YES returns for
// that position, without rendering. A click uses it so that it activates the row under the pointer
// NOW, not the row of the last render (bead oo-3rb.348).
- (int)rowAtVirtualJoystickPosition:(NSPoint)vjpos;
- (void)drawGUIBackground;
- (void)setStatusPage:(NSInteger)pageNum;
- (NSUInteger)statusPage;
- (void)refreshStarChart;
- (void)setStarChartTitle;
- (void)cxx_drawEquipmentList:(const oo::PList&)eqptList z:(GLfloat)z;

- (OOSystemID)targetNextFoundSystem:(int)direction;

@end
