// stb_image_write's implementation, in the vendored library (src/meson.build)
// so that it builds without the game's own warning flags.
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"
