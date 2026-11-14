/*

OOOpenGLMatrixManager.h

Manages OpenGL Model, View, etc. matrices.

C++20 since bead oo-vt0o (proposed ADR-0056). The Objective-C facade was deleted by bead
oo-9ht.18, which moved the manager out of namespace cxx. OOOpenGLMatrixStack had no caller outside
this file, so it never had a facade.

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

#ifndef OOOPENGLMATRIXMANAGER_H
#define OOOPENGLMATRIXMANAGER_H

#include "OOMaths.h"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

extern const char* ooliteStandardMatrixUniforms[];

enum {
    OOLITE_GL_MATRIX_MODELVIEW,
    OOLITE_GL_MATRIX_PROJECTION,
    OOLITE_GL_MATRIX_MODELVIEW_PROJECTION,
    OOLITE_GL_MATRIX_NORMAL,
    OOLITE_GL_MATRIX_MODELVIEW_INVERSE,
    OOLITE_GL_MATRIX_PROJECTION_INVERSE,
    OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_INVERSE,
    OOLITE_GL_MATRIX_MODELVIEW_TRANSPOSE,
    OOLITE_GL_MATRIX_PROJECTION_TRANSPOSE,
    OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_TRANSPOSE,
    OOLITE_GL_MATRIX_MODELVIEW_INVERSE_TRANSPOSE,
    OOLITE_GL_MATRIX_PROJECTION_INVERSE_TRANSPOSE,
    OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_INVERSE_TRANSPOSE,
    OOLITE_GL_MATRIX_END
};

class OOOpenGLMatrixStack : public oo::RefCounted {
public:
    void push(OOMatrix matrix);
    OOMatrix pop();
    NSUInteger stackCount();

private:
    std::vector<OOMatrix> stack = { }; // was a Foundation mutable array of boxed values (bead oo-3rb.10)
};

class OOOpenGLMatrixManager : public oo::RefCounted {
public:
    OOOpenGLMatrixManager();
    void loadModelView(OOMatrix matrix);
    void resetModelView();
    void multModelView(OOMatrix matrix);
    void translateModelView(Vector vector);
    void rotateModelView(GLfloat angle, Vector axis);
    void scaleModelView(Vector scale);
    void lookAtWithEye(Vector eye, Vector center, Vector up);
    void pushModelView();
    OOMatrix popModelView();
    OOMatrix getModelView();
    NSUInteger countModelView();
    void syncModelView();
    void loadProjection(OOMatrix matrix);
    void multProjection(OOMatrix matrix);
    void translateProjection(Vector vector);
    void rotateProjection(GLfloat angle, Vector axis);
    void scaleProjection(Vector scale);
    void frustumLeft(double l, double r, double b, double t, double n, double f);
    void orthoLeft(double l, double r, double b, double t, double n, double f);
    void perspectiveFovy(double fovy, double aspect, double zNear, double zFar);
    void resetProjection();
    void pushProjection();
    OOMatrix popProjection();
    OOMatrix getProjection();
    void syncProjection();
    OOMatrix getMatrix(int which);
    // An array of (location, matrix index, "mat3" / "mat4") triples, as property-list values
    // (Foundation sweep, proposed ADR-0043).
    oo::PList standardMatrixUniformLocations(GLhandleARB program);

private:
    void updateModelView();
    void updateProjection();

    OOMatrix matrices[OOLITE_GL_MATRIX_END] = { };
    bool valid[OOLITE_GL_MATRIX_END] = { };
    oo::Ref<OOOpenGLMatrixStack> modelViewStack = { };
    oo::Ref<OOOpenGLMatrixStack> projectionStack = { };
};

void OOGLPushModelView(void);
OOMatrix OOGLPopModelView(void);
OOMatrix OOGLGetModelView(void);
void OOGLResetModelView(void);
void OOGLLoadModelView(OOMatrix matrix);
void OOGLMultModelView(OOMatrix matrix);
void OOGLTranslateModelView(Vector vector);
void OOGLRotateModelView(GLfloat angle, Vector axis);
void OOGLScaleModelView(Vector scale);
void OOGLLookAt(Vector eye, Vector center, Vector up);

void OOGLResetProjection(void);
void OOGLPushProjection(void);
OOMatrix OOGLPopProjection(void);
OOMatrix OOGLGetProjection(void);
void OOGLLoadProjection(OOMatrix matrix);
void OOGLMultProjection(OOMatrix matrix);
void OOGLTranslateProjection(Vector vector);
void OOGLRotateProjection(GLfloat angle, Vector axis);
void OOGLScaleProjection(Vector scale);
void OOGLFrustum(double left, double right, double bottom, double top, double near, double far);
void OOGLOrtho(double left, double right, double bottom, double top, double near, double far);
void OOGLPerspective(double fovy, double aspect, double zNear, double zFar);

OOMatrix OOGLGetModelViewProjection(void);

#endif // OOOPENGLMATRIXMANAGER_H
