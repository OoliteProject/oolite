/*

GuiDisplayGen.m

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

#import "GuiDisplayGen.h"
#import "Universe.h"
#import "PlayerEntity.h"
#import "OpenGLSprite.h"
#import "ResourceManager.h"
#import "OOSound.h"
#import "OOStringParsing.h"
#import "HeadUpDisplay.h"


@implementation GuiDisplayGen

- (id) init
{
	self = [super init];
		
	size_in_pixels  = NSMakeSize( MAIN_GUI_PIXEL_WIDTH, MAIN_GUI_PIXEL_HEIGHT);
	n_columns		= 6;
	n_rows			= 24;
	pixel_row_center = size_in_pixels.width / 2;
	pixel_row_height = MAIN_GUI_ROW_HEIGHT;
	pixel_row_start	= MAIN_GUI_PIXEL_ROW_START;		// first position down the page...

	pixel_text_size = NSMakeSize( 0.9 * pixel_row_height, pixel_row_height);	// main gui has 18x20 characters
	
	has_title		= YES;
	pixel_title_size = NSMakeSize( pixel_row_height * 1.75, pixel_row_height * 1.5);
	
	int stops[6] = {0, 192, 256, 320, 384, 448};
	int i;
	
	rowRange = NSMakeRange(0,n_rows);

	rowText =   [[NSMutableArray alloc] initWithCapacity:n_rows];   // alloc retains
	rowKey =	[[NSMutableArray alloc] initWithCapacity:n_rows];   // alloc retains
	rowColor =	[[NSMutableArray alloc] initWithCapacity:n_rows];   // alloc retains
	
	for (i = 0; i < n_rows; i++)
	{
		[rowText addObject:@"."];
		[rowKey addObject:[NSString stringWithFormat:@"%d",i]];
		[rowColor addObject:[OOColor yellowColor]];
		rowPosition[i].x = 0.0;
		rowPosition[i].y = size_in_pixels.height - (pixel_row_start + i * pixel_row_height);
		rowAlignment[i] = GUI_ALIGN_LEFT;
	}
	
	for (i = 0; i < n_columns; i++)
	{
		tabStops[i] = stops[i];
	}
	
	title = @"Test Page";
	
	guiclick =  [[ResourceManager ooSoundNamed:@"guiclick.ogg" inFolder:@"Sounds"] retain];
	
	textColor = [[OOColor yellowColor] retain];
	
	drawPosition = make_vector( 0.0, 0.0, 640.0);

	return self;
}

- (id) initWithPixelSize:(NSSize) gui_size Columns:(int) gui_cols Rows:(int) gui_rows RowHeight:(int) gui_row_height RowStart:(int) gui_row_start Title:(NSString*) gui_title
{
	self = [super init];
		
	size_in_pixels  = gui_size;
	n_columns		= gui_cols;
	n_rows			= gui_rows;
	pixel_row_center = size_in_pixels.width / 2;
	pixel_row_height = gui_row_height;
	pixel_row_start	= gui_row_start;		// first position down the page...

	pixel_text_size = NSMakeSize( pixel_row_height, pixel_row_height);
	
	has_title		= (gui_title != nil);
	pixel_title_size = NSMakeSize( pixel_row_height * 1.75, pixel_row_height * 1.5);
	
	int i;
	
	rowRange = NSMakeRange(0,n_rows);

	rowText =   [[NSMutableArray alloc] initWithCapacity:n_rows];   // alloc retains
	rowKey =	[[NSMutableArray alloc] initWithCapacity:n_rows];   // alloc retains
	rowColor =	[[NSMutableArray alloc] initWithCapacity:n_rows];   // alloc retains
	
	for (i = 0; i < n_rows; i++)
	{
		[rowText addObject:@""];
		[rowKey addObject:@""];
		[rowColor addObject:[OOColor greenColor]];
		rowPosition[i].x = 0.0;
		rowPosition[i].y = size_in_pixels.height - (pixel_row_start + i * pixel_row_height);
		rowAlignment[i] = GUI_ALIGN_LEFT;
	}
	
	title = [gui_title retain];
	
	guiclick =  [[ResourceManager ooSoundNamed:@"guiclick.ogg" inFolder:@"Sounds"] retain];
	
	textColor = [[OOColor yellowColor] retain];

	return self;
}

- (void) resizeWithPixelSize:(NSSize) gui_size Columns:(int) gui_cols Rows:(int) gui_rows RowHeight:(int) gui_row_height RowStart:(int) gui_row_start Title:(NSString*) gui_title
{
	[self clear];
	//
	size_in_pixels  = gui_size;
	n_columns		= gui_cols;
	n_rows			= gui_rows;
	pixel_row_center = size_in_pixels.width / 2;
	pixel_row_height = gui_row_height;
	pixel_row_start	= gui_row_start;		// first position down the page...

	pixel_text_size = NSMakeSize( pixel_row_height, pixel_row_height);
	pixel_title_size = NSMakeSize( pixel_row_height * 1.75, pixel_row_height * 1.5);

	rowRange = NSMakeRange(0,n_rows);
	[self clear];
	//
	[self setTitle: gui_title];
}

- (void) resizeTo:(NSSize) gui_size characterHeight:(int) csize Title:(NSString*) gui_title
{
	[self clear];
	//
	size_in_pixels  = gui_size;
	n_columns		= gui_size.width / csize;
	n_rows			= (int)gui_size.height / csize;

	[self setTitle: gui_title];
	
	pixel_row_center = gui_size.width / 2;
	pixel_row_height = csize;
	currentRow = n_rows - 1;		// first position down the page...

	if (has_title)
		pixel_row_start = 2.75 * csize + 0.5 * (gui_size.height - n_rows * csize);
	else
		pixel_row_start = csize + 0.5 * (gui_size.height - n_rows * csize);

	[rowText removeAllObjects];
	[rowKey removeAllObjects];
	[rowColor removeAllObjects];

	int i;
	for (i = 0; i < n_rows; i++)
	{
		[rowText addObject:@""];
		[rowKey addObject:@""];
		[rowColor addObject:[OOColor greenColor]];
		rowPosition[i].x = 0.0;
		rowPosition[i].y = size_in_pixels.height - (pixel_row_start + i * pixel_row_height);
		rowAlignment[i] = GUI_ALIGN_LEFT;
	}

	pixel_text_size = NSMakeSize( csize, csize);
	pixel_title_size = NSMakeSize( csize * 1.75, csize * 1.5);
	
	OOLog(@"gui.reset", @"gui %@ reset to rows:%d columns:%d start:%d", self, n_rows, n_columns, pixel_row_start);

	rowRange = NSMakeRange(0,n_rows);
	[self clear];
}

- (NSSize)	size
{
	return size_in_pixels;
}
- (int)	columns
{
	return n_columns;
}
- (int)	rows
{
	return n_rows;
}
- (int)	rowHeight
{
	return pixel_row_height;
}
- (int)	rowStart
{
	return pixel_row_start;
}
- (NSString*)	title
{
	return title;
}

- (void) dealloc
{
	[backgroundSprite release];
	[backgroundColor release];
	[textColor release];
	[title release];
	[rowText release];
	[rowKey release];
	[rowColor release];
	
	[super dealloc];
}

- (void) setDrawPosition:(Vector) vector
{
	drawPosition = vector;
}

- (Vector) drawPosition
{
	return drawPosition;
}

- (void) fadeOutFromTime:(double) now_time OverDuration:(double) duration
{
	if (fade_alpha <= 0.0)
		return;
	fade_sign = -fade_alpha / duration;
	fade_from_time = now_time;
	fade_duration = duration;
}

- (GLfloat) alpha
{
	return fade_alpha;
}

- (void) setAlpha:(GLfloat) an_alpha
{
	fade_alpha = an_alpha;
}

- (void) setBackgroundColor:(OOColor*) color
{
	if (backgroundColor)	[backgroundColor release];
	if (color == nil)
	{
		backgroundColor = nil;
		return;
	}

	backgroundColor = [color retain];
}

- (void) setTextColor:(OOColor*) color
{
	if (textColor)	[textColor release];
	if (color == nil)
	{
		textColor = [[OOColor yellowColor] retain];
		return;
	}

	textColor = [color retain];
}

- (void) setCharacterSize:(NSSize) character_size
{
	pixel_text_size = character_size;
}

- (void) click
{
	if ([guiclick isPlaying])  [guiclick stop];
	[guiclick play];
}

- (void)setShowAdvancedNavArray:(BOOL)inFlag
{
	showAdvancedNavArray = inFlag;
}

- (void) setColor:(OOColor *) color forRow:(int) row
{
	if ((row >= rowRange.location)&&(row < rowRange.location + rowRange.length))
		[rowColor replaceObjectAtIndex:row withObject:color];
}

- (id) objectForRow:(int) row
{
	if ((row >= rowRange.location)&&(row < rowRange.location + rowRange.length))
		return [rowText objectAtIndex:row];
	else
		return NULL;
}

- (NSString*) keyForRow:(int) row
{
	if ((row >= rowRange.location)&&(row < rowRange.location + rowRange.length))
		return [rowKey objectAtIndex:row];
	else
		return NULL;
}

- (int) selectedRow
{
	if ((selectedRow >= selectableRange.location) && (selectedRow < selectableRange.location+selectableRange.length))
		return selectedRow;
	else
		return -1;
}

- (BOOL) setSelectedRow:(int) row
{
	if ((row == selectedRow)&&(row >= selectableRange.location)&&(row < selectableRange.location+selectableRange.length))
		return YES;
	if ((row >= selectableRange.location) && (row < selectableRange.location+selectableRange.length))
	{
		if (![[rowKey objectAtIndex:row] isEqual:GUI_KEY_SKIP])
		{
			selectedRow = row;
			return YES;
		}
	}
	return NO;
}

- (BOOL) setNextRow:(int) direction
{
	int row = selectedRow + direction;
	while ((row >= selectableRange.location) && (row < selectableRange.location+selectableRange.length))
	{
		if (![[rowKey objectAtIndex:row] isEqual:GUI_KEY_SKIP])
		{
			selectedRow = row;
			return YES;
		}
		row += direction;
	}
	return NO;
}

- (BOOL) setFirstSelectableRow
{
	int row = selectableRange.location;
	while ((row >= selectableRange.location) && (row < selectableRange.location+selectableRange.length))
	{
		if (![[rowKey objectAtIndex:row] isEqual:GUI_KEY_SKIP])
		{
			selectedRow = row;
			return YES;
		}
		row++;
	}
	selectedRow = -1;
	return NO;
}

- (void) setNoSelectedRow
{
	selectedRow = -1;
}

- (NSString *) selectedRowText
{
	if ([[rowText objectAtIndex:selectedRow] isKindOfClass:[NSString class]])
		return (NSString *)[rowText objectAtIndex:selectedRow];
	if ([[rowText objectAtIndex:selectedRow] isKindOfClass:[NSArray class]])
		return (NSString *)[[rowText objectAtIndex:selectedRow] objectAtIndex:0];
	return NULL;
}

- (NSString *) selectedRowKey
{
	if ((selectedRow < 0)||(selectedRow > [rowKey count]))
		return nil;
	else
		return (NSString *)[rowKey objectAtIndex:selectedRow];
}

- (void) setShowTextCursor:(BOOL) yesno
{
	showTextCursor = yesno;
}

- (void) setCurrentRow:(int) value
{
	if ((value < 0)||(value >= n_rows))
	{
		showTextCursor = NO;
		currentRow = -1;
	}
	else
	{
		currentRow = value;
	}
}

- (NSRange) selectableRange
{
	return selectableRange;
}

- (void) setSelectableRange:(NSRange) range
{
	selectableRange = range;
}

- (void) setTabStops:(int *)stops
{
	int i = 0;
	for (i = 0; i < n_columns; i++)
		tabStops[i] = stops[i];
}


- (void) clear
{
	int i;
	[self setTitle: nil];
	for (i = 0; i < n_rows; i++)
	{
		[self setText:@"" forRow:i align:GUI_ALIGN_LEFT];
		[self setColor:textColor forRow:i];
		//
		[self setKey:GUI_KEY_SKIP forRow:i];
		//
		rowFadeTime[i] = 0.0;
	}
	[self setShowTextCursor:NO];
	[self setSelectableRange:NSMakeRange(0,0)];
}

- (void) setTitle: (NSString *) str
{
	if (title)  [title release];
	
	if (str)
	{
		title = [str retain];
		has_title = ![str isEqual:@""];
	}
	else
	{
		title = nil;
		has_title = NO;
	}
}

- (void) setKey: (NSString *) str forRow:(int) row
{
	if ((row >= rowRange.location)&&(row < rowRange.location + rowRange.length))
		[rowKey replaceObjectAtIndex:row withObject:str];
}

- (void) setText: (NSString *) str forRow:(int) row
{
	if ((row >= rowRange.location)&&(row < rowRange.location+rowRange.length))
	{
		[rowText replaceObjectAtIndex:row withObject:str];
	}
}

- (void) setText: (NSString *) str forRow:(int) row align:(int) alignment
{
	if (str != nil && row >= rowRange.location && row < rowRange.location+rowRange.length)
	{
		[rowText replaceObjectAtIndex:row withObject:str];
		rowAlignment[row] = alignment;
	}
}

- (int) addLongText: (NSString *) str startingAtRow:(int) row align:(int) alignment
{
	NSSize chSize = pixel_text_size;
	NSSize strsize = rectForString( str, 0.0, 0.0, chSize).size;
	if (strsize.width < size_in_pixels.width)
	{
		[self setText:str forRow:row align:alignment];
		return row + 1;
	}
	else
	{
		NSMutableArray	*words = ScanTokensFromString(str);
		NSMutableString	*string1 = [NSMutableString stringWithCapacity:256];
		NSMutableString	*string2 = [NSMutableString stringWithCapacity:256];
		strsize.width = 0.0;
		while ((strsize.width < size_in_pixels.width)&&([words count] > 0))
		{
			[string1 appendString:(NSString *)[words objectAtIndex:0]];
			[string1 appendString:@" "];
			[words removeObjectAtIndex:0];
			strsize = rectForString( string1, 0.0, 0.0, chSize).size;
			if ([words count] > 0)
				strsize.width += rectForString( (NSString *)[words objectAtIndex:0], 0.0, 0.0, chSize).size.width;
		}
		[string2 appendString:[words componentsJoinedByString:@" "]];
		[self setText:string1		forRow:row			align:alignment];
		return  [self addLongText:string2   startingAtRow:row+1	align:alignment];
	}
}

- (void) printLongText: (NSString *) str Align:(int) alignment Color:(OOColor*) text_color FadeTime:(float) text_fade Key:(NSString*) text_key AddToArray:(NSMutableArray*) text_array
{
	// print a multi-line message
	//
	if ([str rangeOfString:@"\n"].location != NSNotFound)
	{
		NSArray*	lines = [str componentsSeparatedByString:@"\n"];
		int	i;
		for (i = 0; i < [lines count]; i++)
			[self printLongText:(NSString *)[lines objectAtIndex:i] Align:alignment Color:text_color FadeTime:text_fade Key:text_key AddToArray:text_array];
		return;
	}
	
	int row = currentRow;
	if (row == n_rows - 1)
		[self scrollUp:1];
	NSSize chSize = pixel_text_size;
	NSSize strsize = rectForString( str, 0.0, 0.0, chSize).size;
	if (strsize.width < size_in_pixels.width)
	{
		[self setText:str forRow:row align:alignment];
		if (text_color)
			[self setColor:text_color forRow:row];
		if (text_key)
			[self setKey:text_key forRow:row];
		if (text_array)
			[text_array addObject:str];
		rowFadeTime[row] = text_fade;
		if (currentRow < n_rows - 1)
			currentRow++;
	}
	else
	{
		NSMutableArray	*words = ScanTokensFromString(str);
		NSMutableString	*string1 = [NSMutableString stringWithCapacity:256];
		NSMutableString	*string2 = [NSMutableString stringWithCapacity:256];
		strsize.width = 0.0;
		while ((strsize.width < size_in_pixels.width)&&([words count] > 0))
		{
			[string1 appendString:(NSString *)[words objectAtIndex:0]];
			[string1 appendString:@" "];
			[words removeObjectAtIndex:0];
			strsize = rectForString( string1, 0.0, 0.0, chSize).size;
			if ([words count] > 0)
				strsize.width += rectForString( (NSString *)[words objectAtIndex:0], 0.0, 0.0, chSize).size.width;
		}
		[string2 appendString:[words componentsJoinedByString:@" "]];
		[self setText:string1		forRow:row			align:alignment];
		if (text_color)
			[self setColor:text_color forRow:row];
		if (text_key)
			[self setKey:text_key forRow:row];
		if (text_array)
			[text_array addObject:string1];
		rowFadeTime[row] = text_fade;
		[self printLongText:string2 Align:alignment Color:text_color FadeTime:text_fade Key:text_key AddToArray:text_array];
	}
}

- (void) printLineNoScroll: (NSString *) str Align:(int) alignment Color:(OOColor*) text_color FadeTime:(float) text_fade Key:(NSString*) text_key AddToArray:(NSMutableArray*) text_array
{
	[self setText:str forRow:currentRow align:alignment];
	if (text_color)
		[self setColor:text_color forRow:currentRow];
	if (text_key)
		[self setKey:text_key forRow:currentRow];
	if (text_array)
		[text_array addObject:str];
	rowFadeTime[currentRow] = text_fade;
}


- (void) setArray: (NSArray *) arr forRow:(int) row
{
	if ((row >= rowRange.location)&&(row < rowRange.length))
		[rowText replaceObjectAtIndex:row withObject:arr];
}

- (void) insertItemsFromArray:(NSArray*) items WithKeys:(NSArray*) item_keys IntoRow:(int) row Color:(OOColor*) text_color
{
	if (!items)
		return;
	if([items count] == 0)
		return;
	int n_items = [items count];
	if ((item_keys)&&([item_keys count] != n_items))
	{
		// throw exception
		NSException* myException = [NSException
			exceptionWithName:@"ArrayLengthMismatchException"
			reason:@"The NSArray sent as 'item_keys' to insertItemsFromArray::: must contain the same number of objects as the NSArray 'items'"
			userInfo:nil];
		[myException raise];
		return;
	}

	int i;
	for (i = n_rows; i >= row + n_items ; i--)
	{
		[self setKey:[self keyForRow:i - n_items] forRow:i];
		id	old_row_info = [self objectForRow:i - n_items];
		if ([old_row_info isKindOfClass:[NSArray class]])
			[self setArray:old_row_info forRow:i];
		if ([old_row_info isKindOfClass:[NSString class]])
			[self setText:(NSString *)old_row_info forRow:i];
	}
	for (i = 0; i < n_items; i++)
	{
		id new_row_info = [items objectAtIndex:i];
		if (text_color)
			[self setColor:text_color forRow: row + i];
		else
			[self setColor:textColor forRow: row + i];
		if ([new_row_info isKindOfClass:[NSArray class]])
			[self setArray:new_row_info forRow: row + i];
		if ([new_row_info isKindOfClass:[NSString class]])
			[self setText:(NSString *)new_row_info forRow: row + i];
		if (item_keys)
			[self setKey:[item_keys objectAtIndex:i] forRow: row + i];
		else
			[self setKey:@"" forRow: row + i];
	}
}

- (void) scrollUp:(int) how_much
{
	int i;
	for (i = 0; i + how_much < n_rows; i++)
	{
		[rowText	replaceObjectAtIndex:i withObject:[rowText objectAtIndex:	i + how_much]];
		[rowColor	replaceObjectAtIndex:i withObject:[rowColor objectAtIndex:	i + how_much]];
		[rowKey		replaceObjectAtIndex:i withObject:[rowKey objectAtIndex:	i + how_much]];
		rowAlignment[i] = rowAlignment[i + how_much];
		rowFadeTime[i]	= rowFadeTime[i + how_much];
	}
	for (; i < n_rows; i++)
	{
		[rowText	replaceObjectAtIndex:i withObject:@""];
		[rowColor	replaceObjectAtIndex:i withObject:textColor];
		[rowKey		replaceObjectAtIndex:i withObject:@""];
		rowAlignment[i] = GUI_ALIGN_LEFT;
		rowFadeTime[i]	= 0.0;
	}
}


- (void)setBackgroundTexture:(OOTexture *)backgroundTexture
{
	[backgroundSprite release];
	backgroundSprite = nil;
	
	if (backgroundTexture != nil)
	{
		backgroundSprite = [[OpenGLSprite alloc] initWithTexture:backgroundTexture];
	}
}


- (void)clearBackground
{
	[self setBackgroundTexture:nil];
}


- (void) drawEqptList: (NSArray *)eqptList
{
	int 		eqpt_items_per_column = 12;	// Default value.
	int i;
	
	if (eqptList == nil) return;	
	
	int		equipment_list_items_count = [eqptList count];
	
	// Nikos - Draw the equipment list.
	// How it works: By default we have two columns of 12 items each, for a total of 24. If the player has
	// acquired more than 24 equipment items, the total number of items in the player's posession is checked
	// for oddness/evenness. If it is odd (e.g. for 25 items), then the number of items per column becomes
	// the total number of inventory items over 2 plus 1. If it is even, then number of items per column will
	// be total number of inventory items over 2. So, for example, in the case of 25 or 26 inventory items,
	// this will create two columns, each capable of holding 13 items. For 27 or 28 items, we will have two
	// columns of capacity 14 each. This approach was chosen because it simulates the original equipment list
	// behavior best.
	
	if (equipment_list_items_count > eqpt_items_per_column * 2)
	{
		eqpt_items_per_column = (equipment_list_items_count % 2 == 1) ? 
						(equipment_list_items_count / 2) + 1 :
						 equipment_list_items_count / 2;
	}
	
	for (i=0; i < equipment_list_items_count; i++)
	{
		// Damaged items in the equipment list appear in orange color.
		BOOL is_eqpt_damaged = [[eqptList objectAtIndex:i] hasSuffix:@"(N/A)"];
		if (is_eqpt_damaged == YES) glColor4f (1.0, 0.5, 0.0, 1.0);
		
		if (i < eqpt_items_per_column)
		{
			drawString ([eqptList objectAtIndex:i], -220, 40 - (15 * i), 640, NSMakeSize(15,15));
		}
		else
		{
			drawString ([eqptList objectAtIndex:i], 50, 40 - (15 * (i - eqpt_items_per_column)), 640, NSMakeSize(15,15));
		}
		glColor4f (1.0, 1.0, 0.0, 1.0);		// Reset text color to yellow.
	}
}


- (int) drawGUI:(GLfloat) alpha drawCursor:(BOOL) drawCursor
{
	GLfloat z1 = [[UNIVERSE gameView] display_z];
	if (alpha > 0.05)
	{
		PlayerEntity* player = [PlayerEntity sharedPlayer];

		[self drawGLDisplay: drawPosition.x - 0.5 * size_in_pixels.width :drawPosition.y - 0.5 * size_in_pixels.height :z1 :alpha];

		glEnable(GL_LINE_SMOOTH);

		if (self == [UNIVERSE gui])
		{
			if ([player gui_screen] == GUI_SCREEN_SHORT_RANGE_CHART)
				[self drawStarChart:drawPosition.x - 0.5 * size_in_pixels.width :drawPosition.y - 0.5 * size_in_pixels.height :z1 :alpha];
			if ([player gui_screen] == GUI_SCREEN_LONG_RANGE_CHART)
			{
				[self drawGalaxyChart:drawPosition.x - 0.5 * size_in_pixels.width :drawPosition.y - 0.5 * size_in_pixels.height :z1 :alpha];
			}
			if ([player gui_screen] == GUI_SCREEN_STATUS)
			{
				[self drawEqptList:[player equipmentList]];
			}
		}
		
		if (fade_sign)
		{
			fade_alpha += fade_sign * [UNIVERSE getTimeDelta];
			if (fade_alpha < 0.0)	// done fading out
			{
				fade_alpha = 0.0;
				fade_sign = 0.0;
			}
			if (fade_alpha > 1.0)	// done fading in
			{
				fade_alpha = 1.0;
				fade_sign = 0.0;
			}
		}
	}
	
	int cursor_row = 0;

	if (drawCursor)
	{
		NSPoint vjpos = [[UNIVERSE gameView] virtualJoystickPosition];
		double cursor_x = size_in_pixels.width * vjpos.x;
		if (cursor_x < -size_in_pixels.width * 0.5)  cursor_x = -size_in_pixels.width * 0.5;
		if (cursor_x > size_in_pixels.width * 0.5)   cursor_x = size_in_pixels.width * 0.5;
		double cursor_y = -size_in_pixels.height * vjpos.y;
		if (cursor_y < -size_in_pixels.height * 0.5)  cursor_y = -size_in_pixels.height * 0.5;
		if (cursor_y > size_in_pixels.height * 0.5)   cursor_y = size_in_pixels.height * 0.5;
		
		[[UNIVERSE gameView] setVirtualJoystick:cursor_x/size_in_pixels.width :-cursor_y/size_in_pixels.height];
		cursor_row = 1 + floor((0.5 * size_in_pixels.height - pixel_row_start - cursor_y) / pixel_row_height);
		
		GLfloat h1 = 3.0f;
		GLfloat h3 = 9.0f;
		glColor4f( 0.2f, 0.2f, 1.0f, 0.5f);
		glLineWidth( 2.0f);
		cursor_x += drawPosition.x;
		cursor_y += drawPosition.y;
		glBegin(GL_LINES);
			glVertex3f( cursor_x - h1, cursor_y, z1);	glVertex3f( cursor_x - h3, cursor_y, z1);
			glVertex3f( cursor_x + h1, cursor_y, z1);	glVertex3f( cursor_x + h3, cursor_y, z1);
			glVertex3f( cursor_x, cursor_y - h1, z1);	glVertex3f( cursor_x, cursor_y - h3, z1);
			glVertex3f( cursor_x, cursor_y + h1, z1);	glVertex3f( cursor_x, cursor_y + h3, z1);
		glEnd();
		glLineWidth( 1.0f);
	}
	
	return cursor_row;
}

- (int) drawGUI:(GLfloat)x :(GLfloat)y :(GLfloat)z :(GLfloat) alpha drawCursor:(BOOL) drawCursor
{
	GLfloat z1 = [[UNIVERSE gameView] display_z];
	if (alpha > 0.05)
	{

		PlayerEntity* player = [PlayerEntity sharedPlayer];

		[self drawGLDisplay:x - 0.5 * size_in_pixels.width :y - 0.5 * size_in_pixels.height :z :alpha];

		glEnable(GL_LINE_SMOOTH);

		if (self == [UNIVERSE gui])
		{
			if ([player gui_screen] == GUI_SCREEN_SHORT_RANGE_CHART)
				[self drawStarChart:x - 0.5 * size_in_pixels.width :y - 0.5 * size_in_pixels.height :z :alpha];
			if ([player gui_screen] == GUI_SCREEN_LONG_RANGE_CHART)
			{
				[self drawGalaxyChart:x - 0.5 * size_in_pixels.width :y - 0.5 * size_in_pixels.height :z :alpha];
			}
			if ([player gui_screen] == GUI_SCREEN_STATUS)
			{
				[self drawEqptList:[player equipmentList]];
			}
		}
		
		if (fade_sign)
		{
			fade_alpha += fade_sign * [UNIVERSE getTimeDelta];
			if (fade_alpha < 0.0)	// done fading out
			{
				fade_alpha = 0.0;
				fade_sign = 0.0;
			}
			if (fade_alpha > 1.0)	// done fading in
			{
				fade_alpha = 1.0;
				fade_sign = 0.0;
			}
		}
	}
	
	int cursor_row = 0;

	if (drawCursor)
	{
		NSPoint vjpos = [[UNIVERSE gameView] virtualJoystickPosition];
		double cursor_x = size_in_pixels.width * vjpos.x;
		if (cursor_x < -size_in_pixels.width * 0.5)  cursor_x = -size_in_pixels.width * 0.5;
		if (cursor_x > size_in_pixels.width * 0.5)   cursor_x = size_in_pixels.width * 0.5;
		double cursor_y = -size_in_pixels.height * vjpos.y;
		if (cursor_y < -size_in_pixels.height * 0.5)  cursor_y = -size_in_pixels.height * 0.5;
		if (cursor_y > size_in_pixels.height * 0.5)   cursor_y = size_in_pixels.height * 0.5;
		
		cursor_row = 1 + floor((0.5 * size_in_pixels.height - pixel_row_start - cursor_y) / pixel_row_height);
		
		GLfloat h1 = 3.0f;
		GLfloat h3 = 9.0f;
		glColor4f( 0.2f, 0.2f, 1.0f, 0.5f);
		glLineWidth( 2.0f);
		glBegin(GL_LINES);
			glVertex3f( cursor_x - h1, cursor_y, z1);	glVertex3f( cursor_x - h3, cursor_y, z1);
			glVertex3f( cursor_x + h1, cursor_y, z1);	glVertex3f( cursor_x + h3, cursor_y, z1);
			glVertex3f( cursor_x, cursor_y - h1, z1);	glVertex3f( cursor_x, cursor_y - h3, z1);
			glVertex3f( cursor_x, cursor_y + h1, z1);	glVertex3f( cursor_x, cursor_y + h3, z1);
		glEnd();
		glLineWidth( 1.0f);
		
		[[UNIVERSE gameView] setVirtualJoystick:cursor_x/size_in_pixels.width :-cursor_y/size_in_pixels.height];
	}
	
	return cursor_row;
}

- (void) drawGUI:(GLfloat)x :(GLfloat)y :(GLfloat)z :(GLfloat) alpha
{
	if (alpha < 0.05)
		return;			// too dim to see!

	PlayerEntity* player = [PlayerEntity sharedPlayer];

	[self drawGLDisplay:x - 0.5 * size_in_pixels.width :y - 0.5 * size_in_pixels.height :z :alpha];

	glEnable(GL_LINE_SMOOTH);

	if (self == [UNIVERSE gui])
	{
		if ([player gui_screen] == GUI_SCREEN_SHORT_RANGE_CHART)
			[self drawStarChart:x - 0.5 * size_in_pixels.width :y - 0.5 * size_in_pixels.height :z :alpha];
		if ([player gui_screen] == GUI_SCREEN_LONG_RANGE_CHART)
		{
			[self drawGalaxyChart:x - 0.5 * size_in_pixels.width :y - 0.5 * size_in_pixels.height :z :alpha];
		}
		if ([player gui_screen] == GUI_SCREEN_STATUS)
		{
			[self drawEqptList:[player equipmentList]];
		}
	}
	
	if (fade_sign)
	{
		fade_alpha += fade_sign * [UNIVERSE getTimeDelta];
		if (fade_alpha < 0.0)	// done fading out
		{
			fade_alpha = 0.0;
			fade_sign = 0.0;
		}
		if (fade_alpha > 1.0)	// done fading in
		{
			fade_alpha = 1.0;
			fade_sign = 0.0;
		}
	}
}


- (void) drawGLDisplay:(GLfloat)x :(GLfloat)y :(GLfloat)z :(GLfloat) alpha
{
	NSSize  strsize;
	int i;
	double	delta_t = [UNIVERSE getTimeDelta];
	NSSize characterSize = pixel_text_size;
	NSSize titleCharacterSize = pixel_title_size;
	
	// do backdrop
	//
	if (backgroundColor)
	{
		glColor4f( [backgroundColor redComponent], [backgroundColor greenComponent], [backgroundColor blueComponent], alpha * [backgroundColor alphaComponent]);
		glBegin(GL_QUADS);
			glVertex3f( x + 0.0,					y + 0.0,					z);
			glVertex3f( x + size_in_pixels.width,	y + 0.0,					z);
			glVertex3f( x + size_in_pixels.width,	y + size_in_pixels.height,	z);
			glVertex3f( x + 0.0,					y + size_in_pixels.height,	z);
		glEnd();
	}
	
	// show background image...
	//
	if (backgroundSprite)
	{
		[backgroundSprite blitCentredToX:x + 0.5 * size_in_pixels.width Y:y + 0.5 * size_in_pixels.height Z:z Alpha:alpha];
	}
	
	if ((selectedRow < selectableRange.location)||(selectedRow >= selectableRange.location + selectableRange.length))
		selectedRow = -1;   // out of Range;
	
    ////
	// drawing operations here
	
	if (has_title)
	{
		//
		// draw the title
		//
		strsize = rectForString(title, 0.0, 0.0, titleCharacterSize).size;
		glColor4f( 1.0, 0.0, 0.0, alpha);	// red
		drawString( title, x + pixel_row_center - strsize.width/2.0, y + size_in_pixels.height - pixel_title_size.height, z, titleCharacterSize);
		
		// draw a horizontal divider
		//
		glColor4f( 0.75, 0.75, 0.75, alpha);	// 75% gray
		glBegin( GL_QUADS);
			glVertex3f( x + 0,					y + size_in_pixels.height - pixel_title_size.height + 4,	z);
			glVertex3f( x + size_in_pixels.width,	y + size_in_pixels.height - pixel_title_size.height + 4,	z);
			glVertex3f( x + size_in_pixels.width,	y + size_in_pixels.height - pixel_title_size.height + 2,		z);
			glVertex3f( x + 0,					y + size_in_pixels.height - pixel_title_size.height + 2,		z);
		glEnd();
	}
	
	// draw each row of text
	//
	for (i = 0; i < n_rows; i++)
	{
		OOColor* row_color = (OOColor *)[rowColor objectAtIndex:i];
		GLfloat row_alpha = alpha;
		if (rowFadeTime[i] > 0.0)
		{
			rowFadeTime[i] -= delta_t;
			if (rowFadeTime[i] < 0.0)
			{
				[rowText replaceObjectAtIndex:i withObject:@""];
				rowFadeTime[i] = 0.0;
			}
			if ((rowFadeTime[i] > 0.0)&&(rowFadeTime[i] < 1.0))
				row_alpha *= rowFadeTime[i];
		}
		glColor4f( [row_color redComponent], [row_color greenComponent], [row_color blueComponent], row_alpha);
		
		if ([[rowText objectAtIndex:i] isKindOfClass:[NSString class]])
		{
			NSString*   text = (NSString *)[rowText objectAtIndex:i];
			if (![text isEqual:@""])
			{
				strsize = rectForString(text, 0.0, 0.0, characterSize).size;
				switch (rowAlignment[i])
				{
					case GUI_ALIGN_LEFT :
						rowPosition[i].x = 0.0;
						break;
					case GUI_ALIGN_RIGHT :
						rowPosition[i].x = size_in_pixels.width - strsize.width;
						break;
					case GUI_ALIGN_CENTER :
						rowPosition[i].x = (size_in_pixels.width - strsize.width)/2.0;
						break;
				}
				if (i == selectedRow)
				{
					NSRect block = rectForString( text, x + rowPosition[i].x + 2, y + rowPosition[i].y + 2, characterSize);
					glColor4f( 1.0, 0.0, 0.0, row_alpha);	// red
					glBegin(GL_QUADS);
						glVertex3f( block.origin.x,						block.origin.y,						z);
						glVertex3f( block.origin.x + block.size.width,	block.origin.y,						z);
						glVertex3f( block.origin.x + block.size.width,	block.origin.y + block.size.height,	z);
						glVertex3f( block.origin.x,						block.origin.y + block.size.height,	z);
					glEnd();
					glColor4f( 0.0, 0.0, 0.0, row_alpha);	// black
				}
				drawString( text, x + rowPosition[i].x, y + rowPosition[i].y, z, characterSize);
				
				// draw cursor at end of current Row
				//
				if ((showTextCursor)&&(i == currentRow))
				{
					NSRect	tr = rectForString( text, 0.0, 0.0, characterSize);
					NSPoint cu = NSMakePoint( x + rowPosition[i].x + tr.size.width + 0.2 * characterSize.width, y + rowPosition[i].y);
					tr.origin = cu;
					tr.size.width = 0.5 * characterSize.width;
					GLfloat g_alpha = 0.5 * (1.0 + sin(6 * [UNIVERSE getTime]));
					glColor4f( 1.0, 0.0, 0.0, row_alpha * g_alpha);	// red
					glBegin(GL_QUADS);
						glVertex3f( tr.origin.x,					tr.origin.y,					z);
						glVertex3f( tr.origin.x + tr.size.width,	tr.origin.y,					z);
						glVertex3f( tr.origin.x + tr.size.width,	tr.origin.y + tr.size.height,	z);
						glVertex3f( tr.origin.x,					tr.origin.y + tr.size.height,	z);
					glEnd();
				}
			}
		}
		if ([[rowText objectAtIndex:i] isKindOfClass:[NSArray class]])
		{
			int j;
			NSArray*	array = (NSArray *)[rowText objectAtIndex:i];
			for (j = 0; ((j < [array count])&&(j < n_columns)) ; j++)
			{
				if ([array objectAtIndex:j])
				{
					NSString*   text = (NSString *)[array objectAtIndex:j];
					if (![text isEqual:@""])
					{
						rowPosition[i].x = tabStops[j];
						if (i == selectedRow)
						{
							NSRect block = rectForString( text, x + rowPosition[i].x + 2, y + rowPosition[i].y + 2, characterSize);
							glColor4f( 1.0, 0.0, 0.0, row_alpha);	// red
							glBegin(GL_QUADS);
								glVertex3f( block.origin.x,						block.origin.y,						z);
								glVertex3f( block.origin.x + block.size.width,	block.origin.y,						z);
								glVertex3f( block.origin.x + block.size.width,	block.origin.y + block.size.height,	z);
								glVertex3f( block.origin.x,						block.origin.y + block.size.height,	z);
							glEnd();
							glColor4f( 0.0, 0.0, 0.0, row_alpha);	// black
						}
						drawString( text, x + rowPosition[i].x, y + rowPosition[i].y, z, characterSize);
					}
				}
			}
		}
	}
}

- (void) drawStarChart:(GLfloat)x :(GLfloat)y :(GLfloat)z :(GLfloat) alpha
{
	PlayerEntity* player = [PlayerEntity sharedPlayer];

	if (!player)
		return;

	NSPoint	galaxy_coordinates = [player galaxy_coordinates];
	NSPoint	cursor_coordinates = [player cursor_coordinates];
	NSPoint	cu;
	
	double fuel = 35.0 * [player dial_fuel];
	
	Random_Seed g_seed;
	double		hcenter = size_in_pixels.width/2.0;
	double		vcenter = 160.0;
	double		hscale = 4.0 * size_in_pixels.width / 256.0;
	double		vscale = -4.0 * size_in_pixels.height / 512.0;
	double		hoffset = hcenter - galaxy_coordinates.x*hscale;
	double		voffset = size_in_pixels.height - pixel_title_size.height - 5 - vcenter - galaxy_coordinates.y*vscale;
	int			i;
	NSPoint		star;
	
	if ((abs(cursor_coordinates.x-galaxy_coordinates.x)>=20)||(abs(cursor_coordinates.y-galaxy_coordinates.y)>=38))
		cursor_coordinates = galaxy_coordinates;	// home
	
	// get a list of systems marked as contract destinations
	NSArray* markedDestinations = [player markedDestinations];

	// draw fuel range circle
	//
	glColor4f( 0.0, 1.0, 0.0, alpha);	//	green
	glLineWidth(2.0);
	cu = NSMakePoint(hscale*galaxy_coordinates.x+hoffset,vscale*galaxy_coordinates.y+voffset);
	drawOval( x + cu.x, y + cu.y, z, NSMakeSize( fuel*hscale, 2*fuel*vscale), 5);
		
	// draw marks and stars
	//
	glLineWidth( 1.5);
	glColor4f(1.0, 1.0, 0.75, alpha);	// pale yellow

	for (i = 0; i < 256; i++)
	{
		g_seed = [UNIVERSE systemSeedForSystemNumber:i];
		
		int dx, dy;
		float blob_size = 4.0 + 0.5 * (g_seed.f & 15);
				
		star.x = g_seed.d * hscale + hoffset;
		star.y = g_seed.b * vscale + voffset;
		
		dx = abs(galaxy_coordinates.x - g_seed.d);
		dy = abs(galaxy_coordinates.y - g_seed.b);
		
		if ((dx < 20)&&(dy < 38))
		{
			if ([(NSNumber*)[markedDestinations objectAtIndex:i] boolValue])	// is marked
			{
				GLfloat mark_size = 0.5 * blob_size + 2.5;
				glColor4f( 1.0, 0.0, 0.0, alpha);	// red
				glBegin( GL_LINES);
					glVertex3f( x + star.x - mark_size,	y + star.y - mark_size,	z);
					glVertex3f( x + star.x + mark_size,	y + star.y + mark_size,	z);
					glVertex3f( x + star.x - mark_size,	y + star.y + mark_size,	z);
					glVertex3f( x + star.x + mark_size,	y + star.y - mark_size,	z);
				glEnd();
				glColor4f(1.0, 1.0, 0.75, alpha);	// pale yellow
			}
			drawFilledOval( x + star.x, y + star.y, z, NSMakeSize(blob_size,blob_size), 15);
		}
	}
	
	// draw names
	//
	glColor4f(1.0, 1.0, 0.0, alpha);	// yellow
	for (i = 0; i < 256; i++)
	{
		g_seed = [UNIVERSE systemSeedForSystemNumber:i];
		
		int dx, dy;
		
		star.x = g_seed.d * hscale + hoffset;
		star.y = g_seed.b * vscale + voffset;
		
		dx = abs(galaxy_coordinates.x - g_seed.d);
		dy = abs(galaxy_coordinates.y - g_seed.b);
		
		if ((dx < 20)&&(dy < 38))
		{
			NSDictionary* sys_info = [UNIVERSE generateSystemData:g_seed];
			int tec = [[sys_info objectForKey:KEY_TECHLEVEL] intValue];
			int eco = [[sys_info objectForKey:KEY_ECONOMY] intValue];
			int gov = [[sys_info objectForKey:KEY_GOVERNMENT] intValue];
			NSString*   p_name = (NSString*)[sys_info objectForKey:KEY_NAME];
			if (![player showInfoFlag])
			{
				drawString( p_name, x + star.x, y + star.y, z, NSMakeSize(pixel_row_height,pixel_row_height));
			}
			else
			{
				drawPlanetInfo( gov, eco, tec, x + star.x + 2.0, y + star.y + 2.0, z, NSMakeSize(pixel_row_height,pixel_row_height));
			}
		}
	}
	
	// draw cross-hairs over current location
	//
	glColor4f( 0.0, 1.0, 0.0, alpha);	//	green
	glBegin( GL_QUADS);
		glVertex3f( x + cu.x - 1,	y + cu.y - 14,	z);
		glVertex3f( x + cu.x + 1,	y + cu.y - 14,	z);
		glVertex3f( x + cu.x + 1,	y + cu.y + 14,	z);
		glVertex3f( x + cu.x - 1,	y + cu.y + 14,	z);
		glVertex3f( x + cu.x - 14,	y + cu.y - 1,	z);
		glVertex3f( x + cu.x + 14,	y + cu.y - 1,	z);
		glVertex3f( x + cu.x + 14,	y + cu.y + 1,	z);
		glVertex3f( x + cu.x - 14,	y + cu.y + 1,	z);
	glEnd();
	
	// draw cross hairs over cursor
	//
	glColor4f( 1.0, 0.0, 0.0, alpha);	//	red
	cu = NSMakePoint(hscale*cursor_coordinates.x+hoffset,vscale*cursor_coordinates.y+voffset);
	glBegin( GL_QUADS);
		glVertex3f( x + cu.x - 1,	y + cu.y - 7,	z);
		glVertex3f( x + cu.x + 1,	y + cu.y - 7,	z);
		glVertex3f( x + cu.x + 1,	y + cu.y + 7,	z);
		glVertex3f( x + cu.x - 1,	y + cu.y + 7,	z);
		glVertex3f( x + cu.x - 7,	y + cu.y - 1,	z);
		glVertex3f( x + cu.x + 7,	y + cu.y - 1,	z);
		glVertex3f( x + cu.x + 7,	y + cu.y + 1,	z);
		glVertex3f( x + cu.x - 7,	y + cu.y + 1,	z);
	glEnd();
}

- (void) drawGalaxyChart:(GLfloat)x :(GLfloat)y :(GLfloat)z :(GLfloat) alpha
{
	PlayerEntity* player = [PlayerEntity sharedPlayer];

	NSPoint	galaxy_coordinates = [player galaxy_coordinates];
	NSPoint	cursor_coordinates = [player cursor_coordinates];

	double fuel = 35.0 * [player dial_fuel];

	// get a list of systems marked as contract destinations
	NSArray* markedDestinations = [player markedDestinations];
	
	BOOL* systems_found = [UNIVERSE systems_found];
	
	NSPoint		star, cu;
	
	Random_Seed g_seed;
	double		hscale = size_in_pixels.width / 256.0;
	double		vscale = -1.0 * size_in_pixels.height / 512.0;
	double		hoffset = 0.0;
	double		voffset = size_in_pixels.height - pixel_title_size.height - 5;
	int			i;
	
	if (showAdvancedNavArray && ![UNIVERSE strict] && [player has_extra_equipment:@"EQ_ADVANCED_NAVIGATIONAL_ARRAY"])
	{
		[self drawAdvancedNavArrayAtX:x y:y z:z alpha:alpha];
	}
	
	// draw fuel range circle
	//
	glColor4f( 0.0, 1.0, 0.0, alpha);	//	green
	glLineWidth(2.0);
	cu = NSMakePoint(hscale*galaxy_coordinates.x+hoffset,vscale*galaxy_coordinates.y+voffset);
	drawOval( x + cu.x, y + cu.y, z, NSMakeSize( fuel*hscale, 2*fuel*vscale), 5);
	
	// draw cross-hairs over current location
	//
	glBegin( GL_QUADS);
		glVertex3f( x + cu.x - 1,	y + cu.y - 14,	z);
		glVertex3f( x + cu.x + 1,	y + cu.y - 14,	z);
		glVertex3f( x + cu.x + 1,	y + cu.y + 14,	z);
		glVertex3f( x + cu.x - 1,	y + cu.y + 14,	z);
		glVertex3f( x + cu.x - 14,	y + cu.y - 1,	z);
		glVertex3f( x + cu.x + 14,	y + cu.y - 1,	z);
		glVertex3f( x + cu.x + 14,	y + cu.y + 1,	z);
		glVertex3f( x + cu.x - 14,	y + cu.y + 1,	z);
	glEnd();
	
	// draw cross hairs over cursor
	//
	glColor4f( 1.0, 0.0, 0.0, alpha);	//	red
	cu = NSMakePoint(hscale*cursor_coordinates.x+hoffset,vscale*cursor_coordinates.y+voffset);
	glBegin( GL_QUADS);
		glVertex3f( x + cu.x - 1,	y + cu.y - 7,	z);
		glVertex3f( x + cu.x + 1,	y + cu.y - 7,	z);
		glVertex3f( x + cu.x + 1,	y + cu.y + 7,	z);
		glVertex3f( x + cu.x - 1,	y + cu.y + 7,	z);
		glVertex3f( x + cu.x - 7,	y + cu.y - 1,	z);
		glVertex3f( x + cu.x + 7,	y + cu.y - 1,	z);
		glVertex3f( x + cu.x + 7,	y + cu.y + 1,	z);
		glVertex3f( x + cu.x - 7,	y + cu.y + 1,	z);
	glEnd();
	
	// draw marks
	//
	glLineWidth( 1.5);
	glColor4f( 1.0, 0.0, 0.0, alpha);
	for (i = 0; i < 256; i++)
	{
		g_seed = [UNIVERSE systemSeedForSystemNumber:i];
		BOOL mark = [(NSNumber*)[markedDestinations objectAtIndex:i] boolValue];
		if (mark)
		{
			star.x = g_seed.d * hscale + hoffset;
			star.y = g_seed.b * vscale + voffset;
			glBegin( GL_LINES);
				glVertex3f( x + star.x - 2.5,	y + star.y - 2.5,	z);
				glVertex3f( x + star.x + 2.5,	y + star.y + 2.5,	z);
				glVertex3f( x + star.x - 2.5,	y + star.y + 2.5,	z);
				glVertex3f( x + star.x + 2.5,	y + star.y - 2.5,	z);
			glEnd();
		}
	}
	
	// draw stars
	//
	glColor4f( 1.0, 1.0, 1.0, alpha);
	glBegin( GL_QUADS);
	for (i = 0; i < 256; i++)
	{
		g_seed = [UNIVERSE systemSeedForSystemNumber:i];
		
		star.x = g_seed.d * hscale + hoffset;
		star.y = g_seed.b * vscale + voffset;

		double sz = (4.0 + 0.5 * (0x03 | (g_seed.f & 0x0f))) / 7.0;
		
		glVertex3f( x + star.x,			y + star.y + sz,	z);
		glVertex3f( x + star.x + sz,	y + star.y,			z);
		glVertex3f( x + star.x,			y + star.y - sz,	z);
		glVertex3f( x + star.x - sz,	y + star.y,			z);
	}
	glEnd();
		
	// draw found stars and captions
	//
	glLineWidth( 1.5);
	glColor4f( 0.0, 1.0, 0.0, alpha);
	for (i = 0; i < 256; i++)
	{
		BOOL mark = systems_found[i];
		g_seed = [UNIVERSE systemSeedForSystemNumber:i];
		if (mark)
		{
			star.x = g_seed.d * hscale + hoffset;
			star.y = g_seed.b * vscale + voffset;
			glBegin( GL_LINE_LOOP);
				glVertex3f( x + star.x - 2.0,	y + star.y - 2.0,	z);
				glVertex3f( x + star.x + 2.0,	y + star.y - 2.0,	z);
				glVertex3f( x + star.x + 2.0,	y + star.y + 2.0,	z);
				glVertex3f( x + star.x - 2.0,	y + star.y + 2.0,	z);
			glEnd();
			drawString([UNIVERSE systemNameIndex:i] , x + star.x + 2.0, y + star.y - 10.0, z, NSMakeSize(10,10));
		}
	}
	
	// draw bottom horizontal divider
	//
	glColor4f( 0.75, 0.75, 0.75, alpha);	// 75% gray
	glBegin( GL_QUADS);
		glVertex3f( x + 0,					y + voffset + 260.0*vscale + 0,	z);
		glVertex3f( x + size_in_pixels.width,	y + voffset + 260.0*vscale + 0,	z);
		glVertex3f( x + size_in_pixels.width,	y + voffset + 260.0*vscale - 2,		z);
		glVertex3f( x + 0,					y + voffset + 260.0*vscale - 2,		z);
	glEnd();

}


// Advanced Navigation Array -- galactic chart route mapping - contributed by Nikos Barkas (another_commander).
- (void) drawAdvancedNavArrayAtX:(float)x y:(float)y z:(float)z alpha:(float)alpha
{
	PlayerEntity	*player = [PlayerEntity sharedPlayer];
	NSPoint			galaxy_coordinates = [player galaxy_coordinates];
	NSPoint			cursor_coordinates = [player cursor_coordinates];
	Random_Seed		galaxy_seed = [player galaxy_seed];
	Random_Seed		g_seed, g_seed2;
	int				i, j;
	double			hscale = size_in_pixels.width / 256.0;
	double			vscale = -1.0 * size_in_pixels.height / 512.0;
	double			hoffset = 0.0;
	double			voffset = size_in_pixels.height - pixel_title_size.height - 5;
	NSPoint			star, star2 = NSZeroPoint;
	
	glColor4f( 0.25, 0.25, 0.25, alpha);
	
	glBegin( GL_LINES );
	for (i = 0; i < 256; i++) for (j = i + 1; j < 256; j++)
	{
		g_seed = [UNIVERSE systemSeedForSystemNumber:i];
		g_seed2 = [UNIVERSE systemSeedForSystemNumber:j];
		
		star.x = g_seed.d * hscale + hoffset;
		star.y = g_seed.b * vscale + voffset;
		star2.x = g_seed2.d * hscale + hoffset;
		star2.y = g_seed2.b * vscale + voffset;
		double d = distanceBetweenPlanetPositions(g_seed.d, g_seed.b, g_seed2.d, g_seed2.b);
		
		if (d <= (PLAYER_MAX_FUEL / 10.0))	// another_commander - Default to 7.0 LY.
		{
			glVertex3f( x+star.x, y+star.y, z );
			glVertex3f( x+star2.x, y+star2.y, z );
		}
	}
	glEnd();
	
	// Draw route from player position to currently selected destination.
	int planetNumber = [UNIVERSE findSystemNumberAtCoords:galaxy_coordinates withGalaxySeed:galaxy_seed];
	int destNumber = [UNIVERSE findSystemNumberAtCoords:cursor_coordinates withGalaxySeed:galaxy_seed];
	NSDictionary* routeInfo = [UNIVERSE routeFromSystem:planetNumber ToSystem:destNumber];
	
	if ((destNumber != planetNumber) && routeInfo)
	{
		int route_hops = [(NSArray *)[routeInfo objectForKey:@"route"] count] -1;
		
		glColor4f (1.0, 1.0, 0.0, alpha);	// Yellow for plotting routes.
		for (i = 0; i < route_hops; i++)
		{
			int loc = [(NSNumber *)[[routeInfo objectForKey:@"route"] objectAtIndex:i] intValue];
			int loc2 = [(NSNumber *)[[routeInfo objectForKey:@"route"] objectAtIndex:(i+1)] intValue];
			
			g_seed = [UNIVERSE systemSeedForSystemNumber:loc];
			g_seed2 = [UNIVERSE systemSeedForSystemNumber:(loc2)];        
			star.x = g_seed.d * hscale + hoffset;
			star.y = g_seed.b * vscale + voffset;
			star2.x = g_seed2.d * hscale + hoffset;
			star2.y = g_seed2.b * vscale + voffset; 
			
			glBegin (GL_LINES);
			glVertex3f (x+star.x, y+star.y, z);
			glVertex3f (x+star2.x, y+star2.y, z);
			glEnd();
			
			// Label the route.
			drawString([UNIVERSE systemNameIndex:loc] , x + star.x + 2.0, y + star.y - 6.0, z, NSMakeSize(8,8));
		}
		// Label the destination, which was not included in the above loop.
		drawString([UNIVERSE systemNameIndex:destNumber] , x + star2.x + 2.0, y + star2.y - 6.0, z, NSMakeSize(8,8));	
	}
}

@end
