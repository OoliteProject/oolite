/*

OOPrimaryWindow.h

Trivial NSWindow subclass which lets us intercept toggleFullScreen: in order
to interpose our custom full screen handling when needed.


Copyright (C) 2012 Jens Ayton

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

#import "OOCocoa.h"

@protocol OOPrimaryWindowDelegate;


@interface OOPrimaryWindow: NSWindow
#if !__OBJC2__
{
@private
	id<OOPrimaryWindowDelegate>		_fullScreenDelegate;
}
#endif

@property (nonatomic, assign) IBOutlet id<OOPrimaryWindowDelegate> fullScreenDelegate;

// Call through to standard toggleFullScreen: implementation.
- (void) standardToggleFullScreen:(id)sender;

@end


@protocol OOPrimaryWindowDelegate <NSObject>
@optional

// Sent in response to toggleFullScreen:.
- (void) toggleFullScreenCalledForWindow:(OOPrimaryWindow *)window withSender:(id)sender;

@end
