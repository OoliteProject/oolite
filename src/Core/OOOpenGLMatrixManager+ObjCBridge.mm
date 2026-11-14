/*

OOOpenGLMatrixManager+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-vt0o): the Objective-C OOOpenGLMatrixManager facade over
cxx::OOOpenGLMatrixManager. Every method forwards to its C++ member. Deleted with
OOOpenGLMatrixManager+ObjCBridge.h.

Oolite
Copyright (C) 2004-2014 Giles C Williams and contributors

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

#import "OOOpenGLMatrixManager.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOOpenGLMatrixManager (OOObjCBridgePrivate)

- (id)initWithCxxManager:(cxx::OOOpenGLMatrixManager*)manager;

@end

@implementation OOOpenGLMatrixManager

// Inside the @implementation for the private ivar.
OOOpenGLMatrixManager* oo::ToObjC(cxx::OOOpenGLMatrixManager* manager)
{
    return Peers().peerFor(manager, [manager] { return [[OOOpenGLMatrixManager alloc] initWithCxxManager:manager]; });
}

cxx::OOOpenGLMatrixManager* oo::ToCxx(OOOpenGLMatrixManager* manager)
{
    if (manager == nil)
        return nullptr;
    return manager->_cxxManager.get();
}

- (id)init
{
    // A new manager (MyOpenGLView's), recorded as its facade.
    self = [super init];
    if (self != nil) {
        _cxxManager = oo::makeRef<cxx::OOOpenGLMatrixManager>();
        @autoreleasepool {
            Peers().peerFor(_cxxManager.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

- (id)initWithCxxManager:(cxx::OOOpenGLMatrixManager*)manager
{
    self = [super init];
    if (self != nil)
        _cxxManager = oo::Ref<cxx::OOOpenGLMatrixManager>(manager);
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxManager.get());
    [super dealloc];
}

- (void)loadModelView:(OOMatrix)matrix
{
    _cxxManager->loadModelView(matrix);
}
- (void)resetModelView
{
    _cxxManager->resetModelView();
}
- (void)multModelView:(OOMatrix)matrix
{
    _cxxManager->multModelView(matrix);
}
- (void)translateModelView:(Vector)vector
{
    _cxxManager->translateModelView(vector);
}
- (void)rotateModelView:(GLfloat)angle axis:(Vector)axis
{
    _cxxManager->rotateModelView(angle, axis);
}
- (void)scaleModelView:(Vector)scale
{
    _cxxManager->scaleModelView(scale);
}

- (void)lookAtWithEye:(Vector)eye center:(Vector)center up:(Vector)up
{
    _cxxManager->lookAtWithEye(eye, center, up);
}

- (void)pushModelView
{
    _cxxManager->pushModelView();
}
- (OOMatrix)popModelView
{
    return _cxxManager->popModelView();
}
- (OOMatrix)getModelView
{
    return _cxxManager->getModelView();
}
- (NSUInteger)countModelView
{
    return _cxxManager->countModelView();
}
- (void)syncModelView
{
    _cxxManager->syncModelView();
}
- (void)loadProjection:(OOMatrix)matrix
{
    _cxxManager->loadProjection(matrix);
}
- (void)multProjection:(OOMatrix)matrix
{
    _cxxManager->multProjection(matrix);
}
- (void)translateProjection:(Vector)vector
{
    _cxxManager->translateProjection(vector);
}
- (void)rotateProjection:(GLfloat)angle axis:(Vector)axis
{
    _cxxManager->rotateProjection(angle, axis);
}
- (void)scaleProjection:(Vector)scale
{
    _cxxManager->scaleProjection(scale);
}

- (void)frustumLeft:(double)l right:(double)r bottom:(double)b top:(double)t near:(double)n far:(double)f
{
    _cxxManager->frustumLeft(l, r, b, t, n, f);
}

- (void)orthoLeft:(double)l right:(double)r bottom:(double)b top:(double)t near:(double)n far:(double)f
{
    _cxxManager->orthoLeft(l, r, b, t, n, f);
}

- (void)perspectiveFovy:(double)fovy aspect:(double)aspect zNear:(double)zNear zFar:(double)zFar
{
    _cxxManager->perspectiveFovy(fovy, aspect, zNear, zFar);
}

- (void)resetProjection
{
    _cxxManager->resetProjection();
}
- (void)pushProjection
{
    _cxxManager->pushProjection();
}
- (OOMatrix)popProjection
{
    return _cxxManager->popProjection();
}
- (OOMatrix)getProjection
{
    return _cxxManager->getProjection();
}
- (void)syncProjection
{
    _cxxManager->syncProjection();
}
- (OOMatrix)getMatrix:(int)which
{
    return _cxxManager->getMatrix(which);
}
- (oo::PList)standardMatrixUniformLocations:(GLhandleARB)program
{
    return _cxxManager->standardMatrixUniformLocations(program);
}

@end
