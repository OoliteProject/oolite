/*

OOExhaustPlumeEntity.h


Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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

#import "OOTexture.h"
#import "ShipEntity.h"

#include "oofnd/StdLib.hpp"

typedef struct
{
    double timeframe; // universal time for this frame
    HPVector position;
    Quaternion orientation;
    Vector k; // direction vectors
} Frame;

enum {
    kExhaustFrameCount = 16
};

namespace cxx {

class OOExhaustPlumeEntity : public Entity {
public:
    // definition: the exhaust's tokens (x y z scale_x scale_y scale_z), read as -oo_floatAtIndex: read them.
    // +exhaustForShip:withDefinition:andScale:: a new plume, initialised; null for no tokens. The
    // facade's class method hands it to Objective-C (oo::NewEntityFacade).
    static oo::Ref<OOExhaustPlumeEntity> exhaustForShip(::ShipEntity* ship, const std::vector<std::string>& definition, float scale);
    // -initForShip:withDefinition:andScale:'s body, run once right after construction (amendment
    // oo-vl43 item 2): false where the initialiser answered nil.
    bool initForShip(::ShipEntity* ship, const std::vector<std::string>& definition, float scale);

    void resetPlume();

    Vector scale();
    void setScale(Vector scale);

    ::OOTexture* texture();

    static void setUpTexture();
    static ::OOTexture* plumeTexture();
    // The graphics reset client is the facade class, which forwards here.
    static void resetGraphicsState();

    // OOSubEntity, answered by the facade.
    void rescaleBy(GLfloat factor);
    void rescaleBy(GLfloat factor, bool writeToCache);
    void drawSubEntityImmediate(bool immediate, bool translucent);

    // Entity (OOExhaustPlume), which the facade's category answers from here.
    bool isExhaust();

    double findCollisionRadius() override;
    void update(OOTimeDelta delta_t) override;

private:
    void saveToLastFrame();
    Frame frameAtTime(double t_frame, Frame frame_zero); // t_frame is relative to now ie. -0.5 = half a second ago.

    Vector _exhaustScale = { };
    OOHPScalar _vertices[34 * 3] = { };
    GLfloat _glVertices[34 * 3] = { };
    GLfloat _exhaustBaseColors[34 * 4] = { };
    Frame _track[kExhaustFrameCount] = { };
    OOTimeAbsolute _trackTime = { };
    uint8_t _nextFrame = { };
};

} // namespace cxx

// Transitional: the Objective-C OOExhaustPlumeEntity, for the ships, which make it and message it,
// and the scripting binding. Deleted, with namespace cxx above, by the bridge's deletion bead.
#import "OOExhaustPlumeEntity+ObjCBridge.h"
