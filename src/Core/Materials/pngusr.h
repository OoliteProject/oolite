/*	pngusr.h: customise libpng build */

/* We only want to read PNGs */
#define PNG_NO_WRITE_SUPPORTED

/* No textures embedded in MNGs for us. */
#define PNG_NO_MNG_FEATURES

/* We provide our own libpng error/warning functions */
#define PNG_NO_STDIO

/* Read transformations we don't use */
#define PNG_NO_READ_STRIP_ALPHA
// #define PNG_NO_READ_BGR
#define PNG_NO_READ_SWAP
#define PNG_NO_READ_PACKSWAP
#define PNG_NO_READ_INVERT
#define PNG_NO_READ_DITHER
#define PNG_NO_READ_GAMMA
#define PNG_NO_READ_INVERT_ALPHA
#define PNG_NO_READ_STRIP_ALPHA
#define PNG_NO_READ_USER_TRANSFORM
#define PNG_NO_READ_RGB_TO_GRAY
#define PNG_NO_READ_BACKGROUND
#define PNG_NO_READ_SHIFT

#define PNG_NO_PROGRESSIVE_READ

/* Real men access the info struct directly */
#define PNG_NO_EASY_ACCESS

/* Very definitely do not set PNG_THREAD_UNSAFE_OK */

/* Let libpng do its own malloc()ing */
#define PNG_NO_USER_MEM

/* Static size limit */
#define PNG_NO_SET_USER_LIMITS
#define PNG_USER_WIDTH_MAX		(65536L)
#define PNG_USER_HEIGHT_MAX		PNG_USER_WIDTH_MAX

/* We don't want any ancillary chunks. */
#define PNG_NO_iTXt_SUPPORTED
#define PNG_READ_ANCILLARY_CHUNKS_NOT_SUPPORTED
