/*

GuiDisplayGen.m

Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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
#import "OOCollectionExtractors.h"


OOINLINE BOOL RowInRange(OOGUIRow row, NSRange range)
{
	return ((int)range.location <= row && row < (int)(range.location + range.length));
}


@interface GuiDisplayGen (Internal)

- (void) drawGLDisplay:(GLfloat)x :(GLfloat)y :(GLfloat)z :(GLfloat) alpha;

- (void) drawStarChart:(GLfloat)x :(GLfloat)y :(GLfloat)z :(GLfloat) alpha;
- (void) drawGalaxyChart:(GLfloat)x :(GLfloat)y :(GLfloat)z :(GLfloat) alpha;
- (void) drawEqptList: (NSArray *)eqptList z:(GLfloat)z;
- (void) drawAdvancedNavArrayAtX:(float)x y:(float)y z:(float)z alpha:(float)alpha;

@end


@implementation GuiDisplayGen

- (id) init
{
	self = [super init];
		
	size_in_pixels  = NSMakeSize(MAIN_GUI_PIXEL_WIDTH, MAIN_GUI_PIXEL_HEIGHT);
	n_columns		= GUI_DEFAULT_COLUMNS;
	n_rows			= GUI_DEFAULT_ROWS;
	pixel_row_center = size_in_pixels.width / 2;
	pixel_row_height = MAIN_GUI_ROW_HEIGHT;
	pixel_row_start	= MAIN_GUI_PIXEL_ROW_START;		// first position down the page...

	pixel_text_size = NSMakeSize(0.9f * pixel_row_height, pixel_row_height);	// main gui has 18x20 characters
	
	pixel_title_size = NSMakeSize(pixel_row_height * 1.75f, pixel_row_height * 1.5f);
	
	int stops[6] = {0, 192, 256, 320, 384, 448};
	unsigned i;
	
	rowRange = NSMakeRange(0,n_rows);

	rowText =   [[NSMutableArray alloc] initWithCapacity:n_rows];   // alloc retains
	rowKey =	[[NSMutableArray alloc] initWithCapacity:n_rows];   // alloc retains
	rowColor =	[[NSMutableArray alloc] initWithCapacity:n_rows];   // alloc retains
	
	for (i = 0; i < n_rows; i++)
	{
		[rowText addObject:@"."];
		[rowKey addObject:[NSString stringWithFormat:@"%d",i]];
		[rowColor addObject:[OOColor yellowColor]];
		rowPosition[i].x = 0.0f;
		rowPosition[i].y = size_in_pixels.height - (pixel_row_start + i * pixel_row_height);
		rowAlignment[i] = GUI_ALIGN_LEFT;
	}
	
	for (i = 0; i < n_columns; i++)
	{
		tabStops[i] = stops[i];
	}
	
	title = @"";
	
	textColor = [[OOColor yellowColor] retain];
	
	drawPosition = make_vector(0.0f, 0.0f, 640.0f);

	return self;
}


- (id) initWithPixelSize:(NSSize)gui_size
				 columns:(int)gui_cols 
					rows:(int)gui_rows 
			   rowHeight:(int)gui_row_height
				rowStart:(int)gui_row_start
				   title:(NSString*)gui_title
{
	self = [super init];
		
	size_in_pixels  = gui_size;
	n_columns		= gui_cols;
	n_rows			= gui_rows;
	pixel_row_center = size_in_pixels.width / 2;
	pixel_row_height = gui_row_height;
	pixel_row_start	= gui_row_start;		// first position down the page...

	pixel_text_size = NSMakeSize(pixel_row_height, pixel_row_height);
	
	pixel_title_size = NSMakeSize(pixel_row_height * 1.75f, pixel_row_height * 1.5f);
	
	unsigned i;
	
	rowRange = NSMakeRange(0,n_rows);

	rowText =   [[NSMutableArray alloc] initWithCapacity:n_rows];   // alloc retains
	rowKey =	[[NSMutableArray alloc] initWithCapacity:n_rows];   // alloc retains
	rowColor =	[[NSMutableArray alloc] initWithCapacity:n_rows];   // alloc retains
	
	for (i = 0; i < n_rows; i++)
	{
		[rowText addObject:@""];
		[rowKey addObject:@""];
		[rowColor addObject:[OOColor greenColor]];
		rowPosition[i].x = 0.0f;
		rowPosition[i].y = size_in_pixels.height - (pixel_row_start + i * pixel_row_height);
		rowAlignment[i] = GUI_ALIGN_LEFT;
	}
	
	title = [gui_title retain];
	
	textColor = [[OOColor yellowColor] retain];

	return self;
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


- (void) resizeWithPixelSize:(NSSize)gui_size
					 columns:(int)gui_cols
						rows:(int)gui_rows
				   rowHeight:(int)gui_row_height
					rowStart:(int)gui_row_start
					   title:(NSString*) gui_title
{
	[self clear];
	//
	size_in_pixels  = gui_size;
	n_columns		= gui_cols;
	n_rows			= gui_rows;
	pixel_row_center = size_in_pixels.width / 2;
	pixel_row_height = gui_row_height;
	pixel_row_start	= gui_row_start;		// first position down the page...

	pixel_text_size = NSMakeSize(pixel_row_height, pixel_row_height);
	pixel_title_size = NSMakeSize(pixel_row_height * 1.75f, pixel_row_height * 1.5f);

	rowRange = NSMakeRange(0,n_rows);
	[self clear];
	//
	[self setTitle: gui_title];
}


- (void) resizeTo:(NSSize)gui_size
  characterHeight:(int)csize
			title:(NSString*)gui_title
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

	if (title != nil)
		pixel_row_start = 2.75f * csize + 0.5f * (gui_size.height - n_rows * csize);
	else
		pixel_row_start = csize + 0.5f * (gui_size.height - n_rows * csize);

	[rowText removeAllObjects];
	[rowKey removeAllObjects];
	[rowColor removeAllObjects];

	unsigned i;
	for (i = 0; i < n_rows; i++)
	{
		[rowText addObject:@""];
		[rowKey addObject:@""];
		[rowColor addObject:[OOColor greenColor]];
		rowPosition[i].x = 0.0f;
		rowPosition[i].y = size_in_pixels.height - (pixel_row_start + i * pixel_row_height);
		rowAlignment[i] = GUI_ALIGN_LEFT;
	}

	pixel_text_size = NSMakeSize(csize, csize);
	pixel_title_size = NSMakeSize(csize * 1.75f, csize * 1.5f);
	
	OOLog(@"gui.reset", @"gui %@ reset to rows:%d columns:%d start:%d", self, n_rows, n_columns, pixel_row_start);

	rowRange = NSMakeRange(0,n_rows);
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


- (NSString *)title
{
	return title;
}


- (void) setTitle:(NSString *)str
{
	if (str != title)
	{
		[title release];
		if ([str length] == 0)  str = nil;
		title = [str copy];
	}
}


- (void) setDrawPosition:(Vector) vector
{
	drawPosition = vector;
}


- (Vector) drawPosition
{
	return drawPosition;
}


- (void) fadeOutFromTime:(OOTimeAbsolute) now_time overDuration:(OOTimeDelta) duration
{
	if (fade_alpha <= 0.0f) 
	{
		return;
	}
	fade_sign = (float)(-fade_alpha / duration);
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
	[backgroundColor release];
	backgroundColor = [color retain];
}


- (void) setTextColor:(OOColor*) color
{
	[textColor release];
	if (color == nil)  color = [[OOColor yellowColor] retain];
	textColor = [color retain];
}


- (void) setCharacterSize:(NSSize) character_size
{
	pixel_text_size = character_size;
}


- (void)setShowAdvancedNavArray:(BOOL)inFlag
{
	showAdvancedNavArray = inFlag;
}


- (void) setColor:(OOColor *) color forRow:(OOGUIRow)row
{
	if (RowInRange(row, rowRange))
		[rowColor replaceObjectAtIndex:row withObject:color];
}


- (id) objectForRow:(OOGUIRow)row
{
	if (RowInRange(row, rowRange))
		return [rowText objectAtIndex:row];
	else
		return NULL;
}


- (NSString*) keyForRow:(OOGUIRow)row
{
	if (RowInRange(row, rowRange))
		return [rowKey objectAtIndex:row];
	else
		return NULL;
}


- (int) selectedRow
{
	if (RowInRange(selectedRow, selectableRange))
		return selectedRow;
	else
		return -1;
}


- (BOOL) setSelectedRow:(OOGUIRow)row
{
	if ((row == selectedRow)&&RowInRange(row, selectableRange))
		return YES;
	if (RowInRange(row, selectableRange))
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
	while (RowInRange(row, selectableRange))
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
	while (RowInRange(row, selectableRange))
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
	if ((selectedRow < 0)||((unsigned)selectedRow > [rowKey count]))
		return nil;
	else
		return (NSString *)[rowKey objectAtIndex:selectedRow];
}


- (void) setShowTextCursor:(BOOL) yesno
{
	showTextCursor = yesno;
}


- (void) setCurrentRow:(OOGUIRow) value
{
	if ((value < 0)||((unsigned)value >= n_rows))
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


- (void) setTabStops:(OOGUITabSettings)stops
{
	if (stops != NULL)  memmove(tabStops, stops, sizeof tabStops);
}


- (void) clear
{
	unsigned i;
	[self setTitle: nil];
	for (i = 0; i < n_rows; i++)
	{
		[self setText:@"" forRow:i align:GUI_ALIGN_LEFT];
		[self setColor:textColor forRow:i];
		//
		[self setKey:GUI_KEY_SKIP forRow:i];
		//
		rowFadeTime[i] = 0.0f;
	}
	[self setShowTextCursor:NO];
	[self setSelectableRange:NSMakeRange(0,0)];
}


- (void) setKey:(NSString *)str forRow:(OOGUIRow)row
{
	if (RowInRange(row, rowRange))
		[rowKey replaceObjectAtIndex:row withObject:str];
}


- (void) setText:(NSString *)str forRow:(OOGUIRow)row
{
	if (RowInRange(row, rowRange))
	{
		[rowText replaceObjectAtIndex:row withObject:str];
	}
}


- (void) setText:(NSString *)str forRow:(OOGUIRow)row align:(OOGUIAlignment)alignment
{
	if (str != nil && RowInRange(row, rowRange))
	{
		[rowText replaceObjectAtIndex:row withObject:str];
		rowAlignment[row] = alignment;
	}
}


- (int) addLongText:(NSString *)str
	  startingAtRow:(OOGUIRow)row
			  align:(OOGUIAlignment)alignment
{
	NSSize chSize = pixel_text_size;
	NSSize strsize = OORectFromString(str, 0.0f, 0.0f, chSize).size;
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
		strsize.width = 0.0f;
		while ((strsize.width < size_in_pixels.width)&&([words count] > 0))
		{
			[string1 appendString:(NSString *)[words objectAtIndex:0]];
			[string1 appendString:@" "];
			[words removeObjectAtIndex:0];
			strsize = OORectFromString(string1, 0.0f, 0.0f, chSize).size;
			if ([words count] > 0)
				strsize.width += OORectFromString((NSString *)[words objectAtIndex:0], 0.0f, 0.0f, chSize).size.width;
		}
		[string2 appendString:[words componentsJoinedByString:@" "]];
		[self setText:string1		forRow:row			align:alignment];
		return  [self addLongText:string2   startingAtRow:row+1	align:alignment];
	}
}

- (void) leaveLastLine
{
	unsigned i;
	for (i=0; i < n_rows-1; i++)
	{
		[rowText	replaceObjectAtIndex:i withObject:@""];
		[rowColor	replaceObjectAtIndex:i withObject:textColor];
		[rowKey		replaceObjectAtIndex:i withObject:@""];
		rowAlignment[i] = GUI_ALIGN_LEFT;
		rowFadeTime[i]	= 0.0f;
	}
	rowFadeTime[i]	= 0.4f; // fade the last line...
}

- (void) printLongText:(NSString *)str
				 align:(OOGUIAlignment) alignment
				 color:(OOColor *)text_color
			  fadeTime:(float)text_fade
				   key:(NSString *)text_key
			addToArray:(NSMutableArray *)text_array
{
	// print a multi-line message
	//
	if ([str rangeOfString:@"\n"].location != NSNotFound)
	{
		NSArray		*lines = [str componentsSeparatedByString:@"\n"];
		unsigned	i;
		for (i = 0; i < [lines count]; i++)
			[self printLongText:[lines stringAtIndex:i] align:alignment color:text_color fadeTime:text_fade key:text_key addToArray:text_array];
		return;
	}
	
	OOGUIRow row = currentRow;
	if (row == (OOGUIRow)n_rows - 1)
		[self scrollUp:1];
	NSSize chSize = pixel_text_size;
	NSSize strsize = OORectFromString(str, 0.0f, 0.0f, chSize).size;
	if (strsize.width < size_in_pixels.width)
	{
		[self setText:str forRow:row align:alignment];
		if (text_color)
			[self setColor:text_color forRow:row];
		if (text_key)
			[self setKey:text_key forRow:row];
		rowFadeTime[row] = text_fade;
		if (currentRow < (OOGUIRow)n_rows - 1)
			currentRow++;
	}
	else
	{
		NSMutableArray	*words = ScanTokensFromString(str);
		NSMutableString	*string1 = [NSMutableString stringWithCapacity:256];
		NSMutableString	*string2 = [NSMutableString stringWithCapacity:256];
		strsize.width = 0.0f;
		while ((strsize.width < size_in_pixels.width)&&([words count] > 0))
		{
			[string1 appendString:(NSString *)[words objectAtIndex:0]];
			[string1 appendString:@" "];
			[words removeObjectAtIndex:0];
			strsize = OORectFromString(string1, 0.0f, 0.0f, chSize).size;
			if ([words count] > 0)
				strsize.width += OORectFromString([words stringAtIndex:0], 0.0f, 0.0f, chSize).size.width;
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
		[self printLongText:string2 align:alignment color:text_color fadeTime:text_fade key:text_key addToArray:text_array];
	}
}


- (void) printLineNoScroll:(NSString *)str
					 align:(OOGUIAlignment)alignment
					  color:(OOColor *)text_color
				  fadeTime:(float)text_fade
					   key:(NSString *)text_key
				addToArray:(NSMutableArray *)text_array
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


- (void) setArray:(NSArray *)arr forRow:(OOGUIRow)row
{
	if (RowInRange(row, rowRange))
		[rowText replaceObjectAtIndex:row withObject:arr];
}



- (void) insertItemsFromArray:(NSArray *)items
					 withKeys:(NSArray *)item_keys
					  intoRow:(OOGUIRow)row
						color:(OOColor *)text_color
{
	if (!items)
		return;
	if([items count] == 0)
		return;
	
	unsigned n_items = [items count];
	if ((item_keys)&&([item_keys count] != n_items))
	{
		// throw exception
		[NSException raise:@"ArrayLengthMismatchException"
					format:@"The NSArray sent as 'item_keys' to insertItemsFromArray::: must contain the same number of objects as the NSArray 'items'"];
	}

	unsigned i;
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
	unsigned i;
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
		rowFadeTime[i]	= 0.0f;
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


- (void) setStatusPage:(int)pageNum
{
	if (pageNum==0) 
		statusPage=1;
	else 
		statusPage += pageNum;
}


- (void) drawEqptList:(NSArray *)eqptList z:(GLfloat)z 
{
	if (eqptList == nil) return;
	
	int				first_row = STATUS_EQUIPMENT_FIRST_ROW;
	int				items_per_column = STATUS_EQUIPMENT_MAX_ROWS;

	int				first_y = 40;	// first_row =10 :-> 40  - first_row=11 -> 24 etc...
	int				items_count = [eqptList count];
	int				page_count=1;
	int				i, start;
	NSArray			*info = nil;
	NSString		*name = nil;
	BOOL			damaged;
	
	// Paging calculations. Assuming 10 lines we get - one page:20 items per page (ipp)
	// two pages: 18 ipp - three+ pages:  1st & last 18pp,  middle pages 16ipp
	
	i = items_per_column * 2 + 2;
	if (items_count > i) // don't fit in one page?
	{
		[UNIVERSE setDisplayCursor: YES];
		i = items_per_column * 4; // total items in the first and last pages
		items_per_column--; // for all the middle pages.
		if (items_count <= i) // two pages
		{
			page_count++;
			if (statusPage == 1) start=0;
			else
			{
				statusPage = 2;
				start = i/statusPage; // for the for loop
			}
		}
		else // three or more
		{
			page_count = ceil((float)(items_count-i)/(items_per_column*2)) + 2;
			statusPage = OOClampInteger(statusPage, 1, page_count);
			start = (statusPage == 1) ? 0 : (statusPage-1) * items_per_column * 2 + 2;
		}
	}
	else
	{
		statusPage=page_count; // one page
		start=0;
	}
	
	[self setSelectableRange:NSMakeRange(first_row, first_row + STATUS_EQUIPMENT_MAX_ROWS)];
	if (statusPage > 1)
	{
		[self setColor:[OOColor greenColor] forRow:first_row];
		[self setArray:[NSArray arrayWithObjects:DESC(@"gui-back"),  @"", @" <-- ",nil] forRow:first_row];
		[self setKey:GUI_KEY_OK forRow:first_row];
		first_y -= 16; // start 1 row down!
		if (statusPage == page_count) [self setSelectedRow:first_row];
	}
	if (statusPage < page_count)
	{
		[self setColor:[OOColor greenColor] forRow:first_row + STATUS_EQUIPMENT_MAX_ROWS];
		[self setArray:[NSArray arrayWithObjects:DESC(@"gui-more"),  @"", @" --> ",nil] forRow:first_row + STATUS_EQUIPMENT_MAX_ROWS];
		[self setKey:GUI_KEY_OK forRow:first_row + STATUS_EQUIPMENT_MAX_ROWS];
		if (statusPage == 1) [self setSelectedRow:first_row + STATUS_EQUIPMENT_MAX_ROWS];
	}

	if (statusPage == 1 || statusPage == page_count) items_per_column++;
	items_count = OOClampInteger(items_count, 1, start + items_per_column * 2);
	for (i=start; i < items_count; i++)
	{
		info = [eqptList objectAtIndex:i];
		name = [info stringAtIndex:0];
		damaged = ![info boolAtIndex:1];
		if (damaged)  glColor4f (1.0f, 0.5f, 0.0f, 1.0f); // Damaged items  show up  orange.
		else glColor4f (1.0f, 1.0f, 0.0f, 1.0f);	// Normal items in yellow.
		if([name length] > 42)  name =[[name substringToIndex:40] stringByAppendingString:@"..."];
		if (i - start < items_per_column)
		{
			OODrawString (name, -220, first_y - 16 * (i - start), z, NSMakeSize(15, 15));
		}
		else
		{
			OODrawString (name, 50, first_y - 16 * (i - items_per_column - start), z, NSMakeSize(15, 15));
		}
	}
}


- (int) drawGUI:(GLfloat) alpha drawCursor:(BOOL) drawCursor
{
	GLfloat x = drawPosition.x;
	GLfloat y = drawPosition.y;
	GLfloat z = [[UNIVERSE gameView] display_z];
	
	if (alpha > 0.05f)
	{

		PlayerEntity* player = [PlayerEntity sharedPlayer];

		glEnable(GL_LINE_SMOOTH);

		if (self == [UNIVERSE gui])
		{
			if ([player guiScreen] == GUI_SCREEN_SHORT_RANGE_CHART)
				[self drawStarChart:x - 0.5f * size_in_pixels.width :y - 0.5f * size_in_pixels.height :z :alpha];
			if ([player guiScreen] == GUI_SCREEN_LONG_RANGE_CHART)
			{
				[self drawGalaxyChart:x - 0.5f * size_in_pixels.width :y - 0.5f * size_in_pixels.height :z :alpha];
			}
			if ([player guiScreen] == GUI_SCREEN_STATUS)
			{
				[self drawEqptList:[player equipmentList] z:z ];
			}
		}
		[self drawGLDisplay:x - 0.5f * size_in_pixels.width :y - 0.5f * size_in_pixels.height :z :alpha];
		
		if (fade_sign)
		{
			fade_alpha += (float)(fade_sign * [UNIVERSE getTimeDelta]);
			if (fade_alpha < 0.05f)	// done fading out
			{
				fade_alpha = 0.0f;
				fade_sign = 0.0f;
			}
			if (fade_alpha > 1.0f)	// done fading in
			{
				fade_alpha = 1.0f;
				fade_sign = 0.0f;
			}
		}
	}
	
	int cursor_row = 0;

	if (drawCursor)
	{
		NSPoint vjpos = [[UNIVERSE gameView] virtualJoystickPosition];
		double cursor_x = size_in_pixels.width * vjpos.x;
		if (cursor_x < -size_in_pixels.width * 0.5)  cursor_x = -size_in_pixels.width * 0.5f;
		if (cursor_x > size_in_pixels.width * 0.5)   cursor_x = size_in_pixels.width * 0.5f;
		double cursor_y = -size_in_pixels.height * vjpos.y;
		if (cursor_y < -size_in_pixels.height * 0.5)  cursor_y = -size_in_pixels.height * 0.5f;
		if (cursor_y > size_in_pixels.height * 0.5)   cursor_y = size_in_pixels.height * 0.5f;
		
		cursor_row = 1 + (float)floor((0.5f * size_in_pixels.height - pixel_row_start - cursor_y) / pixel_row_height);
		
		GLfloat h1 = 3.0f;
		GLfloat h3 = 9.0f;
		glColor4f(0.2f, 0.2f, 1.0f, 0.5f);
		glLineWidth(2.0f);
		
		cursor_x += x;
		cursor_y += y;
		[[UNIVERSE gameView] setVirtualJoystick:cursor_x/size_in_pixels.width :-cursor_y/size_in_pixels.height];

		glBegin(GL_LINES);
			glVertex3f((float)cursor_x - h1, (float)cursor_y, z);	glVertex3f((float)cursor_x - h3, (float)cursor_y, z);
			glVertex3f((float)cursor_x + h1, (float)cursor_y, z);	glVertex3f((float)cursor_x + h3, (float)cursor_y, z);
			glVertex3f((float)cursor_x, (float)cursor_y - h1, z);	glVertex3f((float)cursor_x, (float)cursor_y - h3, z);
			glVertex3f((float)cursor_x, (float)cursor_y + h1, z);	glVertex3f((float)cursor_x, (float)cursor_y + h3, z);
		glEnd();
		glLineWidth(1.0f);
		
	}
	
	return cursor_row;
}


- (void) drawGLDisplay:(GLfloat)x :(GLfloat)y :(GLfloat)z :(GLfloat) alpha
{
	NSSize		strsize;
	unsigned	i;
	OOTimeDelta	delta_t = [UNIVERSE getTimeDelta];
	NSSize		characterSize = pixel_text_size;
	NSSize		titleCharacterSize = pixel_title_size;
	
	// do backdrop
	//
	if (backgroundColor)
	{
		glColor4f([backgroundColor redComponent], [backgroundColor greenComponent], [backgroundColor blueComponent], alpha * [backgroundColor alphaComponent]);
		glBegin(GL_QUADS);
			glVertex3f(x + 0.0f,					y + 0.0f,					z);
			glVertex3f(x + size_in_pixels.width,	y + 0.0f,					z);
			glVertex3f(x + size_in_pixels.width,	y + size_in_pixels.height,	z);
			glVertex3f(x + 0.0f,					y + size_in_pixels.height,	z);
		glEnd();
	}
	
	// show background image...
	//
	if (backgroundSprite)
	{
		[backgroundSprite blitCentredToX:x + 0.5f * size_in_pixels.width Y:y + 0.5f * size_in_pixels.height Z:z alpha:alpha];
	}
	
	if (!RowInRange(selectedRow, selectableRange))
		selectedRow = -1;   // out of Range;
	
	////
	// drawing operations here
	
	if (title != nil)
	{
		//
		// draw the title
		//
		strsize = OORectFromString(title, 0.0f, 0.0f, titleCharacterSize).size;
		glColor4f(1.0f, 0.0f, 0.0f, alpha);	// red
		OODrawString(title, x + pixel_row_center - strsize.width/2.0, y + size_in_pixels.height - pixel_title_size.height, z, titleCharacterSize);
		
		// draw a horizontal divider
		//
		glColor4f(0.75f, 0.75f, 0.75f, alpha);	// 75% gray
		glBegin(GL_QUADS);
			glVertex3f(x + 0,					y + size_in_pixels.height - pixel_title_size.height + 4,	z);
			glVertex3f(x + size_in_pixels.width,	y + size_in_pixels.height - pixel_title_size.height + 4,	z);
			glVertex3f(x + size_in_pixels.width,	y + size_in_pixels.height - pixel_title_size.height + 2,		z);
			glVertex3f(x + 0,					y + size_in_pixels.height - pixel_title_size.height + 2,		z);
		glEnd();
	}
	
	// draw each row of text
	//
	for (i = 0; i < n_rows; i++)
	{
		OOColor* row_color = (OOColor *)[rowColor objectAtIndex:i];
		GLfloat row_alpha = alpha;
		if (rowFadeTime[i] > 0.0f)
		{
			rowFadeTime[i] -= (float)delta_t;
			if (rowFadeTime[i] <= 0.0f)
			{
				[rowText replaceObjectAtIndex:i withObject:@""];
				rowFadeTime[i] = 0.0f;
			}
			if ((rowFadeTime[i] > 0.0f)&&(rowFadeTime[i] < 1.0))
				row_alpha *= rowFadeTime[i];
		}
		glColor4f([row_color redComponent], [row_color greenComponent], [row_color blueComponent], row_alpha);
		
		if ([[rowText objectAtIndex:i] isKindOfClass:[NSString class]])
		{
			NSString*   text = (NSString *)[rowText objectAtIndex:i];
			if (![text isEqual:@""])
			{
				strsize = OORectFromString(text, 0.0f, 0.0f, characterSize).size;
				switch (rowAlignment[i])
				{
					case GUI_ALIGN_LEFT :
						rowPosition[i].x = 0.0f;
						break;
					case GUI_ALIGN_RIGHT :
						rowPosition[i].x = size_in_pixels.width - strsize.width;
						break;
					case GUI_ALIGN_CENTER :
						rowPosition[i].x = (size_in_pixels.width - strsize.width)/2.0f;
						break;
				}
				if (i == (unsigned)selectedRow)
				{
					NSRect block = OORectFromString(text, x + rowPosition[i].x + 2, y + rowPosition[i].y + 2, characterSize);
					glColor4f(1.0f, 0.0f, 0.0f, row_alpha);	// red
					glBegin(GL_QUADS);
						glVertex3f(block.origin.x,						block.origin.y,						z);
						glVertex3f(block.origin.x + block.size.width,	block.origin.y,						z);
						glVertex3f(block.origin.x + block.size.width,	block.origin.y + block.size.height,	z);
						glVertex3f(block.origin.x,						block.origin.y + block.size.height,	z);
					glEnd();
					glColor4f(0.0f, 0.0f, 0.0f, row_alpha);	// black
				}
				OODrawString(text, x + rowPosition[i].x, y + rowPosition[i].y, z, characterSize);
				
				// draw cursor at end of current Row
				//
				if ((showTextCursor)&&(i == (unsigned)currentRow))
				{
					NSRect	tr = OORectFromString(text, 0.0f, 0.0f, characterSize);
					NSPoint cu = NSMakePoint(x + rowPosition[i].x + tr.size.width + 0.2f * characterSize.width, y + rowPosition[i].y);
					tr.origin = cu;
					tr.size.width = 0.5f * characterSize.width;
					GLfloat g_alpha = 0.5f * (1.0f + (float)sin(6 * [UNIVERSE getTime]));
					glColor4f(1.0f, 0.0f, 0.0f, row_alpha * g_alpha);	// red
					glBegin(GL_QUADS);
						glVertex3f(tr.origin.x,					tr.origin.y,					z);
						glVertex3f(tr.origin.x + tr.size.width,	tr.origin.y,					z);
						glVertex3f(tr.origin.x + tr.size.width,	tr.origin.y + tr.size.height,	z);
						glVertex3f(tr.origin.x,					tr.origin.y + tr.size.height,	z);
					glEnd();
				}
			}
		}
		if ([[rowText objectAtIndex:i] isKindOfClass:[NSArray class]])
		{
			unsigned j;
			NSArray*	array = (NSArray *)[rowText objectAtIndex:i];
			unsigned max_columns=[array count] < n_columns ? [array count] : n_columns;
			BOOL isLeftAligned;
			
			for (j = 0; j < max_columns ; j++)
			{
				NSString*   text = [array stringAtIndex:j];
				if ([text length] != 0)
				{
					isLeftAligned=tabStops[j]>=0;
					rowPosition[i].x = abs(tabStops[j]);
					NSRect block = OORectFromString(text, x + rowPosition[i].x + 2, y + rowPosition[i].y + 2, characterSize);
					if(!isLeftAligned)
					{
						rowPosition[i].x -=block.size.width+6;
						block = OORectFromString(text, x + rowPosition[i].x, y + rowPosition[i].y + 2, characterSize);
						block.size.width+=2;
					}					
					if (i == (unsigned)selectedRow)
					{
						glColor4f(1.0f, 0.0f, 0.0f, row_alpha);	// red
						glBegin(GL_QUADS);
							glVertex3f(block.origin.x,						block.origin.y,						z);
							glVertex3f(block.origin.x + block.size.width,	block.origin.y,						z);
							glVertex3f(block.origin.x + block.size.width,	block.origin.y + block.size.height,	z);
							glVertex3f(block.origin.x,						block.origin.y + block.size.height,	z);
						glEnd();
						glColor4f(0.0f, 0.0f, 0.0f, row_alpha);	// black
					}
					OODrawString(text, x + rowPosition[i].x, y + rowPosition[i].y, z, characterSize);
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
	
	double fuel = 35.0 * [player dialFuel];
	
	Random_Seed g_seed;
	double		hcenter = size_in_pixels.width/2.0;
	double		vcenter = 160.0f;
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
	glColor4f(0.0f, 1.0f, 0.0f, alpha);	//	green
	glLineWidth(2.0f);
	cu = NSMakePoint((float)(hscale*galaxy_coordinates.x+hoffset),(float)(vscale*galaxy_coordinates.y+voffset));
	GLDrawOval(x + cu.x, y + cu.y, z, NSMakeSize((float)(fuel*hscale), 2*(float)(fuel*vscale)), 5);
		
	// draw marks and stars
	//
	glLineWidth(1.5f);
	glColor4f(1.0f, 1.0f, 0.75f, alpha);	// pale yellow

	for (i = 0; i < 256; i++)
	{
		g_seed = [UNIVERSE systemSeedForSystemNumber:i];
		
		int dx, dy;
		float blob_size = 4.0f + 0.5f * (g_seed.f & 15);
				
		star.x = (float)(g_seed.d * hscale + hoffset);
		star.y = (float)(g_seed.b * vscale + voffset);
		
		dx = abs(galaxy_coordinates.x - g_seed.d);
		dy = abs(galaxy_coordinates.y - g_seed.b);
		
		if ((dx < 20)&&(dy < 38))
		{
			if ([markedDestinations boolAtIndex:i])	// is marked
			{
				GLfloat mark_size = 0.5f * blob_size + 2.5f;
				glColor4f(1.0f, 0.0f, 0.0f, alpha);	// red
				glBegin(GL_LINES);
					glVertex3f(x + star.x - mark_size,	y + star.y - mark_size,	z);
					glVertex3f(x + star.x + mark_size,	y + star.y + mark_size,	z);
					glVertex3f(x + star.x - mark_size,	y + star.y + mark_size,	z);
					glVertex3f(x + star.x + mark_size,	y + star.y - mark_size,	z);
				glEnd();
				glColor4f(1.0f, 1.0f, 0.75f, alpha);	// pale yellow
			}
			GLDrawFilledOval(x + star.x, y + star.y, z, NSMakeSize(blob_size,blob_size), 15);
		}
	}
	
	// draw names
	//
	glColor4f(1.0f, 1.0f, 0.0f, alpha);	// yellow
	for (i = 0; i < 256; i++)
	{
		g_seed = [UNIVERSE systemSeedForSystemNumber:i];
		
		int dx, dy;
		
		star.x = (float)(g_seed.d * hscale + hoffset);
		star.y = (float)(g_seed.b * vscale + voffset);
		
		dx = abs(galaxy_coordinates.x - g_seed.d);
		dy = abs(galaxy_coordinates.y - g_seed.b);
		
		if ((dx < 20)&&(dy < 38))
		{
			NSDictionary* sys_info = [UNIVERSE generateSystemData:g_seed];
			int tec = [sys_info intForKey:KEY_TECHLEVEL];
			int eco = [sys_info intForKey:KEY_ECONOMY];
			int gov = [sys_info intForKey:KEY_GOVERNMENT];
			NSString*   p_name = [sys_info stringForKey:KEY_NAME];
			if (![player showInfoFlag])
			{
				OODrawString(p_name, x + star.x, y + star.y, z, NSMakeSize(pixel_row_height,pixel_row_height));
			}
			else
			{
				OODrawPlanetInfo(gov, eco, tec, x + star.x + 2.0, y + star.y + 2.0, z, NSMakeSize(pixel_row_height,pixel_row_height));
			}
		}
	}
	
	// draw cross-hairs over current location
	//
	glColor4f(0.0f, 1.0f, 0.0f, alpha);	//	green
	glBegin(GL_QUADS);
		glVertex3f(x + cu.x - 1,	y + cu.y - 14,	z);
		glVertex3f(x + cu.x + 1,	y + cu.y - 14,	z);
		glVertex3f(x + cu.x + 1,	y + cu.y + 14,	z);
		glVertex3f(x + cu.x - 1,	y + cu.y + 14,	z);
		glVertex3f(x + cu.x - 14,	y + cu.y - 1,	z);
		glVertex3f(x + cu.x + 14,	y + cu.y - 1,	z);
		glVertex3f(x + cu.x + 14,	y + cu.y + 1,	z);
		glVertex3f(x + cu.x - 14,	y + cu.y + 1,	z);
	glEnd();
	
	// draw cross hairs over cursor
	//
	glColor4f(1.0f, 0.0f, 0.0f, alpha);	//	red
	cu = NSMakePoint((float)(hscale*cursor_coordinates.x+hoffset),(float)(vscale*cursor_coordinates.y+voffset));
	glBegin(GL_QUADS);
		glVertex3f(x + cu.x - 1,	y + cu.y - 7,	z);
		glVertex3f(x + cu.x + 1,	y + cu.y - 7,	z);
		glVertex3f(x + cu.x + 1,	y + cu.y + 7,	z);
		glVertex3f(x + cu.x - 1,	y + cu.y + 7,	z);
		glVertex3f(x + cu.x - 7,	y + cu.y - 1,	z);
		glVertex3f(x + cu.x + 7,	y + cu.y - 1,	z);
		glVertex3f(x + cu.x + 7,	y + cu.y + 1,	z);
		glVertex3f(x + cu.x - 7,	y + cu.y + 1,	z);
	glEnd();
}


- (void) drawGalaxyChart:(GLfloat)x :(GLfloat)y :(GLfloat)z :(GLfloat) alpha
{
	PlayerEntity* player = [PlayerEntity sharedPlayer];

	NSPoint	galaxy_coordinates = [player galaxy_coordinates];
	NSPoint	cursor_coordinates = [player cursor_coordinates];

	double fuel = 35.0 * [player dialFuel];

	// get a list of systems marked as contract destinations
	NSArray* markedDestinations = [player markedDestinations];
	
	BOOL* systems_found = [UNIVERSE systems_found];
	
	NSPoint		star, cu;
	
	Random_Seed g_seed;
	double		hscale = size_in_pixels.width / 256.0;
	double		vscale = -1.0 * size_in_pixels.height / 512.0;
	double		hoffset = 0.0f;
	double		voffset = size_in_pixels.height - pixel_title_size.height - 5;
	int			i;
	
	if (showAdvancedNavArray && ![UNIVERSE strict] && [player hasEquipmentItem:@"EQ_ADVANCED_NAVIGATIONAL_ARRAY"])
	{
		[self drawAdvancedNavArrayAtX:x y:y z:z alpha:alpha];
	}
	
	// draw fuel range circle
	//
	glColor4f(0.0f, 1.0f, 0.0f, alpha);	//	green
	glLineWidth(2.0f);
	cu = NSMakePoint((float)(hscale*galaxy_coordinates.x+hoffset),(float)(vscale*galaxy_coordinates.y+voffset));
	GLDrawOval(x + cu.x, y + cu.y, z, NSMakeSize((float)(fuel*hscale), 2*(float)(fuel*vscale)), 5);
	
	// draw cross-hairs over current location
	//
	glBegin(GL_QUADS);
		glVertex3f(x + cu.x - 1,	y + cu.y - 14,	z);
		glVertex3f(x + cu.x + 1,	y + cu.y - 14,	z);
		glVertex3f(x + cu.x + 1,	y + cu.y + 14,	z);
		glVertex3f(x + cu.x - 1,	y + cu.y + 14,	z);
		glVertex3f(x + cu.x - 14,	y + cu.y - 1,	z);
		glVertex3f(x + cu.x + 14,	y + cu.y - 1,	z);
		glVertex3f(x + cu.x + 14,	y + cu.y + 1,	z);
		glVertex3f(x + cu.x - 14,	y + cu.y + 1,	z);
	glEnd();
	
	// draw cross hairs over cursor
	//
	glColor4f(1.0f, 0.0f, 0.0f, alpha);	//	red
	cu = NSMakePoint((float)(hscale*cursor_coordinates.x+hoffset),(float)(vscale*cursor_coordinates.y+voffset));
	glBegin(GL_QUADS);
		glVertex3f(x + cu.x - 1,	y + cu.y - 7,	z);
		glVertex3f(x + cu.x + 1,	y + cu.y - 7,	z);
		glVertex3f(x + cu.x + 1,	y + cu.y + 7,	z);
		glVertex3f(x + cu.x - 1,	y + cu.y + 7,	z);
		glVertex3f(x + cu.x - 7,	y + cu.y - 1,	z);
		glVertex3f(x + cu.x + 7,	y + cu.y - 1,	z);
		glVertex3f(x + cu.x + 7,	y + cu.y + 1,	z);
		glVertex3f(x + cu.x - 7,	y + cu.y + 1,	z);
	glEnd();
	
	// draw marks
	//
	glLineWidth(1.5f);
	glColor4f(1.0f, 0.0f, 0.0f, alpha);
	for (i = 0; i < 256; i++)
	{
		g_seed = [UNIVERSE systemSeedForSystemNumber:i];
		BOOL mark = [(NSNumber*)[markedDestinations objectAtIndex:i] boolValue];
		if (mark)
		{
			star.x = (float)(g_seed.d * hscale + hoffset);
			star.y = (float)(g_seed.b * vscale + voffset);
			glBegin(GL_LINES);
				glVertex3f(x + star.x - 2.5f,	y + star.y - 2.5f,	z);
				glVertex3f(x + star.x + 2.5f,	y + star.y + 2.5f,	z);
				glVertex3f(x + star.x - 2.5f,	y + star.y + 2.5f,	z);
				glVertex3f(x + star.x + 2.5f,	y + star.y - 2.5f,	z);
			glEnd();
		}
	}
	
	// draw stars
	//
	glColor4f(1.0f, 1.0f, 1.0f, alpha);
	glBegin(GL_QUADS);
	for (i = 0; i < 256; i++)
	{
		g_seed = [UNIVERSE systemSeedForSystemNumber:i];
		
		star.x = (float)(g_seed.d * hscale + hoffset);
		star.y = (float)(g_seed.b * vscale + voffset);

		float sz = (4.0f + 0.5f * (0x03 | (g_seed.f & 0x0f))) / 7.0f;
		
		glVertex3f(x + star.x, y + star.y + sz, z);
		glVertex3f(x + star.x + sz,	y + star.y, z);
		glVertex3f(x + star.x, y + star.y - sz, z);
		glVertex3f(x + star.x - sz,	y + star.y, z);
	}
	glEnd();
		
	// draw found stars and captions
	//
	glLineWidth(1.5f);
	glColor4f(0.0f, 1.0f, 0.0f, alpha);
	int n_matches=0;
	for (i = 0; i < 256; i++) if (systems_found[i]) n_matches++;
	BOOL drawNames=n_matches<4;
	for (i = 0; i < 256; i++)
	{
		BOOL mark = systems_found[i];
		g_seed = [UNIVERSE systemSeedForSystemNumber:i];
		if (mark)
		{
			star.x = (float)(g_seed.d * hscale + hoffset);
			star.y = (float)(g_seed.b * vscale + voffset);
			glBegin(GL_LINE_LOOP);
				glVertex3f(x + star.x - 2.0f,	y + star.y - 2.0f,	z);
				glVertex3f(x + star.x + 2.0f,	y + star.y - 2.0f,	z);
				glVertex3f(x + star.x + 2.0f,	y + star.y + 2.0f,	z);
				glVertex3f(x + star.x - 2.0f,	y + star.y + 2.0f,	z);
			glEnd();
			if (drawNames)
				OODrawString([UNIVERSE systemNameIndex:i] , x + star.x + 2.0, y + star.y - 10.0f, z, NSMakeSize(10,10));
		}
	}
	
	// draw bottom horizontal divider
	//
	glColor4f(0.75f, 0.75f, 0.75f, alpha);	// 75% gray
	glBegin(GL_QUADS);
		glVertex3f(x + 0, (float)(y + voffset + 260.0f*vscale + 0),	z);
		glVertex3f(x + size_in_pixels.width, y + (float)(voffset + 260.0f*vscale + 0), z);
		glVertex3f(x + size_in_pixels.width, (float)(y + voffset + 260.0f*vscale - 2), z);
		glVertex3f(x + 0, (float)(y + voffset + 260.0f*vscale - 2), z);
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
	double			hoffset = 0.0f;
	double			voffset = size_in_pixels.height - pixel_title_size.height - 5;
	NSPoint			star, star2 = NSZeroPoint;
	
	glColor4f(0.25f, 0.25f, 0.25f, alpha);
	
	glBegin(GL_LINES );
	for (i = 0; i < 256; i++) for (j = i + 1; j < 256; j++)
	{
		g_seed = [UNIVERSE systemSeedForSystemNumber:i];
		g_seed2 = [UNIVERSE systemSeedForSystemNumber:j];
		
		star.x = (float)(g_seed.d * hscale + hoffset);
		star.y = (float)(g_seed.b * vscale + voffset);
		star2.x = (float)(g_seed2.d * hscale + hoffset);
		star2.y = (float)(g_seed2.b * vscale + voffset);
		double d = distanceBetweenPlanetPositions(g_seed.d, g_seed.b, g_seed2.d, g_seed2.b);
		
		if (d <= ([player fuelCapacity] / 10.0f))	// another_commander - Default to 7.0 LY.
		{
			glVertex3f(x+star.x, y+star.y, z);
			glVertex3f(x+star2.x, y+star2.y, z);
		}
	}
	glEnd();
	
	// Draw route from player position to currently selected destination.
	int planetNumber = [UNIVERSE findSystemNumberAtCoords:galaxy_coordinates withGalaxySeed:galaxy_seed];
	int destNumber = [UNIVERSE findSystemNumberAtCoords:cursor_coordinates withGalaxySeed:galaxy_seed];
	NSDictionary* routeInfo = [UNIVERSE routeFromSystem:planetNumber toSystem:destNumber];
	
	if ((destNumber != planetNumber) && routeInfo)
	{
		int route_hops = [(NSArray *)[routeInfo objectForKey:@"route"] count] -1;
		
		glColor4f (1.0f, 1.0f, 0.0f, alpha); // Yellow for plotting routes.
		for (i = 0; i < route_hops; i++)
		{
			int loc = [(NSNumber *)[[routeInfo objectForKey:@"route"] objectAtIndex:i] intValue];
			int loc2 = [(NSNumber *)[[routeInfo objectForKey:@"route"] objectAtIndex:(i+1)] intValue];
			
			g_seed = [UNIVERSE systemSeedForSystemNumber:loc];
			g_seed2 = [UNIVERSE systemSeedForSystemNumber:(loc2)];
			star.x = (float)(g_seed.d * hscale + hoffset);
			star.y = (float)(g_seed.b * vscale + voffset);
			star2.x = (float)(g_seed2.d * hscale + hoffset);
			star2.y = (float)(g_seed2.b * vscale + voffset);
			
			glBegin (GL_LINES);
			glVertex3f (x+star.x, y+star.y, z);
			glVertex3f (x+star2.x, y+star2.y, z);
			glEnd();
			
			// Label the route.
			OODrawString([UNIVERSE systemNameIndex:loc] , x + star.x + 2.0, y + star.y - 6.0, z, NSMakeSize(8,8));
		}
		// Label the destination, which was not included in the above loop.
		OODrawString([UNIVERSE systemNameIndex:destNumber] , x + star2.x + 2.0, y + star2.y - 6.0, z, NSMakeSize(8,8));	
	}
}

@end
