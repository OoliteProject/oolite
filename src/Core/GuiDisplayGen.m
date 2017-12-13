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
#import "Universe.h"
#import "GameController.h"
#import "PlayerEntity.h"
#import "PlayerEntityControls.h"
#import "OOTextureSprite.h"
#import "ResourceManager.h"
#import "OOSound.h"
#import "OOStringExpander.h"
#import "OOStringParsing.h"
#import "HeadUpDisplay.h"
#import "OOCollectionExtractors.h"
#import "OOTexture.h"
#import "OOJavaScriptEngine.h"
#import "PlayerEntityStickProfile.h"
#import "OOSystemDescriptionManager.h"

OOINLINE BOOL RowInRange(OOGUIRow row, NSRange range)
{
	return ((int)range.location <= row && row < (int)(range.location + range.length));
}

@interface GuiDisplayGen (Internal)

- (void) drawGLDisplay:(GLfloat)x :(GLfloat)y :(GLfloat)z :(GLfloat) alpha;

- (void) drawCrossHairsWithSize:(GLfloat) size x:(GLfloat)x y:(GLfloat)y z:(GLfloat)z;
- (void) drawStarChart:(GLfloat)x :(GLfloat)y :(GLfloat)z :(GLfloat) alpha :(BOOL) compact;
- (void) drawSystemMarkers:(NSArray *)marker atX:(GLfloat)x andY:(GLfloat)y andZ:(GLfloat)z withAlpha:(GLfloat)alpha andScale:(GLfloat)scale;
- (void) drawSystemMarker:(NSDictionary *)marker atX:(GLfloat)x andY:(GLfloat)y andZ:(GLfloat)z withAlpha:(GLfloat)alpha andScale:(GLfloat)scale;

- (void) drawEquipmentList:(NSArray *)eqptList z:(GLfloat)z;
- (void) drawAdvancedNavArrayAtX:(float)x y:(float)y z:(float)z alpha:(float)alpha usingRoute:(NSDictionary *) route optimizedBy:(OORouteType) optimizeBy zoom: (OOScalar) zoom;

@end


@implementation GuiDisplayGen

static BOOL _refreshStarChart = NO;

- (id) init
{
	if ((self = [super init]))
	{
		size_in_pixels  = NSMakeSize(MAIN_GUI_PIXEL_WIDTH, MAIN_GUI_PIXEL_HEIGHT);
		n_columns		= GUI_DEFAULT_COLUMNS;
		n_rows			= GUI_DEFAULT_ROWS;
		pixel_row_center = size_in_pixels.width / 2;
		pixel_row_height = MAIN_GUI_ROW_HEIGHT;
		pixel_row_start	= MAIN_GUI_PIXEL_ROW_START;		// first position down the page...
		max_alpha = 1.0;
		
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
		
		backgroundSpecial = GUI_BACKGROUND_SPECIAL_NONE;

		guiUserSettings = [[ResourceManager dictionaryFromFilesNamed:@"gui-settings.plist" inFolder:@"Config" andMerge:YES] retain];
	}
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
	max_alpha = 1.0;

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
	[foregroundSprite release];
	[backgroundColor release];
	[textColor release];
	[title release];
	[rowText release];
	[rowKey release];
	[rowColor release];
	[guiUserSettings release];

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


- (NSDictionary *) userSettings
{
	return guiUserSettings;
}


- (void) fadeOutFromTime:(OOTimeAbsolute) now_time overDuration:(OOTimeDelta) duration
{
	if (fade_alpha <= 0.0f) 
	{
		return;
	}
	if (duration == 0.0)
		fade_sign = -1000.0f;
	else
		fade_sign = (float)(-fade_alpha / duration);
}


- (void) stopFadeOuts
{
	fade_sign = 0.0f;
}


- (GLfloat) alpha
{
	return fade_alpha;
}


- (void) setAlpha:(GLfloat) an_alpha
{
	fade_alpha = an_alpha * max_alpha;
}


- (void) setMaxAlpha:(GLfloat) an_alpha
{
	max_alpha = an_alpha;
}


- (void) setBackgroundColor:(OOColor*) color
{
	[backgroundColor release];
	backgroundColor = [color retain];
}


- (OOColor *) textColor
{
	return textColor;
}


// default text colour for rows
- (void) setTextColor:(OOColor*) color
{
	[textColor release];
	if (color == nil)  color = [[OOColor yellowColor] retain];
	textColor = [color retain];
}


- (OOColor *) textCommsColor
{
	return textCommsColor;
}


- (void) setTextCommsColor:(OOColor*) color
{
	[textCommsColor release];
	if (color == nil)  color = [[OOColor yellowColor] retain];
	textCommsColor = [color retain];
}


- (OOColor *) colorFromSetting:(NSString *)setting defaultValue:(OOColor *)def
{
	
	OOColor *col = nil;
	if (setting != nil) {
		col = [OOColor colorWithDescription:[guiUserSettings objectForKey:setting]];
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


- (void) setGLColorFromSetting:(NSString *)setting defaultValue:(OOColor *)def alpha:(GLfloat)alpha
{
	GLfloat r,g,b,a;
	OOColor *col = [self colorFromSetting:setting defaultValue:def];
	[col getRed:&r green:&g blue:&b alpha:&a];

	OOGL(glColor4f(r, g, b, a*alpha));
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


- (OOGUIRow) rowForKey:(NSString*)key
{
	for (unsigned i=0;i<[rowKey count];i++)
	{
		if ([key isEqualToString:[rowKey objectAtIndex:i]])
		{
			return (OOGUIRow)i;
		}
	}
	return -1;
}


- (NSString*) keyForRow:(OOGUIRow)row
{
	if (RowInRange(row, rowRange))
		return [rowKey objectAtIndex:row];
	else
		return NULL;
}


- (OOGUIRow) selectedRow
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
	OOGUIRow row = selectedRow + direction;
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
	NSUInteger row = selectableRange.location;
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


- (BOOL) setLastSelectableRow
{
	NSUInteger row = selectableRange.location + selectableRange.length - 1;
	while (RowInRange(row, selectableRange))
	{
		if (![[rowKey objectAtIndex:row] isEqual:GUI_KEY_SKIP])
		{
			selectedRow = row;
			return YES;
		}
		row--;
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

- (void) overrideTabs:(OOGUITabSettings)stops from:(NSString *)setting length:(NSUInteger)len
{
	NSArray *override = [guiUserSettings oo_arrayForKey:setting defaultValue:nil];
	NSUInteger i;
	if (stops != NULL && override != nil)
	{
		if (len > GUI_MAX_COLUMNS)
		{
			len = GUI_MAX_COLUMNS;
		}
		for (i=0;i<len;i++) 
		{
			stops[i] = [override oo_unsignedIntegerAtIndex:i defaultValue:stops[i]];
		}
	}
}


- (void) clear
{
	[self clearAndKeepBackground:NO];
}


- (void) clearAndKeepBackground:(BOOL)keepBackground
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
	if (!keepBackground) [self clearBackground];
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


- (OOGUIRow) addLongText:(NSString *)str
		   startingAtRow:(OOGUIRow)row
				   align:(OOGUIAlignment)alignment
{

	if ([str rangeOfString:@"\n"].location != NSNotFound)
	{
		NSArray		*lines = [str componentsSeparatedByString:@"\n"];
		unsigned	i;
		for (i = 0; i < [lines count]; i++)
		{
			row = [self addLongText:[lines oo_stringAtIndex:i] startingAtRow:row align:alignment];
		}
		return row;
	}
	
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


- (NSString *) reflowTextForMFD:(NSString *)input
{
	NSMutableString	*output = [[NSMutableString alloc] initWithCapacity:512];
	NSArray			 *lines = [input componentsSeparatedByString:@"\n"];
	NSSize  		 chSize = pixel_text_size;
	NSUInteger  	  limit = chSize.width * 15;
	NSString  		  *line = nil;
	foreach (line, lines)
	{
		NSMutableArray	*words = ScanTokensFromString(line);
		NSMutableString *accum = [NSMutableString stringWithCapacity:64];
		if ([words count] > 0)
		{
			while ([words count] > 1)
			{
				[accum appendString:[words oo_stringAtIndex:0]];
				[accum appendString:@" "];
				if (OORectFromString(accum, 0.0f, 0.0f,chSize).size.width + OORectFromString([words oo_stringAtIndex:1], 0.0f, 0.0f,chSize).size.width > limit)
				{
					// can't fit next word on this line
					[output appendString:[accum stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
					[output appendString:@"\n"];
					[accum setString:@""];
				}
				[words removeObjectAtIndex:0];
			}
			[output appendString:accum];
			[output appendString:[words oo_stringAtIndex:0]];
		}
		[output appendString:@"\n"];
	}

	return [output autorelease];
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


- (NSArray *) getLastLines	// text, colour, fade time - text, colour, fade time
{
	if (n_rows <1) return nil;
	
	// we have at least 1 row!
	
	unsigned				i = n_rows-1;
	OORGBAComponents		col = [(OOColor *)[rowColor objectAtIndex:i] rgbaComponents];
	
	if (i>0)
	{
		// we have at least 2 rows!
		OORGBAComponents	col0 = [(OOColor *)[rowColor objectAtIndex:i-1] rgbaComponents];
		return [NSArray arrayWithObjects:[rowText oo_stringAtIndex:i-1],
										[NSString stringWithFormat:@"%.3g %.3g %.3g %.3g", col0.r, col0.g, col0.b, col0.a],
										[NSNumber numberWithFloat:rowFadeTime[i-1]],
										[rowText oo_stringAtIndex:i],
										[NSString stringWithFormat:@"%.3g %.3g %.3g %.3g", col.r, col.g, col.b, col.a],
										[NSNumber numberWithFloat:rowFadeTime[i]], nil];
	}
	else
	{
		return [NSArray arrayWithObjects:[rowText oo_stringAtIndex:i],
										[NSString stringWithFormat:@"%.3g %.3g %.3g %.3g", col.r, col.g, col.b, col.a],
										[NSNumber numberWithFloat:rowFadeTime[i]], nil];
	}
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
			[self printLongText:[lines oo_stringAtIndex:i] align:alignment color:text_color fadeTime:text_fade key:text_key addToArray:text_array];
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
		if (text_array)
			[text_array addObject:str];
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
				strsize.width += OORectFromString([words oo_stringAtIndex:0], 0.0f, 0.0f, chSize).size.width;
		}

		[self setText:string1		forRow:row			align:alignment];

		[string2 appendString:[words componentsJoinedByString:@" "]];
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
	
	NSUInteger n_items = [items count];
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


- (void) clearBackground
{
	[self setBackgroundTextureDescriptor:nil];
	[self setForegroundTextureDescriptor:nil];
}


static OOTexture *TextureForGUITexture(NSDictionary *descriptor)
{
	return [OOTexture textureWithName:[descriptor oo_stringForKey:@"name"]
							 inFolder:@"Images"
							  options:kOOTextureDefaultOptions | kOOTextureNoShrink
						   anisotropy:kOOTextureDefaultAnisotropy
							  lodBias:kOOTextureDefaultLODBias];
}


/*
	Load a texture sprite given a descriptor. The caller owns a reference to
	the result.
*/
static OOTextureSprite *NewTextureSpriteWithDescriptor(NSDictionary *descriptor)
{
	OOTexture		*texture = nil;
	NSSize			size;
	
	texture = TextureForGUITexture(descriptor);
	if (texture == nil)  return nil;
	
	double specifiedWidth = [descriptor oo_doubleForKey:@"width" defaultValue:-INFINITY];
	double specifiedHeight = [descriptor oo_doubleForKey:@"height" defaultValue:-INFINITY];
	BOOL haveWidth = isfinite(specifiedWidth);
	BOOL haveHeight = isfinite(specifiedHeight);
	
	if (haveWidth && haveHeight)
	{
		// Both specified, use directly without calling -originalDimensions (which may block).
		size.width = specifiedWidth;
		size.height = specifiedHeight;
	}
	else
	{
		NSSize originalDimensions = [texture originalDimensions];
		
		if (haveWidth)
		{
			// Width specified, but not height; preserve aspect ratio.
			CGFloat ratio = originalDimensions.height / originalDimensions.width;
			size.width = specifiedWidth;
			size.height = ratio * size.width;
		}
		else if (haveHeight)
		{
			// Height specified, but not width; preserve aspect ratio.
			CGFloat ratio = originalDimensions.width / originalDimensions.height;
			size.height = specifiedHeight;
			size.width = ratio * size.height;
		}
		else
		{
			// Neither specified; use backwards-compatible behaviour.
			size = originalDimensions;
		}
	}
	
	return [[OOTextureSprite alloc] initWithTexture:texture size:size];
}


- (void) setBackgroundTextureSpecial:(OOGUIBackgroundSpecial)spec withBackground:(BOOL)withBackground
{
	if (withBackground) 
	{
		NSDictionary *bgDescriptor = nil;
		OOGalaxyID galaxy_number = [PLAYER galaxyNumber];

		switch (spec) 
		{
		case GUI_BACKGROUND_SPECIAL_SHORT:
			bgDescriptor = [UNIVERSE screenTextureDescriptorForKey:@"short_range_chart_mission"];
			if (bgDescriptor == nil) 
			{
				bgDescriptor = [UNIVERSE screenTextureDescriptorForKey:@"short_range_chart"];
			}
			break;
		case GUI_BACKGROUND_SPECIAL_LONG:
		case GUI_BACKGROUND_SPECIAL_LONG_ANA_SHORTEST:
		case GUI_BACKGROUND_SPECIAL_LONG_ANA_QUICKEST:
			bgDescriptor = [UNIVERSE screenTextureDescriptorForKey:[NSString stringWithFormat:@"long_range_chart%d_mission", galaxy_number+1]];
			if (bgDescriptor == nil) 
			{
				bgDescriptor = [UNIVERSE screenTextureDescriptorForKey:@"long_range_chart_mission"];
				if (bgDescriptor == nil) 
				{
					bgDescriptor = [UNIVERSE screenTextureDescriptorForKey:[NSString stringWithFormat:@"long_range_chart%d", galaxy_number+1]];
					if (bgDescriptor == nil) 
					{
						bgDescriptor = [UNIVERSE screenTextureDescriptorForKey:@"long_range_chart"];
						
					}
				}
			}
			break;
		case GUI_BACKGROUND_SPECIAL_NONE:
			break;
		}
		if (bgDescriptor != nil)
		{
			[self setBackgroundTextureDescriptor:bgDescriptor];
		}
	}
	backgroundSpecial = spec;
	[self refreshStarChart];
}


- (BOOL) setBackgroundTextureDescriptor:(NSDictionary *)descriptor
{
	[backgroundSprite autorelease];
	backgroundSpecial = GUI_BACKGROUND_SPECIAL_NONE; // reset
	backgroundSprite = NewTextureSpriteWithDescriptor(descriptor);
	return backgroundSprite != nil;
}


- (BOOL) setForegroundTextureDescriptor:(NSDictionary *)descriptor
{
	[foregroundSprite autorelease];
	foregroundSprite = NewTextureSpriteWithDescriptor(descriptor);
	return foregroundSprite != nil;
}


- (BOOL) setBackgroundTextureKey:(NSString *)key
{
	return [self setBackgroundTextureDescriptor:[UNIVERSE screenTextureDescriptorForKey:key]];
}


- (BOOL) setForegroundTextureKey:(NSString *)key
{
	return [self setForegroundTextureDescriptor:[UNIVERSE screenTextureDescriptorForKey:key]];
}


- (BOOL) preloadGUITexture:(NSDictionary *)descriptor
{
	return TextureForGUITexture(descriptor) != nil;
}


- (NSDictionary *) textureDescriptorFromJSValue:(jsval)value
									  inContext:(JSContext *)context
							  callerDescription:(NSString *)callerDescription
{
	OOJS_PROFILE_ENTER
	
	NSDictionary	*result = nil;
	
	if (JSVAL_IS_OBJECT(value))
	{
		// Null may be used to indicate no texture.
		if (JSVAL_IS_NULL(value))  return [NSDictionary dictionary];
		
		JSObject *objValue = JSVAL_TO_OBJECT(value);
		
		if (OOJSGetClass(context, objValue) != [[OOJavaScriptEngine sharedEngine] stringClass])
		{
			result = OOJSDictionaryFromJSObject(context, objValue);
		}
	}
	
	if (result == nil)
	{
		NSString *name = OOStringFromJSValue(context, value);

		if (name != nil)
		{
			result = [NSDictionary dictionaryWithObject:name forKey:@"name"];
			if ([name length] == 0)  return result;	// Explicit empty string may be used to indicate no texture.
		}
	}
	
	// Start loading the texture, and return nil if it doesn't exist.
	if (result != nil && ![self preloadGUITexture:result])
	{
		OOJSReportWarning(context, @"%@: texture \"%@\" could not be found.", callerDescription, [result oo_stringForKey:@"name"]);
		result = nil;
	}
	
	return result;
	
	OOJS_PROFILE_EXIT
}


- (void) setStatusPage:(NSInteger)pageNum
{
	if (pageNum == 0 || (pageNum < 0 && ((NSUInteger)-pageNum) >= statusPage))
	{ 
		statusPage = 1;
	}
	else 
	{
		statusPage += pageNum;
	}
}


- (NSUInteger) statusPage
{
	return statusPage;
}


- (void) drawEquipmentList:(NSArray *)eqptList z:(GLfloat)z
{
	if ([eqptList count] == 0) return;
	
	OOGUIRow		firstRow = STATUS_EQUIPMENT_FIRST_ROW;
	NSUInteger		maxRows = STATUS_EQUIPMENT_MAX_ROWS;
	if ([[PLAYER hud] allowBigGui])
	{
		maxRows += STATUS_EQUIPMENT_BIGGUI_EXTRA_ROWS;
	}
	NSUInteger		itemsPerColumn = maxRows;


	NSInteger		firstY = 40;	// firstRow =10 :-> 40  - firstRow=11 -> 24 etc...
	NSUInteger		eqptCount = [eqptList count];
	NSUInteger		pageCount = 1;
	NSUInteger		i;
	NSInteger		start;
	NSArray			*info = nil;
	NSString		*name = nil;
	BOOL			damaged;
	
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
			if (statusPage == 1)
			{
				start = 0;
			}
			else
			{
				statusPage = 2;
				start = i/statusPage; // for the for loop
			}
		}
		else // three or more
		{
			pageCount = ceil((float)(eqptCount-i)/(itemsPerColumn*2)) + 2;
			statusPage = (NSInteger)OOClampInteger(statusPage, 1, pageCount);
			start = (statusPage == 1) ? 0 : (statusPage-1) * itemsPerColumn * 2 + 2;
		}
	}
	else
	{
		statusPage = pageCount; // one page
		start = 0;
		// if we have mouse interaction active, it means that we had more than one
		// pages earlier, but only one now, as e.g. in the case of a hud that wss
		// subsequently hidden, resulting in the equip list fitting in one page,
		// so we need to deactivate it
		if (OOMouseInteractionModeIsUIScreen([[UNIVERSE gameController] mouseInteractionMode]))
		{
			// clear the gui-more and gui-back key rows first
			[self setText:@"" forRow:firstRow];
			[self setKey:GUI_KEY_SKIP forRow:firstRow];
			[self setText:@"" forRow:firstRow + STATUS_EQUIPMENT_MAX_ROWS];
			[self setKey:GUI_KEY_SKIP forRow:firstRow + STATUS_EQUIPMENT_MAX_ROWS];
			[self setSelectableRange:NSMakeRange(0,0)];
			
			[[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:NO];
		}
	}
	
	if (statusPage > 1)
	{
		[self setColor:[self colorFromSetting:kGuiStatusEquipmentScrollColor defaultValue:[OOColor greenColor]] forRow:firstRow];
		[self setArray:[NSArray arrayWithObjects:DESC(@"gui-back"),  @"", @" <-- ",nil] forRow:firstRow];
		[self setKey:GUI_KEY_OK forRow:firstRow];
		firstY -= 16; // start 1 row down!
		if (statusPage == pageCount)
		{
			[self setSelectableRange:NSMakeRange(firstRow, 1)];
			[self setSelectedRow:firstRow];
		}
	}
	if (statusPage < pageCount)
	{
		[self setColor:[self colorFromSetting:kGuiStatusEquipmentScrollColor defaultValue:[OOColor greenColor]] forRow:firstRow + maxRows];
		[self setArray:[NSArray arrayWithObjects:DESC(@"gui-more"),  @"", @" --> ",nil] forRow:firstRow + maxRows];
		[self setKey:GUI_KEY_OK forRow:firstRow + maxRows];
		if (statusPage == 1)
		{
			[self setSelectableRange:NSMakeRange(firstRow + maxRows, 1)];
			[self setSelectedRow:firstRow + maxRows];
		}
	}
	if (statusPage > 1 && statusPage < pageCount)
	{
		[self setSelectableRange:NSMakeRange(firstRow, firstRow + maxRows)];
		// default selected row to 'More -->' if we are looking at one of the middle pages
		if ([self selectedRow] == -1)  [self setSelectedRow:firstRow + maxRows];
	}

	if (statusPage == 1 || statusPage == pageCount) itemsPerColumn++;
	eqptCount = (NSInteger)OOClampInteger(eqptCount, 1, start + itemsPerColumn * 2);
	for (i = start; i < eqptCount; i++)
	{
		info = [eqptList oo_arrayAtIndex:i];
		name = [info oo_stringAtIndex:0];
		if([name length] > 42)  name = [[name substringToIndex:40] stringByAppendingString:@"..."];
		
		damaged = ![info oo_boolAtIndex:1];
		if (damaged) 
		{
			// Damaged items show up orange.
			[self setGLColorFromSetting:@"status_equipment_damaged_color" defaultValue:[OOColor orangeColor] alpha:1.0];
		} 
		else /// add color selection here
		{
			OOColor				*dispCol = [info oo_objectAtIndex:2];
			// Normal items in default colour
			[self setGLColorFromSetting:@"status_equipment_ok_color" defaultValue:dispCol alpha:1.0];
		}
		
		if (i - start < itemsPerColumn)
		{
			OODrawString(name, -220, firstY - 16 * (NSInteger)(i - start), z, NSMakeSize(15, 15));
		}
		else
		{
			OODrawString(name, 50, firstY - 16 * (NSInteger)(i - itemsPerColumn - start), z, NSMakeSize(15, 15));
		}
	}
}


- (void) drawGUIBackground
{
	GLfloat x = drawPosition.x;
	GLfloat y = drawPosition.y;
	GLfloat z = [[UNIVERSE gameView] display_z];

	if (backgroundSprite!=nil)
	{
		[backgroundSprite blitBackgroundCentredToX:x Y:y Z:z alpha:1.0f];
	}
	
}


- (void) refreshStarChart
{
	_refreshStarChart = YES;
}


- (int) drawGUI:(GLfloat) alpha drawCursor:(BOOL) drawCursor
{
	GLfloat x = drawPosition.x;
	GLfloat y = drawPosition.y;
	GLfloat z = [[UNIVERSE gameView] display_z];
	
	if (alpha > 0.05f)
	{
		PlayerEntity* player = PLAYER;
		
		[self drawGLDisplay:x - 0.5f * size_in_pixels.width :y - 0.5f * size_in_pixels.height :z :alpha];
		
		if (self == [UNIVERSE gui])
		{
			if ([player guiScreen] == GUI_SCREEN_SHORT_RANGE_CHART || [player guiScreen] == GUI_SCREEN_LONG_RANGE_CHART || backgroundSpecial == GUI_BACKGROUND_SPECIAL_SHORT)
			{
				[self drawStarChart:x - 0.5f * size_in_pixels.width :y - 0.5f * size_in_pixels.height :z :alpha :NO];
			}
			if (backgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG || 
					backgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG_ANA_QUICKEST ||
					backgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG_ANA_SHORTEST)
			{
				[self drawStarChart:x - 0.5f * size_in_pixels.width :y - 0.5f * size_in_pixels.height :z :alpha :YES];
			}
			if ([player guiScreen] == GUI_SCREEN_STATUS)
			{
				[self drawEquipmentList:[player equipmentList] z:z];
			}
			if ([player guiScreen] == GUI_SCREEN_STICKPROFILE)
			{
				[player stickProfileGraphAxisProfile: alpha screenAt: make_vector(x,y,z) screenSize: size_in_pixels];
			}
		}
		
		if (fade_sign)
		{
			fade_alpha += (float)(fade_sign * [UNIVERSE getTimeDelta]);
			if (fade_alpha < 0.05f)	// done fading out
			{
				fade_alpha = 0.0f;
				fade_sign = 0.0f;
			}
			if (fade_alpha >= max_alpha)	// done fading in
			{
				fade_alpha = max_alpha;
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
		OOGL(glColor4f(0.6f, 0.6f, 1.0f, 0.5f)); // original value of (0.2f, 0.2f, 1.0f, 0.5f) too dark - Nikos 20130616
		OOGL(GLScaledLineWidth(2.0f));
		
		cursor_x += x;
		cursor_y += y;
		[[UNIVERSE gameView] setVirtualJoystick:cursor_x/size_in_pixels.width :-cursor_y/size_in_pixels.height];

		OOGLBEGIN(GL_LINES);
			glVertex3f((float)cursor_x - h1, (float)cursor_y, z);	glVertex3f((float)cursor_x - h3, (float)cursor_y, z);
			glVertex3f((float)cursor_x + h1, (float)cursor_y, z);	glVertex3f((float)cursor_x + h3, (float)cursor_y, z);
			glVertex3f((float)cursor_x, (float)cursor_y - h1, z);	glVertex3f((float)cursor_x, (float)cursor_y - h3, z);
			glVertex3f((float)cursor_x, (float)cursor_y + h1, z);	glVertex3f((float)cursor_x, (float)cursor_y + h3, z);
		OOGLEND();
		OOGL(GLScaledLineWidth(1.0f));
		
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
	float		backgroundAlpha = self == [UNIVERSE messageGUI] && ![UNIVERSE permanentMessageLog] ? 0.0f : alpha;
	float		row_alpha[n_rows];
	
	// calculate fade out time and alpha for each row. Do it before
	// applying a potential background because we need the maximum alpha
	// of all rows to be the alpha applied to the background color
	for (i = 0; i < n_rows; i++)
	{
		row_alpha[i] = alpha;
		
		if(![UNIVERSE autoMessageLogBg] && [PLAYER guiScreen] == GUI_SCREEN_MAIN)  backgroundAlpha = alpha;
		
		if (rowFadeTime[i] > 0.0f && ![UNIVERSE permanentMessageLog])
		{
			rowFadeTime[i] -= (float)delta_t;
			if (rowFadeTime[i] <= 0.0f)
			{
				[rowText replaceObjectAtIndex:i withObject:@""];
				rowFadeTime[i] = 0.0f;
				continue;
			}
			if ((rowFadeTime[i] > 0.0f)&&(rowFadeTime[i] < 1.0))
			{
				row_alpha[i] *= rowFadeTime[i];
				if (backgroundAlpha < row_alpha[i])  backgroundAlpha = row_alpha[i];
			}
			else
			{
				backgroundAlpha = alpha;
			}
		}
	}
	
	// do backdrop
	// don't draw it if docked, unless message_gui is permanent
	// don't draw it on the intro screens
	if (backgroundColor)
	{
		int playerStatus = [PLAYER status];
		if (playerStatus != STATUS_START_GAME && playerStatus != STATUS_DEAD)
		{
			OOGL(glColor4f([backgroundColor redComponent], [backgroundColor greenComponent], [backgroundColor blueComponent], backgroundAlpha * [backgroundColor alphaComponent]));
			OOGLBEGIN(GL_QUADS);
				glVertex3f(x + 0.0f,					y + 0.0f,					z);
				glVertex3f(x + size_in_pixels.width,	y + 0.0f,					z);
				glVertex3f(x + size_in_pixels.width,	y + size_in_pixels.height,	z);
				glVertex3f(x + 0.0f,					y + size_in_pixels.height,	z);
			OOGLEND();
		}
	}
	
	// show the 'foreground', aka overlay!
	
	if (foregroundSprite != nil)
	{
		[foregroundSprite blitCentredToX:x + 0.5f * size_in_pixels.width Y:y + 0.5f * size_in_pixels.height Z:z alpha:alpha];
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
		[self setGLColorFromSetting:kGuiScreenTitleColor defaultValue:[OOColor redColor] alpha:alpha];

		OODrawString(title, x + pixel_row_center - strsize.width/2.0, y + size_in_pixels.height - pixel_title_size.height, z, titleCharacterSize);
		
		// draw a horizontal divider
		//
		[self setGLColorFromSetting:kGuiScreenDividerColor defaultValue:[OOColor colorWithWhite:0.75 alpha:1.0] alpha:alpha];

		OOGLBEGIN(GL_QUADS);
			glVertex3f(x + 0,					y + size_in_pixels.height - pixel_title_size.height + 4,	z);
			glVertex3f(x + size_in_pixels.width,	y + size_in_pixels.height - pixel_title_size.height + 4,	z);
			glVertex3f(x + size_in_pixels.width,	y + size_in_pixels.height - pixel_title_size.height + 2,		z);
			glVertex3f(x + 0,					y + size_in_pixels.height - pixel_title_size.height + 2,		z);
		OOGLEND();
	}
	
	// draw each row of text
	//
	OOStartDrawingStrings();
	for (i = 0; i < n_rows; i++)
	{
		OOColor* row_color = (OOColor *)[rowColor objectAtIndex:i];
		glColor4f([row_color redComponent], [row_color greenComponent], [row_color blueComponent], row_alpha[i]);
		
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
					NSRect		block = OORectFromString(text, x + rowPosition[i].x + 2, y + rowPosition[i].y + 2, characterSize);
					OOStopDrawingStrings();
					[self setGLColorFromSetting:kGuiSelectedRowBackgroundColor defaultValue:[OOColor redColor] alpha:alpha];
					OOGLBEGIN(GL_QUADS);
						glVertex3f(block.origin.x,						block.origin.y,						z);
						glVertex3f(block.origin.x + block.size.width,	block.origin.y,						z);
						glVertex3f(block.origin.x + block.size.width,	block.origin.y + block.size.height,	z);
						glVertex3f(block.origin.x,						block.origin.y + block.size.height,	z);
					OOGLEND();
					[self setGLColorFromSetting:kGuiSelectedRowColor defaultValue:[OOColor blackColor] alpha:alpha];
					OOStartDrawingStrings();
				}
				OODrawStringQuadsAligned(text, x + rowPosition[i].x, y + rowPosition[i].y, z, characterSize, NO);
				
				// draw cursor at end of current Row
				//
				if ((showTextCursor)&&(i == (unsigned)currentRow))
				{
					NSRect	tr = OORectFromString(text, 0.0f, 0.0f, characterSize);
					NSPoint cu = NSMakePoint(x + rowPosition[i].x + tr.size.width + 0.2f * characterSize.width, y + rowPosition[i].y);
					tr.origin = cu;
					tr.size.width = 0.5f * characterSize.width;
					GLfloat g_alpha = 0.5f * (1.0f + (float)sin(6 * [UNIVERSE getTime]));
					OOStopDrawingStrings();
					[self setGLColorFromSetting:kGuiTextInputCursorColor defaultValue:[OOColor redColor] alpha:row_alpha[i]*g_alpha];
					OOGLBEGIN(GL_QUADS);
						glVertex3f(tr.origin.x,					tr.origin.y,					z);
						glVertex3f(tr.origin.x + tr.size.width,	tr.origin.y,					z);
						glVertex3f(tr.origin.x + tr.size.width,	tr.origin.y + tr.size.height,	z);
						glVertex3f(tr.origin.x,					tr.origin.y + tr.size.height,	z);
					OOGLEND();
					OOStartDrawingStrings();
				}
			}
		}
		if ([[rowText objectAtIndex:i] isKindOfClass:[NSArray class]])
		{
			NSArray		*array = [rowText oo_arrayAtIndex:i];
			NSUInteger	j, max_columns = MIN([array count], n_columns);
			BOOL		isLeftAligned;
			
			for (j = 0; j < max_columns; j++)
			{
				NSString*   text = [array oo_stringAtIndex:j];
				if ([text length] != 0)
				{
					isLeftAligned = tabStops[j] >= 0;
					rowPosition[i].x = labs(tabStops[j]);
					
					// we don't want to highlight leading space(s) or narrow spaces (\037s)
					NSString	*hilitedText = [text stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \037"]];
					NSRange		txtRange = [text rangeOfString:hilitedText];
					unsigned	leadingSpaces = 0;
					
					if (EXPECT_NOT(txtRange.location == NSNotFound))
					{
						// This never happens!
						hilitedText = text;
					}
					else if (txtRange.location > 0)
					{
						// padded string!
						NSRange padRange;
						padRange.location = 0;
						padRange.length = txtRange.location;
						NSRect charBlock = OORectFromString([text substringWithRange:padRange], 0, 0, characterSize);
						leadingSpaces = (unsigned)charBlock.size.width;

/*						// if we're displaying commodity-quantity-none, let's try and be pixel perfect!
						NSString *qtyNone = DESC(@"commodity-quantity-none");
						txtRange = [hilitedText rangeOfString:qtyNone];
						
						if (txtRange.location == 0) // bingo!
						{
							rowPosition[i].x += OORectFromString(@"0", 0, 0, characterSize).size.width - OORectFromString(qtyNone, 0, 0, characterSize).size.width;
							} */
					}
					
					// baseline text rect, needed for correct highlight positioning.
					NSRect		block = OORectFromString(text, x + rowPosition[i].x + 2, y + rowPosition[i].y + 2, characterSize);
					
					if(!isLeftAligned)
					{
						rowPosition[i].x -= block.size.width + 3;
					}
					block = OORectFromString(hilitedText, x + rowPosition[i].x + 1 + leadingSpaces, y + rowPosition[i].y + 2, characterSize);
					block.size.width += 3;
						
					
					if (i == (unsigned)selectedRow)
					{
						OOStopDrawingStrings();
						[self setGLColorFromSetting:kGuiSelectedRowBackgroundColor defaultValue:[OOColor redColor] alpha:alpha];
						OOGLBEGIN(GL_QUADS);
							glVertex3f(block.origin.x,						block.origin.y,						z);
							glVertex3f(block.origin.x + block.size.width,	block.origin.y,						z);
							glVertex3f(block.origin.x + block.size.width,	block.origin.y + block.size.height,	z);
							glVertex3f(block.origin.x,						block.origin.y + block.size.height,	z);
						OOGLEND();
						[self setGLColorFromSetting:kGuiSelectedRowColor defaultValue:[OOColor blackColor] alpha:alpha];
						OOStartDrawingStrings();
					}
					OODrawStringQuadsAligned(text, x + rowPosition[i].x, y + rowPosition[i].y, z, characterSize,NO);
				}
			}
		}
	}
	OOStopDrawingStrings();
	[OOTexture applyNone];
}


- (void) drawCrossHairsWithSize:(GLfloat) size x:(GLfloat)x y:(GLfloat)y z:(GLfloat)z
{
	OOGLBEGIN(GL_QUADS);
		glVertex3f(x - 1,	y - size,	z);
		glVertex3f(x + 1,	y - size,	z);
		glVertex3f(x + 1,	y + size,	z);
		glVertex3f(x - 1,	y + size,	z);
		glVertex3f(x - size,	y - 1,	z);
		glVertex3f(x + size,	y - 1,	z);
		glVertex3f(x + size,	y + 1,	z);
		glVertex3f(x - size,	y + 1,	z);
	OOGLEND();
}


- (void) setStarChartTitle
{
	PlayerEntity *player = PLAYER;
	OOGalaxyID galaxy_number = [player galaxyNumber];
	NSInteger system_id = [UNIVERSE findSystemNumberAtCoords:[player cursor_coordinates] withGalaxy:[player galaxyNumber] includingHidden:NO];

	NSString *location_key = [NSString stringWithFormat:@"long-range-chart-title-%d-%ld", galaxy_number, (long)system_id];
	if ([[UNIVERSE descriptions] valueForKey:location_key] == nil)
	{
		NSString *gal_key = [NSString stringWithFormat:@"long-range-chart-title-%d", galaxy_number];
		if ([[UNIVERSE descriptions] valueForKey:gal_key] == nil)
		{
			[self setTitle:[NSString stringWithFormat:DESC(@"long-range-chart-title-d"), galaxy_number+1]];
		}
		else
		{
			[self setTitle:[UNIVERSE descriptionForKey:gal_key]];
		}
	}
	else
	{
		[self setTitle:[UNIVERSE descriptionForKey:location_key]];
	}
}


- (void) drawStarChart:(GLfloat)x :(GLfloat)y :(GLfloat)z :(GLfloat) alpha :(BOOL)compact
{
	PlayerEntity* player = PLAYER;

	if (!player)
		return;

	OOSystemDescriptionManager *systemManager = [UNIVERSE systemManager];

	OOScalar	zoom = [player chart_zoom];
	NSPoint	chart_centre_coordinates = [player adjusted_chart_centre];
	NSPoint	galaxy_coordinates = [player galaxy_coordinates];
	NSPoint	cursor_coordinates = [player cursor_coordinates];
	NSPoint info_system_coordinates = [[UNIVERSE systemManager] getCoordinatesForSystem: [player infoSystemID] inGalaxy: [player galaxyNumber]];
	OOLongRangeChartMode chart_mode = [player longRangeChartMode];
	OOGalaxyID		galaxy_id = [player galaxyNumber];
	GLfloat			r = 1.0, g = 1.0, b = 1.0;
	BOOL			noNova;
	NSPoint	cu;
	NSUInteger		systemParameter;

	double fuel = 35.0 * [player dialFuel];
	
	double		hcenter = size_in_pixels.width/2.0;
	double		hscale = size_in_pixels.width / (CHART_WIDTH_AT_MAX_ZOOM*zoom);
	double		vscale = -size_in_pixels.height / (2*CHART_HEIGHT_AT_MAX_ZOOM*zoom);
	double		vcenter = CHART_SCREEN_VERTICAL_CENTRE;
	double		hoffset = hcenter - chart_centre_coordinates.x*hscale;
	double		voffset = size_in_pixels.height - vcenter - chart_centre_coordinates.y*vscale;

	if (compact)
	{
		hscale = size_in_pixels.width / 256.0;
		vscale = -1.0 * size_in_pixels.height / 512.0;
		hoffset = 0.0f;
		voffset = size_in_pixels.height - pixel_title_size.height - 5;
		vcenter = CHART_SCREEN_VERTICAL_CENTRE_COMPACT;
		chart_centre_coordinates.x = 128.0;
		chart_centre_coordinates.y = 128.0;
		zoom = CHART_MAX_ZOOM;
	}
	
	int			i;
	double		d, distance = 0.0, time = 0.0;
	int		jumps = 0;
	NSPoint		star;
	OOScalar	pixelRatio;
	NSRect		clipRect;
	
	OORouteType	advancedNavArrayMode = [player ANAMode];
	BOOL		routeExists = NO;

	NSInteger concealment[256];
	for (i=0;i<256;i++) {
		NSDictionary *systemInfo = [systemManager getPropertiesForSystem:i inGalaxy:galaxy_id];
		concealment[i] = [systemInfo oo_intForKey:@"concealment" defaultValue:OO_SYSTEMCONCEALMENT_NONE];
	}
	
	BOOL		*systemsFound = [UNIVERSE systemsFound];
	NSSize		viewSize = [[UNIVERSE gameView] backingViewSize];
	double aspect_ratio = viewSize.width / viewSize.height;

	// default colours - match those in HeadUpDisplay:OODrawPlanetInfo
	GLfloat govcol[] = {	0.5, 0.0, 0.7,
							0.7, 0.5, 0.3,
							0.0, 1.0, 0.3,
							1.0, 0.8, 0.1,
							1.0, 0.0, 0.0,
							0.1, 0.5, 1.0,
							0.7, 0.7, 0.7,
							0.7, 1.0, 1.0};

	if (aspect_ratio > 4.0/3.0)
	{
		pixelRatio = viewSize.height / 480.0;
	}
	else
	{
		pixelRatio = viewSize.width / 640.0;
	}

	NSInteger textRow = compact ? GUI_ROW_CHART_SYSTEM_COMPACT : GUI_ROW_CHART_SYSTEM;
	
	clipRect = NSMakeRect((viewSize.width - size_in_pixels.width*pixelRatio)/2.0,
				(viewSize.height + size_in_pixels.height*pixelRatio)/2.0 - (pixel_title_size.height + 15 + (textRow-2)*MAIN_GUI_ROW_HEIGHT) * pixelRatio,
				size_in_pixels.width * pixelRatio,
				(textRow-1) * MAIN_GUI_ROW_HEIGHT * pixelRatio);

	OOSystemID target = [PLAYER targetSystemID];
	double dx, dy;
	
	// get a list of systems marked as contract destinations
	NSDictionary* markedDestinations = [player markedDestinations];
	
	// get present location
	cu = NSMakePoint((float)(hscale*galaxy_coordinates.x+hoffset),(float)(vscale*galaxy_coordinates.y+voffset));

	// enable draw clipping; limit drawing area within the chart area
	OOGL(glEnable(GL_SCISSOR_TEST));
	OOGL(glScissor(clipRect.origin.x, clipRect.origin.y, clipRect.size.width, clipRect.size.height));

	// Cache nearby systems so that [UNIVERSE generateSystemData:] does not get called on every frame
	// Caching code submitted by Y A J, 20091022
	
	static OOGalaxyID saved_galaxy_id;
	static struct saved_system
	{
		OOSystemID sysid;
		int tec, eco, gov;
		NSString* p_name;
		BOOL nova;
	} nearby_systems[ 256 ];
	static int num_nearby_systems = 0;

	if ( _refreshStarChart || galaxy_id != saved_galaxy_id)
	{
		// saved systems are stale; recompute
		_refreshStarChart = NO;
		for (i = 0; i < num_nearby_systems; i++)
			[nearby_systems[ i ].p_name release];

		num_nearby_systems = 0;
		for (i = 0; i < 256; i++)
		{

			NSDictionary* sys_info = [UNIVERSE generateSystemData:i];
			if (EXPECT_NOT([sys_info oo_boolForKey:@"sun_gone_nova"]))
			{
				nearby_systems[ num_nearby_systems ].gov = -1;	// Flag up nova systems!
			}
			else
			{
				nearby_systems[ num_nearby_systems ].tec = [sys_info oo_intForKey:KEY_TECHLEVEL];
				nearby_systems[ num_nearby_systems ].eco = [sys_info oo_intForKey:KEY_ECONOMY];
				nearby_systems[ num_nearby_systems ].gov = [sys_info oo_intForKey:KEY_GOVERNMENT];
			}
			nearby_systems[ num_nearby_systems ].sysid = i;
			nearby_systems[ num_nearby_systems ].p_name = [[sys_info oo_stringForKey:KEY_NAME] retain];
			nearby_systems[ num_nearby_systems ].nova = [[UNIVERSE generateSystemData:i] oo_boolForKey:@"sun_gone_nova"];
			num_nearby_systems++;
		}
		saved_galaxy_id = [player galaxyNumber];
	}
	
	static OOSystemID savedPlanetNumber = 0;
	static OOSystemID savedDestNumber = 0;
	static OORouteType savedArrayMode = OPTIMIZED_BY_NONE;
	static NSDictionary *routeInfo = nil;

	/* May override current mode for mission screens */
	if (backgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG_ANA_SHORTEST)
	{
		advancedNavArrayMode = OPTIMIZED_BY_JUMPS;
	}
	else if (backgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG_ANA_QUICKEST)
	{
		advancedNavArrayMode = OPTIMIZED_BY_TIME;
	}
	
	if (advancedNavArrayMode != OPTIMIZED_BY_NONE && [player hasEquipmentItemProviding:@"EQ_ADVANCED_NAVIGATIONAL_ARRAY"])
	{
		OOSystemID planetNumber = [PLAYER systemID];
		OOSystemID destNumber = [PLAYER targetSystemID];
		if (routeInfo == nil || planetNumber != savedPlanetNumber || destNumber != savedDestNumber || advancedNavArrayMode != savedArrayMode)
		{
			[routeInfo release];
			routeInfo = [[UNIVERSE routeFromSystem:planetNumber toSystem:destNumber optimizedBy:advancedNavArrayMode] retain];
			savedPlanetNumber = planetNumber;
			savedDestNumber = destNumber;
			savedArrayMode = advancedNavArrayMode;
		}
		target = destNumber;
		
		// if the ANA has been activated and we are in string input mode (i.e. planet search),
		// get out of it so that distance and time data can be displayed
		//if ([[[UNIVERSE gameView] typedString] length] > 0)  [player clearPlanetSearchString];
		
		if (routeInfo)  routeExists = YES;
		
		[self drawAdvancedNavArrayAtX:x+hoffset y:y+voffset z:z alpha:alpha usingRoute: (planetNumber != destNumber ? (id)routeInfo : nil) optimizedBy:advancedNavArrayMode zoom: zoom];

		if (routeExists)
		{
			distance = [routeInfo oo_doubleForKey:@"distance"];
			time = [routeInfo oo_doubleForKey:@"time"];
			jumps = [routeInfo oo_intForKey:@"jumps"];

			if (distance == 0.0 && planetNumber != destNumber)
			{
				// zero-distance double fix
				distance = 0.1;
				time = 0.01;
			}
		}
	}
	else
	{
		[self drawAdvancedNavArrayAtX:x+hoffset y:y+voffset z:z alpha:alpha usingRoute:nil optimizedBy:OPTIMIZED_BY_NONE zoom: zoom];
	}
	if (!routeExists)
	{
		NSPoint targetCoordinates = [systemManager getCoordinatesForSystem:target inGalaxy:galaxy_id];

		distance = distanceBetweenPlanetPositions(targetCoordinates.x,targetCoordinates.y,galaxy_coordinates.x,galaxy_coordinates.y);
		if (distance == 0.0)
		{
			if (target != [PLAYER systemID])
			{
				// looking at the other half of a zero-distance double
				// distance is treated as 0.1 LY
				distance = 0.1;
			}
		}
		if ([player hasHyperspaceMotor] && distance <= [player fuel]/10.0)
		{
			time = distance * distance;
		}
		else
		{
			time = 0.0;
		}
	}

	if ([player hasHyperspaceMotor])
	{
		// draw fuel range circle
		OOGL(GLScaledLineWidth(2.0f));
		[self setGLColorFromSetting:kGuiChartRangeColor defaultValue:[OOColor greenColor] alpha:alpha];
						
		GLDrawOval(x + cu.x, y + cu.y, z, NSMakeSize((float)(fuel*hscale), 2*(float)(fuel*vscale)), 5);
	}

	
	// draw crosshairs over current location
	//
	[self setGLColorFromSetting:kGuiChartCrosshairColor defaultValue:[OOColor greenColor] alpha:alpha];

	[self drawCrossHairsWithSize:12/zoom+2 x:x + cu.x y:y + cu.y z:z];


	// draw crosshairs over cursor
	//
	[self setGLColorFromSetting:kGuiChartCursorColor defaultValue:[OOColor redColor] alpha:alpha];
	cu = NSMakePoint((float)(hscale*cursor_coordinates.x+hoffset),(float)(vscale*cursor_coordinates.y+voffset));
	[self drawCrossHairsWithSize:7/zoom+2 x:x + cu.x y:y + cu.y z:z];

	// draw marks and stars
	//
	OOGL(GLScaledLineWidth(1.5f));
	OOGL(glColor4f(1.0f, 1.0f, 0.75f, alpha));	// pale yellow

	for (i = 0; i < num_nearby_systems; i++)
	{
		NSPoint sys_coordinates = [systemManager getCoordinatesForSystem:i inGalaxy:galaxy_id];
		
		dx = fabs(chart_centre_coordinates.x - sys_coordinates.x);
		dy = fabs(chart_centre_coordinates.y - sys_coordinates.y);
	
		if ((dx > zoom*(CHART_WIDTH_AT_MAX_ZOOM/2.0 + CHART_CLIP_BORDER))||(dy > zoom*(CHART_HEIGHT_AT_MAX_ZOOM + CHART_CLIP_BORDER)))
			continue;


		if (concealment[i] >= OO_SYSTEMCONCEALMENT_NOTHING) {
			// system is not known
			continue;
		}

		NSDictionary *systemInfo = [systemManager getPropertiesForSystem:i inGalaxy:galaxy_id];
		float blob_factor = [guiUserSettings oo_floatForKey:kGuiChartCircleScale defaultValue:0.0017];
		float blob_size = (1.0f + blob_factor * [systemInfo oo_floatForKey:@"radius"])/zoom;
		if (blob_size < 0.5) blob_size = 0.5;

		star.x = (float)(sys_coordinates.x * hscale + hoffset);
		star.y = (float)(sys_coordinates.y * vscale + voffset);

		noNova = !nearby_systems[i].nova;
		NSAssert1(chart_mode <= OOLRC_MODE_TECHLEVEL, @"Long range chart mode %i out of range", (int)chart_mode);
	
		NSArray *markers = [markedDestinations objectForKey:[NSNumber numberWithInt:i]];
		if (markers != nil)	// is marked
		{
			GLfloat base_size = 0.5f * blob_size + 2.5f;
			[self drawSystemMarkers:markers atX:x+star.x andY:y+star.y andZ:z withAlpha:alpha andScale:base_size];
		}

		if (concealment[i] >= OO_SYSTEMCONCEALMENT_NODATA) {
			// no system data available
			r = g = b = 0.7;
			OOGL(glColor4f(r, g, b, alpha));
		} else {
			switch (chart_mode)
			{
			case OOLRC_MODE_ECONOMY:
				if (EXPECT(noNova))
				{
					systemParameter = nearby_systems[i].eco;
					GLfloat ce1 = 1.0f - 0.125f * systemParameter;
					[self setGLColorFromSetting:[NSString stringWithFormat:kGuiChartEconomyUColor, (unsigned long)systemParameter]
								   defaultValue:[OOColor colorWithRed:ce1 green:1.0f blue:0.0f alpha:1.0f] 
										  alpha:1.0];
				}
				else
				{
					r = g = b = 0.3;
					OOGL(glColor4f(r, g, b, alpha));
				}
				break;
			case OOLRC_MODE_GOVERNMENT:
				if (EXPECT(noNova))
				{
					systemParameter = nearby_systems[i].gov;
					[self setGLColorFromSetting:[NSString stringWithFormat:kGuiChartGovernmentUColor, (unsigned long)systemParameter]
								   defaultValue:[OOColor colorWithRed:govcol[systemParameter*3] green:govcol[1+(systemParameter*3)] blue:govcol[2+(systemParameter*3)] alpha:1.0f] 
										  alpha:1.0];
				}
				else
				{
					r = g = b = 0.3;
					OOGL(glColor4f(r, g, b, alpha));
				}
				break;
			case OOLRC_MODE_TECHLEVEL:
				if (EXPECT(noNova))
				{
					systemParameter = nearby_systems[i].tec;
					r = 0.6;
					g = b = 0.20 + (0.05 * (GLfloat)systemParameter);
				}
				else
				{
					r = g = b = 0.3;
				}			
				OOGL(glColor4f(r, g, b, alpha));
				break;
			case OOLRC_MODE_NORMAL:
				if (EXPECT(noNova))
				{
					r = g = b = 1.0;
					OOColor *sunColor = [OOColor colorWithDescription:[[UNIVERSE systemManager] getProperty:@"sun_color" forSystem:i inGalaxy:galaxy_id]];
					if (sunColor != nil) {
						[sunColor getRed:&r green:&g blue:&b alpha:&alpha];
						alpha = 1.0; // reset
					}
				}
				else
				{
					r = 1.0;
					g = 0.2;
					b = 0.0;
				}
				OOGL(glColor4f(r, g, b, alpha));
				break;
			}
		}
		
		GLDrawFilledOval(x + star.x, y + star.y, z, NSMakeSize(blob_size,blob_size), 15);
	}
	
	// draw found stars and captions
	//
	GLfloat systemNameScale = [guiUserSettings oo_floatForKey:kGuiChartLabelScale defaultValue:1.0];

	OOGL(GLScaledLineWidth(1.5f));
	[self setGLColorFromSetting:kGuiChartMatchBoxColor defaultValue:[OOColor greenColor] alpha:alpha];

	int n_matches = 0, foundIndex = -1;
	
	for (i = 0; i < 256; i++) if (systemsFound[i])
	{
		if(foundSystem == n_matches) foundIndex = i;
		n_matches++;
	}
	
	if (n_matches == 0)
	{
		foundSystem = 0;
	}
	else if (backgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG_ANA_SHORTEST || backgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG_ANA_QUICKEST || backgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG)
	{
		// do nothing at this stage
	}
	else
	{
		for (i = 0; i < 256; i++)
		{
			if (concealment[i] >= OO_SYSTEMCONCEALMENT_NONAME)
			{
				continue;
			}
			
			BOOL mark = systemsFound[i];
			float marker_size = 8.0/zoom;
			NSPoint sys_coordinates = [systemManager getCoordinatesForSystem:i inGalaxy:galaxy_id];

			dx = fabs(chart_centre_coordinates.x - sys_coordinates.x);
			dy = fabs(chart_centre_coordinates.y - sys_coordinates.y);
		
			if (mark && (dx <= zoom*(CHART_WIDTH_AT_MAX_ZOOM/2.0+CHART_CLIP_BORDER))&&(dy <= zoom*(CHART_HEIGHT_AT_MAX_ZOOM+CHART_CLIP_BORDER)))
			{
				star.x = (float)(sys_coordinates.x * hscale + hoffset);
				star.y = (float)(sys_coordinates.y * vscale + voffset);
				OOGLBEGIN(GL_LINE_LOOP);
					glVertex3f(x + star.x - marker_size,	y + star.y - marker_size,	z);
					glVertex3f(x + star.x + marker_size,	y + star.y - marker_size,	z);
					glVertex3f(x + star.x + marker_size,	y + star.y + marker_size,	z);
					glVertex3f(x + star.x - marker_size,	y + star.y + marker_size,	z);
				OOGLEND();
				if (i == foundIndex || n_matches == 1)
				{
					if (n_matches == 1) foundSystem = 0;
					if (zoom > CHART_ZOOM_SHOW_LABELS && advancedNavArrayMode == OPTIMIZED_BY_NONE)
					{
						[self setGLColorFromSetting:kGuiChartMatchLabelColor defaultValue:[OOColor cyanColor] alpha:alpha];
						OODrawString([UNIVERSE systemNameIndex:i] , x + star.x + 2.0, y + star.y - 10.0f, z, NSMakeSize(10*systemNameScale,10*systemNameScale));
						[self setGLColorFromSetting:kGuiChartMatchBoxColor defaultValue:[OOColor greenColor] alpha:alpha];
					}
				}
				else if (zoom > CHART_ZOOM_SHOW_LABELS)
				{
					OODrawString([UNIVERSE systemNameIndex:i] , x + star.x + 2.0, y + star.y - 10.0f, z, NSMakeSize(10*systemNameScale,10*systemNameScale));
				}
			}
		}
	}

	// draw names
	//
//	OOGL(glColor4f(1.0f, 1.0f, 0.0f, alpha));	// yellow
	
	int targetIdx = -1;
	struct saved_system *sys;
	NSSize chSize = NSMakeSize(pixel_row_height*systemNameScale/zoom,pixel_row_height*systemNameScale/zoom);
	
	double jumpRange = MAX_JUMP_RANGE * [PLAYER dialFuel];
	for (i = 0; i < num_nearby_systems; i++)
	{
		if (concealment[i] >= OO_SYSTEMCONCEALMENT_NONAME)
		{
			continue;
		}

		sys = nearby_systems + i;
		NSPoint sys_coordinates = [systemManager getCoordinatesForSystem:sys->sysid inGalaxy:galaxy_id];

		dx = fabs(chart_centre_coordinates.x - sys_coordinates.x);
		dy = fabs(chart_centre_coordinates.y - sys_coordinates.y);
		
		if ((dx > zoom*(CHART_WIDTH_AT_MAX_ZOOM/2.0+CHART_CLIP_BORDER))||(dy > zoom*(CHART_HEIGHT_AT_MAX_ZOOM+CHART_CLIP_BORDER)))
			continue;
		star.x = (float)(sys_coordinates.x * hscale + hoffset);
		star.y = (float)(sys_coordinates.y * vscale + voffset);
		if (sys->sysid == target)		// not overlapping twin? (example: Divees & Tezabi in galaxy 5)
		{
			 targetIdx = i;		// we have a winner!
		}


		
		if (zoom < CHART_ZOOM_SHOW_LABELS)
		{
			if (![player showInfoFlag])	// System's name
			{

				d = distanceBetweenPlanetPositions(galaxy_coordinates.x, galaxy_coordinates.y, sys_coordinates.x, sys_coordinates.y);
				if (d <= jumpRange)
				{
					[self setGLColorFromSetting:kGuiChartLabelReachableColor defaultValue:[OOColor yellowColor] alpha:alpha];
				}
				else
				{
					[self setGLColorFromSetting:kGuiChartLabelColor defaultValue:[OOColor yellowColor] alpha:alpha];

				}

				OODrawString(sys->p_name, x + star.x + 2.0, y + star.y, z, chSize);
			}
			else if (EXPECT(sys->gov >= 0))	// Not a nova? Show the info.
			{
				if (concealment[i] >= OO_SYSTEMCONCEALMENT_NODATA)
				{
					[self setGLColorFromSetting:kGuiChartLabelColor defaultValue:[OOColor yellowColor] alpha:alpha];
					OODrawHilightedString(@"???", x + star.x + 2.0, y + star.y, z, chSize);
				}
				else
				{
					OODrawPlanetInfo(sys->gov, sys->eco, sys->tec, x + star.x + 2.0, y + star.y + 2.0, z, chSize);
				}
			}
		}
	}
	
	// highlight the name of the currently selected system
	// (needed to get things right in closely-overlapping systems)
	if( targetIdx != -1 && zoom <= CHART_ZOOM_SHOW_LABELS)
	{
		if (concealment[targetIdx] < OO_SYSTEMCONCEALMENT_NONAME)
		{
			sys = nearby_systems + targetIdx;
			NSPoint sys_coordinates = [systemManager getCoordinatesForSystem:sys->sysid inGalaxy:galaxy_id];

			star.x = (float)(sys_coordinates.x * hscale + hoffset);
			star.y = (float)(sys_coordinates.y * vscale + voffset);
		
			if (![player showInfoFlag])
			{
				d = distanceBetweenPlanetPositions(galaxy_coordinates.x, galaxy_coordinates.y, sys_coordinates.x, sys_coordinates.y);
				if (d <= jumpRange)
				{
					[self setGLColorFromSetting:kGuiChartLabelReachableColor defaultValue:[OOColor yellowColor] alpha:alpha];
				}
				else
				{
					[self setGLColorFromSetting:kGuiChartLabelColor defaultValue:[OOColor yellowColor] alpha:alpha];
				
				}

				OODrawHilightedString(sys->p_name, x + star.x + 2.0, y + star.y, z, chSize);
			}
			else if (sys->gov >= 0)	// Not a nova? Show the info.
			{
				if (concealment[targetIdx] >= OO_SYSTEMCONCEALMENT_NODATA)
				{
					[self setGLColorFromSetting:kGuiChartLabelColor defaultValue:[OOColor yellowColor] alpha:alpha];
					OODrawHilightedString(@"???", x + star.x + 2.0, y + star.y, z, chSize);
				}
				else
				{
					OODrawHilightedPlanetInfo(sys->gov, sys->eco, sys->tec, x + star.x + 2.0, y + star.y + 2.0, z, chSize);
				}
			}
		}
	}
	
	OOGUITabSettings tab_stops;
	tab_stops[0] = 0;
	tab_stops[1] = 96;
	tab_stops[2] = 288;
	[self overrideTabs:tab_stops from:kGuiChartTraveltimeTabs length:3];
	[self setTabStops:tab_stops];
	NSString *targetName = [[UNIVERSE getSystemName:target] retain];

	// distance-f & est-travel-time-f are identical between short & long range charts in standard Oolite, however can be alterered separately via OXPs
	NSString *travelDistLine = @"";
	if (distance > 0)
	{
		travelDistLine = OOExpandKey(@"long-range-chart-distance", distance);
	}
	NSString *travelTimeLine = @"";
	if (time > 0)
	{
		travelTimeLine = OOExpandKey(@"long-range-chart-est-travel-time", time);
	}
	
	if(concealment[target] < OO_SYSTEMCONCEALMENT_NONAME)
	{
		[self setArray:[NSArray arrayWithObjects:targetName, travelDistLine,travelTimeLine,nil] forRow:textRow];
	}
	else
	{
		[self setArray:[NSArray arrayWithObjects:@"", travelDistLine,travelTimeLine,nil] forRow:textRow];
	}
	if ([PLAYER guiScreen] == GUI_SCREEN_SHORT_RANGE_CHART)
	{
		if (jumps > 0)
		{
			[self setArray:[NSArray arrayWithObjects: @"", OOExpandKey(@"short-range-chart-jumps", jumps), nil] forRow: textRow + 1];
		}
		else
		{
			[self setArray:[NSArray array] forRow: textRow + 1];
		}
	}
	[targetName release];

	// draw planet info circle
	OOGL(GLScaledLineWidth(2.0f));
	[self setGLColorFromSetting: kGuiChartInfoMarkerColor defaultValue:[OOColor blueColor] alpha:alpha];
	cu = NSMakePoint((float)(hscale*info_system_coordinates.x+hoffset),(float)(vscale*info_system_coordinates.y+voffset));
	GLDrawOval(x + cu.x, y + cu.y, z, NSMakeSize(6.0f/zoom+2.0f, 6.0f/zoom+2.0f), 5);

	// disable draw clipping
	OOGL(glDisable(GL_SCISSOR_TEST));

	// Draw bottom divider
	[self setGLColorFromSetting:kGuiScreenDividerColor defaultValue:[OOColor colorWithWhite:0.75 alpha:1.0] alpha:alpha];
	OOGLBEGIN(GL_QUADS);
		glVertex3f(x + 0, (float)(y + size_in_pixels.height - (textRow-1)*MAIN_GUI_ROW_HEIGHT - pixel_title_size.height),	z);
		glVertex3f(x + size_in_pixels.width, (GLfloat)(y + size_in_pixels.height - (textRow-1)*MAIN_GUI_ROW_HEIGHT - pixel_title_size.height), z);
		glVertex3f(x + size_in_pixels.width, (GLfloat)(y + size_in_pixels.height - (textRow-1)*MAIN_GUI_ROW_HEIGHT - pixel_title_size.height - 2), z);
		glVertex3f(x + 0, (GLfloat)(y + size_in_pixels.height - (textRow-1)*MAIN_GUI_ROW_HEIGHT - pixel_title_size.height - 2), z);
	OOGLEND();
}


- (void) drawSystemMarkers:(NSArray *)markers atX:(GLfloat)x andY:(GLfloat)y andZ:(GLfloat)z withAlpha:(GLfloat)alpha andScale:(GLfloat)scale
{
	NSEnumerator *mEnum; 
	NSDictionary *marker;
	for (mEnum = [markers objectEnumerator]; (marker = [mEnum nextObject]); )
	{
		[self drawSystemMarker:marker atX:x andY:y andZ:z withAlpha:alpha andScale:scale];
	}
}


- (void) drawSystemMarker:(NSDictionary *)marker atX:(GLfloat)x andY:(GLfloat)y andZ:(GLfloat)z withAlpha:(GLfloat)alpha andScale:(GLfloat)scale
{
	NSString *colorDesc = [marker oo_stringForKey:@"markerColor" defaultValue:@"redColor"];
	OORGBAComponents color = [[OOColor colorWithDescription:colorDesc] rgbaComponents];
	
	OOGL(glColor4f(color.r, color.g, color.b, alpha));	// red
	GLfloat mark_size = [marker oo_floatForKey:@"markerScale" defaultValue:1.0];
	if (mark_size > 2.0)
	{
		mark_size = 2.0;
	}
	else if (mark_size < 0.5)
	{
		mark_size = 0.5;
	}
	mark_size *= scale;

	NSString *shape = [marker oo_stringForKey:@"markerShape" defaultValue:@"MARKER_X"];

	OOGLBEGIN(GL_LINES);
	if ([shape isEqualToString:@"MARKER_X"])
	{
		glVertex3f(x - mark_size,	y - mark_size,	z);
		glVertex3f(x + mark_size,	y + mark_size,	z);
		glVertex3f(x - mark_size,	y + mark_size,	z);
		glVertex3f(x + mark_size,	y - mark_size,	z);
	}
	else if ([shape isEqualToString:@"MARKER_PLUS"])
	{
		mark_size *= 1.4; // match volumes
		glVertex3f(x,	y - mark_size,	z);
		glVertex3f(x,	y + mark_size,	z);
		glVertex3f(x - mark_size,	y,	z);
		glVertex3f(x + mark_size,	y,	z);
	}
	else if ([shape isEqualToString:@"MARKER_SQUARE"])
	{
		glVertex3f(x - mark_size,	y - mark_size,	z);
		glVertex3f(x - mark_size,	y + mark_size,	z);
		glVertex3f(x - mark_size,	y + mark_size,	z);
		glVertex3f(x + mark_size,	y + mark_size,	z);
		glVertex3f(x + mark_size,	y + mark_size,	z);
		glVertex3f(x + mark_size,	y - mark_size,	z);
		glVertex3f(x + mark_size,	y - mark_size,	z);
		glVertex3f(x - mark_size,	y - mark_size,	z);
	}
	else if ([shape isEqualToString:@"MARKER_DIAMOND"])
	{
		mark_size *= 1.4; // match volumes
		glVertex3f(x,	y - mark_size,	z);
		glVertex3f(x - mark_size,	y,	z);
		glVertex3f(x - mark_size,	y,	z);
		glVertex3f(x,	y + mark_size,	z);
		glVertex3f(x,	y + mark_size,	z);
		glVertex3f(x + mark_size,	y,	z);
		glVertex3f(x + mark_size,	y,	z);
		glVertex3f(x,	y - mark_size,	z);
	}
	OOGLEND();
}


- (OOSystemID) targetNextFoundSystem:(int)direction // +1 , 0 , -1
{
	OOSystemID sys = [PLAYER targetSystemID];
	if ([PLAYER guiScreen] != GUI_SCREEN_SHORT_RANGE_CHART && [PLAYER guiScreen] != GUI_SCREEN_LONG_RANGE_CHART) return sys;
	
	BOOL		*systemsFound = [UNIVERSE systemsFound];
	unsigned 	i, first = 0, last = 0, count = 0;
	int 		systemIndex = foundSystem + direction;
	
	if (direction == 0) systemIndex = 0;
	
	for (i = 0; i <= kOOMaximumSystemID; i++)
	{
		if (systemsFound[i])
		{
			if (count == 0)
			{
				first = last = i;
			}
			else
			{
				last = i;
			}
			if (systemIndex == (int)count) 
			{
				sys = i;
			}
			count++;
		}
	}
	
	if (count == 0) return sys; // empty systemFound list.
	
	// loop back if needed.
	if (systemIndex < 0)
	{
		systemIndex = count - 1;
		sys = last;
	}
	if (systemIndex >= (int)count)
	{
		systemIndex = 0;
		sys = first;
	}
	
	foundSystem = systemIndex;
	return sys;
}


// Advanced Navigation Array -- galactic chart route mapping - contributed by Nikos Barkas (another_commander).
- (void) drawAdvancedNavArrayAtX:(float)x y:(float)y z:(float)z alpha:(float)alpha usingRoute:(NSDictionary *) routeInfo optimizedBy:(OORouteType) optimizeBy zoom: (OOScalar) zoom
{
	GLfloat lr,lg,lb,la,lr2,lg2,lb2,la2;
	double			hscale = size_in_pixels.width / (CHART_WIDTH_AT_MAX_ZOOM*zoom);
	double			vscale = -1.0 * size_in_pixels.height / (2*CHART_HEIGHT_AT_MAX_ZOOM*zoom);
	NSPoint			star = NSZeroPoint, 
		star2 = NSZeroPoint, 
		starabs = NSZeroPoint, 
		star2abs = NSZeroPoint;
	OOSystemDescriptionManager *systemManager = [UNIVERSE systemManager];
	OOGalaxyID		g = [PLAYER galaxyNumber];
	OOSystemID planetNumber = [PLAYER systemID];

	OOColor *defaultConnectionColor = [self colorFromSetting:kGuiChartConnectionColor defaultValue:[OOColor colorWithWhite:0.25 alpha:1.0]];
	OOColor *currentJumpColorStart = [self colorFromSetting:kGuiChartCurrentJumpStartColor defaultValue:[OOColor colorWithWhite:0.25 alpha:0.0]];
	OOColor *currentJumpColorEnd = [self colorFromSetting:kGuiChartCurrentJumpEndColor defaultValue:[OOColor colorWithWhite:0.25 alpha:0.0]];

	OOColor *thisConnectionColor = nil;
	OOColor *thatConnectionColor = nil;
	
	float jumpRange = MAX_JUMP_RANGE * ((optimizeBy == OPTIMIZED_BY_NONE) ? [PLAYER dialFuel] : 1.0);

	NSInteger concealment[256];
	for (NSUInteger i=0;i<256;i++) {
		NSDictionary *systemInfo = [systemManager getPropertiesForSystem:i inGalaxy:g];
		concealment[i] = [systemInfo oo_intForKey:@"concealment" defaultValue:OO_SYSTEMCONCEALMENT_NONE];
	}

	
	OOGLBEGIN(GL_LINES);
	for (OOSystemID i = 0; i < 256; i++)
	{

		if (concealment[i] >= OO_SYSTEMCONCEALMENT_NOTHING) {
			// system is not known
			continue;
		}
		
		/* Concealment */
		if (optimizeBy == OPTIMIZED_BY_NONE && i != planetNumber)
		{
			continue;
		}

		starabs = [systemManager getCoordinatesForSystem:i inGalaxy:g];

		star.x = (float)(starabs.x * hscale);
		star.y = (float)(starabs.y * vscale);

		// if in non-route mode, we're always starting from i, so need
		// to do <i here too.
		OOSystemID loopstart = (optimizeBy == OPTIMIZED_BY_NONE) ? 0 : (i+1);

		for (OOSystemID j = loopstart; j < 256; j++)
		{
			if (i == j)
			{
				continue; // for OPTIMIZED_BY_NONE case
			}

			if (concealment[j] >= OO_SYSTEMCONCEALMENT_NOTHING) {
				// system is not known
				continue;
			}
			
			star2abs = [systemManager getCoordinatesForSystem:j inGalaxy:g];
			double d = distanceBetweenPlanetPositions(starabs.x, starabs.y, star2abs.x, star2abs.y);
		
			if (d <= jumpRange)	// another_commander - Default to 7.0 LY.
			{
				star2.x = (float)(star2abs.x * hscale);
				star2.y = (float)(star2abs.y * vscale);
				if (optimizeBy == OPTIMIZED_BY_NONE)
				{
					[currentJumpColorStart getRed:&lr green:&lg blue:&lb alpha:&la];
					[currentJumpColorEnd getRed:&lr2 green:&lg2 blue:&lb2 alpha:&la2];
					OOGL(glColor4f(lr, lg, lb, la*alpha));
					glVertex3f(x+star.x, y+star.y, z);

					float frac = (d/jumpRange);
					OOGL(glColor4f(
							 OOLerp(lr,lr2,frac),
							 OOLerp(lg,lg2,frac),
							 OOLerp(lb,lb2,frac),
							 OOLerp(la,la2,frac)
							 ));
					glVertex3f(x+star2.x, y+star2.y, z);

				}
				else
				{
					thisConnectionColor = [OOColor colorWithDescription:[systemManager getProperty:@"link_color" forSystemKey:[NSString stringWithFormat:@"interstellar: %d %ld %ld", g, (long)i, (long)j]]];
				
					if (thisConnectionColor == nil)
					{
						thisConnectionColor = defaultConnectionColor;
					}
					[thisConnectionColor getRed:&lr green:&lg blue:&lb alpha:&la];
					OOGL(glColor4f(lr, lg, lb, la*alpha));

					glVertex3f(x+star.x, y+star.y, z);

					// and the other colour for the other end
					thatConnectionColor = [OOColor colorWithDescription:[systemManager getProperty:@"link_color" forSystemKey:[NSString stringWithFormat:@"interstellar: %d %ld %ld", g, (long)j, (long)i]]];
				
					if (thatConnectionColor == nil)
					{
						thatConnectionColor = thisConnectionColor;
					}
					[thatConnectionColor getRed:&lr green:&lg blue:&lb alpha:&la];
					OOGL(glColor4f(lr, lg, lb, la*alpha));

					glVertex3f(x+star2.x, y+star2.y, z);
				}
			}
		}
	}
	OOGLEND();
	
	if (optimizeBy == OPTIMIZED_BY_NONE)
	{
		return;
	}

	if (routeInfo)
	{
		NSUInteger i, route_hops = [[routeInfo oo_arrayForKey:@"route"] count] - 1;
		
		if (optimizeBy == OPTIMIZED_BY_JUMPS)
		{
			// route optimised by distance
			[self setGLColorFromSetting:kGuiChartRouteShortColor defaultValue:[OOColor yellowColor] alpha:alpha];
		}
		else
		{
			// route optimised by time
			[self setGLColorFromSetting:kGuiChartRouteQuickColor defaultValue:[OOColor cyanColor] alpha:alpha];
		}
		OOSystemID loc;
		for (i = 0; i < route_hops; i++)
		{
			loc = [[routeInfo objectForKey:@"route"] oo_intAtIndex:i];
			starabs = [systemManager getCoordinatesForSystem:loc inGalaxy:g];
			star2abs = [systemManager getCoordinatesForSystem:[[routeInfo objectForKey:@"route"] oo_intAtIndex:i+1] inGalaxy:g];

			star.x = (float)(starabs.x * hscale);
			star.y = (float)(starabs.y * vscale);
			
			star2.x = (float)(star2abs.x * hscale);
			star2.y = (float)(star2abs.y * vscale);

			
			OOGLBEGIN(GL_LINES);
				glVertex3f(x+star.x, y+star.y, z);
				glVertex3f(x+star2.x, y+star2.y, z);
			OOGLEND();
			
			// Label the route, if not already labelled
			if (zoom > CHART_ZOOM_SHOW_LABELS && concealment[loc] < OO_SYSTEMCONCEALMENT_NONAME)
			{
				OODrawString([UNIVERSE systemNameIndex:loc], x + star.x + 2.0, y + star.y, z, NSMakeSize(8,8));
			}
		}
		// Label the destination, which was not included in the above loop.
		if (zoom > CHART_ZOOM_SHOW_LABELS)
		{
			loc = [[routeInfo objectForKey:@"route"] oo_intAtIndex:i];
			if(concealment[loc] < OO_SYSTEMCONCEALMENT_NONAME)
			{
				OODrawString([UNIVERSE systemNameIndex:loc], x + star2.x + 2.0, y + star2.y, z, NSMakeSize(10,10));
			}
		}
	}
}

@end
