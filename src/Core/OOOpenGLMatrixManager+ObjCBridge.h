/*

OOOpenGLMatrixManager+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-vt0o): the Objective-C OOOpenGLMatrixManager, a facade
over the C++ cxx::OOOpenGLMatrixManager (OOOpenGLMatrixManager.h), for callers that are not
converted yet (MyOpenGLView makes and owns the game view's manager; OOShaderProgram reads it).
Its interface is the one OOOpenGLMatrixManager.h declared before the conversion, copied exactly
(same selectors, same types), so those callers compile and behave unchanged; each method
forwards to its C++ member. Imported as the last line of OOOpenGLMatrixManager.h; do not import
it directly.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  ----------------------------
        still Objective-C                      OOOpenGLMatrixManager *         nothing: messages as before
        converted (C++)                        oo::Ref<cxx::OOOpenGLMatrixManager>, cxx::OOOpenGLMatrixManager *
          handing a manager to Objective-C                                     oo::ToObjC(manager)
          taking one from Objective-C                                          oo::ToCxx(objcManager)

[[OOOpenGLMatrixManager alloc] init] makes a new C++ manager, whose facade it is. oo::ToObjC gives
the manager's one live facade (oo::ObjCPeers), so identity survives a round trip. Never add to this
file; converted code does not message the facade. Deleted by its deletion bead once no file outside
OOOpenGLMatrixManager.* names the Objective-C OOOpenGLMatrixManager.

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

#ifndef OOOPENGLMATRIXMANAGER_OBJCBRIDGE_H
#define OOOPENGLMATRIXMANAGER_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@interface OOOpenGLMatrixManager : OOObject {
@private
    oo::Ref<cxx::OOOpenGLMatrixManager> _cxxManager;
}

- (id)init;
- (void)dealloc;
- (void)loadModelView:(OOMatrix)matrix;
- (void)resetModelView;
- (void)multModelView:(OOMatrix)matrix;
- (void)translateModelView:(Vector)vector;
- (void)rotateModelView:(GLfloat)angle axis:(Vector)axis;
- (void)scaleModelView:(Vector)scale;
- (void)lookAtWithEye:(Vector)eye center:(Vector)center up:(Vector)up;
- (void)pushModelView;
- (OOMatrix)popModelView;
- (OOMatrix)getModelView;
- (NSUInteger)countModelView;
- (void)syncModelView;
- (void)loadProjection:(OOMatrix)matrix;
- (void)multProjection:(OOMatrix)matrix;
- (void)translateProjection:(Vector)vector;
- (void)rotateProjection:(GLfloat)angle axis:(Vector)axis;
- (void)scaleProjection:(Vector)scale;
- (void)frustumLeft:(double)l right:(double)r bottom:(double)b top:(double)t near:(double)n far:(double)f;
- (void)orthoLeft:(double)l right:(double)r bottom:(double)b top:(double)t near:(double)n far:(double)f;
- (void)perspectiveFovy:(double)fovy aspect:(double)aspect zNear:(double)zNear zFar:(double)zFar;
- (void)resetProjection;
- (void)pushProjection;
- (OOMatrix)popProjection;
- (OOMatrix)getProjection;
- (void)syncProjection;
- (OOMatrix)getMatrix:(int)which;
// An array of (location, matrix index, "mat3" / "mat4") triples, as property-list values
// (Foundation sweep, proposed ADR-0043); a null PList from a nil manager.
- (oo::PList)standardMatrixUniformLocations:(GLhandleARB)program;

@end

namespace oo {

// The manager's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OOOpenGLMatrixManager* ToObjC(cxx::OOOpenGLMatrixManager* manager);
inline OOOpenGLMatrixManager* ToObjC(const Ref<cxx::OOOpenGLMatrixManager>& manager) { return ToObjC(manager.get()); }

// The C++ manager behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOOpenGLMatrixManager* ToCxx(OOOpenGLMatrixManager* manager);

} // namespace oo

#endif // OOOPENGLMATRIXMANAGER_OBJCBRIDGE_H
