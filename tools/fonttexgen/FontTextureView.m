//
//  FontTextureView.m
//  fonttexgen
//
//  Created by Jens Ayton on 2008-01-27.
//  Copyright 2008 Jens Ayton. All rights reserved.
//

// Hackerific: it's a view that thinks it's a controller.

#import "FontTextureView.h"


#define ENCODING 11//NSWindowsCP1252StringEncoding


@interface NSString (StringWithCharacter)

+ (NSString *) stringWithCharacter:(unichar)value;

@end


@implementation FontTextureView

@synthesize offsetX = _offsetX, offsetY = _offsetY;
@synthesize alternatingColors = _alternatingColors;


+ (void) initialize
{
	[self exposeBinding:@"offsetX"];
	[self exposeBinding:@"offsetY"];
	[self exposeBinding:@"alternatingColors"];
	
	[[NSUserDefaults standardUserDefaults] registerDefaults:
	 [NSDictionary dictionaryWithObjectsAndKeys:
	  [NSNumber numberWithInt:4], @"offsetX",
	  nil]];
}


- (void) setOffsetX:(int)x
{
	_offsetX = x;
	[self setNeedsDisplay:YES];
}


- (void) setOffsetY:(int)y
{
	_offsetY = y;
	[self setNeedsDisplay:YES];
}


- (void) setAlternatingColors:(BOOL)flag
{
	_alternatingColors = flag;
	[self setNeedsDisplay:YES];
}


- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self)
	{
		[self bind:@"offsetX"
		  toObject:[NSUserDefaultsController sharedUserDefaultsController]
	   withKeyPath:@"values.offsetX"
		   options:nil];
		[self bind:@"offsetY"
		  toObject:[NSUserDefaultsController sharedUserDefaultsController]
	   withKeyPath:@"values.offsetY"
		   options:nil];
		[self bind:@"alternatingColors"
		  toObject:[NSUserDefaultsController sharedUserDefaultsController]
	   withKeyPath:@"values.alternatingColors"
		   options:nil];
		
		_topRows = [NSImage imageNamed:@"toprows"];
		_credits = [NSImage imageNamed:@"credits"];
		
		_template = [[NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"template" ofType:@"plist"]] copy];
    }
    return self;
}


- (BOOL) isFlipped
{
	return YES;
}


- (void)drawRect:(NSRect)rect
{
	[[NSColor blackColor] set];
	[NSBezierPath fillRect:rect];
	
	NSFont *font = [NSFont fontWithName:@"Helvetica Bold" size:25.0];
	if (font == nil)  NSLog(@"Failed to find font!");
	NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, [NSColor whiteColor], NSForegroundColorAttributeName, nil];
	
	NSMutableArray *widths = [[_template objectForKey:@"widths"] mutableCopy];
	
	unsigned x, y;
	for (y = 0; y < 16; ++y)
	{
		for (x = 0; x < 16; ++x)
		{
			if (_alternatingColors && ((x % 2) == (y % 2)))
			{
				NSRect frame = {{ x * 32, y * 32 }, { 32, 32 }};
				[[NSColor darkGrayColor] set];
				[NSBezierPath fillRect:frame];
			}
			
			uint8_t value = y * 16 + x;
			if (value < 32 && value != '\t' && value != 0x08 && value != 0x18)  continue;
			
			if (value == 0x7F)  value = '?'; // Substitution glyph for unknown characters
			NSString *string = [[NSString alloc] initWithBytes:&value length:1 encoding:ENCODING];
			
			if (value == 0x08)  string = [NSString stringWithCharacter:0x2605];	// Black Star
			if (value == 0x18)  string = [NSString stringWithCharacter:0x2606];	// White Star
			
			// Replace Euro sign with Cruzeiro sign.
			if ([string characterAtIndex:0] == 0x20AC)  string = [NSString stringWithCharacter:0x20A2];
			// Replace tab with space.
			if ([string characterAtIndex:0] == '\t')  string = [NSString stringWithCharacter:' '];
			
			NSPoint point = NSMakePoint(x * 32 + self.offsetX, y * 32 + self.offsetY);
			[string drawAtPoint:point withAttributes:attrs];
			
			NSNumber *width = [NSNumber numberWithFloat:[string sizeWithAttributes:attrs].width / 4.0];
			if (value < 32)
			{
				[widths replaceObjectAtIndex:value withObject:width];
			}
			else
			{
				[widths addObject:width];
			}
		}
	}
	
	[_topRows compositeToPoint:NSMakePoint(0, _topRows.size.height) operation:NSCompositePlusLighter];
	_widths = [widths copy];
}


- (IBAction) saveImage:(id)sender
{
	NSSavePanel *savePanel = [NSSavePanel savePanel];
	[savePanel setRequiredFileType:(NSString *)kUTTypeTIFF];
	[savePanel setCanSelectHiddenExtension:YES];
	[savePanel setExtensionHidden:NO];
	if ([savePanel runModalForDirectory:nil file:@"oolite-font.tiff"] == NSOKButton)
	{
		NSBitmapImageRep *rep = [self bitmapImageRepForCachingDisplayInRect:self.bounds];
		[self cacheDisplayInRect:self.bounds toBitmapImageRep:rep];
		NSString *path = [savePanel filename];
		[[rep TIFFRepresentation] writeToFile:path atomically:YES];
		
		NSMutableDictionary *plist = [_template mutableCopy];
		[plist setObject:_widths forKey:@"widths"];
		 [plist setObject:[NSNumber numberWithInt:ENCODING] forKey:@"encoding"];
		
		path = [[path stringByDeletingPathExtension] stringByAppendingPathExtension:@"plist"];
		[plist writeToFile:path atomically:YES];
	}
}

@end


@implementation NSString (StringWithCharacter)

+ (NSString *) stringWithCharacter:(unichar)value
{
	return [NSString stringWithCharacters:&value length:1];
}

@end
