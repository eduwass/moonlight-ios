#pragma once
#include <stdbool.h>

typedef struct {
    bool held, waiting, hasRelease;
    double firstTap, lastRelease;
} SofaMicTapState;

// Device trace: quick taps have release-only reports; holds have down + up,
// sometimes with duplicated ups. Only two distinct short taps may send Enter.
static inline bool SofaMicTap(SofaMicTapState *s, bool down, bool dictating, double now) {
    if (down) { s->held=true; s->waiting=false; return false; }
    if (s->hasRelease && now-s->lastRelease<0.075) return false;
    s->hasRelease=true; s->lastRelease=now;
    if (s->held || dictating) { s->held=false; s->waiting=false; return false; }
    if (s->waiting && now-s->firstTap<=0.4) { s->waiting=false; return true; }
    s->waiting=true; s->firstTap=now;
    return false;
}
