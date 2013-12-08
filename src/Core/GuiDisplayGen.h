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

#import "OOCocoa.h"
#import "OOMaths.h"
#import "OOTypes.h"
#include <jsapi.h>


#define GUI_DEFAULT_COLUMNS			6
#define GUI_DEFAULT_ROWS			30

#define GUI_MAX_ROWS				64
#define GUI_MAX_COLUMNS				40
#define MAIN_GUI_PIXEL_HEIGHT		480
#define MAIN_GUI_PIXEL_WIDTH		480
#define MAIN_GUI_ROW_HEIGHT			16
#define MAIN_GUI_ROW_WIDTH			16
#define MAIN_GUI_PIXEL_ROW_START	40


typedef enum
{
	GUI_ALIGN_LEFT,
	GUI_ALIGN_RIGHT,
	GUI_ALIGN_CENTER
} OOGUIAlignment;

typedef enum
{
	GUI_BACKGROUND_SPECIAL_NONE,
	GUI_BACKGROUND_SPECIAL_SHORT,
	GUI_BACKGROUND_SPECIAL_LONG,
	GUI_BACKGROUND_SPECIAL_LONG_ANA_SHORTEST,
	GUI_BACKGROUND_SPECIAL_LONG_ANA_QUICKEST
} OOGUIBackgroundSpecial;

#define GUI_KEY_OK				@"OK"
#define GUI_KEY_SKIP			@"SKIP-ROW"


@class OOSound, OOColor, OOTexture, OOTextureSprite, HeadUpDisplay;


typedef NSInteger OOGUIRow;	// -1 for none
typedef int OOGUITabStop; // negative value = right align text
typedef OOGUITabStop OOGUITabSettings[GUI_MAX_COLUMNS];


@interface GuiDisplayGen: NSObject
{
@private
	NSSize					size_in_pixels;
	unsigned				n_columns;
	unsigned				n_rows;
	int						pixel_row_center;
	unsigned				pixel_row_height;
	int						pixel_row_start;
	NSSize					pixel_text_size;
	
	BOOL					showAdvancedNavArray;
	
	NSSize					pixel_title_size;
	
	OOColor					*backgroundColor;
	OOColor					*textColor;
	
	OOTextureSprite			*backgroundSprite;
	OOTextureSprite			*foregroundSprite;
	OOGUIBackgroundSpecial	backgroundSpecial;	
	
	NSString				*title;
	
	NSMutableArray			*rowText;
	NSMutableArray			*rowKey;
	NSMutableArray			*rowColor;
	
	Vector					drawPosition;
	
	NSPoint					rowPosition[GUI_MAX_ROWS];
	OOGUIAlignment			rowAlignment[GUI_MAX_ROWS];
	float					rowFadeTime[GUI_MAX_ROWS];
	
	OOGUITabSettings		tabStops;
	
	NSRange					rowRange;
	
	OOGUIRow				selectedRow;
	NSRange					selectableRange;
	
	BOOL					showTextCursor;
	OOGUIRow				currentRow;
	
	GLfloat					max_alpha;			// main alpha setting
	GLfloat					fade_alpha;			// for fade-in / fade-out
	GLfloat					fade_sign;			//	-1.0 to 1.0
	NSUInteger				statusPage; 		// status  screen: paging equipped items
	OOSystemID				foundSystem;
}

- (id) init;
- (id) initWithPixelSize:(NSSize)gui_size
				 columns:(int)gui_cols 
					rows:(int)gui_rows 
			   rowHeight:(int)gui_row_height
				rowStart:(int)gui_row_start
				   title:(NSString*)gui_title;

- (void) resizeWithPixelSize:(NSSize)gui_size
					 columns:(int)gui_cols
						rows:(int)gui_rows
				   rowHeight:(int)gui_row_height
					rowStart:(int)gui_row_start
					   title:(NSString*) gui_title;
- (void) resizeTo:(NSSize)gui_size
  characterHeight:(int)csize
			title:(NSString*)gui_title;
- (NSSize)size;
- (unsigned)columns;
- (unsigned)rows;
- (unsigned)rowHeight;
- (int)rowStart;

- (NSString *)title;
- (void) setTitle:(NSString *)str;

- (void) dealloc;

- (void) setDrawPosition:(Vector) vector;
- (Vector) drawPosition;

- (void) fadeOutFromTime:(OOTimeAbsolute) now_time overDuration:(OOTimeDelta) duration;
- (void) stopFadeOuts;

- (GLfloat) alpha;
- (void) setAlpha:(GLfloat) an_alpha;
- (void) setMaxAlpha:(GLfloat) an_alpha;

- (void) setBackgroundColor:(OOColor*) color;

- (void) setTextColor:(OOColor*) color;

- (void) setCharacterSize:(NSSize) character_size;

- (void) setShowAdvancedNavArray:(BOOL)inFlag;

- (void) setColor:(OOColor *)color forRow:(OOGUIRow)row;

- (id) objectForRow:(OOGUIRow)row;
- (NSString *) keyForRow:(OOGUIRow)row;
- (OOGUIRow) rowForKey:(NSString*)key;
- (OOGUIRow) selectedRow;
- (BOOL) setSelectedRow:(OOGUIRow)row;
- (BOOL) setNextRow:(int) direction;
- (BOOL) setFirstSelectableRow;
- (BOOL) setLastSelectableRow;
- (void) setNoSelectedRow;
- (NSString *) selectedRowText;
- (NSString *) selectedRowKey;

- (void) setShowTextCursor:(BOOL) yesno;
- (void) setCurrentRow:(OOGUIRow) value;

- (NSRange) selectableRange;
- (void) setSelectableRange:(NSRange) range;

- (void) setTabStops:(OOGUITabSettings)stops;

- (void) clear;
- (void) clearAndKeepBackground:(BOOL)keepBackground;

- (void) setKey:(NSString *)str forRow:(OOGUIRow)row;
- (void) setText:(NSString *)str forRow:(OOGUIRow)row;
- (void) setText:(NSString *)str forRow:(OOGUIRow)row align:(OOGUIAlignment)alignment;
- (NSString *) reflowTextForMFD:(NSString *)input;
- (OOGUIRow) addLongText:(NSString *)str
		   startingAtRow:(OOGUIRow)row
				   align:(OOGUIAlignment)alignment;
- (void) printLongText:(NSString *)str
				 align:(OOGUIAlignment)alignment
				 color:(OOColor *)text_color
			  fadeTime:(float)text_fade
				   key:(NSString *)text_key
			addToArray:(NSMutableArray *)text_array;
- (void) printLineNoScroll:(NSString *)str
					 align:(OOGUIAlignment)alignment
					 color:(OOColor *)text_color
				  fadeTime:(float)text_fade
					   key:(NSString *)text_key
				addToArray:(NSMutableArray *)text_array;

- (void) setArray:(NSArray *)arr forRow:(OOGUIRow)row;

- (void) insertItemsFromArray:(NSArray *)items
					 withKeys:(NSArray *)item_keys
					  intoRow:(OOGUIRow)row
						color:(OOColor *)text_color;

/////////////////////////////////////////////////////

- (void) scrollUp:(int) how_much;

/* allows the use of special dynamic backgrounds */
- (void) setBackgroundTextureSpecial:(OOGUIBackgroundSpecial)spec withBackground:(BOOL)withBackground;

/*
	A background/foreground texture descriptor is a dictionary with a string
	property keyed "name" and optional number properties keyed "width" and
	"height".
*/

- (BOOL) setBackgroundTextureDescriptor:(NSDictionary *)descriptor;
- (BOOL) setForegroundTextureDescriptor:(NSDictionary *)descriptor;
- (BOOL) setBackgroundTextureKey:(NSString *)key;
- (BOOL) setForegroundTextureKey:(NSString *)key;

- (BOOL) preloadGUITexture:(NSDictionary *)descriptor;

/*
	Interpret a JavaScript value as a texture descriptor for
	-[GUIDisplayGen set{Background|Foreground}TextureDescriptor:]. Also starts
	preloading the texture.
	
	callerDescription is a string describing the context in which this was
	called, generally a method name (like "mission.runScreen()") for warning
	generation.
	
	Requires a request on context.
*/
- (NSDictionary *) textureDescriptorFromJSValue:(jsval)value inContext:(JSContext *)context callerDescription:(NSString *)callerDescription;

- (void) clearBackground;

- (void) leaveLastLine;
- (NSArray *) getLastLines;

- (int) drawGUI:(GLfloat) alpha drawCursor:(BOOL) drawCursor;
- (void) drawGUIBackground;
- (void) setStatusPage:(NSUInteger) pageNum;
- (NSUInteger) statusPage;
- (void) refreshStarChart;

- (Random_Seed) targetNextFoundSystem:(int)direction;

@end
