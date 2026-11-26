/*

OOOpenGLMatrixManager.mm

Manages OpenGL Model, View, etc. matrices.

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

#include "OOOpenGLMatrixManager.h"
#include "MyOpenGLView.h"
#include "OOMacroOpenGL.h"
#include "OOOpenGLExtensionManager.h"
#include "Universe.h"

const char* ooliteStandardMatrixUniforms[] = {
    "ooliteModelView",
    "ooliteProjection",
    "ooliteModelViewProjection",
    "ooliteNormalMatrix",
    "ooliteModelViewInverse",
    "ooliteProjectionInverse",
    "ooliteModelViewProjectionInverse",
    "ooliteModelViewTranspose",
    "ooliteProjectionTranspose",
    "ooliteModelViewProjectionTranspose",
    "ooliteModelViewInverseTranspose",
    "ooliteProjectionInverseTranspose",
    "ooliteModelViewProjectionInverseTranspose"
};

// -init and -dealloc only called super: the implicit constructor and destructor.

void OOOpenGLMatrixStack::push(OOMatrix matrix)
{
    stack.push_back(matrix);
}

OOMatrix OOOpenGLMatrixStack::pop()
{
    if (stack.empty()) {
        return kIdentityMatrix;
    }
    OOMatrix matrix = stack.back();
    stack.pop_back();
    return matrix;
}

NSUInteger OOOpenGLMatrixStack::stackCount()
{
    return stack.size();
}

void OOOpenGLMatrixManager::updateModelView()
{
    valid[OOLITE_GL_MATRIX_MODELVIEW_PROJECTION] = NO;
    valid[OOLITE_GL_MATRIX_NORMAL] = NO;
    valid[OOLITE_GL_MATRIX_MODELVIEW_INVERSE] = NO;
    valid[OOLITE_GL_MATRIX_PROJECTION_INVERSE] = NO;
    valid[OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_INVERSE] = NO;
    valid[OOLITE_GL_MATRIX_MODELVIEW_TRANSPOSE] = NO;
    valid[OOLITE_GL_MATRIX_PROJECTION_TRANSPOSE] = NO;
    valid[OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_TRANSPOSE] = NO;
    valid[OOLITE_GL_MATRIX_MODELVIEW_INVERSE_TRANSPOSE] = NO;
    valid[OOLITE_GL_MATRIX_PROJECTION_INVERSE_TRANSPOSE] = NO;
    valid[OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_INVERSE_TRANSPOSE] = NO;
}

void OOOpenGLMatrixManager::updateProjection()
{
    valid[OOLITE_GL_MATRIX_MODELVIEW_PROJECTION] = NO;
    valid[OOLITE_GL_MATRIX_PROJECTION_INVERSE] = NO;
    valid[OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_INVERSE] = NO;
    valid[OOLITE_GL_MATRIX_PROJECTION_TRANSPOSE] = NO;
    valid[OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_TRANSPOSE] = NO;
    valid[OOLITE_GL_MATRIX_PROJECTION_INVERSE_TRANSPOSE] = NO;
    valid[OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_INVERSE_TRANSPOSE] = NO;
}

OOOpenGLMatrixManager::OOOpenGLMatrixManager()
{
    int i;
    for (i = 0; i < OOLITE_GL_MATRIX_END; i++) {
        switch (i) {
        case OOLITE_GL_MATRIX_MODELVIEW:
        case OOLITE_GL_MATRIX_PROJECTION:
            matrices[i] = kIdentityMatrix;
            valid[i] = YES;
            break;

        default:
            valid[i] = NO;
            break;
        }
    }
    modelViewStack = oo::makeRef<OOOpenGLMatrixStack>();
    projectionStack = oo::makeRef<OOOpenGLMatrixStack>();
}

// -dealloc released the two stacks: their oo::Ref members do.

void OOOpenGLMatrixManager::loadModelView(OOMatrix matrix)
{
    matrices[OOLITE_GL_MATRIX_MODELVIEW] = matrix;
    updateModelView();
    return;
}

void OOOpenGLMatrixManager::resetModelView()
{
    matrices[OOLITE_GL_MATRIX_MODELVIEW] = kIdentityMatrix;
    updateModelView();
}

void OOOpenGLMatrixManager::multModelView(OOMatrix matrix)
{
    matrices[OOLITE_GL_MATRIX_MODELVIEW] = OOMatrixMultiply(matrix, matrices[OOLITE_GL_MATRIX_MODELVIEW]);
    updateModelView();
}

void OOOpenGLMatrixManager::translateModelView(Vector vector)
{
    OOMatrix matrix = kIdentityMatrix;
    matrix.m[3][0] = vector.x;
    matrix.m[3][1] = vector.y;
    matrix.m[3][2] = vector.z;
    multModelView(matrix);
}

void OOOpenGLMatrixManager::rotateModelView(GLfloat angle, Vector axis)
{
    multModelView(OOMatrixForRotation(axis, angle));
}

void OOOpenGLMatrixManager::scaleModelView(Vector scale)
{
    multModelView(OOMatrixForScale(scale.x, scale.y, scale.z));
}

void OOOpenGLMatrixManager::lookAtWithEye(Vector eye, Vector center, Vector up)
{
    Vector k = vector_normal(vector_subtract(eye, center));
    Vector i = cross_product(up, k);
    Vector j = cross_product(k, i);
    OOMatrix m1 = OOMatrixConstruct(
        i.x, j.x, k.x, 0.0,
        i.y, j.y, k.y, 0.0,
        i.z, j.z, k.z, 0.0,
        -eye.x, -eye.y, -eye.z, 1.0);
    multModelView(m1);
    return;
}

void OOOpenGLMatrixManager::pushModelView()
{
    modelViewStack->push(matrices[OOLITE_GL_MATRIX_MODELVIEW]);
}

OOMatrix OOOpenGLMatrixManager::popModelView()
{
    matrices[OOLITE_GL_MATRIX_MODELVIEW] = modelViewStack->pop();
    updateModelView();
    return matrices[OOLITE_GL_MATRIX_MODELVIEW];
}

OOMatrix OOOpenGLMatrixManager::getModelView()
{
    return matrices[OOLITE_GL_MATRIX_MODELVIEW];
}

NSUInteger OOOpenGLMatrixManager::countModelView()
{
    return modelViewStack->stackCount();
}

void OOOpenGLMatrixManager::syncModelView()
{
    OO_ENTER_OPENGL();
    OOGL(glMatrixMode(GL_MODELVIEW));
    GLLoadOOMatrix(getModelView());
    return;
}

void OOOpenGLMatrixManager::loadProjection(OOMatrix matrix)
{
    matrices[OOLITE_GL_MATRIX_PROJECTION] = matrix;
    updateProjection();
    return;
}

void OOOpenGLMatrixManager::multProjection(OOMatrix matrix)
{
    matrices[OOLITE_GL_MATRIX_PROJECTION] = OOMatrixMultiply(matrix, matrices[OOLITE_GL_MATRIX_PROJECTION]);
    updateProjection();
}

void OOOpenGLMatrixManager::translateProjection(Vector vector)
{
    OOMatrix matrix = kIdentityMatrix;
    matrix.m[0][3] = vector.x;
    matrix.m[1][3] = vector.y;
    matrix.m[2][3] = vector.z;
    multProjection(matrix);
}

void OOOpenGLMatrixManager::rotateProjection(GLfloat angle, Vector axis)
{
    multProjection(OOMatrixForRotation(axis, angle));
}

void OOOpenGLMatrixManager::scaleProjection(Vector scale)
{
    multProjection(OOMatrixForScale(scale.x, scale.y, scale.z));
}

void OOOpenGLMatrixManager::frustumLeft(double l, double r, double b, double t, double n, double f)
{
    if (l == r || t == b || n == f || n <= 0 || f <= 0)
        return;
    multProjection(OOMatrixConstruct(
        2 * n / (r - l), 0.0, 0.0, 0.0,
        0.0, 2 * n / (t - b), 0.0, 0.0,
        (r + l) / (r - l), (t + b) / (t - b), -(f + n) / (f - n), -1.0,
        0.0, 0.0, -2 * f * n / (f - n), 0.0));
}

void OOOpenGLMatrixManager::orthoLeft(double l, double r, double b, double t, double n, double f)
{
    if (l == r || t == b || n == f)
        return;
    multProjection(OOMatrixConstruct(
        2 / (r - l), 0.0, 0.0, 0.0,
        0.0, 2 / (t - b), 0.0, 0.0,
        0.0, 0.0, 2 / (n - f), 0.0,
        (l + r) / (l - r), (b + t) / (b - t), (n + f) / (n - f), 1.0));
}

void OOOpenGLMatrixManager::perspectiveFovy(double fovy, double aspect, double zNear, double zFar)
{
    if (aspect == 0.0 || zNear == zFar)
        return;
    double f = 1.0 / tan(M_PI * fovy / 360);
    multProjection(OOMatrixConstruct(
        f / aspect, 0.0, 0.0, 0.0,
        0.0, f, 0.0, 0.0,
        0.0, 0.0, (zFar + zNear) / (zNear - zFar), -1.0,
        0.0, 0.0, 2 * zFar * zNear / (zNear - zFar), 0.0));
}

void OOOpenGLMatrixManager::resetProjection()
{
    matrices[OOLITE_GL_MATRIX_PROJECTION] = kIdentityMatrix;
    updateProjection();
}

void OOOpenGLMatrixManager::pushProjection()
{
    projectionStack->push(matrices[OOLITE_GL_MATRIX_PROJECTION]);
}

OOMatrix OOOpenGLMatrixManager::popProjection()
{
    matrices[OOLITE_GL_MATRIX_PROJECTION] = projectionStack->pop();
    updateProjection();
    return matrices[OOLITE_GL_MATRIX_PROJECTION];
}

OOMatrix OOOpenGLMatrixManager::getProjection()
{
    return matrices[OOLITE_GL_MATRIX_PROJECTION];
}

void OOOpenGLMatrixManager::syncProjection()
{
    OO_ENTER_OPENGL();
    OOGL(glMatrixMode(GL_PROJECTION));
    GLLoadOOMatrix(getProjection());
    return;
}

OOMatrix OOOpenGLMatrixManager::getMatrix(int which)
{
    if (which < 0 || which >= OOLITE_GL_MATRIX_END)
        return kIdentityMatrix;
    if (valid[which])
        return matrices[which];
    OOScalar d;
    switch (which) {
    case OOLITE_GL_MATRIX_MODELVIEW_PROJECTION:
        matrices[which] = OOMatrixMultiply(matrices[OOLITE_GL_MATRIX_MODELVIEW], matrices[OOLITE_GL_MATRIX_PROJECTION]);
        break;
    case OOLITE_GL_MATRIX_NORMAL:
        matrices[which] = matrices[OOLITE_GL_MATRIX_MODELVIEW];
        matrices[which].m[3][0] = 0.0;
        matrices[which].m[3][1] = 0.0;
        matrices[which].m[3][2] = 0.0;
        matrices[which].m[0][3] = 0.0;
        matrices[which].m[1][3] = 0.0;
        matrices[which].m[2][3] = 0.0;
        matrices[which].m[3][3] = 1.0;
        matrices[which] = OOMatrixTranspose(OOMatrixInverseWithDeterminant(matrices[which], &d));
        if (d != 0.0) {
            d = powf(fabsf(d), 1.0 / 3);
            for (int i = 0; i < 3; i++) {
                for (int j = 0; j < 3; j++) {
                    matrices[which].m[i][j] /= d;
                }
            }
        }
        break;
    case OOLITE_GL_MATRIX_MODELVIEW_INVERSE:
        matrices[which] = OOMatrixInverse(matrices[OOLITE_GL_MATRIX_MODELVIEW]);
        break;
    case OOLITE_GL_MATRIX_PROJECTION_INVERSE:
        matrices[which] = OOMatrixInverse(matrices[OOLITE_GL_MATRIX_PROJECTION]);
        break;
    case OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_INVERSE:
        matrices[which] = OOMatrixInverse(getMatrix(OOLITE_GL_MATRIX_MODELVIEW_PROJECTION));
        break;
    case OOLITE_GL_MATRIX_MODELVIEW_TRANSPOSE:
        matrices[which] = OOMatrixTranspose(matrices[OOLITE_GL_MATRIX_MODELVIEW]);
        break;
    case OOLITE_GL_MATRIX_PROJECTION_TRANSPOSE:
        matrices[which] = OOMatrixTranspose(matrices[OOLITE_GL_MATRIX_PROJECTION]);
        break;
    case OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_TRANSPOSE:
        matrices[which] = OOMatrixTranspose(getMatrix(OOLITE_GL_MATRIX_MODELVIEW_PROJECTION));
        break;
    case OOLITE_GL_MATRIX_MODELVIEW_INVERSE_TRANSPOSE:
        matrices[which] = OOMatrixTranspose(getMatrix(OOLITE_GL_MATRIX_MODELVIEW_INVERSE));
        break;
    case OOLITE_GL_MATRIX_PROJECTION_INVERSE_TRANSPOSE:
        matrices[which] = OOMatrixTranspose(getMatrix(OOLITE_GL_MATRIX_PROJECTION_INVERSE));
        break;
    case OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_INVERSE_TRANSPOSE:
        matrices[which] = OOMatrixTranspose(getMatrix(OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_INVERSE));
        break;
    }
    valid[which] = YES;
    return matrices[which];
}

oo::PList OOOpenGLMatrixManager::standardMatrixUniformLocations(GLhandleARB program)
{
    GLint location;
    NSUInteger i;
    oo::PList::Array locationSet;

    OO_ENTER_OPENGL();

    for (i = 0; i < OOLITE_GL_MATRIX_END; i++) {
        location = glGetUniformLocationARB(program, ooliteStandardMatrixUniforms[i]);
        if (location >= 0) {
            if (i == OOLITE_GL_MATRIX_NORMAL) {
                locationSet.push_back(oo::PList(oo::PList::Array {
                    oo::PList(location),
                    oo::PList(static_cast<NSInteger>(i)),
                    oo::PList("mat3") }));
            } else {
                locationSet.push_back(oo::PList(oo::PList::Array {
                    oo::PList(location),
                    oo::PList(static_cast<NSInteger>(i)),
                    oo::PList("mat4") }));
            }
        }
    }
    return oo::PList(std::move(locationSet));
}

namespace {

// The game view's manager, taken from the C++ view. Null when there is no universe or view, and
// each OOGL function below then does what its messages to nil did: nothing, or a zero matrix.
OOOpenGLMatrixManager* GameViewMatrixManager()
{
    MyOpenGLView* view = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
    return (view != nullptr) ? view->getOpenGLMatrixManager() : nullptr;
}

} // namespace

void OOGLPushModelView()
{
    OOOpenGLMatrixManager* matrixManager = GameViewMatrixManager();
    if (matrixManager != nullptr)
        matrixManager->pushModelView();
    if (matrixManager != nullptr)
        matrixManager->syncModelView();
}

OOMatrix OOGLPopModelView()
{
    OOOpenGLMatrixManager* matrixManager = GameViewMatrixManager();
    OOMatrix matrix = matrixManager != nullptr ? matrixManager->popModelView() : kZeroMatrix;
    if (matrixManager != nullptr)
        matrixManager->syncModelView();
    return matrix;
}

OOMatrix OOGLGetModelView()
{
    OOOpenGLMatrixManager* matrixManager = GameViewMatrixManager();
    OOMatrix matrix = matrixManager != nullptr ? matrixManager->getModelView() : kZeroMatrix;
    return matrix;
}

void OOGLResetModelView()
{
    OOOpenGLMatrixManager* matrixManager = GameViewMatrixManager();
    if (matrixManager != nullptr)
        matrixManager->resetModelView();
    if (matrixManager != nullptr)
        matrixManager->syncModelView();
}

void OOGLLoadModelView(OOMatrix matrix)
{
    OOOpenGLMatrixManager* matrixManager = GameViewMatrixManager();
    if (matrixManager != nullptr)
        matrixManager->loadModelView(matrix);
    if (matrixManager != nullptr)
        matrixManager->syncModelView();
}

void OOGLMultModelView(OOMatrix matrix)
{
    OOOpenGLMatrixManager* matrixManager = GameViewMatrixManager();
    if (matrixManager != nullptr)
        matrixManager->multModelView(matrix);
    if (matrixManager != nullptr)
        matrixManager->syncModelView();
}

void OOGLTranslateModelView(Vector vector)
{
    OOOpenGLMatrixManager* matrixManager = GameViewMatrixManager();
    if (matrixManager != nullptr)
        matrixManager->translateModelView(vector);
    if (matrixManager != nullptr)
        matrixManager->syncModelView();
}

void OOGLRotateModelView(GLfloat angle, Vector axis)
{
    OOOpenGLMatrixManager* matrixManager = GameViewMatrixManager();
    if (matrixManager != nullptr)
        matrixManager->rotateModelView(angle, axis);
    if (matrixManager != nullptr)
        matrixManager->syncModelView();
}

void OOGLScaleModelView(Vector scale)
{
    OOOpenGLMatrixManager* matrixManager = GameViewMatrixManager();
    if (matrixManager != nullptr)
        matrixManager->scaleModelView(scale);
    if (matrixManager != nullptr)
        matrixManager->syncModelView();
}

void OOGLLookAt(Vector eye, Vector center, Vector up)
{
    OOOpenGLMatrixManager* matrixManager = GameViewMatrixManager();
    if (matrixManager != nullptr)
        matrixManager->lookAtWithEye(eye, center, up);
    if (matrixManager != nullptr)
        matrixManager->syncModelView();
}

void OOGLResetProjection()
{
    OOOpenGLMatrixManager* matrixManager = GameViewMatrixManager();
    if (matrixManager != nullptr)
        matrixManager->resetProjection();
    if (matrixManager != nullptr)
        matrixManager->syncProjection();
}

void OOGLPushProjection()
{
    OOOpenGLMatrixManager* matrixManager = GameViewMatrixManager();
    if (matrixManager != nullptr)
        matrixManager->pushProjection();
    if (matrixManager != nullptr)
        matrixManager->syncProjection();
}

OOMatrix OOGLPopProjection()
{
    OOOpenGLMatrixManager* matrixManager = GameViewMatrixManager();
    OOMatrix matrix = matrixManager != nullptr ? matrixManager->popProjection() : kZeroMatrix;
    if (matrixManager != nullptr)
        matrixManager->syncProjection();
    return matrix;
}

OOMatrix OOGLGetProjection()
{
    OOOpenGLMatrixManager* matrixManager = GameViewMatrixManager();
    OOMatrix matrix = matrixManager != nullptr ? matrixManager->getProjection() : kZeroMatrix;
    return matrix;
}

void OOGLLoadProjection(OOMatrix matrix)
{
    OOOpenGLMatrixManager* matrixManager = GameViewMatrixManager();
    if (matrixManager != nullptr)
        matrixManager->loadProjection(matrix);
    if (matrixManager != nullptr)
        matrixManager->syncProjection();
}

void OOGLMultProjection(OOMatrix matrix)
{
    OOOpenGLMatrixManager* matrixManager = GameViewMatrixManager();
    if (matrixManager != nullptr)
        matrixManager->multProjection(matrix);
    if (matrixManager != nullptr)
        matrixManager->syncProjection();
}

void OOGLTranslateProjection(Vector vector)
{
    OOOpenGLMatrixManager* matrixManager = GameViewMatrixManager();
    if (matrixManager != nullptr)
        matrixManager->translateProjection(vector);
    if (matrixManager != nullptr)
        matrixManager->syncProjection();
}

void OOGLRotateProjection(GLfloat angle, Vector axis)
{
    OOOpenGLMatrixManager* matrixManager = GameViewMatrixManager();
    if (matrixManager != nullptr)
        matrixManager->rotateProjection(angle, axis);
    if (matrixManager != nullptr)
        matrixManager->syncProjection();
}

void OOGLScaleProjection(Vector scale)
{
    OOOpenGLMatrixManager* matrixManager = GameViewMatrixManager();
    if (matrixManager != nullptr)
        matrixManager->scaleProjection(scale);
    if (matrixManager != nullptr)
        matrixManager->syncProjection();
}

void OOGLFrustum(double frleft, double frright, double frbottom, double frtop, double frnear, double frfar)
{
    OOOpenGLMatrixManager* matrixManager = GameViewMatrixManager();
    if (matrixManager != nullptr)
        matrixManager->frustumLeft(frleft, frright, frbottom, frtop, frnear, frfar);
    if (matrixManager != nullptr)
        matrixManager->syncProjection();
}

void OOGLOrtho(double orleft, double orright, double orbottom, double ortop, double ornear, double orfar)
{
    OOOpenGLMatrixManager* matrixManager = GameViewMatrixManager();
    if (matrixManager != nullptr)
        matrixManager->orthoLeft(orleft, orright, orbottom, ortop, ornear, orfar);
    if (matrixManager != nullptr)
        matrixManager->syncProjection();
}

void OOGLPerspective(double fovy, double aspect, double zNear, double zFar)
{
    OOOpenGLMatrixManager* matrixManager = GameViewMatrixManager();
    if (matrixManager != nullptr)
        matrixManager->perspectiveFovy(fovy, aspect, zNear, zFar);
    if (matrixManager != nullptr)
        matrixManager->syncProjection();
}

OOMatrix OOGLGetModelViewProjection()
{
    OOOpenGLMatrixManager* matrixManager = GameViewMatrixManager();
    return matrixManager != nullptr ? matrixManager->getMatrix(OOLITE_GL_MATRIX_MODELVIEW_PROJECTION) : kZeroMatrix;
}
