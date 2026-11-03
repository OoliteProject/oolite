/*

OOMaterial.m


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

#import "OOMaterial.h"
#import "OOFoundationBridge.h"
#import "OOFunctionAttributes.h"
#import "OOLogging.h"

static OOMaterial* sActiveMaterial = nil;

@implementation OOMaterial

+ (void)setUp
{
    // I thought we'd need this, but the stuff I needed it for turned out to be problematic. Maybe in future. -- Ahruman
}

- (void)dealloc
{
    // Ensure cleanup happens; doing it more than once is safe.
    [self willDealloc];

    [super dealloc];
}

- (id)descriptionComponents // shared selector (proposed ADR-0043)
{
    return oo::NSStringFrom("\"" + oo::DescriptionOf([self name]) + "\""); // "%@" of the name, quoted
}

- (id)name // shared selector (proposed ADR-0043)
{
    OOLogGenericParameterError();
    return nil;
}

// Make this the current GL shader program.
- (void)apply
{
    [sActiveMaterial unapplyWithNext:self];
    [sActiveMaterial release];
    sActiveMaterial = nil;

    if ([self doApply]) {
        sActiveMaterial = [self retain];
    }
}

+ (void)applyNone
{
    [sActiveMaterial unapplyWithNext:nil];
    [sActiveMaterial release];
    sActiveMaterial = nil;
}

+ (OOMaterial*)current
{
    return [[sActiveMaterial retain] autorelease];
}

- (void)ensureFinishedLoading
{
}

- (BOOL)isFinishedLoading
{
    return YES;
}

- (void)setBindingTarget:(id<OOWeakReferenceSupport>)target
{
}

- (BOOL)wantsNormalsAsTextureCoordinates
{
    return NO;
}

#if OO_MULTITEXTURE
- (NSUInteger)countOfTextureUnitsWithBaseCoordinates
{
    return 1;
}
#endif

#ifdef OO_DEBUG_MONITOR_ENABLED
- (id)allTextures // shared selector (proposed ADR-0043)
{
    return nil;
}
#endif

@end

@implementation OOMaterial (OOSubclassInterface)

- (BOOL)doApply
{
    OOLogGenericSubclassResponsibility();
    return NO;
}

- (void)unapplyWithNext:(OOMaterial*)next
{
    // Do nothing.
}

- (void)willDealloc
{
    if (EXPECT_NOT(sActiveMaterial == self)) {
        OO_LOG("shader.dealloc.imbalance", "{}", "***** Material deallocated while active, indicating a retain/release imbalance.");
        [self unapplyWithNext:nil];
        sActiveMaterial = nil;
    }
}

@end
