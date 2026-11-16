/*

GuiDisplayGen+FoundationBridge.mm

TRANSITIONAL: see GuiDisplayGen+FoundationBridge.h. Each method forwards to its cxx_ counterpart
and converts the result exactly as the old method produced it (nil for nil).

*/

#import "GuiDisplayGen.h" // declares the bridge category at its end
#import "OOFoundationBridge.h"

@implementation GuiDisplayGen (OOFoundationBridge)

// Chunk 1 (oo-3rb.92).

- (id)initWithPixelSize:(NSSize)gui_size
                columns:(int)gui_cols
                   rows:(int)gui_rows
              rowHeight:(int)gui_row_height
               rowStart:(int)gui_row_start
                  title:(NSString*)gui_title
{
    return [self cxx_initWithPixelSize:gui_size columns:gui_cols rows:gui_rows rowHeight:gui_row_height rowStart:gui_row_start title:oo::OptionalString(gui_title)];
}

- (void)resizeWithPixelSize:(NSSize)gui_size
                    columns:(int)gui_cols
                       rows:(int)gui_rows
                  rowHeight:(int)gui_row_height
                   rowStart:(int)gui_row_start
                      title:(NSString*)gui_title
{
    [self cxx_resizeWithPixelSize:gui_size columns:gui_cols rows:gui_rows rowHeight:gui_row_height rowStart:gui_row_start title:oo::OptionalString(gui_title)];
}

- (void)resizeTo:(NSSize)gui_size
    characterHeight:(int)csize
              title:(NSString*)gui_title
{
    [self cxx_resizeTo:gui_size characterHeight:csize title:oo::OptionalString(gui_title)];
}

- (NSString*)keyForRow:(OOGUIRow)row
{
    return oo::NSStringOrNil([self cxx_keyForRow:row]);
}

- (OOGUIRow)rowForKey:(NSString*)key
{
    return [self cxx_rowForKey:oo::OptionalString(key)];
}

- (NSString*)selectedRowText
{
    return oo::NSStringOrNil([self cxx_selectedRowText]);
}

- (NSString*)selectedRowKey
{
    return oo::NSStringOrNil([self cxx_selectedRowKey]);
}

- (void)setKey:(NSString*)str forRow:(OOGUIRow)row
{
    [self cxx_setKey:oo::StdString(str) forRow:row];
}

- (void)setText:(NSString*)str forRow:(OOGUIRow)row
{
    [self cxx_setText:oo::StdString(str) forRow:row];
}

- (void)setText:(NSString*)str forRow:(OOGUIRow)row align:(OOGUIAlignment)alignment
{
    [self cxx_setText:oo::OptionalString(str) forRow:row align:alignment];
}

- (void)setArray:(NSArray*)arr forRow:(OOGUIRow)row
{
    [self cxx_setArray:oo::StringsFrom(arr) forRow:row];
}

// Chunk 2 (oo-3rb.93).

- (NSString*)reflowTextForMFD:(NSString*)input
{
    return oo::NSStringOrNil([self cxx_reflowTextForMFD:oo::OptionalString(input)]);
}

- (OOGUIRow)addLongText:(NSString*)str
          startingAtRow:(OOGUIRow)row
                  align:(OOGUIAlignment)alignment
{
    return [self cxx_addLongText:oo::OptionalString(str) startingAtRow:row align:alignment];
}

- (void)printLongText:(NSString*)str
                align:(OOGUIAlignment)alignment
                color:(OOColor*)text_color
             fadeTime:(float)text_fade
                  key:(NSString*)text_key
           addToArray:(NSMutableArray*)text_array
{
    std::vector<std::string> lines;
    [self cxx_printLongText:oo::OptionalString(str) align:alignment color:text_color fadeTime:text_fade key:oo::OptionalString(text_key) addToArray:(text_array != nil) ? &lines : nullptr];
    for (const std::string& line : lines)
        [text_array addObject:oo::NSStringFrom(line)];
}

- (void)printLineNoScroll:(NSString*)str
                    align:(OOGUIAlignment)alignment
                    color:(OOColor*)text_color
                 fadeTime:(float)text_fade
                      key:(NSString*)text_key
               addToArray:(NSMutableArray*)text_array
{
    std::vector<std::string> lines;
    [self cxx_printLineNoScroll:oo::OptionalString(str) align:alignment color:text_color fadeTime:text_fade key:oo::OptionalString(text_key) addToArray:(text_array != nil) ? &lines : nullptr];
    for (const std::string& line : lines)
        [text_array addObject:oo::NSStringFrom(line)];
}

- (void)insertItemsFromArray:(NSArray*)items
                    withKeys:(NSArray*)item_keys
                     intoRow:(OOGUIRow)row
                       color:(OOColor*)text_color
{
    [self cxx_insertItemsFromArray:oo::PListFrom(items) withKeys:oo::PListFrom(item_keys) intoRow:row color:text_color];
}

- (NSArray*)getLastLines
{
    return oo::ObjectFromPList([self cxx_getLastLines]);
}

// Chunk 3 (oo-3rb.94).

- (NSDictionary*)userSettings
{
    return oo::ObjectFromPList([self cxx_userSettings]); // the same values and objects, a new dictionary
}

- (OOColor*)colorFromSetting:(NSString*)setting defaultValue:(OOColor*)def
{
    return [self cxx_colorFromSetting:oo::OptionalString(setting) defaultValue:def];
}

- (void)setGLColorFromSetting:(NSString*)setting defaultValue:(OOColor*)def alpha:(GLfloat)alpha
{
    [self cxx_setGLColorFromSetting:oo::OptionalString(setting) defaultValue:def alpha:alpha];
}

- (void)setGuiColorSettingFromKey:(NSString*)key color:(OOColor*)col
{
    [self cxx_setGuiColorSettingFromKey:oo::StdString(key) color:col];
}

- (void)overrideTabs:(OOGUITabSettings)stops from:(NSString*)setting length:(NSUInteger)len
{
    [self cxx_overrideTabs:stops from:oo::StdString(setting) length:len];
}

// Chunk 4 (oo-3rb.95).

- (BOOL)setBackgroundTextureDescriptor:(NSDictionary*)descriptor
{
    return [self cxx_setBackgroundTextureDescriptor:oo::PListFrom(descriptor)];
}

- (BOOL)setForegroundTextureDescriptor:(NSDictionary*)descriptor
{
    return [self cxx_setForegroundTextureDescriptor:oo::PListFrom(descriptor)];
}

- (BOOL)setBackgroundTextureKey:(NSString*)key
{
    return [self cxx_setBackgroundTextureKey:oo::OptionalString(key)];
}

- (BOOL)setForegroundTextureKey:(NSString*)key
{
    return [self cxx_setForegroundTextureKey:oo::OptionalString(key)];
}

- (BOOL)preloadGUITexture:(NSDictionary*)descriptor
{
    return [self cxx_preloadGUITexture:oo::PListFrom(descriptor)];
}

- (NSDictionary*)textureDescriptorFromJSValue:(JSValue)value inContext:(JSContext*)context callerDescription:(NSString*)callerDescription
{
    return oo::ObjectFromPList([self cxx_textureDescriptorFromJSValue:value inContext:context callerDescription:oo::OptionalString(callerDescription)]);
}

@end
