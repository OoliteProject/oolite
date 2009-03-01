/*	pngusr.h: customise libpng build */

/* We only want to read PNGs */
#define PNG_NO_WRITE_SUPPORTED

/* No textures embedded in MNGs for us. */
#define PNG_NO_MNG_FEATURES

/* Read transformations we don't use */
#define PNG_NO_READ_STRIP_ALPHA
#define PNG_NO_READ_SWAP
#define PNG_NO_READ_PACKSWAP
#define PNG_NO_READ_DITHER
#define PNG_NO_READ_GAMMA
#define PNG_NO_READ_INVERT_ALPHA
#define PNG_NO_READ_USER_TRANSFORM
#define PNG_NO_READ_BACKGROUND
#define PNG_NO_READ_SHIFT

#define PNG_NO_PROGRESSIVE_READ

/* Real men access the info struct directly */
#define PNG_NO_EASY_ACCESS

/* Let libpng do its own malloc()ing */
#define PNG_NO_USER_MEM

/* Static size limit */
#define PNG_NO_SET_USER_LIMITS
#define PNG_USER_WIDTH_MAX		(65536L)
#define PNG_USER_HEIGHT_MAX		PNG_USER_WIDTH_MAX

/* We don't want any ancillary chunks. */
#define PNG_NO_READ_TEXT
#define PNG_READ_ANCILLARY_CHUNKS_NOT_SUPPORTED

/* tRNS chunk support has a	vulnerability prior to libpng 1.2.18, and we don't need it anyway. */
#define PNG_NO_READ_tRNS
