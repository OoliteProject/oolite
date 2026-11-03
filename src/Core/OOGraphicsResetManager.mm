/*

OOGraphicsResetManager.m


Copyright (C) 2007-2013 Jens Ayton and contributors

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

#import "OOGraphicsResetManager.h"
#import "OOOpenGLExtensionManager.h"
#import "OOTexture.h"

static OOGraphicsResetManager* sSingleton = nil;

@implementation OOGraphicsResetManager

- (void)dealloc
{
    if (sSingleton == self)
        sSingleton = nil;

    [super dealloc];
}

+ (OOGraphicsResetManager*)sharedManager
{
    if (sSingleton == nil)
        sSingleton = [[self alloc] init];
    return sSingleton;
}

- (void)registerClient:(id<OOGraphicsResetClient>)client
{
    if (client != nil) {
        clients.insert(client);
    }
}

- (void)unregisterClient:(id<OOGraphicsResetClient>)client
{
    clients.erase(client);
}

- (void)resetGraphicsState
{
    OOGL(glFinish());

    OOLog(@"rendering.reset.start", @"%@", @"Resetting graphics state.");
    OOLogIndentIf(@"rendering.reset.start");

    [[OOOpenGLExtensionManager sharedManager] reset];
    [OOTexture rebindAllTextures];

    // A copy, so a client may register or unregister during the reset (one unregistered by an
    // earlier client is skipped). Unordered, as the NSSet was: its order was pointer-hash order,
    // so it already varied from run to run.
    const std::vector<id> snapshot(clients.begin(), clients.end());
    for (id client : snapshot) {
        if (clients.find(client) == clients.end())
            continue;
        @try {
            [client resetGraphicsState];
        }
        @catch (NSException* exception) {
            OOLog(kOOLogException, @"***** EXCEPTION -- %@ : %@ -- ignored during graphics reset.", [exception name], [exception reason]);
        }
    }

    OOLogOutdentIf(@"rendering.reset.start");
    OOLog(@"rendering.reset.end", @"%@", @"End of graphics state reset.");
}

@end

@implementation OOGraphicsResetManager (Singleton)

/*	Canonical singleton boilerplate.
        See Cocoa Fundamentals Guide: Creating a Singleton Instance.
        See also +sharedManager above.

        // NOTE: assumes single-threaded first access.
*/

+ (id)allocWithZone:(OOZone*)inZone
{
    if (sSingleton == nil) {
        sSingleton = [super allocWithZone:inZone];
        return sSingleton;
    }
    return nil;
}

- (id)copyWithZone:(OOZone*)inZone
{
    return self;
}

- (id)retain
{
    return self;
}

- (NSUInteger)retainCount
{
    return UINT_MAX;
}

- (void)release
{
}

- (id)autorelease
{
    return self;
}

@end
