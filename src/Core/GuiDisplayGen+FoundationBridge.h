/*

GuiDisplayGen+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; made by bead oo-3rb.92, chunk 1 of the
GuiDisplayGen sweep oo-ol63, and extended only by its later chunks oo-3rb.93-.96). GuiDisplayGen's
Foundation-typed API as it was before its sweep, with the same selector names and types,
forwarding to the cxx_ API in GuiDisplayGen.h. It exists so that GuiDisplayGen's callers (13
files) compile unchanged; each caller moves to the cxx_ API in its own sweep bead. When
`git grep` finds no caller of anything declared here, the bridge bead deletes this file,
GuiDisplayGen+FoundationBridge.mm, its line in Core/meson.build and the #import at the end of
GuiDisplayGen.h. Never add to it outside the GuiDisplayGen chunks; never call it from migrated
code. oo-qps (the removal of gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2004-2013 Giles C Williams and contributors (GuiDisplayGen.h)

*/

// Imported only from the end of GuiDisplayGen.h (which declares everything used here); never
// import it directly, and never import GuiDisplayGen.h from it (a cycle).
#ifndef GUIDISPLAYGEN_FOUNDATIONBRIDGE_H
#define GUIDISPLAYGEN_FOUNDATIONBRIDGE_H

@interface GuiDisplayGen (OOFoundationBridge)

// Chunk 1 (oo-3rb.92): row text and keys, title initialisers.
- (id)initWithPixelSize:(NSSize)gui_size
                columns:(int)gui_cols
                   rows:(int)gui_rows
              rowHeight:(int)gui_row_height
               rowStart:(int)gui_row_start
                  title:(NSString*)gui_title; // -> -cxx_initWithPixelSize:columns:rows:rowHeight:rowStart:title:

- (void)resizeWithPixelSize:(NSSize)gui_size
                    columns:(int)gui_cols
                       rows:(int)gui_rows
                  rowHeight:(int)gui_row_height
                   rowStart:(int)gui_row_start
                      title:(NSString*)gui_title; // -> -cxx_resizeWithPixelSize:columns:rows:rowHeight:rowStart:title:
- (void)resizeTo:(NSSize)gui_size
    characterHeight:(int)csize
              title:(NSString*)gui_title; // -> -cxx_resizeTo:characterHeight:title:

- (NSString*)keyForRow:(OOGUIRow)row; // -> -cxx_keyForRow:
- (OOGUIRow)rowForKey:(NSString*)key; // -> -cxx_rowForKey:
- (NSString*)selectedRowText; // -> -cxx_selectedRowText
- (NSString*)selectedRowKey; // -> -cxx_selectedRowKey

- (void)setKey:(NSString*)str forRow:(OOGUIRow)row; // -> -cxx_setKey:forRow:
- (void)setText:(NSString*)str forRow:(OOGUIRow)row; // -> -cxx_setText:forRow:
- (void)setText:(NSString*)str forRow:(OOGUIRow)row align:(OOGUIAlignment)alignment; // -> -cxx_setText:forRow:align:

- (void)setArray:(NSArray*)arr forRow:(OOGUIRow)row; // -> -cxx_setArray:forRow:

// Chunk 2 (oo-3rb.93): long text, reflow and item lists.
- (NSString*)reflowTextForMFD:(NSString*)input; // -> -cxx_reflowTextForMFD:
- (OOGUIRow)addLongText:(NSString*)str
          startingAtRow:(OOGUIRow)row
                  align:(OOGUIAlignment)alignment; // -> -cxx_addLongText:startingAtRow:align:
- (void)printLongText:(NSString*)str
                align:(OOGUIAlignment)alignment
                color:(OOColor*)text_color
             fadeTime:(float)text_fade
                  key:(NSString*)text_key
           addToArray:(NSMutableArray*)text_array; // -> -cxx_printLongText:align:color:fadeTime:key:addToArray:
- (void)printLineNoScroll:(NSString*)str
                    align:(OOGUIAlignment)alignment
                    color:(OOColor*)text_color
                 fadeTime:(float)text_fade
                      key:(NSString*)text_key
               addToArray:(NSMutableArray*)text_array; // -> -cxx_printLineNoScroll:align:color:fadeTime:key:addToArray:

- (void)insertItemsFromArray:(NSArray*)items
                    withKeys:(NSArray*)item_keys
                     intoRow:(OOGUIRow)row
                       color:(OOColor*)text_color; // -> -cxx_insertItemsFromArray:withKeys:intoRow:color:

- (NSArray*)getLastLines; // -> -cxx_getLastLines

// Chunk 3 (oo-3rb.94): settings, colours and tab stops.
- (NSDictionary*)userSettings; // -> -cxx_userSettings
- (OOColor*)colorFromSetting:(NSString*)setting defaultValue:(OOColor*)def; // -> -cxx_colorFromSetting:defaultValue:
- (void)setGLColorFromSetting:(NSString*)setting defaultValue:(OOColor*)def alpha:(GLfloat)alpha; // -> -cxx_setGLColorFromSetting:defaultValue:alpha:
- (void)setGuiColorSettingFromKey:(NSString*)key color:(OOColor*)col; // -> -cxx_setGuiColorSettingFromKey:color:
- (void)overrideTabs:(OOGUITabSettings)stops from:(NSString*)setting length:(NSUInteger)len; // -> -cxx_overrideTabs:from:length:

// Chunk 4 (oo-3rb.95): background and foreground textures.
- (BOOL)setBackgroundTextureDescriptor:(NSDictionary*)descriptor; // -> -cxx_setBackgroundTextureDescriptor:
- (BOOL)setForegroundTextureDescriptor:(NSDictionary*)descriptor; // -> -cxx_setForegroundTextureDescriptor:
- (BOOL)setBackgroundTextureKey:(NSString*)key; // -> -cxx_setBackgroundTextureKey:
- (BOOL)setForegroundTextureKey:(NSString*)key; // -> -cxx_setForegroundTextureKey:
- (BOOL)preloadGUITexture:(NSDictionary*)descriptor; // -> -cxx_preloadGUITexture:
- (NSDictionary*)textureDescriptorFromJSValue:(JSValue)value inContext:(JSContext*)context callerDescription:(NSString*)callerDescription; // -> -cxx_textureDescriptorFromJSValue:inContext:callerDescription:

@end

// Chunk 3 (oo-3rb.94): the gui-settings.plist keys as they were declared in GuiDisplayGen.h
// (-> cxx_kGui* there).
static NSString* const kGuiDefaultTextColor = @"default_text_color";
static NSString* const kGuiScreenTitleColor = @"screen_title_color";
static NSString* const kGuiScreenDividerColor = @"screen_divider_color";
static NSString* const kGuiSelectedRowBackgroundColor = @"selected_row_background_color";
static NSString* const kGuiSelectedRowColor = @"selected_row_color";
static NSString* const kGuiTextInputCursorColor = @"text_input_cursor_color";
// F3
static NSString* const kGuiEquipmentCashColor = @"equipment_cash_color";
static NSString* const kGuiEquipmentUnavailableColor = @"equipment_unavailable_color";
static NSString* const kGuiEquipmentScrollColor = @"equipment_scroll_color";
static NSString* const kGuiEquipmentOptionColor = @"equipment_option_color";
static NSString* const kGuiEquipmentRepairColor = @"equipment_repair_color";
static NSString* const kGuiEquipmentDescriptionColor = @"equipment_description_color";
static NSString* const kGuiEquipmentLaserColor = @"equipment_laser_color";
static NSString* const kGuiEquipmentLaserFittedColor = @"equipment_laser_fitted_color";
static NSString* const kGuiEquipmentTabs = @"equipment_tabs";
// F3 F3
static NSString* const kGuiShipyardHeadingColor = @"shipyard_heading_color";
static NSString* const kGuiShipyardScrollColor = @"shipyard_scroll_color";
static NSString* const kGuiShipyardEntryColor = @"shipyard_entry_color";
static NSString* const kGuiShipyardNoshipColor = @"shipyard_noship_color";
static NSString* const kGuiShipyardTradeinColor = @"shipyard_tradein_color";
static NSString* const kGuiShipyardDescriptionColor = @"shipyard_description_color";
static NSString* const kGuiShipyardTabs = @"shipyard_tabs";
// F4
static NSString* const kGuiInterfaceHeadingColor = @"interface_heading_color";
static NSString* const kGuiInterfaceScrollColor = @"interface_scroll_color";
static NSString* const kGuiInterfaceEntryColor = @"interface_entry_color";
static NSString* const kGuiInterfaceDescriptionColor = @"interface_description_color";
static NSString* const kGuiInterfaceNoneColor = @"interface_none_color";
static NSString* const kGuiInterfaceTabs = @"interface_tabs";
// F5
static NSString* const kGuiStatusShipnameColor = @"status_shipname_color";
static NSString* const kGuiStatusDataColor = @"status_data_color";
static NSString* const kGuiStatusEquipmentHeadingColor = @"status_equipment_heading_color";
static NSString* const kGuiStatusEquipmentScrollColor = @"status_equipment_scroll_color";
static NSString* const kGuiStatusEquipmentOkColor = @"status_equipment_ok_color";
static NSString* const kGuiStatusEquipmentDamagedColor = @"status_equipment_damaged_color";
static NSString* const kGuiStatusTabs = @"status_tabs";
static NSString* const kGuiStatusPrioritiseDamaged = @"status_prioritise_damaged";
// F5 F5
static NSString* const kGuiManifestSubheadColor = @"manifest_subhead_color";
static NSString* const kGuiManifestEntryColor = @"manifest_entry_color";
static NSString* const kGuiManifestScrollColor = @"manifest_scroll_color";
static NSString* const kGuiManifestNoScrollColor = @"manifest_no_scroll_color";
static NSString* const kGuiManifestTabs = @"manifest_tabs";
// F6
static NSString* const kGuiChartLabelScale = @"chart_label_scale";
static NSString* const kGuiChartCircleScale = @"chart_circle_scale";
static NSString* const kGuiChartLabelColor = @"chart_label_color";
static NSString* const kGuiChartLabelReachableColor = @"chart_labelreachable_color";
static NSString* const kGuiChartRangeColor = @"chart_range_color";
static NSString* const kGuiChartCrosshairColor = @"chart_crosshair_color";
static NSString* const kGuiChartCursorColor = @"chart_cursor_color";
static NSString* const kGuiChartInfoMarkerColor = @"chart_info_marker_color";
static NSString* const kGuiChartMatchBoxColor = @"chart_match_box_color";
static NSString* const kGuiChartMatchLabelColor = @"chart_match_label_color";
static NSString* const kGuiChartConnectionColor = @"chart_connection_color";
static NSString* const kGuiChartCurrentJumpStartColor = @"chart_currentjumpstart_color";
static NSString* const kGuiChartCurrentJumpEndColor = @"chart_currentjumpend_color";
static NSString* const kGuiChartRouteShortColor = @"chart_route_short_color";
static NSString* const kGuiChartRouteQuickColor = @"chart_route_quick_color";
static NSString* const kGuiChartTraveltimeTabs = @"chart_traveltime_tabs";

static NSString* const kGuiChartEconomyUColor = @"chart_economy_%zu_color";
static NSString* const kGuiChartGovernmentUColor = @"chart_government_%zu_color";
static NSString* const kGuiChartTechColor = @"chart_tech_color";
// F7
static NSString* const kGuiSystemdataFactsColor = @"systemdata_facts_color";
static NSString* const kGuiSystemdataDescriptionColor = @"systemdata_description_color";
static NSString* const kGuiSystemdataTabs = @"systemdata_tabs";
// F8
static NSString* const kGuiMarketHeadingColor = @"market_heading_color";
static NSString* const kGuiMarketCommodityColor = @"market_commodity_color";
static NSString* const kGuiMarketScrollColor = @"market_scroll_color";
static NSString* const kGuiMarketFilteredAllColor = @"market_filtered_all_color";
static NSString* const kGuiMarketFilterInfoColor = @"market_filter_info_color";
static NSString* const kGuiMarketCashColor = @"market_cash_color";
// F8 F8 extras
static NSString* const kGuiMarketContractedColor = @"market_contracted_color";
static NSString* const kGuiMarketDescriptionColor = @"market_description_color";
static NSString* const kGuiMarketTabs = @"market_tabs";
// Docking report
static NSString* const kGuiDockingReportColor = @"docking_report_color";
static NSString* const kGuiDockingSummaryColor = @"docking_summary_color";
static NSString* const kGuiDockingContinueColor = @"docking_continue_color";

#endif // GUIDISPLAYGEN_FOUNDATIONBRIDGE_H
