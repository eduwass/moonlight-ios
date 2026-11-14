#pragma once
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
// Same bounded header as moonlight-qt's cursorshare_mac.mm.
static inline bool SofaCursorHeader(const char *line, int *w, int *h, int *x, int *y, unsigned long *bytes) {
    int used = 0;
    return strlen(line) <= 40 && sscanf(line, "%4d %4d %4d %4d %8lu\n%n", w,h,x,y,bytes,&used) == 5 &&
        line[used] == 0 && *w > 0 && *h > 0 && *w <= 256 && *h <= 256 &&
        *x >= 0 && *y >= 0 && *x < *w && *y < *h && *bytes > 0 && *bytes <= 4*1024*1024;
}
