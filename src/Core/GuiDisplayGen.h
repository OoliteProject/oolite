/*

GuiDisplayGen.h

Class handling interface elements, primarily text, that are not part of the 3D
game world, together with GuiDisplayGen.

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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

#define GUI_MAX_ROWS			64
#define GUI_MAX_COLUMNS			40
#define MAIN_GUI_PIXEL_HEIGHT		480
#define MAIN_GUI_PIXEL_WIDTH		480
#define MAIN_GUI_ROW_HEIGHT			16
#define MAIN_GUI_ROW_WIDTH			16
#define MAIN_GUI_PIXEL_ROW_START	40

#define GUI_ALIGN_LEFT			0
#define GUI_ALIGN_RIGHT			1
#define GUI_ALIGN_CENTER		2

#define GUI_KEY_OK				@"OK"
#define GUI_KEY_SKIP			@"SKIP-ROW"

#import "OpenGLSprite.h"
#import "HeadUpDisplay.h"

@class OOSound, OOColor;

extern int debug;

@interface GuiDisplayGen : NSObject {

	NSSize			size_in_pixels;
	int				n_columns;
	int				n_rows;
	int				pixel_row_center;
	int				pixel_row_height;
	int				pixel_row_start;
	NSSize			pixel_text_size;
	
	BOOL			showAdvancedNavArray;
	
	BOOL			has_title;
	NSSize			pixel_title_size;
	
	OOSound			*guiclick;

#ifdef GNUSTEP
	SDLImage		*backgroundImage;
#else
	NSImage			*backgroundImage;
#endif

	OOColor			*backgroundColor;
	OOColor			*textColor;
	
	OpenGLSprite	*backgroundSprite;
	
	NSString		*title;
	
	NSMutableArray  *rowText;
	NSMutableArray  *rowKey;
	NSMutableArray  *rowColor;
	
	Vector			drawPosition;
	
	NSPoint			rowPosition[GUI_MAX_ROWS];
	int				rowAlignment[GUI_MAX_ROWS];
	float			rowFadeTime[GUI_MAX_ROWS];
	
	int				tabStops[GUI_MAX_COLUMNS];
	
	NSRange			rowRange;

	int				selectedRow;
	NSRange			selectableRange;
	
	BOOL			showTextCursor;
	int				currentRow;
	
	GLfloat			fade_alpha;			// for fade-in / fade-out
	double			fade_duration;		// period
	double			fade_from_time;		// from [universe getTime]
	GLfloat			fade_sign;			//	-1.0 to 1.0
}

- (id) init;
- (id) initWithPixelSize:(NSSize) gui_size Columns:(int) gui_cols Rows:(int) gui_rows RowHeight:(int) gui_row_height RowStart:(int) gui_row_start Title:(NSString*) gui_title;

- (void) resizeWithPixelSize:(NSSize) gui_size Columns:(int) gui_cols Rows:(int) gui_rows RowHeight:(int) gui_row_height RowStart:(int) gui_row_start Title:(NSString*) gui_title;
- (void) resizeTo:(NSSize) gui_size characterHeight:(int) csize Title:(NSString*) gui_title;
- (NSSize)	size;
- (int)	columns;
- (int)	rows;
- (int)	rowHeight;
- (int)	rowStart;
- (NSString*)	title;


- (void) dealloc;

- (void) setDrawPosition:(Vector) vector;
- (Vector) drawPosition;

- (void) fadeOutFromTime:(double) now_time OverDuration:(double) duration;

- (GLfloat) alpha;
- (void) setAlpha:(GLfloat) an_alpha;

- (void) setBackgroundColor:(OOColor*) color;

- (void) setTextColor:(OOColor*) color;

- (void) setCharacterSize:(NSSize) character_size;

- (void) click;

- (void)setShowAdvancedNavArray:(BOOL)inFlag;

- (void) setColor:(OOColor *) color forRow:(int) row;

- (id) objectForRow:(int) row;
- (NSString*) keyForRow:(int) row;
- (int) selectedRow;
- (BOOL) setSelectedRow:(int) row;
- (BOOL) setNextRow:(int) direction;
- (BOOL) setFirstSelectableRow;
- (void) setNoSelectedRow;
- (NSString *) selectedRowText;
- (NSString *) selectedRowKey;

- (void) setShowTextCursor:(BOOL) yesno;
- (void) setCurrentRow:(int) value;

- (NSRange) selectableRange;
- (void) setSelectableRange:(NSRange) range;

- (void) setTabStops:(int *)stops;

- (void) clear;

- (void) setTitle: (NSString *) str;

- (void) setKey: (NSString *) str forRow:(int) row;
- (void) setText: (NSString *) str forRow:(int) row;
- (void) setText: (NSString *) str forRow:(int) row align:(int) alignment;
- (int) addLongText: (NSString *) str startingAtRow:(int) row align:(int) alignment;
- (void) printLongText: (NSString *) str Align:(int) alignment Color:(OOColor*) text_color FadeTime:(float) text_fade Key:(NSString*) text_key AddToArray:(NSMutableArray*) text_array;
- (void) printLineNoScroll: (NSString *) str Align:(int) alignment Color:(OOColor*) text_color FadeTime:(float) text_fade Key:(NSString*) text_key AddToArray:(NSMutableArray*) text_array;

- (void) setArray: (NSArray *) arr forRow:(int) row;

- (void) insertItemsFromArray:(NSArray*) items WithKeys:(NSArray*) item_keys IntoRow:(int) row Color:(OOColor*) text_color;

/////////////////////////////////////////////////////

- (void) scrollUp:(int) how_much;

#ifdef GNUSTEP
- (void) setBackgroundImage:(SDLImage *) bg_image;
#else
- (void) setBackgroundImage:(NSImage *) bg_image;
#endif

- (int) drawGUI:(GLfloat) alpha drawCursor:(BOOL) drawCursor;
- (int) drawGUI:(GLfloat)x :(GLfloat)y :(GLfloat)z :(GLfloat) alpha drawCursor:(BOOL) drawCursor;
- (void) drawGUI:(GLfloat)x :(GLfloat)y :(GLfloat)z :(GLfloat) alpha;

- (void) drawGLDisplay:(GLfloat)x :(GLfloat)y :(GLfloat)z :(GLfloat) alpha;

- (void) drawStarChart:(GLfloat)x :(GLfloat)y :(GLfloat)z :(GLfloat) alpha;
- (void) drawGalaxyChart:(GLfloat)x :(GLfloat)y :(GLfloat)z :(GLfloat) alpha;

- (void) drawAdvancedNavArrayAtX:(float)x y:(float)y z:(float)z alpha:(float)alpha;

@end
