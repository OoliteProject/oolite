//
//  FontTextureView.m
//  fonttexgen
//
//  Created by Jens Ayton on 2008-01-27.
//  Copyright 2008 Jens Ayton. All rights reserved.
//

// Hackerific: it's a view that thinks it's a controller.

#import "FontTextureView.h"
#import <QuartzCore/QuartzCore.h>
#import "OOEncodingConverter.h"


@interface NSImage ()
@property (setter=setFlipped:, getter=isFlipped) BOOL flipped;
@end


static inline NSPoint ScalePoint(NSPoint point, NSPoint scale)
{
	point.x *= scale.x;
	point.y *= scale.y;
	return point;
}


static inline NSSize ScaleSize(NSSize size, NSPoint scale)
{
	size.width *= scale.x;
	size.height *= scale.y;
	return size;
}


static inline NSRect ScaleRect(NSRect rect, NSPoint scale)
{
	rect.origin = ScalePoint(rect.origin, scale);
	rect.size = ScaleSize(rect.size, scale);
	return rect;
}


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
	  [NSNumber numberWithInt:NSWindowsCP1252StringEncoding], @"encoding",
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
		
		_encoding = [[NSUserDefaults standardUserDefaults] integerForKey:@"encoding"];
		[encodingPopUp selectItemWithTag:_encoding];
		
		_topRows = [NSImage imageNamed:@"toprows"];
		_topRows.flipped = YES;
		
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
	// Disable subpixel anti-aliasing.
	CGContextRef cgCtxt = [[NSGraphicsContext currentContext] graphicsPort];
	CGContextSaveGState(cgCtxt);
	CGContextSetShouldSmoothFonts(cgCtxt, NO);
	
	[[NSColor blackColor] set];
	[NSBezierPath fillRect:rect];
	
	// Originally hard-coded at 512x512 pixels, scale is used to transform magic numbers as appropriate.
	NSPoint scale = { self.bounds.size.width / 512, self.bounds.size.height / 512 };
	
	NSFont *font = [NSFont fontWithName:@"Helvetica Bold" size:25.0 * scale.y];
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
				NSRect frame = {{ x * 32.0 * scale.x, y * 32.0 * scale.y }, { 32.0 * scale.x, 32.0 * scale.y }};
				[[NSColor darkGrayColor] set];
				[NSBezierPath fillRect:frame];
			}
			
			uint8_t value = y * 16 + x;
			
			if (y >= 2 || value == '\t' || value == 0x08 || value == 0x18)
			{
			//	if (value == 0x7F)  value = '?'; // Substitution glyph for unknown characters -- not used
				NSString *string = [[NSString alloc] initWithBytes:&value length:1 encoding:_encoding];
				
				if (value == 0x08)  string = [NSString stringWithCharacter:0x2605];	// Black Star
				if (value == 0x18)  string = [NSString stringWithCharacter:0x2606];	// White Star
				
				// Replace Euro sign with Cruzeiro sign.
				if ([string characterAtIndex:0] == 0x20AC)  string = [NSString stringWithCharacter:0x20A2];
				// Replace tab with space.
				if ([string characterAtIndex:0] == '\t')  string = [NSString stringWithCharacter:' '];
				
				NSPoint point = NSMakePoint((x * 32.0 + self.offsetX) * scale.x, (y * 32.0 + self.offsetY) * scale.y);
				[string drawAtPoint:point withAttributes:attrs];
				
				NSNumber *width = [NSNumber numberWithFloat:[string sizeWithAttributes:attrs].width / (4.0 * scale.x)];
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
	}
	
	[NSGraphicsContext currentContext].imageInterpolation = NSImageInterpolationHigh;
	NSRect srcRect = {{0, 0}, _topRows.size};
	NSRect dstRect = {{0, 0}, {32.0 * scale.x * 8.0, 32.0 * scale.y * 2.0}};
	[_topRows drawInRect:dstRect fromRect:srcRect operation:NSCompositePlusLighter fraction:1.0];
	
	_widths = [widths copy];
	
	CGContextRestoreGState(cgCtxt);
}


- (IBAction) saveImage:(id)sender
{
	NSSavePanel *savePanel = [NSSavePanel savePanel];
	[savePanel setAllowedFileTypes:[NSArray arrayWithObject:(NSString *)kUTTypeTIFF]];
	[savePanel setCanSelectHiddenExtension:YES];
	[savePanel setExtensionHidden:NO];
	[savePanel setNameFieldStringValue:@"oolite-font.tiff"];
	
	if ([savePanel runModal] == NSOKButton)
	{
		NSBitmapImageRep *rep = [self bitmapImageRepForCachingDisplayInRect:self.bounds];
		[self cacheDisplayInRect:self.bounds toBitmapImageRep:rep];
		NSString *path = [[savePanel URL] path];
		[[rep TIFFRepresentation] writeToFile:path atomically:YES];
		
		NSMutableDictionary *plist = [_template mutableCopy];
		[plist setObject:_widths forKey:@"widths"];
		 [plist setObject:StringFromEncoding(_encoding) forKey:@"encoding"];
		
		path = [[path stringByDeletingPathExtension] stringByAppendingPathExtension:@"plist"];
		[plist writeToFile:path atomically:YES];
	}
}


- (IBAction) takeEncodingFromTag:(id)sender
{
	_encoding = [[sender selectedItem] tag];
	[[NSUserDefaults standardUserDefaults] setInteger:_encoding forKey:@"encoding"];
	[self setNeedsDisplay:YES];
}

@end


@implementation NSString (StringWithCharacter)

+ (NSString *) stringWithCharacter:(unichar)value
{
	return [NSString stringWithCharacters:&value length:1];
}

@end
