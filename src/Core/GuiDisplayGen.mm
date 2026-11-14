/*

GuiDisplayGen.m

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

#include <vector>
#import "GameController.h"
#import "HeadUpDisplay.h"
#import "OOFoundationBridge.h"
#import "OOJavaScriptEngine.h"
#import "OOPListView.h"
#import "OOSound.h"
#import "OOStringExpander.h"
#import "OOStringParsing.h"
#import "OOSystemDescriptionManager.h"
#import "OOTexture.h"
#import "OOTextureSprite.h"
#import "PlayerEntity.h"
#import "PlayerEntityControls.h"
#import "PlayerEntityStickProfile.h"
#import "ResourceManager.h"
#import "Universe.h"
#include "oofnd/objc/OOAssert.h"
#include "oofnd/objc/OOException.h"

#include "oofnd/Log.hpp"
#include "oofnd/String.hpp"
#include <map>

OOINLINE BOOL RowInRange(OOGUIRow row, NSRange range)
{
    return ((int)range.location <= row && row < (int)(range.location + range.length));
}

namespace {

// words[from...] joined by single spaces (as the old array join with @" " did).
std::string WordsJoinedBySpace(const std::vector<std::string>& words, std::size_t from)
{
    std::string result;
    for (std::size_t i = from; i < words.size(); i++) {
        if (i != from)
            result += " ";
        result += words[i];
    }
    return result;
}

// -setTitle:'s rule: an empty title is no title.
std::optional<std::string> TitleFrom(const std::optional<std::string>& title)
{
    if (title.has_value() && title->empty())
        return std::nullopt;
    return title;
}

// A row key that makes a row unselectable (GUI_KEY_SKIP).
bool IsSkipKey(const std::string& key)
{
    return key == "SKIP-ROW";
}

// The characters -drawGLDisplay does not highlight at either end of a column (' ' and the narrow
// space '\037'), trimmed as -stringByTrimmingCharactersInSet: did: both are ASCII, so bytes.
std::string TrimmedForHighlight(const std::string& text)
{
    const char* const kTrimmed = " \037";
    const std::size_t first = text.find_first_not_of(kTrimmed);
    if (first == std::string::npos)
        return std::string();
    const std::size_t last = text.find_last_not_of(kTrimmed);
    return text.substr(first, last - first + 1);
}

} // namespace

@interface GuiDisplayGen (Internal)

- (void)drawGLDisplay:(GLfloat)x y:(GLfloat)y z:(GLfloat)z alpha:(GLfloat)alpha;

- (void)drawCrossHairsWithSize:(GLfloat)size x:(GLfloat)x y:(GLfloat)y z:(GLfloat)z;
- (void)drawStarChart:(GLfloat)x y:(GLfloat)y z:(GLfloat)z alpha:(GLfloat)alpha compact:(BOOL)compact;
- (void)drawSystemMarkers:(const oo::PList&)marker atX:(GLfloat)x andY:(GLfloat)y andZ:(GLfloat)z withAlpha:(GLfloat)alpha andScale:(GLfloat)scale;
- (void)drawSystemMarker:(const oo::PList&)marker atX:(GLfloat)x andY:(GLfloat)y andZ:(GLfloat)z withAlpha:(GLfloat)alpha andScale:(GLfloat)scale;

- (void)cxx_drawEquipmentList:(const oo::PList&)eqptList z:(GLfloat)z;
- (void)drawAdvancedNavArrayAtX:(float)x y:(float)y z:(float)z alpha:(float)alpha usingRoute:(const oo::PList&)route optimizedBy:(OORouteType)optimizeBy zoom:(OOScalar)zoom;

@end

@implementation GuiDisplayGen

static BOOL _refreshStarChart = NO;

- (id)init
{
    if ((self = [super init])) {
        size_in_pixels = NSMakeSize(MAIN_GUI_PIXEL_WIDTH, MAIN_GUI_PIXEL_HEIGHT);
        n_columns = GUI_DEFAULT_COLUMNS;
        n_rows = GUI_DEFAULT_ROWS;
        pixel_row_center = size_in_pixels.width / 2;
        pixel_row_height = MAIN_GUI_ROW_HEIGHT;
        pixel_row_start = MAIN_GUI_PIXEL_ROW_START; // first position down the page...
        max_alpha = 1.0;

        pixel_text_size = NSMakeSize(0.9f * pixel_row_height, pixel_row_height); // main gui has 18x20 characters

        pixel_title_size = NSMakeSize(pixel_row_height * 1.75f, pixel_row_height * 1.5f);

        int stops[6] = { 0, 192, 256, 320, 384, 448 };
        unsigned i;

        rowRange = NSMakeRange(0, n_rows);

        rowText.reserve(n_rows);
        rowKey.reserve(n_rows);
        rowColor.reserve(n_rows);

        for (i = 0; i < n_rows; i++) {
            rowText.push_back(oo::PList("."));
            rowKey.push_back(oo::str::format("%d", (int)i));
            rowColor.push_back(oo::ObjCRef<OOColor*>([OOColor yellowColor]));
            rowPosition[i].x = 0.0f;
            rowPosition[i].y = size_in_pixels.height - (pixel_row_start + i * pixel_row_height);
            rowAlignment[i] = GUI_ALIGN_LEFT;
        }

        for (i = 0; i < n_columns; i++) {
            tabStops[i] = stops[i];
        }

        title = std::string(); // an empty title, not none (-setTitle: would have made it none)
        textColor = [[OOColor yellowColor] retain];

        drawPosition = make_vector(0.0f, 0.0f, 640.0f);

        backgroundSpecial = GUI_BACKGROUND_SPECIAL_NONE;

        guiUserSettings = [ResourceManager cxx_dictionaryFromFilesNamed:"gui-settings.plist" inFolder:"Config" andMerge:YES];
    }
    return self;
}

- (id)cxx_initWithPixelSize:(NSSize)gui_size
                    columns:(int)gui_cols
                       rows:(int)gui_rows
                  rowHeight:(int)gui_row_height
                   rowStart:(int)gui_row_start
                      title:(const std::optional<std::string>&)gui_title
{
    self = [super init];

    size_in_pixels = gui_size;
    n_columns = gui_cols;
    n_rows = gui_rows;
    pixel_row_center = size_in_pixels.width / 2;
    pixel_row_height = gui_row_height;
    pixel_row_start = gui_row_start; // first position down the page...
    max_alpha = 1.0;

    pixel_text_size = NSMakeSize(pixel_row_height, pixel_row_height);

    pixel_title_size = NSMakeSize(pixel_row_height * 1.75f, pixel_row_height * 1.5f);

    unsigned i;

    rowRange = NSMakeRange(0, n_rows);

    rowText.reserve(n_rows);
    rowKey.reserve(n_rows);
    rowColor.reserve(n_rows);

    for (i = 0; i < n_rows; i++) {
        rowText.push_back(oo::PList(""));
        rowKey.push_back(std::string());
        rowColor.push_back(oo::ObjCRef<OOColor*>([OOColor greenColor]));
        rowPosition[i].x = 0.0f;
        rowPosition[i].y = size_in_pixels.height - (pixel_row_start + i * pixel_row_height);
        rowAlignment[i] = GUI_ALIGN_LEFT;
    }

    title = gui_title; // as given (not through -setTitle:)
    textColor = [[OOColor yellowColor] retain];

    return self;
}

- (void)dealloc
{
    [backgroundSprite release];
    [foregroundSprite release];
    [backgroundColor release];
    [textColor release];

    [super dealloc];
}

- (void)cxx_resizeWithPixelSize:(NSSize)gui_size
                        columns:(int)gui_cols
                           rows:(int)gui_rows
                      rowHeight:(int)gui_row_height
                       rowStart:(int)gui_row_start
                          title:(const std::optional<std::string>&)gui_title
{
    [self clear];
    //
    size_in_pixels = gui_size;
    n_columns = gui_cols;
    n_rows = gui_rows;
    pixel_row_center = size_in_pixels.width / 2;
    pixel_row_height = gui_row_height;
    pixel_row_start = gui_row_start; // first position down the page...

    pixel_text_size = NSMakeSize(pixel_row_height, pixel_row_height);
    pixel_title_size = NSMakeSize(pixel_row_height * 1.75f, pixel_row_height * 1.5f);

    rowRange = NSMakeRange(0, n_rows);
    [self clear];
    //
    title = TitleFrom(gui_title);
}

- (void)cxx_resizeTo:(NSSize)gui_size
     characterHeight:(int)csize
               title:(const std::optional<std::string>&)gui_title
{
    [self clear];
    //
    size_in_pixels = gui_size;
    n_columns = gui_size.width / csize;
    n_rows = (int)gui_size.height / csize;

    title = TitleFrom(gui_title);

    pixel_row_center = gui_size.width / 2;
    pixel_row_height = csize;
    currentRow = n_rows - 1; // first position down the page...

    if (title.has_value())
        pixel_row_start = 2.75f * csize + 0.5f * (gui_size.height - n_rows * csize);
    else
        pixel_row_start = csize + 0.5f * (gui_size.height - n_rows * csize);

    rowText.clear();
    rowKey.clear();
    rowColor.clear();

    unsigned i;
    for (i = 0; i < n_rows; i++) {
        rowText.push_back(oo::PList(""));
        rowKey.push_back(std::string());
        rowColor.push_back(oo::ObjCRef<OOColor*>([OOColor greenColor]));
        rowPosition[i].x = 0.0f;
        rowPosition[i].y = size_in_pixels.height - (pixel_row_start + i * pixel_row_height);
        rowAlignment[i] = GUI_ALIGN_LEFT;
    }

    pixel_text_size = NSMakeSize(csize, csize);
    pixel_title_size = NSMakeSize(csize * 1.75f, csize * 1.5f);

    OO_LOG("gui.reset", "gui {} reset to rows:{} columns:{} start:{}", oo::DescriptionOf(self), n_rows, n_columns, pixel_row_start);

    rowRange = NSMakeRange(0, n_rows);
    [self clear];
}

- (NSSize)size
{
    return size_in_pixels;
}

- (unsigned)columns
{
    return n_columns;
}

- (unsigned)rows
{
    return n_rows;
}

- (unsigned)rowHeight
{
    return pixel_row_height;
}

- (int)rowStart
{
    return pixel_row_start;
}

- (id)title // shared selector (Foundation declares -title too; retires with oo-qps)
{
    return oo::NSStringOrNil([self cxx_title]);
}

- (std::optional<std::string>)cxx_title
{
    return title;
}

- (void)setTitle:(id)str // shared selector (Foundation declares -setTitle: too; retires with oo-qps)
{
    [self cxx_setTitle:oo::OptionalString(str)];
}

- (void)cxx_setTitle:(const std::optional<std::string>&)str
{
    title = TitleFrom(str);
}

- (void)setDrawPosition:(Vector)vector
{
    drawPosition = vector;
}

- (Vector)drawPosition
{
    return drawPosition;
}

- (oo::PList)cxx_userSettings
{
    return guiUserSettings;
}

- (void)fadeOutFromTime:(OOTimeAbsolute)now_time overDuration:(OOTimeDelta)duration
{
    if (fade_alpha <= 0.0f) {
        return;
    }
    if (duration == 0.0)
        fade_sign = -1000.0f;
    else
        fade_sign = (float)(-fade_alpha / duration);
}

- (void)stopFadeOuts
{
    fade_sign = 0.0f;
}

- (GLfloat)alpha
{
    return fade_alpha;
}

- (void)setAlpha:(GLfloat)an_alpha
{
    fade_alpha = an_alpha * max_alpha;
}

- (void)setMaxAlpha:(GLfloat)an_alpha
{
    max_alpha = an_alpha;
}

- (void)setBackgroundColor:(OOColor*)color
{
    [backgroundColor release];
    backgroundColor = [color retain];
}

- (OOColor*)textColor
{
    return textColor;
}

// default text colour for rows
- (void)setTextColor:(OOColor*)color
{
    [textColor release];
    if (color == nil)
        color = [[OOColor yellowColor] retain];
    textColor = [color retain];
}

- (OOColor*)textCommsColor
{
    return textCommsColor;
}

- (void)setTextCommsColor:(OOColor*)color
{
    [textCommsColor release];
    if (color == nil)
        color = [[OOColor yellowColor] retain];
    textCommsColor = [color retain];
}

- (OOColor*)cxx_colorFromSetting:(const std::optional<std::string>&)setting defaultValue:(OOColor*)def
{

    OOColor* col = nil;
    if (setting.has_value()) {
        const oo::PList* description = guiUserSettings.find(*setting);
        col = [OOColor colorWithDescription:(description != nullptr) ? oo::ObjectFromPList(*description) : nil];
    }
    if (col == nil) {
        if (def != nil) {
            col = def;
            // def = nil => use default_text_color
        } else {
            col = textColor;
        }
    }
    return [[col copy] autorelease];
}

- (void)cxx_setGLColorFromSetting:(const std::optional<std::string>&)setting defaultValue:(OOColor*)def alpha:(GLfloat)alpha
{
    GLfloat r, g, b, a;
    OOColor* col = [self cxx_colorFromSetting:setting defaultValue:def];
    [col getRed:&r green:&g blue:&b alpha:&a];

    OOGL(glColor4f(r, g, b, a * alpha));
}

- (void)cxx_setGuiColorSettingFromKey:(const std::string&)key color:(OOColor*)col
{
    // With no settings (nil), the mutable copy was nil too and nothing changed.
    oo::PList::Dict* settings = guiUserSettings.getIf<oo::PList::Dict>();
    if (settings == nullptr)
        return;
    if (col == nil) {
        settings->erase(key);
    } else {
        (*settings)[key] = oo::PListObject(col);
    }
}

- (void)setCharacterSize:(NSSize)character_size
{
    pixel_text_size = character_size;
}

- (void)setShowAdvancedNavArray:(BOOL)inFlag
{
    showAdvancedNavArray = inFlag;
}

- (void)setColor:(OOColor*)color forRow:(OOGUIRow)row
{
    if (RowInRange(row, rowRange))
        rowColor[row] = oo::ObjCRef<OOColor*>(color);
}

- (id)objectForRow:(OOGUIRow)row
{
    if (RowInRange(row, rowRange))
        return oo::ObjectFromPList(rowText[row]); // a string, or an array of column strings
    else
        return NULL;
}

- (OOGUIRow)cxx_rowForKey:(const std::optional<std::string>&)key
{
    if (!key.has_value())
        return -1; // a nil key matched nothing
    for (unsigned i = 0; i < rowKey.size(); i++) {
        if (*key == rowKey[i]) {
            return (OOGUIRow)i;
        }
    }
    return -1;
}

- (std::optional<std::string>)cxx_keyForRow:(OOGUIRow)row
{
    if (RowInRange(row, rowRange))
        return rowKey[row];
    else
        return std::nullopt;
}

- (OOGUIRow)selectedRow
{
    if (RowInRange(selectedRow, selectableRange))
        return selectedRow;
    else
        return -1;
}

- (BOOL)setSelectedRow:(OOGUIRow)row
{
    if ((row == selectedRow) && RowInRange(row, selectableRange)) {
        return YES;
    }
    if (RowInRange(row, selectableRange)) {
        if (!IsSkipKey(rowKey[row])) {
            selectedRow = row;
            [self reportSelectedRow:row];
            return YES;
        }
    }
    return NO;
}

- (BOOL)setNextRow:(int)direction
{
    OOGUIRow row = selectedRow + direction;
    while (RowInRange(row, selectableRange)) {
        if (!IsSkipKey(rowKey[row])) {
            selectedRow = row;
            [self reportSelectedRow:row];
            return YES;
        }
        row += direction;
    }
    return NO;
}

- (BOOL)setFirstSelectableRow
{
    NSUInteger row = selectableRange.location;
    while (RowInRange(row, selectableRange)) {
        if (!IsSkipKey(rowKey[row])) {
            selectedRow = row;
            [self reportSelectedRow:row];
            return YES;
        }
        row++;
    }
    selectedRow = -1;
    return NO;
}

- (BOOL)setLastSelectableRow
{
    NSUInteger row = selectableRange.location + selectableRange.length - 1;
    while (RowInRange(row, selectableRange)) {
        if (!IsSkipKey(rowKey[row])) {
            selectedRow = row;
            [self reportSelectedRow:row];
            return YES;
        }
        row--;
    }
    selectedRow = -1;
    return NO;
}

- (void)reportSelectedRow:(int)row
{
    // key, row, text - stopping at the first missing one, as +arrayWithObjects: stopped at nil.
    std::vector<oo::ObjCRef<id>> arguments;
    const std::optional<std::string> key = [self cxx_keyForRow:row];
    if (key.has_value()) {
        arguments.emplace_back(oo::NSStringFrom(*key));
        arguments.emplace_back(oo::ObjectFromPList(oo::PList(row))); // +numberWithInt: (the same JS number)
        const std::optional<std::string> text = [self cxx_selectedRowText];
        if (text.has_value())
            arguments.emplace_back(oo::NSStringFrom(*text));
    }
    [PLAYER cxx_doScriptEvent:OOJSID("guiSelectedRowChanged") withArguments:arguments];
}

- (void)setNoSelectedRow
{
    selectedRow = -1;
}

- (std::optional<std::string>)cxx_selectedRowText
{
    const oo::PList& text = rowText[selectedRow];
    if (const std::string* string = text.getIf<std::string>())
        return *string;
    if (text.isArray()) {
        const oo::PList* first = text.at(0); // the first column
        if (first != nullptr && first->isString())
            return *first->getIf<std::string>();
    }
    return std::nullopt;
}

- (std::optional<std::string>)cxx_selectedRowKey
{
    // (the old test let selectedRow == count through, and -objectAtIndex: then raised)
    if ((selectedRow < 0) || ((unsigned)selectedRow >= rowKey.size()))
        return std::nullopt;
    else
        return rowKey[selectedRow];
}

- (void)setShowTextCursor:(BOOL)yesno
{
    showTextCursor = yesno;
}

- (void)setCurrentRow:(OOGUIRow)value
{
    if ((value < 0) || ((unsigned)value >= n_rows)) {
        showTextCursor = NO;
        currentRow = -1;
    } else {
        currentRow = value;
    }
}

- (NSRange)selectableRange
{
    return selectableRange;
}

- (void)setSelectableRange:(NSRange)range
{
    selectableRange = range;
}

- (void)setTabStops:(OOGUITabSettings)stops
{
    if (stops != NULL)
        memmove(tabStops, stops, sizeof tabStops);
}

- (void)cxx_overrideTabs:(OOGUITabSettings)stops from:(const std::string&)setting length:(NSUInteger)len
{
    const oo::PList* override = guiUserSettings.get<oo::PList::Array>(setting, nullptr);
    NSUInteger i;
    if (stops != NULL && override != nil) {
        if (len > GUI_MAX_COLUMNS) {
            len = GUI_MAX_COLUMNS;
        }
        for (i = 0; i < len; i++) {
            stops[i] = override->at<NSUInteger>(i, stops[i]);
        }
    }
}

- (void)clear
{
    [self clearAndKeepBackground:NO];
}

- (void)clearAndKeepBackground:(BOOL)keepBackground
{
    unsigned i;
    [self cxx_setTitle:std::nullopt];
    for (i = 0; i < n_rows; i++) {
        [self cxx_setText:"" forRow:i align:GUI_ALIGN_LEFT];
        [self setColor:textColor forRow:i];
        //
        [self cxx_setKey:std::string(GUI_KEY_SKIP) forRow:i];
        //
        rowFadeTime[i] = 0.0f;
    }
    [self setShowTextCursor:NO];
    [self setSelectableRange:NSMakeRange(0, 0)];
    if (!keepBackground)
        [self clearBackground];
}

- (void)cxx_setKey:(const std::string&)str forRow:(OOGUIRow)row
{
    if (RowInRange(row, rowRange))
        rowKey[row] = str;
}

- (void)cxx_setText:(const std::string&)str forRow:(OOGUIRow)row
{
    if (RowInRange(row, rowRange)) {
        rowText[row] = oo::PList(str);
    }
}

- (void)cxx_setText:(const std::optional<std::string>&)str forRow:(OOGUIRow)row align:(OOGUIAlignment)alignment
{
    if (str.has_value() && RowInRange(row, rowRange)) {
        rowText[row] = oo::PList(*str);
        rowAlignment[row] = alignment;
    }
}

- (OOGUIRow)cxx_addLongText:(const std::optional<std::string>&)str
              startingAtRow:(OOGUIRow)row
                      align:(OOGUIAlignment)alignment
{
    // nil: -rangeOfString: answered location 0 and -componentsSeparatedByString: no lines.
    if (!str.has_value())
        return row;

    if (str->find('\n') != std::string::npos) {
        for (const std::string& line : oo::str::split(*str, "\n")) {
            row = [self cxx_addLongText:line startingAtRow:row align:alignment];
        }
        return row;
    }

    NSSize chSize = pixel_text_size;
    NSSize strsize = cxx_OORectFromString(*str, 0.0f, 0.0f, chSize).size;
    if (strsize.width < size_in_pixels.width) {
        [self cxx_setText:str forRow:row align:alignment];
        return row + 1;
    } else {
        const std::vector<std::string> words = oo::str::tokens(*str);
        std::size_t next = 0; // words moved to string1
        std::string string1;
        strsize.width = 0.0f;
        while ((strsize.width < size_in_pixels.width) && (next < words.size())) {
            string1 += words[next];
            string1 += " ";
            next++;
            strsize = cxx_OORectFromString(string1, 0.0f, 0.0f, chSize).size;
            if (next < words.size())
                strsize.width += cxx_OORectFromString(words[next], 0.0f, 0.0f, chSize).size.width;
        }
        const std::string string2 = WordsJoinedBySpace(words, next);
        [self cxx_setText:string1 forRow:row align:alignment];
        return [self cxx_addLongText:string2 startingAtRow:row + 1 align:alignment];
    }
}

- (std::optional<std::string>)cxx_reflowTextForMFD:(const std::optional<std::string>&)input
{
    std::string output;
    NSSize chSize = pixel_text_size;
    NSUInteger limit = chSize.width * 15;
    // nil split into no lines: the result was an empty string, not nil.
    if (!input.has_value())
        return output;
    for (const std::string& line : oo::str::split(*input, "\n")) {
        const std::vector<std::string> words = oo::str::tokens(line);
        std::size_t first = 0; // words consumed
        std::string accum;
        if (!words.empty()) {
            while (words.size() - first > 1) {
                accum += words[first];
                accum += " ";
                if (cxx_OORectFromString(accum, 0.0f, 0.0f, chSize).size.width + cxx_OORectFromString(words[first + 1], 0.0f, 0.0f, chSize).size.width > limit) {
                    // can't fit next word on this line
                    // (-whitespaceCharacterSet trimming: accum holds tokens and spaces, no newlines)
                    output += oo::str::trimWhitespaceAndNewlines(accum);
                    output += "\n";
                    accum.clear();
                }
                first++;
            }
            output += accum;
            output += words[first];
        }
        output += "\n";
    }

    return output;
}

- (void)leaveLastLine
{
    unsigned i;
    for (i = 0; i < n_rows - 1; i++) {
        rowText[i] = oo::PList("");
        rowColor[i] = oo::ObjCRef<OOColor*>(textColor);
        rowKey[i] = std::string();
        rowAlignment[i] = GUI_ALIGN_LEFT;
        rowFadeTime[i] = 0.0f;
    }
    rowFadeTime[i] = 0.4f; // fade the last line...
}

- (oo::PList)cxx_getLastLines // text, colour, fade time - text, colour, fade time
{
    if (n_rows < 1)
        return oo::PList();

    // we have at least 1 row!

    unsigned i = n_rows - 1;
    OORGBAComponents col = [rowColor[i].get() rgbaComponents];
    oo::PList::Array result;

    /*	Row r's text, colour and fade time, as -arrayWithObjects: took them: the text is what
            -oo_stringAtIndex: read (a string, or a number's -stringValue); anything else was nil, which
            ended the list there. Returns whether it was appended.
    */
    auto appendRow = [&](unsigned r, const OORGBAComponents& c) -> bool {
        const oo::PList& text = rowText[r];
        if (!text.isString() && !text.isNumber())
            return false;
        result.emplace_back(oo::PList(oo::PList::Array { text }).at<std::string>(0));
        result.emplace_back(oo::str::format("%.3g %.3g %.3g %.3g", c.r, c.g, c.b, c.a));
        result.push_back(oo::PList::singleReal(rowFadeTime[r])); // +numberWithFloat:
        return true;
    };

    if (i > 0) {
        // we have at least 2 rows!
        OORGBAComponents col0 = [rowColor[i - 1].get() rgbaComponents];
        if (appendRow(i - 1, col0))
            appendRow(i, col);
    } else {
        appendRow(i, col);
    }
    return oo::PList(std::move(result));
}

- (void)cxx_printLongText:(const std::optional<std::string>&)str
                    align:(OOGUIAlignment)alignment
                    color:(OOColor*)text_color
                 fadeTime:(float)text_fade
                      key:(const std::optional<std::string>&)text_key
               addToArray:(std::vector<std::string>*)text_array
{
    // print a multi-line message
    //
    // nil: -rangeOfString: answered location 0 and -componentsSeparatedByString: no lines.
    if (!str.has_value())
        return;
    if (str->find('\n') != std::string::npos) {
        for (const std::string& line : oo::str::split(*str, "\n"))
            [self cxx_printLongText:line align:alignment color:text_color fadeTime:text_fade key:text_key addToArray:text_array];
        return;
    }

    OOGUIRow row = currentRow;
    if (row == (OOGUIRow)n_rows - 1)
        [self scrollUp:1];
    NSSize chSize = pixel_text_size;
    NSSize strsize = cxx_OORectFromString(*str, 0.0f, 0.0f, chSize).size;
    if (strsize.width < size_in_pixels.width) {
        [self cxx_setText:str forRow:row align:alignment];
        if (text_color)
            [self setColor:text_color forRow:row];
        if (text_key.has_value())
            [self cxx_setKey:*text_key forRow:row];
        rowFadeTime[row] = text_fade;
        if (currentRow < (OOGUIRow)n_rows - 1)
            currentRow++;
        if (text_array)
            text_array->push_back(*str);
    } else {
        const std::vector<std::string> words = oo::str::tokens(*str);
        std::size_t next = 0; // words moved to string1
        std::string string1;
        strsize.width = 0.0f;
        while ((strsize.width < size_in_pixels.width) && (next < words.size())) {
            string1 += words[next];
            string1 += " ";
            next++;
            strsize = cxx_OORectFromString(string1, 0.0f, 0.0f, chSize).size;
            if (next < words.size())
                strsize.width += cxx_OORectFromString(words[next], 0.0f, 0.0f, chSize).size.width;
        }

        [self cxx_setText:string1 forRow:row align:alignment];

        const std::string string2 = WordsJoinedBySpace(words, next);
        if (text_color)
            [self setColor:text_color forRow:row];
        if (text_key.has_value())
            [self cxx_setKey:*text_key forRow:row];
        if (text_array)
            text_array->push_back(string1);
        rowFadeTime[row] = text_fade;
        [self cxx_printLongText:string2 align:alignment color:text_color fadeTime:text_fade key:text_key addToArray:text_array];
    }
}

- (void)cxx_printLineNoScroll:(const std::optional<std::string>&)str
                        align:(OOGUIAlignment)alignment
                        color:(OOColor*)text_color
                     fadeTime:(float)text_fade
                          key:(const std::optional<std::string>&)text_key
                   addToArray:(std::vector<std::string>*)text_array
{
    [self cxx_setText:str forRow:currentRow align:alignment];
    if (text_color)
        [self setColor:text_color forRow:currentRow];
    if (text_key.has_value())
        [self cxx_setKey:*text_key forRow:currentRow];
    if (text_array && str.has_value()) // adding nil raised
        text_array->push_back(*str);
    rowFadeTime[currentRow] = text_fade;
}

- (void)cxx_setArray:(const std::vector<std::string>&)arr forRow:(OOGUIRow)row
{
    if (RowInRange(row, rowRange)) {
        oo::PList::Array columns;
        for (const std::string& column : arr)
            columns.push_back(oo::PList(column));
        rowText[row] = oo::PList(std::move(columns));
    }
}

- (void)cxx_insertItemsFromArray:(const oo::PList&)items
                        withKeys:(const oo::PList&)item_keys
                         intoRow:(OOGUIRow)row
                           color:(OOColor*)text_color
{
    if (items.isNull())
        return;
    if (items.count() == 0)
        return;

    NSUInteger n_items = items.count();
    if ((!item_keys.isNull()) && (item_keys.count() != n_items)) {
        // throw exception
        [OOException raise:"ArrayLengthMismatchException"
                    format:"The array sent as 'item_keys' to insertItemsFromArray::: must contain the same number of objects as the array 'items'"];
    }

    unsigned i;
    for (i = n_rows; i >= row + n_items; i--) {
        [self cxx_setKey:[self cxx_keyForRow:i - n_items].value_or("") forRow:i];
        // the row's text or columns moved down (-objectForRow: gave nil out of range)
        const oo::PList old_row_info = RowInRange(i - n_items, rowRange) ? rowText[i - n_items] : oo::PList();
        if (old_row_info.isArray() && RowInRange(i, rowRange))
            rowText[i] = old_row_info;
        if (const std::string* text = old_row_info.getIf<std::string>())
            [self cxx_setText:*text forRow:i];
    }
    for (i = 0; i < n_items; i++) {
        const oo::PList& new_row_info = *items.at(i);
        if (text_color)
            [self setColor:text_color forRow:row + i];
        else
            [self setColor:textColor forRow:row + i];
        if (const oo::PList::Array* columns = new_row_info.getIf<oo::PList::Array>()) {
            std::vector<std::string> columnTexts;
            for (const oo::PList& column : *columns) {
                if (const std::string* text = column.getIf<std::string>())
                    columnTexts.push_back(*text);
            }
            [self cxx_setArray:columnTexts forRow:row + i];
        }
        if (const std::string* text = new_row_info.getIf<std::string>())
            [self cxx_setText:*text forRow:row + i];
        if (!item_keys.isNull())
            [self cxx_setKey:item_keys.at<std::string>(i) forRow:row + i];
        else
            [self cxx_setKey:"" forRow:row + i];
    }
}

- (void)scrollUp:(int)how_much
{
    unsigned i;
    for (i = 0; i + how_much < n_rows; i++) {
        rowText[i] = rowText[i + how_much];
        rowColor[i] = rowColor[i + how_much];
        rowKey[i] = rowKey[i + how_much];
        rowAlignment[i] = rowAlignment[i + how_much];
        rowFadeTime[i] = rowFadeTime[i + how_much];
    }
    for (; i < n_rows; i++) {
        rowText[i] = oo::PList("");
        rowColor[i] = oo::ObjCRef<OOColor*>(textColor);
        rowKey[i] = std::string();
        rowAlignment[i] = GUI_ALIGN_LEFT;
        rowFadeTime[i] = 0.0f;
    }
}

- (void)clearBackground
{
    [self cxx_setBackgroundTextureDescriptor:oo::PList()];
    [self cxx_setForegroundTextureDescriptor:oo::PList()];
}

namespace {

// The descriptor's "name" as -oo_stringForKey: read it (a string, or a number's -stringValue), or
// nullopt (nil).
std::optional<std::string> DescriptorName(const oo::PList& descriptor)
{
    const oo::PList* name = descriptor.find("name");
    if (name == nullptr || !(name->isString() || name->isNumber()))
        return std::nullopt;
    return descriptor.get<std::string>("name");
}

OOTexture* TextureForGUITexture(const oo::PList& descriptor, uint32_t srgbaOption)
{
    /*
            GUI textures like backgrounds, foregrounds etc. are not processed in any way after loading. However, they are
            subject to tone nmapping and gamma correction at the end of the render pass. So we need to declare them as
            SRGBA textures here so that OpenGL will automatically convert them to linear space upon loading and the
            subsequent tone mapping and gamma correction shader operations will not result in heavy distortion of their
            colors.

            Also, remember that if no shaders are in use (as in lower detail levels), then we don't need to declare anything.
    */
    if (![UNIVERSE useShaders])
        srgbaOption = 0;
    return [OOTexture cxx_textureWithName:DescriptorName(descriptor)
                                 inFolder:"Images"
                                  options:kOOTextureDefaultOptions | kOOTextureNoShrink | srgbaOption
                               anisotropy:kOOTextureDefaultAnisotropy
                                  lodBias:kOOTextureDefaultLODBias];
}

/*
        Load a texture sprite given a descriptor. The caller owns a reference to
        the result.
*/
OOTextureSprite* NewTextureSpriteWithDescriptor(const oo::PList& descriptor, uint32_t srgbaOption)
{
    OOTexture* texture = nil;
    NSSize size;

    texture = TextureForGUITexture(descriptor, srgbaOption);
    if (texture == nil)
        return nil;

    double specifiedWidth = descriptor.get<double>("width", -INFINITY);
    double specifiedHeight = descriptor.get<double>("height", -INFINITY);
    BOOL haveWidth = isfinite(specifiedWidth);
    BOOL haveHeight = isfinite(specifiedHeight);

    if (haveWidth && haveHeight) {
        // Both specified, use directly without calling -originalDimensions (which may block).
        size.width = specifiedWidth;
        size.height = specifiedHeight;
    } else {
        NSSize originalDimensions = [texture originalDimensions];

        if (haveWidth) {
            // Width specified, but not height; preserve aspect ratio.
            CGFloat ratio = originalDimensions.height / originalDimensions.width;
            size.width = specifiedWidth;
            size.height = ratio * size.width;
        } else if (haveHeight) {
            // Height specified, but not width; preserve aspect ratio.
            CGFloat ratio = originalDimensions.width / originalDimensions.height;
            size.height = specifiedHeight;
            size.width = ratio * size.height;
        } else {
            // Neither specified; use backwards-compatible behaviour.
            size = originalDimensions;
        }
    }

    return [[OOTextureSprite alloc] initWithTexture:texture size:size];
}

} // namespace

- (void)setBackgroundTextureSpecial:(OOGUIBackgroundSpecial)spec withBackground:(BOOL)withBackground
{
    if (withBackground) {
        oo::PList bgDescriptor;
        OOGalaxyID galaxy_number = [PLAYER galaxyNumber];

        switch (spec) {
        case GUI_BACKGROUND_SPECIAL_CUSTOM:
        case GUI_BACKGROUND_SPECIAL_CUSTOM_ANA_SHORTEST:
        case GUI_BACKGROUND_SPECIAL_CUSTOM_ANA_QUICKEST:
            bgDescriptor = [UNIVERSE cxx_screenTextureDescriptorForKey:"custom_chart_mission"];
            if (bgDescriptor.isNull()) {
                bgDescriptor = [UNIVERSE cxx_screenTextureDescriptorForKey:"short_range_chart_mission"];
                if (bgDescriptor.isNull()) {
                    bgDescriptor = [UNIVERSE cxx_screenTextureDescriptorForKey:"short_range_chart"];
                }
            }
            break;
        case GUI_BACKGROUND_SPECIAL_SHORT:
        case GUI_BACKGROUND_SPECIAL_SHORT_ANA_SHORTEST:
        case GUI_BACKGROUND_SPECIAL_SHORT_ANA_QUICKEST:
            bgDescriptor = [UNIVERSE cxx_screenTextureDescriptorForKey:"short_range_chart_mission"];
            if (bgDescriptor.isNull()) {
                bgDescriptor = [UNIVERSE cxx_screenTextureDescriptorForKey:"short_range_chart"];
            }
            break;
        case GUI_BACKGROUND_SPECIAL_LONG:
        case GUI_BACKGROUND_SPECIAL_LONG_ANA_SHORTEST:
        case GUI_BACKGROUND_SPECIAL_LONG_ANA_QUICKEST:
            bgDescriptor = [UNIVERSE cxx_screenTextureDescriptorForKey:oo::str::format("long_range_chart%d_mission", galaxy_number + 1)];
            if (bgDescriptor.isNull()) {
                bgDescriptor = [UNIVERSE cxx_screenTextureDescriptorForKey:"long_range_chart_mission"];
                if (bgDescriptor.isNull()) {
                    bgDescriptor = [UNIVERSE cxx_screenTextureDescriptorForKey:oo::str::format("long_range_chart%d", galaxy_number + 1)];
                    if (bgDescriptor.isNull()) {
                        bgDescriptor = [UNIVERSE cxx_screenTextureDescriptorForKey:"long_range_chart"];
                    }
                }
            }
            break;
        case GUI_BACKGROUND_SPECIAL_NONE:
            break;
        }
        if (!bgDescriptor.isNull()) {
            [self cxx_setBackgroundTextureDescriptor:bgDescriptor];
        }
    }
    backgroundSpecial = spec;
    [self refreshStarChart];
}

- (BOOL)cxx_setBackgroundTextureDescriptor:(const oo::PList&)descriptor
{
    [backgroundSprite autorelease];
    backgroundSpecial = GUI_BACKGROUND_SPECIAL_NONE; // reset
    backgroundSprite = NewTextureSpriteWithDescriptor(descriptor, kOOTextureSRGBA);
    return backgroundSprite != nil;
}

- (BOOL)cxx_setForegroundTextureDescriptor:(const oo::PList&)descriptor
{
    [foregroundSprite autorelease];
    // FIXME: for some reason passing kOOTextureSRGBA when in SDR results in double gamma correction
    uint32_t srgbaOption = [[UNIVERSE gameView] hdrOutput] ? kOOTextureSRGBA : 0;
    foregroundSprite = NewTextureSpriteWithDescriptor(descriptor, srgbaOption);
    return foregroundSprite != nil;
}

- (BOOL)cxx_setBackgroundTextureKey:(const std::optional<std::string>&)key
{
    return [self cxx_setBackgroundTextureDescriptor:[UNIVERSE cxx_screenTextureDescriptorForKey:key.value_or("")]];
}

- (BOOL)cxx_setForegroundTextureKey:(const std::optional<std::string>&)key
{
    return [self cxx_setForegroundTextureDescriptor:[UNIVERSE cxx_screenTextureDescriptorForKey:key.value_or("")]];
}

- (BOOL)cxx_preloadGUITexture:(const oo::PList&)descriptor
{
    return TextureForGUITexture(descriptor, kOOTextureSRGBA) != nil;
}

- (oo::PList)cxx_textureDescriptorFromJSValue:(JSValue)value
                                    inContext:(JSContext*)context
                            callerDescription:(const std::optional<std::string>&)callerDescription
{
    OOJS_PROFILE_ENTER

    oo::PList result;

    // Null may be used to indicate no texture.
    if (JS_IsNull(value))
        return oo::PList(oo::PList::Dict { });

    if (JS_IsObject(value)) {
        // String objects are converted to NSStrings; anything else is treated as a dictionary.
        if (JS_GetClassID(value) != gOOJSStringClassID) {
            result = cxx_OOJSDictionaryFromJSObject(context, value);
        }
    }

    if (result.isNull()) {
        const std::optional<std::string> name = cxx_OOStringFromJSValue(context, value);

        if (name.has_value()) {
            result = oo::PList(oo::PList::Dict { { "name", oo::PList(*name) } });
            if (name->empty())
                return result; // Explicit empty string may be used to indicate no texture.
        }
    }

    // Start loading the texture, and return nil if it doesn't exist.
    if (!result.isNull() && ![self cxx_preloadGUITexture:result]) {
        cxx_OOJSReportWarning(context, "%s: texture \"%s\" could not be found.", (callerDescription ? callerDescription->c_str() : "(null)"), DescriptorName(result).value_or("(null)").c_str());
        result = oo::PList();
    }

    return result;

    OOJS_PROFILE_EXIT
}

- (void)setStatusPage:(NSInteger)pageNum
{
    if (pageNum == 0 || (pageNum < 0 && ((NSUInteger)-pageNum) >= statusPage)) {
        statusPage = 1;
    } else {
        statusPage += pageNum;
    }
}

- (NSUInteger)statusPage
{
    return statusPage;
}

- (void)cxx_drawEquipmentList:(const oo::PList&)eqptList z:(GLfloat)z
{
    const oo::PList::Array* eqptArray = eqptList.getIf<oo::PList::Array>();
    if (eqptArray == nullptr || eqptArray->empty())
        return;

    OOGUIRow firstRow = STATUS_EQUIPMENT_FIRST_ROW;
    NSUInteger maxRows = STATUS_EQUIPMENT_MAX_ROWS;
    if ([[PLAYER hud] allowBigGui]) {
        maxRows += STATUS_EQUIPMENT_BIGGUI_EXTRA_ROWS;
    }
    NSUInteger itemsPerColumn = maxRows;

    NSInteger firstY = 40; // firstRow =10 :-> 40  - firstRow=11 -> 24 etc...
    NSUInteger eqptCount = eqptArray->size();
    NSUInteger pageCount = 1;
    NSUInteger i;
    NSInteger start;
    BOOL damaged;

    // Paging calculations. Assuming 10 lines we get - one page:20 items per page (ipp)
    // two pages: 18 ipp - three+ pages:  1st & last 18pp,  middle pages 16ipp

    i = itemsPerColumn * 2 + 2;
    if (eqptCount > i) // don't fit in one page?
    {
        [[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:YES];

        i = itemsPerColumn * 4; // total items in the first and last pages
        itemsPerColumn--; // for all the middle pages.
        if (eqptCount <= i) // two pages
        {
            pageCount++;
            if (statusPage == 1) {
                start = 0;
            } else {
                statusPage = 2;
                start = i / statusPage; // for the for loop
            }
        } else // three or more
        {
            pageCount = ceil((float)(eqptCount - i) / (itemsPerColumn * 2)) + 2;
            statusPage = (NSInteger)OOClampInteger(statusPage, 1, pageCount);
            start = (statusPage == 1) ? 0 : (statusPage - 1) * itemsPerColumn * 2 + 2;
        }
    } else {
        statusPage = pageCount; // one page
        start = 0;
        // if we have mouse interaction active, it means that we had more than one
        // pages earlier, but only one now, as e.g. in the case of a hud that wss
        // subsequently hidden, resulting in the equip list fitting in one page,
        // so we need to deactivate it
        if (OOMouseInteractionModeIsUIScreen([[UNIVERSE gameController] mouseInteractionMode])) {
            // clear the gui-more and gui-back key rows first
            [self cxx_setText:"" forRow:firstRow];
            [self cxx_setKey:"SKIP-ROW" forRow:firstRow];
            [self cxx_setText:"" forRow:firstRow + STATUS_EQUIPMENT_MAX_ROWS];
            [self cxx_setKey:"SKIP-ROW" forRow:firstRow + STATUS_EQUIPMENT_MAX_ROWS];
            [self setSelectableRange:NSMakeRange(0, 0)];

            [[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:NO];
        }
    }

    if (statusPage > 1) {
        [self setColor:[self cxx_colorFromSetting:cxx_kGuiStatusEquipmentScrollColor defaultValue:[OOColor greenColor]] forRow:firstRow];
        [self cxx_setArray:{ OO_DESC("gui-back"), "", " <-- " } forRow:firstRow];
        [self cxx_setKey:"OK" forRow:firstRow];
        firstY -= 16; // start 1 row down!
        if (statusPage == pageCount) {
            [self setSelectableRange:NSMakeRange(firstRow, 1)];
            [self setSelectedRow:firstRow];
        }
    }
    if (statusPage < pageCount) {
        [self setColor:[self cxx_colorFromSetting:cxx_kGuiStatusEquipmentScrollColor defaultValue:[OOColor greenColor]] forRow:firstRow + maxRows];
        [self cxx_setArray:{ OO_DESC("gui-more"), "", " --> " } forRow:firstRow + maxRows];
        [self cxx_setKey:"OK" forRow:firstRow + maxRows];
        if (statusPage == 1) {
            [self setSelectableRange:NSMakeRange(firstRow + maxRows, 1)];
            [self setSelectedRow:firstRow + maxRows];
        }
    }
    if (statusPage > 1 && statusPage < pageCount) {
        [self setSelectableRange:NSMakeRange(firstRow, MIN(firstRow + maxRows, GUI_DEFAULT_ROWS - firstRow))];
        // default selected row to 'More -->' if we are looking at one of the middle pages
        if ([self selectedRow] == -1)
            [self setSelectedRow:firstRow + maxRows];
    }

    if (statusPage == 1 || statusPage == pageCount)
        itemsPerColumn++;
    eqptCount = (NSInteger)OOClampInteger(eqptCount, 1, start + itemsPerColumn * 2);
    for (i = start; i < eqptCount; i++) {
        const oo::PList& info = (*eqptArray)[i];
        std::string name = info.at<std::string>(0);
        if (oo::str::length(name) > 42) {
            name = oo::utf16ToUtf8(oo::utf8ToUtf16(name).substr(0, 40)) + "...";
        }

        damaged = !info.at<bool>(1);
        if (damaged) {
            // Damaged items show up orange.
            [self cxx_setGLColorFromSetting:"status_equipment_damaged_color" defaultValue:[OOColor orangeColor] alpha:1.0];
        } else /// add color selection here
        {
            OOColor* dispCol = nil;
            if (const oo::PList::Array* row = info.getIf<oo::PList::Array>()) {
                if (row->size() > 2)
                    dispCol = (OOColor*)oo::ObjectIn((*row)[2]);
            }
            // Normal items in default colour
            [self cxx_setGLColorFromSetting:"status_equipment_ok_color" defaultValue:dispCol alpha:1.0];
        }

        if (i - start < itemsPerColumn) {
            cxx_OODrawString(name, -220, firstY - 16 * (NSInteger)(i - start), z, NSMakeSize(15, 15));
        } else {
            cxx_OODrawString(name, 50, firstY - 16 * (NSInteger)(i - itemsPerColumn - start), z, NSMakeSize(15, 15));
        }
    }
}

- (void)drawGUIBackground
{
    GLfloat x = drawPosition.x;
    GLfloat y = drawPosition.y;
    GLfloat z = [[UNIVERSE gameView] display_z];

    if (backgroundSprite != nil) {
        [backgroundSprite blitBackgroundCentredToX:x Y:y Z:z alpha:1.0f];
    }
}

- (void)refreshStarChart
{
    _refreshStarChart = YES;
}

- (int)drawGUI:(GLfloat)alpha drawCursor:(BOOL)drawCursor
{
    GLfloat x = drawPosition.x;
    GLfloat y = drawPosition.y;
    GLfloat z = [[UNIVERSE gameView] display_z];

    if (alpha > 0.05f) {
        PlayerEntity* player = PLAYER;

        [self drawGLDisplay:x - 0.5f * size_in_pixels.width y:y - 0.5f * size_in_pixels.height z:z alpha:alpha];

        if (self == [UNIVERSE gui]) {
            if ([player guiScreen] == GUI_SCREEN_SHORT_RANGE_CHART || [player guiScreen] == GUI_SCREEN_LONG_RANGE_CHART || backgroundSpecial == GUI_BACKGROUND_SPECIAL_SHORT || backgroundSpecial == GUI_BACKGROUND_SPECIAL_SHORT_ANA_QUICKEST || backgroundSpecial == GUI_BACKGROUND_SPECIAL_SHORT_ANA_SHORTEST || backgroundSpecial == GUI_BACKGROUND_SPECIAL_CUSTOM || backgroundSpecial == GUI_BACKGROUND_SPECIAL_CUSTOM_ANA_QUICKEST || backgroundSpecial == GUI_BACKGROUND_SPECIAL_CUSTOM_ANA_SHORTEST) {
                [self drawStarChart:x - 0.5f * size_in_pixels.width y:y - 0.5f * size_in_pixels.height z:z alpha:alpha compact:NO];
            }
            if (backgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG || backgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG_ANA_QUICKEST || backgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG_ANA_SHORTEST) {
                [self drawStarChart:x - 0.5f * size_in_pixels.width y:y - 0.5f * size_in_pixels.height z:z alpha:alpha compact:YES];
            }
            if ([player guiScreen] == GUI_SCREEN_STATUS) {
                [self cxx_drawEquipmentList:oo::PList([player cxx_equipmentList]) z:z];
            }
            if ([player guiScreen] == GUI_SCREEN_STICKPROFILE) {
                [player stickProfileGraphAxisProfile:alpha screenAt:make_vector(x, y, z) screenSize:size_in_pixels];
            }
        }

        if (fade_sign) {
            fade_alpha += (float)(fade_sign * [UNIVERSE getTimeDelta]);
            if (fade_alpha < 0.05f) // done fading out
            {
                fade_alpha = 0.0f;
                fade_sign = 0.0f;
            }
            if (fade_alpha >= max_alpha) // done fading in
            {
                fade_alpha = max_alpha;
                fade_sign = 0.0f;
            }
        }
    }

    int cursor_row = 0;

    if (drawCursor) {
        NSPoint vjpos = [[UNIVERSE gameView] virtualJoystickPosition];
        double cursor_x = size_in_pixels.width * vjpos.x;
        if (cursor_x < -size_in_pixels.width * 0.5)
            cursor_x = -size_in_pixels.width * 0.5f;
        if (cursor_x > size_in_pixels.width * 0.5)
            cursor_x = size_in_pixels.width * 0.5f;
        double cursor_y = -size_in_pixels.height * vjpos.y;
        if (cursor_y < -size_in_pixels.height * 0.5)
            cursor_y = -size_in_pixels.height * 0.5f;
        if (cursor_y > size_in_pixels.height * 0.5)
            cursor_y = size_in_pixels.height * 0.5f;

        cursor_row = 1 + (float)floor((0.5f * size_in_pixels.height - pixel_row_start - cursor_y) / pixel_row_height);

        GLfloat h1 = 3.0f;
        GLfloat h3 = 9.0f;
        OOGL(glColor4f(0.6f, 0.6f, 1.0f, 1.0f)); // original value of (0.2f, 0.2f, 1.0f, 0.5f) too dark - Nikos 20130616
        OOGL(GLScaledLineWidth(2.0f));

        cursor_x += x;
        cursor_y += y;
        [[UNIVERSE gameView] setVirtualJoystick:cursor_x / size_in_pixels.width vmy:-cursor_y / size_in_pixels.height];

        OOGLBEGIN(GL_LINES);
        glVertex3f((float)cursor_x - h1, (float)cursor_y, z);
        glVertex3f((float)cursor_x - h3, (float)cursor_y, z);
        glVertex3f((float)cursor_x + h1, (float)cursor_y, z);
        glVertex3f((float)cursor_x + h3, (float)cursor_y, z);
        glVertex3f((float)cursor_x, (float)cursor_y - h1, z);
        glVertex3f((float)cursor_x, (float)cursor_y - h3, z);
        glVertex3f((float)cursor_x, (float)cursor_y + h1, z);
        glVertex3f((float)cursor_x, (float)cursor_y + h3, z);
        OOGLEND();
        OOGL(GLScaledLineWidth(1.0f));
    }

    return cursor_row;
}

- (void)drawGLDisplay:(GLfloat)x y:(GLfloat)y z:(GLfloat)z alpha:(GLfloat)alpha
{
    NSSize strsize;
    unsigned i;
    OOTimeDelta delta_t = [UNIVERSE getTimeDelta];
    NSSize characterSize = pixel_text_size;
    NSSize titleCharacterSize = pixel_title_size;
    float backgroundAlpha = self == [UNIVERSE messageGUI] && ![UNIVERSE permanentMessageLog] ? 0.0f : alpha;
    std::vector<float> row_alpha(n_rows);

    // calculate fade out time and alpha for each row. Do it before
    // applying a potential background because we need the maximum alpha
    // of all rows to be the alpha applied to the background color
    for (i = 0; i < n_rows; i++) {
        row_alpha[i] = alpha;

        if (![UNIVERSE autoMessageLogBg] && [PLAYER guiScreen] == GUI_SCREEN_MAIN)
            backgroundAlpha = alpha;

        if (rowFadeTime[i] > 0.0f && ![UNIVERSE permanentMessageLog]) {
            rowFadeTime[i] -= (float)delta_t;
            if (rowFadeTime[i] <= 0.0f) {
                rowText[i] = oo::PList("");
                rowFadeTime[i] = 0.0f;
                continue;
            }
            if ((rowFadeTime[i] > 0.0f) && (rowFadeTime[i] < 1.0)) {
                row_alpha[i] *= rowFadeTime[i];
                if (backgroundAlpha < row_alpha[i])
                    backgroundAlpha = row_alpha[i];
            } else {
                backgroundAlpha = alpha;
            }
        }
    }

    // do backdrop
    // don't draw it if docked, unless message_gui is permanent
    // don't draw it on the intro screens
    if (backgroundColor) {
        int playerStatus = [PLAYER status];
        if (playerStatus != STATUS_START_GAME && playerStatus != STATUS_DEAD) {
            OOGL(glColor4f([backgroundColor redComponent], [backgroundColor greenComponent], [backgroundColor blueComponent], backgroundAlpha * [backgroundColor alphaComponent]));
            OOGLBEGIN(GL_QUADS);
            glVertex3f(x + 0.0f, y + 0.0f, z);
            glVertex3f(x + size_in_pixels.width, y + 0.0f, z);
            glVertex3f(x + size_in_pixels.width, y + size_in_pixels.height, z);
            glVertex3f(x + 0.0f, y + size_in_pixels.height, z);
            OOGLEND();
        }
    }

    // show the 'foreground', aka overlay!

    if (foregroundSprite != nil) {
        [foregroundSprite blitCentredToX:x + 0.5f * size_in_pixels.width Y:y + 0.5f * size_in_pixels.height Z:z alpha:alpha];
    }

    if (!RowInRange(selectedRow, selectableRange))
        selectedRow = -1; // out of Range;

    ////
    // drawing operations here

    if (title.has_value()) {
        //
        // draw the title
        //
        strsize = cxx_OORectFromString(*title, 0.0f, 0.0f, titleCharacterSize).size;
        [self cxx_setGLColorFromSetting:cxx_kGuiScreenTitleColor defaultValue:[OOColor redColor] alpha:alpha];

        cxx_OODrawString(*title, x + pixel_row_center - strsize.width / 2.0, y + size_in_pixels.height - pixel_title_size.height, z, titleCharacterSize);

        // draw a horizontal divider
        //
        [self cxx_setGLColorFromSetting:cxx_kGuiScreenDividerColor defaultValue:[OOColor colorWithWhite:0.75 alpha:1.0] alpha:alpha];

        OOGLBEGIN(GL_QUADS);
        glVertex3f(x + 0, y + size_in_pixels.height - pixel_title_size.height + 4, z);
        glVertex3f(x + size_in_pixels.width, y + size_in_pixels.height - pixel_title_size.height + 4, z);
        glVertex3f(x + size_in_pixels.width, y + size_in_pixels.height - pixel_title_size.height + 2, z);
        glVertex3f(x + 0, y + size_in_pixels.height - pixel_title_size.height + 2, z);
        OOGLEND();
    }

    // draw each row of text
    //
    OOStartDrawingStrings();
    for (i = 0; i < n_rows; i++) {
        OOColor* row_color = rowColor[i].get();
        glColor4f([row_color redComponent], [row_color greenComponent], [row_color blueComponent], row_alpha[i]);

        if (const std::string* rowString = rowText[i].getIf<std::string>()) {
            const std::string& text = *rowString;
            if (!text.empty()) {
                strsize = cxx_OORectFromString(text, 0.0f, 0.0f, characterSize).size;
                switch (rowAlignment[i]) {
                case GUI_ALIGN_LEFT:
                    rowPosition[i].x = 0.0f;
                    break;
                case GUI_ALIGN_RIGHT:
                    rowPosition[i].x = size_in_pixels.width - strsize.width;
                    break;
                case GUI_ALIGN_CENTER:
                    rowPosition[i].x = (size_in_pixels.width - strsize.width) / 2.0f;
                    break;
                }
                if (i == (unsigned)selectedRow) {
                    NSRect block = cxx_OORectFromString(text, x + rowPosition[i].x + 2, y + rowPosition[i].y + 2, characterSize);
                    OOStopDrawingStrings();
                    [self cxx_setGLColorFromSetting:cxx_kGuiSelectedRowBackgroundColor defaultValue:[OOColor redColor] alpha:alpha];
                    OOGLBEGIN(GL_QUADS);
                    glVertex3f(block.origin.x, block.origin.y, z);
                    glVertex3f(block.origin.x + block.size.width, block.origin.y, z);
                    glVertex3f(block.origin.x + block.size.width, block.origin.y + block.size.height, z);
                    glVertex3f(block.origin.x, block.origin.y + block.size.height, z);
                    OOGLEND();
                    [self cxx_setGLColorFromSetting:cxx_kGuiSelectedRowColor defaultValue:[OOColor blackColor] alpha:alpha];
                    OOStartDrawingStrings();
                }
                cxx_OODrawStringQuadsAligned(text, x + rowPosition[i].x, y + rowPosition[i].y, z, characterSize, NO);

                // draw cursor at end of current Row
                //
                if ((showTextCursor) && (i == (unsigned)currentRow)) {
                    NSRect tr = cxx_OORectFromString(text, 0.0f, 0.0f, characterSize);
                    NSPoint cu = NSMakePoint(x + rowPosition[i].x + tr.size.width + 0.2f * characterSize.width, y + rowPosition[i].y);
                    tr.origin = cu;
                    tr.size.width = 0.5f * characterSize.width;
                    GLfloat g_alpha = 0.5f * (1.0f + (float)sin(6 * [UNIVERSE getTime]));
                    OOStopDrawingStrings();
                    [self cxx_setGLColorFromSetting:cxx_kGuiTextInputCursorColor defaultValue:[OOColor redColor] alpha:row_alpha[i] * g_alpha];
                    OOGLBEGIN(GL_QUADS);
                    glVertex3f(tr.origin.x, tr.origin.y, z);
                    glVertex3f(tr.origin.x + tr.size.width, tr.origin.y, z);
                    glVertex3f(tr.origin.x + tr.size.width, tr.origin.y + tr.size.height, z);
                    glVertex3f(tr.origin.x, tr.origin.y + tr.size.height, z);
                    OOGLEND();
                    OOStartDrawingStrings();
                }
            }
        }
        if (rowText[i].isArray()) {
            const oo::PList& array = rowText[i];
            NSUInteger j, max_columns = MIN(array.count(), n_columns);
            BOOL isLeftAligned;

            for (j = 0; j < max_columns; j++) {
                const std::string text = array.at<std::string>(j); // -oo_stringAtIndex: ("" for none)
                if (text.size() != 0) {
                    isLeftAligned = tabStops[j] >= 0;
                    rowPosition[i].x = llabs(tabStops[j]);

                    // we don't want to highlight leading space(s) or narrow spaces (\037s)
                    std::string hilitedText = TrimmedForHighlight(text);
                    // -rangeOfString: of an empty string answered NSNotFound.
                    const std::size_t txtLocation = hilitedText.empty() ? std::string::npos : text.find(hilitedText);
                    unsigned leadingSpaces = 0;

                    if (EXPECT_NOT(txtLocation == std::string::npos)) {
                        // This never happens!
                        hilitedText = text;
                    } else if (txtLocation > 0) {
                        // padded string! (the padding is ASCII, so its bytes are its characters)
                        NSRect charBlock = cxx_OORectFromString(text.substr(0, txtLocation), 0, 0, characterSize);
                        leadingSpaces = (unsigned)charBlock.size.width;

                        /*						// if we're displaying commodity-quantity-none, let's try and be pixel perfect!
                                                                        std::string qtyNone = OO_DESC("commodity-quantity-none");
                                                                        txtRange = [hilitedText rangeOfString:qtyNone];

                                                                        if (txtRange.location == 0) // bingo!
                                                                        {
                                                                                rowPosition[i].x += OORectFromString(@"0", 0, 0, characterSize).size.width - OORectFromString(qtyNone, 0, 0, characterSize).size.width;
                                                                                } */
                    }

                    // baseline text rect, needed for correct highlight positioning.
                    NSRect block = cxx_OORectFromString(text, x + rowPosition[i].x + 2, y + rowPosition[i].y + 2, characterSize);

                    if (!isLeftAligned) {
                        rowPosition[i].x -= block.size.width + 3;
                    }
                    block = cxx_OORectFromString(hilitedText, x + rowPosition[i].x + 1 + leadingSpaces, y + rowPosition[i].y + 2, characterSize);
                    block.size.width += 3;

                    if (i == (unsigned)selectedRow) {
                        OOStopDrawingStrings();
                        [self cxx_setGLColorFromSetting:cxx_kGuiSelectedRowBackgroundColor defaultValue:[OOColor redColor] alpha:alpha];
                        OOGLBEGIN(GL_QUADS);
                        glVertex3f(block.origin.x, block.origin.y, z);
                        glVertex3f(block.origin.x + block.size.width, block.origin.y, z);
                        glVertex3f(block.origin.x + block.size.width, block.origin.y + block.size.height, z);
                        glVertex3f(block.origin.x, block.origin.y + block.size.height, z);
                        OOGLEND();
                        [self cxx_setGLColorFromSetting:cxx_kGuiSelectedRowColor defaultValue:[OOColor blackColor] alpha:alpha];
                        OOStartDrawingStrings();
                    }
                    cxx_OODrawStringQuadsAligned(text, x + rowPosition[i].x, y + rowPosition[i].y, z, characterSize, NO);
                }
            }
        }
    }
    OOStopDrawingStrings();
    [OOTexture applyNone];
}

- (void)drawCrossHairsWithSize:(GLfloat)size x:(GLfloat)x y:(GLfloat)y z:(GLfloat)z
{
    OOGLBEGIN(GL_QUADS);
    glVertex3f(x - 1, y - size, z);
    glVertex3f(x + 1, y - size, z);
    glVertex3f(x + 1, y + size, z);
    glVertex3f(x - 1, y + size, z);
    glVertex3f(x - size, y - 1, z);
    glVertex3f(x + size, y - 1, z);
    glVertex3f(x + size, y + 1, z);
    glVertex3f(x - size, y + 1, z);
    OOGLEND();
}

- (void)setStarChartTitle
{
    PlayerEntity* player = PLAYER;
    OOGalaxyID galaxy_number = [player galaxyNumber];
    NSInteger system_id = [UNIVERSE findSystemNumberAtCoords:[player cursor_coordinates] withGalaxy:[player galaxyNumber] includingHidden:NO];

    const std::string location_key = oo::str::format("long-range-chart-title-%d-%ld", galaxy_number, (long)system_id);
    if (![UNIVERSE cxx_descriptionForKey:location_key]) {
        const std::string gal_key = oo::str::format("long-range-chart-title-%d", galaxy_number);
        if (![UNIVERSE cxx_descriptionForKey:gal_key]) {
            [self cxx_setTitle:oo::str::formatRuntime(OO_DESC("long-range-chart-title-d"), { galaxy_number + 1 })];
        } else {
            [self cxx_setTitle:[UNIVERSE cxx_descriptionForKey:gal_key]];
        }
    } else {
        [self cxx_setTitle:[UNIVERSE cxx_descriptionForKey:location_key]];
    }
}

- (void)drawStarChart:(GLfloat)x y:(GLfloat)y z:(GLfloat)z alpha:(GLfloat)alpha compact:(BOOL)compact
{
    PlayerEntity* player = PLAYER;

    if (!player)
        return;

    OOSystemDescriptionManager* systemManager = [UNIVERSE systemManager];

    OOScalar zoom = [player chart_zoom];
    NSPoint chart_centre_coordinates = [player adjusted_chart_centre];
    NSPoint galaxy_coordinates = [player galaxy_coordinates];
    NSPoint cursor_coordinates = [player cursor_coordinates];
    NSPoint info_system_coordinates = [[UNIVERSE systemManager] getCoordinatesForSystem:[player infoSystemID] inGalaxy:[player galaxyNumber]];
    OOLongRangeChartMode chart_mode = [player longRangeChartMode];
    OOGalaxyID galaxy_id = [player galaxyNumber];
    GLfloat r = 1.0, g = 1.0, b = 1.0;
    BOOL noNova;
    NSPoint cu;
    NSUInteger systemParameter;

    double fuel = 35.0 * [player dialFuel];

    double hcenter = size_in_pixels.width / 2.0;
    double hscale = size_in_pixels.width / (CHART_WIDTH_AT_MAX_ZOOM * zoom);
    double vscale = -size_in_pixels.height / (2 * CHART_HEIGHT_AT_MAX_ZOOM * zoom);
    double vcenter = CHART_SCREEN_VERTICAL_CENTRE;
    double hoffset = hcenter - chart_centre_coordinates.x * hscale;
    double voffset = size_in_pixels.height - vcenter - chart_centre_coordinates.y * vscale;

    if (compact) {
        hscale = size_in_pixels.width / 256.0;
        vscale = -1.0 * size_in_pixels.height / 512.0;
        hoffset = 0.0f;
        voffset = size_in_pixels.height - pixel_title_size.height - 5;
        vcenter = CHART_SCREEN_VERTICAL_CENTRE_COMPACT;
        chart_centre_coordinates.x = 128.0;
        chart_centre_coordinates.y = 128.0;
        zoom = CHART_MAX_ZOOM;
    }

    int i;
    double d, distance = 0.0, time = 0.0;
    int jumps = 0;
    NSPoint star;
    OOScalar pixelRatio;
    NSRect clipRect;

    OORouteType advancedNavArrayMode = [player ANAMode];
    BOOL routeExists = NO;

    NSInteger concealment[256];
    for (i = 0; i < 256; i++) {
        const oo::PList systemInfo = [systemManager cxx_getPropertiesForSystem:i inGalaxy:galaxy_id];
        concealment[i] = systemInfo.get<int>("concealment", OO_SYSTEMCONCEALMENT_NONE);
    }

    BOOL* systemsFound = [UNIVERSE systemsFound];
    NSSize viewSize = [[UNIVERSE gameView] backingViewSize];
    double aspect_ratio = viewSize.width / viewSize.height;

    // default colours - match those in HeadUpDisplay:OODrawPlanetInfo
    GLfloat govcol[] = { 0.5, 0.0, 0.7,
        0.7, 0.5, 0.3,
        0.0, 1.0, 0.3,
        1.0, 0.8, 0.1,
        1.0, 0.0, 0.0,
        0.1, 0.5, 1.0,
        0.7, 0.7, 0.7,
        0.7, 1.0, 1.0 };

    if (aspect_ratio > 4.0 / 3.0) {
        pixelRatio = viewSize.height / 480.0;
    } else {
        pixelRatio = viewSize.width / 640.0;
    }

    NSInteger textRow = compact ? GUI_ROW_CHART_SYSTEM_COMPACT : GUI_ROW_CHART_SYSTEM;

    clipRect = NSMakeRect((viewSize.width - size_in_pixels.width * pixelRatio) / 2.0,
        (viewSize.height + size_in_pixels.height * pixelRatio) / 2.0 - (pixel_title_size.height + 15 + (textRow - 2) * MAIN_GUI_ROW_HEIGHT) * pixelRatio,
        size_in_pixels.width * pixelRatio,
        (textRow - 1) * MAIN_GUI_ROW_HEIGHT * pixelRatio);

    OOSystemID target = [PLAYER targetSystemID];
    double dx, dy;

    // get a list of systems marked as contract destinations
    const std::optional<std::map<int, std::vector<oo::PList>>> markedDestinations = [player cxx_markedDestinations];

    // get present location
    cu = NSMakePoint((float)(hscale * galaxy_coordinates.x + hoffset), (float)(vscale * galaxy_coordinates.y + voffset));

    // enable draw clipping; limit drawing area within the chart area
    OOGL(glEnable(GL_SCISSOR_TEST));
    OOGL(glScissor(clipRect.origin.x, clipRect.origin.y, clipRect.size.width, clipRect.size.height));

    // Cache nearby systems so that [UNIVERSE generateSystemData:] does not get called on every frame
    // Caching code submitted by Y A J, 20091022

    static OOGalaxyID saved_galaxy_id;
    static struct saved_system {
        OOSystemID sysid;
        int tec, eco, gov;
        std::string p_name;
        BOOL nova;
    } nearby_systems[256];
    static int num_nearby_systems = 0;

    if (_refreshStarChart || galaxy_id != saved_galaxy_id) {
        // saved systems are stale; recompute
        _refreshStarChart = NO;

        num_nearby_systems = 0;
        for (i = 0; i < 256; i++) {

            const oo::PList sys_info = [UNIVERSE cxx_generateSystemData:i];
            if (EXPECT_NOT(sys_info.get<bool>("sun_gone_nova"))) {
                nearby_systems[num_nearby_systems].gov = -1; // Flag up nova systems!
            } else {
                nearby_systems[num_nearby_systems].tec = sys_info.get<int>(std::string(KEY_TECHLEVEL));
                nearby_systems[num_nearby_systems].eco = sys_info.get<int>(std::string(KEY_ECONOMY));
                nearby_systems[num_nearby_systems].gov = sys_info.get<int>(std::string(KEY_GOVERNMENT));
            }
            nearby_systems[num_nearby_systems].sysid = i;
            nearby_systems[num_nearby_systems].p_name = sys_info.get<std::string>(std::string(KEY_NAME));
            nearby_systems[num_nearby_systems].nova = [UNIVERSE cxx_generateSystemData:i].get<bool>("sun_gone_nova");
            num_nearby_systems++;
        }
        saved_galaxy_id = [player galaxyNumber];
    }

    static OOSystemID savedPlanetNumber = 0;
    static OOSystemID savedDestNumber = 0;
    static OORouteType savedArrayMode = OPTIMIZED_BY_NONE;
    static oo::PList routeInfo; // null: no cached route

    /* May override current mode for mission screens */
    if (backgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG_ANA_SHORTEST || backgroundSpecial == GUI_BACKGROUND_SPECIAL_SHORT_ANA_SHORTEST || backgroundSpecial == GUI_BACKGROUND_SPECIAL_CUSTOM_ANA_SHORTEST) {
        advancedNavArrayMode = OPTIMIZED_BY_JUMPS;
    } else if (backgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG_ANA_QUICKEST || backgroundSpecial == GUI_BACKGROUND_SPECIAL_SHORT_ANA_QUICKEST || backgroundSpecial == GUI_BACKGROUND_SPECIAL_CUSTOM_ANA_QUICKEST) {
        advancedNavArrayMode = OPTIMIZED_BY_TIME;
    }

    if (advancedNavArrayMode != OPTIMIZED_BY_NONE && [player cxx_hasEquipmentItemProviding:"EQ_ADVANCED_NAVIGATIONAL_ARRAY"]) {
        OOSystemID planetNumber = [PLAYER systemID];
        OOSystemID destNumber = [PLAYER targetSystemID];
        if (routeInfo.isNull() || planetNumber != savedPlanetNumber || destNumber != savedDestNumber || advancedNavArrayMode != savedArrayMode) {
            routeInfo = [UNIVERSE cxx_routeFromSystem:planetNumber toSystem:destNumber optimizedBy:advancedNavArrayMode];
            savedPlanetNumber = planetNumber;
            savedDestNumber = destNumber;
            savedArrayMode = advancedNavArrayMode;
        }
        target = destNumber;

        // if the ANA has been activated and we are in string input mode (i.e. planet search),
        // get out of it so that distance and time data can be displayed
        // if ([[[UNIVERSE gameView] typedString] length] > 0)  [player clearPlanetSearchString];

        if (!routeInfo.isNull())
            routeExists = YES;

        [self drawAdvancedNavArrayAtX:x + hoffset y:y + voffset z:z alpha:alpha usingRoute:(planetNumber != destNumber ? routeInfo : oo::PList()) optimizedBy:advancedNavArrayMode zoom:zoom];

        if (routeExists) {
            distance = routeInfo.get<double>("distance");
            time = routeInfo.get<double>("time");
            jumps = routeInfo.get<int>("jumps");

            if (distance == 0.0 && planetNumber != destNumber) {
                // zero-distance double fix
                distance = 0.1;
                time = 0.01;
            }
        }
    } else {
        [self drawAdvancedNavArrayAtX:x + hoffset y:y + voffset z:z alpha:alpha usingRoute:oo::PList() optimizedBy:OPTIMIZED_BY_NONE zoom:zoom];
    }
    if (!routeExists) {
        NSPoint targetCoordinates = [systemManager getCoordinatesForSystem:target inGalaxy:galaxy_id];

        distance = distanceBetweenPlanetPositions(targetCoordinates.x, targetCoordinates.y, galaxy_coordinates.x, galaxy_coordinates.y);
        if (distance == 0.0) {
            if (target != [PLAYER systemID]) {
                // looking at the other half of a zero-distance double
                // distance is treated as 0.1 LY
                distance = 0.1;
            }
        }
        if ([player hasHyperspaceMotor] && distance <= [player fuel] / 10.0) {
            time = distance * distance;
        } else {
            time = 0.0;
        }
    }

    if ([player hasHyperspaceMotor]) {
        // draw fuel range circle
        OOGL(GLScaledLineWidth(2.0f));
        [self cxx_setGLColorFromSetting:cxx_kGuiChartRangeColor defaultValue:[OOColor greenColor] alpha:alpha];

        GLDrawOval(x + cu.x, y + cu.y, z, NSMakeSize((float)(fuel * hscale), 2 * (float)(fuel * vscale)), 5);
    }

    // draw crosshairs over current location
    //
    [self cxx_setGLColorFromSetting:cxx_kGuiChartCrosshairColor defaultValue:[OOColor greenColor] alpha:alpha];

    [self drawCrossHairsWithSize:12 / zoom + 2 x:x + cu.x y:y + cu.y z:z];

    // draw crosshairs over cursor
    //
    [self cxx_setGLColorFromSetting:cxx_kGuiChartCursorColor defaultValue:[OOColor redColor] alpha:alpha];
    cu = NSMakePoint((float)(hscale * cursor_coordinates.x + hoffset), (float)(vscale * cursor_coordinates.y + voffset));
    [self drawCrossHairsWithSize:7 / zoom + 2 x:x + cu.x y:y + cu.y z:z];

    // draw marks and stars
    //
    OOGL(GLScaledLineWidth(1.5f));
    OOGL(glColor4f(1.0f, 1.0f, 0.75f, alpha)); // pale yellow

    for (i = 0; i < num_nearby_systems; i++) {
        NSPoint sys_coordinates = [systemManager getCoordinatesForSystem:i inGalaxy:galaxy_id];

        dx = fabs(chart_centre_coordinates.x - sys_coordinates.x);
        dy = fabs(chart_centre_coordinates.y - sys_coordinates.y);

        if ((dx > zoom * (CHART_WIDTH_AT_MAX_ZOOM / 2.0 + CHART_CLIP_BORDER)) || (dy > zoom * (CHART_HEIGHT_AT_MAX_ZOOM + CHART_CLIP_BORDER)))
            continue;

        if (concealment[i] >= OO_SYSTEMCONCEALMENT_NOTHING) {
            // system is not known
            continue;
        }

        const oo::PList systemInfo = [systemManager cxx_getPropertiesForSystem:i inGalaxy:galaxy_id];
        float blob_factor = guiUserSettings.get<float>(cxx_kGuiChartCircleScale, 0.0017);
        float blob_size = (1.0f + blob_factor * systemInfo.get<float>("radius")) / zoom;
        if (blob_size < 0.5)
            blob_size = 0.5;

        star.x = (float)(sys_coordinates.x * hscale + hoffset);
        star.y = (float)(sys_coordinates.y * vscale + voffset);

        noNova = !nearby_systems[i].nova;
        OOAssert(chart_mode <= OOLRC_MODE_TECHLEVEL, "Long range chart mode %i out of range", (int)chart_mode);

        if (markedDestinations.has_value()) {
            const auto markersIt = markedDestinations->find(i);
            if (markersIt != markedDestinations->end()) // is marked
            {
                GLfloat base_size = 0.5f * blob_size + 2.5f;
                [self drawSystemMarkers:oo::PList(oo::PList::Array(markersIt->second.begin(), markersIt->second.end()))
                                    atX:x + star.x
                                   andY:y + star.y
                                   andZ:z
                              withAlpha:alpha
                               andScale:base_size];
            }
        }

        if (concealment[i] >= OO_SYSTEMCONCEALMENT_NODATA) {
            // no system data available
            r = g = b = 0.7;
            OOGL(glColor4f(r, g, b, alpha));
        } else {
            switch (chart_mode) {
            case OOLRC_MODE_ECONOMY:
                if (EXPECT(noNova)) {
                    systemParameter = nearby_systems[i].eco;
                    GLfloat ce1 = 1.0f - 0.125f * systemParameter;
                    [self cxx_setGLColorFromSetting:oo::str::format(cxx_kGuiChartEconomyUColor, systemParameter)
                                       defaultValue:[OOColor colorWithRed:ce1 green:1.0f blue:0.0f alpha:1.0f]
                                              alpha:1.0];
                } else {
                    r = g = b = 0.3;
                    OOGL(glColor4f(r, g, b, alpha));
                }
                break;
            case OOLRC_MODE_GOVERNMENT:
                if (EXPECT(noNova)) {
                    systemParameter = nearby_systems[i].gov;
                    [self cxx_setGLColorFromSetting:oo::str::format(cxx_kGuiChartGovernmentUColor, systemParameter)
                                       defaultValue:[OOColor colorWithRed:govcol[systemParameter * 3] green:govcol[1 + (systemParameter * 3)] blue:govcol[2 + (systemParameter * 3)] alpha:1.0f]
                                              alpha:1.0];
                } else {
                    r = g = b = 0.3;
                    OOGL(glColor4f(r, g, b, alpha));
                }
                break;
            case OOLRC_MODE_TECHLEVEL:
                if (EXPECT(noNova)) {
                    systemParameter = nearby_systems[i].tec;
                    r = 0.6;
                    g = b = 0.20 + (0.05 * (GLfloat)systemParameter);
                } else {
                    r = g = b = 0.3;
                }
                OOGL(glColor4f(r, g, b, alpha));
                break;
            case OOLRC_MODE_UNKNOWN:
            case OOLRC_MODE_SUNCOLOR:
                if (EXPECT(noNova)) {
                    r = g = b = 1.0;
                    OOColor* sunColor = [OOColor colorWithDescription:oo::ObjectFromPList([[UNIVERSE systemManager] cxx_getProperty:"sun_color" forSystem:i inGalaxy:galaxy_id])];
                    if (sunColor != nil) {
                        [sunColor getRed:&r green:&g blue:&b alpha:&alpha];
                        alpha = 1.0; // reset
                    }
                } else {
                    r = 1.0;
                    g = 0.2;
                    b = 0.0;
                }
                OOGL(glColor4f(r, g, b, alpha));
                break;
            }
        }

        GLDrawFilledOval(x + star.x, y + star.y, z, NSMakeSize(blob_size, blob_size), 15);
    }

    // draw found stars and captions
    //
    GLfloat systemNameScale = guiUserSettings.get<float>(cxx_kGuiChartLabelScale, 1.0);

    OOGL(GLScaledLineWidth(1.5f));
    [self cxx_setGLColorFromSetting:cxx_kGuiChartMatchBoxColor defaultValue:[OOColor greenColor] alpha:alpha];

    int n_matches = 0, foundIndex = -1;

    for (i = 0; i < 256; i++)
        if (systemsFound[i]) {
            if (foundSystem == n_matches)
                foundIndex = i;
            n_matches++;
        }

    if (n_matches == 0) {
        foundSystem = 0;
    } else if (backgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG_ANA_SHORTEST || backgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG_ANA_QUICKEST || backgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG) {
        // do nothing at this stage
    } else {
        for (i = 0; i < 256; i++) {
            if (concealment[i] >= OO_SYSTEMCONCEALMENT_NONAME) {
                continue;
            }

            BOOL mark = systemsFound[i];
            float marker_size = 8.0 / zoom;
            NSPoint sys_coordinates = [systemManager getCoordinatesForSystem:i inGalaxy:galaxy_id];

            dx = fabs(chart_centre_coordinates.x - sys_coordinates.x);
            dy = fabs(chart_centre_coordinates.y - sys_coordinates.y);

            if (mark && (dx <= zoom * (CHART_WIDTH_AT_MAX_ZOOM / 2.0 + CHART_CLIP_BORDER)) && (dy <= zoom * (CHART_HEIGHT_AT_MAX_ZOOM + CHART_CLIP_BORDER))) {
                star.x = (float)(sys_coordinates.x * hscale + hoffset);
                star.y = (float)(sys_coordinates.y * vscale + voffset);
                OOGLBEGIN(GL_LINE_LOOP);
                glVertex3f(x + star.x - marker_size, y + star.y - marker_size, z);
                glVertex3f(x + star.x + marker_size, y + star.y - marker_size, z);
                glVertex3f(x + star.x + marker_size, y + star.y + marker_size, z);
                glVertex3f(x + star.x - marker_size, y + star.y + marker_size, z);
                OOGLEND();
                if (i == foundIndex || n_matches == 1) {
                    if (n_matches == 1)
                        foundSystem = 0;
                    if (zoom > CHART_ZOOM_SHOW_LABELS && advancedNavArrayMode == OPTIMIZED_BY_NONE) {
                        [self cxx_setGLColorFromSetting:cxx_kGuiChartMatchLabelColor defaultValue:[OOColor cyanColor] alpha:alpha];
                        cxx_OODrawString([UNIVERSE cxx_systemNameIndex:i].value_or(""), x + star.x + 2.0, y + star.y - 10.0f, z, NSMakeSize(10 * systemNameScale, 10 * systemNameScale));
                        [self cxx_setGLColorFromSetting:cxx_kGuiChartMatchBoxColor defaultValue:[OOColor greenColor] alpha:alpha];
                    }
                } else if (zoom > CHART_ZOOM_SHOW_LABELS) {
                    cxx_OODrawString([UNIVERSE cxx_systemNameIndex:i].value_or(""), x + star.x + 2.0, y + star.y - 10.0f, z, NSMakeSize(10 * systemNameScale, 10 * systemNameScale));
                }
            }
        }
    }

    // draw names
    //
    //	OOGL(glColor4f(1.0f, 1.0f, 0.0f, alpha));	// yellow

    int targetIdx = -1;
    struct saved_system* sys;
    NSSize chSize = NSMakeSize(pixel_row_height * systemNameScale / zoom, pixel_row_height * systemNameScale / zoom);

    double jumpRange = MAX_JUMP_RANGE * [PLAYER dialFuel];
    for (i = 0; i < num_nearby_systems; i++) {
        if (concealment[i] >= OO_SYSTEMCONCEALMENT_NONAME) {
            continue;
        }

        sys = nearby_systems + i;
        NSPoint sys_coordinates = [systemManager getCoordinatesForSystem:sys->sysid inGalaxy:galaxy_id];

        dx = fabs(chart_centre_coordinates.x - sys_coordinates.x);
        dy = fabs(chart_centre_coordinates.y - sys_coordinates.y);

        if ((dx > zoom * (CHART_WIDTH_AT_MAX_ZOOM / 2.0 + CHART_CLIP_BORDER)) || (dy > zoom * (CHART_HEIGHT_AT_MAX_ZOOM + CHART_CLIP_BORDER)))
            continue;
        star.x = (float)(sys_coordinates.x * hscale + hoffset);
        star.y = (float)(sys_coordinates.y * vscale + voffset);
        if (sys->sysid == target) // not overlapping twin? (example: Divees & Tezabi in galaxy 5)
        {
            targetIdx = i; // we have a winner!
        }

        if (zoom < CHART_ZOOM_SHOW_LABELS) {
            if (![player showInfoFlag]) // System's name
            {

                d = distanceBetweenPlanetPositions(galaxy_coordinates.x, galaxy_coordinates.y, sys_coordinates.x, sys_coordinates.y);
                if (d <= jumpRange) {
                    [self cxx_setGLColorFromSetting:cxx_kGuiChartLabelReachableColor defaultValue:[OOColor yellowColor] alpha:alpha];
                } else {
                    [self cxx_setGLColorFromSetting:cxx_kGuiChartLabelColor defaultValue:[OOColor yellowColor] alpha:alpha];
                }

                cxx_OODrawString(sys->p_name, x + star.x + 2.0, y + star.y, z, chSize);
            } else if (EXPECT(sys->gov >= 0)) // Not a nova? Show the info.
            {
                if (concealment[i] >= OO_SYSTEMCONCEALMENT_NODATA) {
                    [self cxx_setGLColorFromSetting:cxx_kGuiChartLabelColor defaultValue:[OOColor yellowColor] alpha:alpha];
                    cxx_OODrawHilightedString("???", x + star.x + 2.0, y + star.y, z, chSize);
                } else {
                    OODrawPlanetInfo(sys->gov, sys->eco, sys->tec, x + star.x + 2.0, y + star.y + 2.0, z, chSize);
                }
            }
        }
    }

    // highlight the name of the currently selected system
    // (needed to get things right in closely-overlapping systems)
    if (targetIdx != -1 && zoom <= CHART_ZOOM_SHOW_LABELS) {
        if (concealment[targetIdx] < OO_SYSTEMCONCEALMENT_NONAME) {
            sys = nearby_systems + targetIdx;
            NSPoint sys_coordinates = [systemManager getCoordinatesForSystem:sys->sysid inGalaxy:galaxy_id];

            star.x = (float)(sys_coordinates.x * hscale + hoffset);
            star.y = (float)(sys_coordinates.y * vscale + voffset);

            if (![player showInfoFlag]) {
                d = distanceBetweenPlanetPositions(galaxy_coordinates.x, galaxy_coordinates.y, sys_coordinates.x, sys_coordinates.y);
                if (d <= jumpRange) {
                    [self cxx_setGLColorFromSetting:cxx_kGuiChartLabelReachableColor defaultValue:[OOColor yellowColor] alpha:alpha];
                } else {
                    [self cxx_setGLColorFromSetting:cxx_kGuiChartLabelColor defaultValue:[OOColor yellowColor] alpha:alpha];
                }

                cxx_OODrawHilightedString(sys->p_name, x + star.x + 2.0, y + star.y, z, chSize);
            } else if (sys->gov >= 0) // Not a nova? Show the info.
            {
                if (concealment[targetIdx] >= OO_SYSTEMCONCEALMENT_NODATA) {
                    [self cxx_setGLColorFromSetting:cxx_kGuiChartLabelColor defaultValue:[OOColor yellowColor] alpha:alpha];
                    cxx_OODrawHilightedString("???", x + star.x + 2.0, y + star.y, z, chSize);
                } else {
                    OODrawHilightedPlanetInfo(sys->gov, sys->eco, sys->tec, x + star.x + 2.0, y + star.y + 2.0, z, chSize);
                }
            }
        }
    }

    OOGUITabSettings tab_stops;
    tab_stops[0] = 0;
    tab_stops[1] = 96;
    tab_stops[2] = 288;
    [self cxx_overrideTabs:tab_stops from:cxx_kGuiChartTraveltimeTabs length:3];
    [self setTabStops:tab_stops];
    const std::string targetName = [UNIVERSE cxx_getSystemName:target].value_or(std::string());

    // distance-f & est-travel-time-f are identical between short & long range charts in standard Oolite, however can be alterered separately via OXPs
    std::string travelDistLine;
    if (distance > 0) {
        travelDistLine = cxx_OOExpandKey("long-range-chart-distance", distance).value_or(std::string());
    }
    std::string travelTimeLine;
    if (time > 0) {
        travelTimeLine = cxx_OOExpandKey("long-range-chart-est-travel-time", time).value_or(std::string());
    }

    if (concealment[target] < OO_SYSTEMCONCEALMENT_NONAME) {
        [self cxx_setArray:{ targetName, travelDistLine, travelTimeLine } forRow:textRow];
    } else {
        [self cxx_setArray:{ "", travelDistLine, travelTimeLine } forRow:textRow];
    }
    if ([PLAYER guiScreen] == GUI_SCREEN_SHORT_RANGE_CHART) {
        if (jumps > 0) {
            [self cxx_setArray:{ "", cxx_OOExpandKey("short-range-chart-jumps", jumps).value_or(std::string()) } forRow:textRow + 1];
        } else {
            [self cxx_setArray:{ } forRow:textRow + 1];
        }
    }

    // draw planet info circle
    OOGL(GLScaledLineWidth(2.0f));
    [self cxx_setGLColorFromSetting:cxx_kGuiChartInfoMarkerColor defaultValue:[OOColor blueColor] alpha:alpha];
    cu = NSMakePoint((float)(hscale * info_system_coordinates.x + hoffset), (float)(vscale * info_system_coordinates.y + voffset));
    GLDrawOval(x + cu.x, y + cu.y, z, NSMakeSize(6.0f / zoom + 2.0f, 6.0f / zoom + 2.0f), 5);

    // disable draw clipping
    OOGL(glDisable(GL_SCISSOR_TEST));

    // Draw bottom divider
    [self cxx_setGLColorFromSetting:cxx_kGuiScreenDividerColor defaultValue:[OOColor colorWithWhite:0.75 alpha:1.0] alpha:alpha];
    OOGLBEGIN(GL_QUADS);
    glVertex3f(x + 0, (float)(y + size_in_pixels.height - (textRow - 1) * MAIN_GUI_ROW_HEIGHT - pixel_title_size.height), z);
    glVertex3f(x + size_in_pixels.width, (GLfloat)(y + size_in_pixels.height - (textRow - 1) * MAIN_GUI_ROW_HEIGHT - pixel_title_size.height), z);
    glVertex3f(x + size_in_pixels.width, (GLfloat)(y + size_in_pixels.height - (textRow - 1) * MAIN_GUI_ROW_HEIGHT - pixel_title_size.height - 2), z);
    glVertex3f(x + 0, (GLfloat)(y + size_in_pixels.height - (textRow - 1) * MAIN_GUI_ROW_HEIGHT - pixel_title_size.height - 2), z);
    OOGLEND();
}

- (void)drawSystemMarkers:(const oo::PList&)markers atX:(GLfloat)x andY:(GLfloat)y andZ:(GLfloat)z withAlpha:(GLfloat)alpha andScale:(GLfloat)scale
{
    const oo::PList::Array* markerList = markers.getIf<oo::PList::Array>();
    if (markerList == nullptr)
        return;
    for (const oo::PList& marker : *markerList) {
        [self drawSystemMarker:marker atX:x andY:y andZ:z withAlpha:alpha andScale:scale];
    }
}

- (void)drawSystemMarker:(const oo::PList&)marker atX:(GLfloat)x andY:(GLfloat)y andZ:(GLfloat)z withAlpha:(GLfloat)alpha andScale:(GLfloat)scale
{
    const std::string colorDesc = marker.get<std::string>("markerColor", "redColor");
    OORGBAComponents color = [[OOColor colorWithDescription:oo::NSStringFrom(colorDesc)] rgbaComponents];

    OOGL(glColor4f(color.r, color.g, color.b, alpha)); // red
    GLfloat mark_size = marker.get<float>("markerScale", 1.0);
    if (mark_size > 2.0) {
        mark_size = 2.0;
    } else if (mark_size < 0.5) {
        mark_size = 0.5;
    }
    mark_size *= scale;

    const std::string shape = marker.get<std::string>("markerShape", "MARKER_X");

    OOGLBEGIN(GL_LINES);
    if (shape == "MARKER_X") {
        glVertex3f(x - mark_size, y - mark_size, z);
        glVertex3f(x + mark_size, y + mark_size, z);
        glVertex3f(x - mark_size, y + mark_size, z);
        glVertex3f(x + mark_size, y - mark_size, z);
    } else if (shape == "MARKER_PLUS") {
        mark_size *= 1.4; // match volumes
        glVertex3f(x, y - mark_size, z);
        glVertex3f(x, y + mark_size, z);
        glVertex3f(x - mark_size, y, z);
        glVertex3f(x + mark_size, y, z);
    } else if (shape == "MARKER_SQUARE") {
        glVertex3f(x - mark_size, y - mark_size, z);
        glVertex3f(x - mark_size, y + mark_size, z);
        glVertex3f(x - mark_size, y + mark_size, z);
        glVertex3f(x + mark_size, y + mark_size, z);
        glVertex3f(x + mark_size, y + mark_size, z);
        glVertex3f(x + mark_size, y - mark_size, z);
        glVertex3f(x + mark_size, y - mark_size, z);
        glVertex3f(x - mark_size, y - mark_size, z);
    } else if (shape == "MARKER_DIAMOND") {
        mark_size *= 1.4; // match volumes
        glVertex3f(x, y - mark_size, z);
        glVertex3f(x - mark_size, y, z);
        glVertex3f(x - mark_size, y, z);
        glVertex3f(x, y + mark_size, z);
        glVertex3f(x, y + mark_size, z);
        glVertex3f(x + mark_size, y, z);
        glVertex3f(x + mark_size, y, z);
        glVertex3f(x, y - mark_size, z);
    }
    OOGLEND();
}

- (OOSystemID)targetNextFoundSystem:(int)direction // +1 , 0 , -1
{
    OOSystemID sys = [PLAYER targetSystemID];
    if ([PLAYER guiScreen] != GUI_SCREEN_SHORT_RANGE_CHART && [PLAYER guiScreen] != GUI_SCREEN_LONG_RANGE_CHART)
        return sys;

    BOOL* systemsFound = [UNIVERSE systemsFound];
    unsigned i, first = 0, last = 0, count = 0;
    int systemIndex = foundSystem + direction;

    if (direction == 0)
        systemIndex = 0;

    for (i = 0; i <= kOOMaximumSystemID; i++) {
        if (systemsFound[i]) {
            if (count == 0) {
                first = last = i;
            } else {
                last = i;
            }
            if (systemIndex == (int)count) {
                sys = i;
            }
            count++;
        }
    }

    if (count == 0)
        return sys; // empty systemFound list.

    // loop back if needed.
    if (systemIndex < 0) {
        systemIndex = count - 1;
        sys = last;
    }
    if (systemIndex >= (int)count) {
        systemIndex = 0;
        sys = first;
    }

    foundSystem = systemIndex;
    return sys;
}

// Advanced Navigation Array -- galactic chart route mapping - contributed by Nikos Barkas (another_commander).
- (void)drawAdvancedNavArrayAtX:(float)x y:(float)y z:(float)z alpha:(float)alpha usingRoute:(const oo::PList&)routeInfo optimizedBy:(OORouteType)optimizeBy zoom:(OOScalar)zoom
{
    GLfloat lr, lg, lb, la, lr2, lg2, lb2, la2;
    double hscale = size_in_pixels.width / (CHART_WIDTH_AT_MAX_ZOOM * zoom);
    double vscale = -1.0 * size_in_pixels.height / (2 * CHART_HEIGHT_AT_MAX_ZOOM * zoom);
    NSPoint star = NSZeroPoint,
            star2 = NSZeroPoint,
            starabs = NSZeroPoint,
            star2abs = NSZeroPoint;
    OOSystemDescriptionManager* systemManager = [UNIVERSE systemManager];
    OOGalaxyID g = [PLAYER galaxyNumber];
    OOSystemID planetNumber = [PLAYER systemID];

    OOColor* defaultConnectionColor = [self cxx_colorFromSetting:cxx_kGuiChartConnectionColor defaultValue:[OOColor colorWithWhite:0.25 alpha:1.0]];
    OOColor* currentJumpColorStart = [self cxx_colorFromSetting:cxx_kGuiChartCurrentJumpStartColor defaultValue:[OOColor colorWithWhite:0.25 alpha:0.0]];
    OOColor* currentJumpColorEnd = [self cxx_colorFromSetting:cxx_kGuiChartCurrentJumpEndColor defaultValue:[OOColor colorWithWhite:0.25 alpha:0.0]];

    OOColor* thisConnectionColor = nil;
    OOColor* thatConnectionColor = nil;

    float jumpRange = MAX_JUMP_RANGE * ((optimizeBy == OPTIMIZED_BY_NONE) ? [PLAYER dialFuel] : 1.0);

    NSInteger concealment[256];
    for (NSUInteger i = 0; i < 256; i++) {
        concealment[i] = [systemManager cxx_getPropertiesForSystem:i inGalaxy:g].get<int>("concealment", OO_SYSTEMCONCEALMENT_NONE);
    }

    OOGLBEGIN(GL_LINES);
    for (OOSystemID i = 0; i < 256; i++) {

        if (concealment[i] >= OO_SYSTEMCONCEALMENT_NOTHING) {
            // system is not known
            continue;
        }

        /* Concealment */
        if (optimizeBy == OPTIMIZED_BY_NONE && i != planetNumber) {
            continue;
        }

        starabs = [systemManager getCoordinatesForSystem:i inGalaxy:g];

        star.x = (float)(starabs.x * hscale);
        star.y = (float)(starabs.y * vscale);

        // if in non-route mode, we're always starting from i, so need
        // to do <i here too.
        OOSystemID loopstart = (optimizeBy == OPTIMIZED_BY_NONE) ? 0 : (i + 1);

        for (OOSystemID j = loopstart; j < 256; j++) {
            if (i == j) {
                continue; // for OPTIMIZED_BY_NONE case
            }

            if (concealment[j] >= OO_SYSTEMCONCEALMENT_NOTHING) {
                // system is not known
                continue;
            }

            star2abs = [systemManager getCoordinatesForSystem:j inGalaxy:g];
            double d = distanceBetweenPlanetPositions(starabs.x, starabs.y, star2abs.x, star2abs.y);

            if (d <= jumpRange) // another_commander - Default to 7.0 LY.
            {
                star2.x = (float)(star2abs.x * hscale);
                star2.y = (float)(star2abs.y * vscale);
                if (optimizeBy == OPTIMIZED_BY_NONE) {
                    [currentJumpColorStart getRed:&lr green:&lg blue:&lb alpha:&la];
                    [currentJumpColorEnd getRed:&lr2 green:&lg2 blue:&lb2 alpha:&la2];
                    OOGL(glColor4f(lr, lg, lb, la * alpha));
                    glVertex3f(x + star.x, y + star.y, z);

                    float frac = (d / jumpRange);
                    OOGL(glColor4f(
                        OOLerp(lr, lr2, frac),
                        OOLerp(lg, lg2, frac),
                        OOLerp(lb, lb2, frac),
                        OOLerp(la, la2, frac)));
                    glVertex3f(x + star2.x, y + star2.y, z);

                } else {
                    thisConnectionColor = [OOColor colorWithDescription:oo::ObjectFromPList([systemManager cxx_getProperty:"link_color" forSystemKey:oo::str::format("interstellar: %d %ld %ld", g, (long)i, (long)j)])];

                    if (thisConnectionColor == nil) {
                        thisConnectionColor = defaultConnectionColor;
                    }
                    [thisConnectionColor getRed:&lr green:&lg blue:&lb alpha:&la];
                    OOGL(glColor4f(lr, lg, lb, la * alpha));

                    glVertex3f(x + star.x, y + star.y, z);

                    // and the other colour for the other end
                    thatConnectionColor = [OOColor colorWithDescription:oo::ObjectFromPList([systemManager cxx_getProperty:"link_color" forSystemKey:oo::str::format("interstellar: %d %ld %ld", g, (long)j, (long)i)])];

                    if (thatConnectionColor == nil) {
                        thatConnectionColor = thisConnectionColor;
                    }
                    [thatConnectionColor getRed:&lr green:&lg blue:&lb alpha:&la];
                    OOGL(glColor4f(lr, lg, lb, la * alpha));

                    glVertex3f(x + star2.x, y + star2.y, z);
                }
            }
        }
    }
    OOGLEND();

    if (optimizeBy == OPTIMIZED_BY_NONE) {
        return;
    }

    if (!routeInfo.isNull()) {
        // "route" as -oo_arrayForKey: read it (its count: 0 when it is not an array), and as
        // -objectForKey: gave it to the index reads (null reads as 0, as messaging nil did).
        const oo::PList* routeArray = routeInfo.get<oo::PList::Array>("route");
        const oo::PList route = (routeInfo.find("route") != nullptr) ? *routeInfo.find("route") : oo::PList();
        NSUInteger i, route_hops = ((routeArray != nullptr) ? routeArray->count() : 0) - 1;

        if (optimizeBy == OPTIMIZED_BY_JUMPS) {
            // route optimised by distance
            [self cxx_setGLColorFromSetting:cxx_kGuiChartRouteShortColor defaultValue:[OOColor yellowColor] alpha:alpha];
        } else {
            // route optimised by time
            [self cxx_setGLColorFromSetting:cxx_kGuiChartRouteQuickColor defaultValue:[OOColor cyanColor] alpha:alpha];
        }
        OOSystemID loc;
        for (i = 0; i < route_hops; i++) {
            loc = route.at<int>(i);
            starabs = [systemManager getCoordinatesForSystem:loc inGalaxy:g];
            star2abs = [systemManager getCoordinatesForSystem:route.at<int>(i + 1) inGalaxy:g];

            star.x = (float)(starabs.x * hscale);
            star.y = (float)(starabs.y * vscale);

            star2.x = (float)(star2abs.x * hscale);
            star2.y = (float)(star2abs.y * vscale);

            OOGLBEGIN(GL_LINES);
            glVertex3f(x + star.x, y + star.y, z);
            glVertex3f(x + star2.x, y + star2.y, z);
            OOGLEND();

            // Label the route, if not already labelled
            if (zoom > CHART_ZOOM_SHOW_LABELS && concealment[loc] < OO_SYSTEMCONCEALMENT_NONAME) {
                cxx_OODrawString([UNIVERSE cxx_systemNameIndex:loc].value_or(""), x + star.x + 2.0, y + star.y, z, NSMakeSize(8, 8));
            }
        }
        // Label the destination, which was not included in the above loop.
        if (zoom > CHART_ZOOM_SHOW_LABELS) {
            loc = route.at<int>(i);
            if (concealment[loc] < OO_SYSTEMCONCEALMENT_NONAME) {
                cxx_OODrawString([UNIVERSE cxx_systemNameIndex:loc].value_or(""), x + star2.x + 2.0, y + star2.y, z, NSMakeSize(10, 10));
            }
        }
    }
}

@end
