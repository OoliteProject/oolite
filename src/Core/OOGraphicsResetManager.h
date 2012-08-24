/*

OOGraphicsResetManager.h

Tracks objects with state that needs to be reset when the graphics context is
modified (for instance, when switching between windowed and full-screen mode
in SDL builds). This means re-uploading all textures, and also resetting any
display lists relying on old texture names. All objects which have display
lists must therefore register with the OOGraphicsResetManager on init, and
unregister on dealloc.


Copyright (C) 2007-2012 Jens Ayton and contributors

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


@protocol OOGraphicsResetClient

- (void) resetGraphicsState;

@end


@interface OOGraphicsResetManager: NSObject
{
@private
	NSMutableSet			*clients;
}

+ (OOGraphicsResetManager *) sharedManager;

// Clients are not retained.
- (void) registerClient:(id<OOGraphicsResetClient>)client;
- (void) unregisterClient:(id<OOGraphicsResetClient>)client;

// Forwarded to all clients, after resetting textures.
- (void) resetGraphicsState;

@end
