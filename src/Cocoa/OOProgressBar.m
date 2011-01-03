/*

OOProgressBar.m


Copyright (C) 2008-2011 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOProgressBar.h"


@implementation OOProgressBar

- (id) initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame]))
	{
		_value = -1.0f;
	}
	return self;
}


- (void)drawRect:(NSRect)rect
{
	if (_value >= 0.0)
	{
		[NSGraphicsContext saveGraphicsState];
		[[NSColor yellowColor] set];
		
		rect = NSInsetRect(rect, 0.5f, 0.5f);
		[NSBezierPath strokeRect:rect];
		
		rect = NSInsetRect(rect, 1.5f, 1.5f);
		rect.size.width *= fmin(_value, 1.0);
		[NSBezierPath fillRect:rect];
		
		[NSGraphicsContext restoreGraphicsState];
	}
}


- (double) doubleValue
{
	return _value;
}


- (void) setDoubleValue:(double)value
{
	_value = value;
}

@end
