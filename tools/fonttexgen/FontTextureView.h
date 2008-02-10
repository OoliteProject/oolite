//
//  FontTextureView.h
//  fonttexgen
//
//  Created by Jens Ayton on 2008-01-27.
//  Copyright 2008 Jens Ayton. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface FontTextureView: NSView
{
	int						_offsetX, _offsetY;
	BOOL					_alternatingColors;
	NSImage					*_topRows;
	NSArray					*_widths;
	NSDictionary			*_template;
	NSStringEncoding		_encoding;
	
	IBOutlet NSPopUpButton	*encodingPopUp;
}

@property (nonatomic) int offsetX, offsetY;
@property (nonatomic) BOOL alternatingColors;

- (IBAction) saveImage:(id)sender;
- (IBAction) takeEncodingFromTag:(id)sender;

@end
