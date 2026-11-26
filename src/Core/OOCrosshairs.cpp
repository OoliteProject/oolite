/*

OOCrosshairs.m
Oolite


Copyright (C) 2008 Jens Ayton

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

#include "OOCrosshairs.h"
#include "MyOpenGLView.h"
#include "OOColor.h"
#include "OOMacroOpenGL.h"
#include "Universe.h"
#include "oofnd/PListGet.hpp"

OOCrosshairs::OOCrosshairs(const oo::PList& points, GLfloat scale, OOColor* color, GLfloat alpha)
{
    if (alpha > 0.0f && (color == nullptr || color->alphaComponent() != 0.0f)) {
        setUpDataWithPoints(points, scale, color, alpha);
    }
}

OOCrosshairs::~OOCrosshairs()
{
    free(_data);
}

void OOCrosshairs::render()
{
    if (_data != NULL) {
        OO_ENTER_OPENGL();
        OOSetOpenGLState(OPENGL_STATE_OVERLAY);

        OOGL(glPushAttrib(GL_ENABLE_BIT));
        OOGL(glDisable(GL_LIGHTING));
        OOGL(glDisable(GL_TEXTURE_2D));
        OOGLPushModelView();
        OOGLTranslateModelView(make_vector(0.0, 0.0, (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getDisplay_z() : 0.0f)));

        OOGL(glVertexPointer(2, GL_FLOAT, sizeof(GLfloat) * 6, _data));
        OOGL(glColorPointer(4, GL_FLOAT, sizeof(GLfloat) * 6, _data + 2));

        OOGL(glEnableClientState(GL_VERTEX_ARRAY));
        OOGL(glEnableClientState(GL_COLOR_ARRAY));

        OOGL(glDrawArrays(GL_LINES, 0, _count * 2));

        OOGL(glDisableClientState(GL_VERTEX_ARRAY));
        OOGL(glDisableClientState(GL_COLOR_ARRAY));

        OOGLPopModelView();
        OOGL(glPopAttrib());

        OOVerifyOpenGLState();
        cxx_OOCheckOpenGLErrors("OOCrosshairs after rendering");
    }
}

void OOCrosshairs::setUpDataWithPoints(const oo::PList& points, GLfloat scale, OOColor* color, GLfloat alpha)
{
    NSUInteger i;
    float colorComps[4] = { 0.0f, 1.0f, 0.0f, 1.0f };
    GLfloat* data = NULL;

    _count = points.count();
    if (_count == 0)
        return;

    _data = (GLfloat*)malloc(sizeof(GLfloat) * 12 * _count); // 2 coordinates, 4 colour components for each endpoint of each line segment
    if (color != nullptr)
        color->getRed(&colorComps[0], &colorComps[1], &colorComps[2], &colorComps[3]);

    // Turn the point array into GL-friendly element array
    data = _data;
    for (i = 0; i < _count; i++) {
        setUpDataForOnePoint(points.at<oo::PList::Array>(i), scale, colorComps, alpha, data);
        data += 12;
    }
}

void OOCrosshairs::setUpDataForOnePoint(const oo::PList* pointInfo, GLfloat scale, float colorComps[4], GLfloat alpha, GLfloat* ioBuffer)
{
    GLfloat x1, y1, a1, x2, y2, a2;
    GLfloat r, g, b, a;

    if (pointInfo != nullptr && pointInfo->count() >= 6) {
        a1 = pointInfo->at<float>(0);
        x1 = pointInfo->at<float>(1) * scale;
        y1 = pointInfo->at<float>(2) * scale;
        a2 = pointInfo->at<float>(3);
        x2 = pointInfo->at<float>(4) * scale;
        y2 = pointInfo->at<float>(5) * scale;
        r = colorComps[0];
        g = colorComps[1];
        b = colorComps[2];
        a = colorComps[3];

        /*	a1/a2 * a is hud.plist and crosshairs.plist - specified alpha,
                which must be clamped to 0..1 so the plist-specified alpha can't
                "escape" the overall alpha range. The result of scaling this by
                overall HUD alpha is then clamped again for robustness.
         */
        a1 = OOClamp_0_1_f(OOClamp_0_1_f(a1 * a) * alpha);
        a2 = OOClamp_0_1_f(OOClamp_0_1_f(a2 * a) * alpha);
    } else {
        // Bad entry, write red point in middle.
        x1 = -0.01f;
        x2 = 0.01f;
        y1 = y2 = 0.0f;
        r = 1.0f;
        g = b = 0.0f;
        a1 = a2 = 1.0;
    }

    *ioBuffer++ = x1;
    *ioBuffer++ = y1;
    *ioBuffer++ = r;
    *ioBuffer++ = g;
    *ioBuffer++ = b;
    *ioBuffer++ = a1;

    *ioBuffer++ = x2;
    *ioBuffer++ = y2;
    *ioBuffer++ = r;
    *ioBuffer++ = g;
    *ioBuffer++ = b;
    *ioBuffer++ = a2;

    (void)ioBuffer;
}
