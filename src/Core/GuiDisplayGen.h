//
//  GuiDisplayGen.h
/*
 *
 *  Oolite
 *
 *  Created by Giles Williams on Sat Apr 03 2004.
 *  Copyright (c) 2004 for aegidian.org. All rights reserved.
 *

Copyright (c) 2004, Giles C Williams
All rights reserved.

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Noncommercial. You may not use this work for commercial purposes.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

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

@class Universe, OOSound;

extern int debug;

@interface GuiDisplayGen : NSObject {

	NSSize			size_in_pixels;
	int				n_columns;
	int				n_rows;
	int				pixel_row_center;
	int				pixel_row_height;
	int				pixel_row_start;
	NSSize			pixel_text_size;
	
	BOOL			has_title;
	NSSize			pixel_title_size;
	
	OOSound			*guiclick;

	NSImage			*backgroundImage;
	NSColor			*backgroundColor;
	NSColor			*textColor;
	
	OpenGLSprite	*backgroundSprite;
	
	NSString		*title;
	
	NSMutableArray  *rowText;
	NSMutableArray  *rowKey;
	NSMutableArray  *rowColor;
	
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

- (void) dealloc;

- (void) fadeOutFromTime:(double) now_time OverDuration:(double) duration;

- (GLfloat) alpha;
- (void) setAlpha:(GLfloat) an_alpha;

- (void) setBackgroundColor:(NSColor*) color;

- (void) setTextColor:(NSColor*) color;

- (void) setCharacterSize:(NSSize) character_size;

- (void) click;

- (void) setColor:(NSColor *) color forRow:(int) row;

- (id) objectForRow:(int) row;
- (NSString*) keyForRow:(int) row;
- (int) selectedRow;
- (BOOL) setSelectedRow:(int) row;
- (BOOL) setNextRow:(int) direction;
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
- (void) printLongText: (NSString *) str Align:(int) alignment Color:(NSColor*) text_color FadeTime:(float) text_fade Key:(NSString*) text_key AddToArray:(NSMutableArray*) text_array;
- (void) printLineNoScroll: (NSString *) str Align:(int) alignment Color:(NSColor*) text_color FadeTime:(float) text_fade Key:(NSString*) text_key AddToArray:(NSMutableArray*) text_array;

- (void) setArray: (NSArray *) arr forRow:(int) row;

- (void) insertItemsFromArray:(NSArray*) items WithKeys:(NSArray*) item_keys IntoRow:(int) row Color:(NSColor*) text_color;

/////////////////////////////////////////////////////

- (void) scrollUp:(int) how_much;

- (void) setBackgroundImage:(NSImage *) bg_image;

- (void) drawGUI:(GLfloat) x :(GLfloat) y :(GLfloat) z :(GLfloat) alpha forUniverse:(Universe*) universe;

- (void) drawGLDisplay:(GLfloat) x :(GLfloat) y :(GLfloat) z :(GLfloat) alpha forUniverse:(Universe*) universe;

- (void) drawStarChart:(GLfloat) x:(GLfloat) y:(GLfloat) z:(GLfloat) alpha forUniverse:(Universe*) universe;
- (void) drawGalaxyChart:(GLfloat) x:(GLfloat) y:(GLfloat) z:(GLfloat) alpha forUniverse:(Universe*) universe;

@end
