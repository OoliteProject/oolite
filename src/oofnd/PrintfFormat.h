/*
oofnd/PrintfFormat.h

OO_PRINTF_FORMAT(fmt, first): the format attribute of a printf-style function (C
or C++).

GCC on MinGW reads format(printf, ...) as the Microsoft runtime's printf (its
ms_printf), which has no %zu, %lld or %hhd, so every size_t argument the game
formats warned "unknown conversion type character 'z'". What the game actually
calls is C99's: libstdc++ defines __USE_MINGW_ANSI_STDIO=1 unconditionally
(bits/os_defines.h), so std::vsnprintf under GCC is MinGW's C99 printf, which
GCC names gnu_printf; Clang's printf already checks C99 and is unchanged.
*/

#pragma once

#if defined(__MINGW32__) && defined(__GNUC__) && !defined(__clang__)
#define OO_PRINTF_FORMAT(fmt, first) \
  __attribute__((format(gnu_printf, fmt, first)))
#elif defined(__GNUC__) || defined(__clang__)
#define OO_PRINTF_FORMAT(fmt, first) __attribute__((format(printf, fmt, first)))
#else
#define OO_PRINTF_FORMAT(fmt, first)
#endif
