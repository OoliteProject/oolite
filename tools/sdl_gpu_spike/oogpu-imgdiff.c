/*

oogpu-imgdiff.c

Compares two images of the same size, for renderer regression checks.

Usage: oogpu-imgdiff <a> <b> [-x x0,y0,x1,y1]... [-o <diff image>]
    -x  exclude a rectangle (pixels, inclusive-exclusive), e.g. animated areas
    -o  write a difference image: changed pixels in red, scaled up 8x
Prints the mean and maximum per-channel difference and the share of pixels
that differ by more than 2/255. Exits 0 if no pixel differs by more than
2/255, 1 otherwise, 2 on error.


Copyright (C) 2026 Oolite contributors

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

#include <SDL3/SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum {
    kMaxExclusions = 32
};

static SDL_Surface* Load(const char* path)
{
    size_t length = strlen(path);
    SDL_Surface* loaded;
    if (length > 4 && SDL_strcasecmp(path + length - 4, ".bmp") == 0)
        loaded = SDL_LoadBMP(path);
    else
#if SDL_VERSION_ATLEAST(3, 4, 0)
        loaded = SDL_LoadPNG(path);
#else
        loaded = NULL;
#endif
    if (loaded == NULL) {
        fprintf(stderr, "cannot load %s: %s\n", path, SDL_GetError());
        return NULL;
    }
    SDL_Surface* converted = SDL_ConvertSurface(loaded, SDL_PIXELFORMAT_RGBA32);
    SDL_DestroySurface(loaded);
    return converted;
}

int main(int argc, char* argv[])
{
    int rects[kMaxExclusions][4];
    int rectCount = 0;
    const char* diffPath = NULL;
    const char* paths[2] = { NULL, NULL };
    int pathCount = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-x") == 0 && i + 1 < argc && rectCount < kMaxExclusions) {
            int* r = rects[rectCount];
            if (sscanf(argv[++i], "%d,%d,%d,%d", &r[0], &r[1], &r[2], &r[3]) == 4)
                rectCount++;
        } else if (strcmp(argv[i], "-o") == 0 && i + 1 < argc) {
            diffPath = argv[++i];
        } else if (pathCount < 2) {
            paths[pathCount++] = argv[i];
        }
    }
    if (pathCount != 2) {
        fprintf(stderr, "usage: %s <a> <b> [-x x0,y0,x1,y1]... [-o diff.png]\n", argv[0]);
        return 2;
    }

    SDL_Surface* a = Load(paths[0]);
    SDL_Surface* b = Load(paths[1]);
    if (a == NULL || b == NULL)
        return 2;
    if (a->w != b->w || a->h != b->h) {
        fprintf(stderr, "sizes differ: %dx%d and %dx%d\n", a->w, a->h, b->w, b->h);
        return 2;
    }

    SDL_Surface* diff = diffPath ? SDL_CreateSurface(a->w, a->h, SDL_PIXELFORMAT_RGBA32) : NULL;
    double sum = 0;
    int maxDiff = 0;
    unsigned long compared = 0, differing = 0;
    for (int y = 0; y < a->h; y++) {
        const uint8_t* pa = (const uint8_t*)a->pixels + y * a->pitch;
        const uint8_t* pb = (const uint8_t*)b->pixels + y * b->pitch;
        uint8_t* pd = diff ? (uint8_t*)diff->pixels + y * diff->pitch : NULL;
        for (int x = 0; x < a->w; x++) {
            bool excluded = false;
            for (int r = 0; r < rectCount && !excluded; r++)
                excluded = x >= rects[r][0] && y >= rects[r][1] && x < rects[r][2] && y < rects[r][3];
            int pixelMax = 0;
            if (!excluded) {
                for (int c = 0; c < 3; c++) {
                    int d = abs((int)pa[x * 4 + c] - (int)pb[x * 4 + c]);
                    sum += d;
                    if (d > pixelMax)
                        pixelMax = d;
                }
                compared++;
                if (pixelMax > maxDiff)
                    maxDiff = pixelMax;
                if (pixelMax > 2)
                    differing++;
            }
            if (pd != NULL) {
                // Grey copy of a, with differences in red and exclusions dimmed.
                uint8_t grey = (uint8_t)((pa[x * 4] + pa[x * 4 + 1] + pa[x * 4 + 2]) / 6);
                int boosted = pixelMax * 8 > 255 ? 255 : pixelMax * 8;
                pd[x * 4 + 0] = pixelMax > 2 ? (uint8_t)boosted : grey;
                pd[x * 4 + 1] = excluded ? 0 : grey;
                pd[x * 4 + 2] = excluded ? 64 : grey;
                pd[x * 4 + 3] = 255;
            }
        }
    }
    printf("mean %.3f  max %d  differing %.3f%%  (%lu pixels compared)\n",
        compared ? sum / (compared * 3.0) : 0.0, maxDiff, compared ? 100.0 * differing / compared : 0.0, compared);
    if (diff != NULL) {
#if SDL_VERSION_ATLEAST(3, 4, 0)
        if (!SDL_SavePNG(diff, diffPath))
#else
        if (!SDL_SaveBMP(diff, diffPath))
#endif
            fprintf(stderr, "cannot save %s: %s\n", diffPath, SDL_GetError());
        SDL_DestroySurface(diff);
    }
    SDL_DestroySurface(a);
    SDL_DestroySurface(b);
    return differing == 0 ? 0 : 1;
}
