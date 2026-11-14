# distancemap

Command-line tool that turns a large 8-bit greyscale PNG into a downscaled signed distance map
(see `distancemap.c`), plus a test shader in `dmap-shader/`. Plain C, using libpng:

```bash
cc -O2 -o distancemap distancemap.c GrayMap.c -lpng -lm
```
