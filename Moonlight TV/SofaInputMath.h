#pragma once
#include <math.h>
#include <stdint.h>
#include <limits.h>
static inline double SofaBound(double value, double delta, double maximum) {
    return isfinite(delta) ? fmin(fmax(value + delta, 0), fmax(0, maximum)) : value;
}
static inline short SofaTakeDelta(double *remainder, double delta) {
    if (!isfinite(delta)) return 0;
    *remainder = fmin(SHRT_MAX, fmax(SHRT_MIN, *remainder + delta));
    short whole = (short)*remainder;
    *remainder -= whole;
    return whole;
}
// Suppress buttons held across a host/foreground transition until released.
static inline uint32_t SofaButtons(uint32_t raw, uint32_t *blocked) {
    *blocked &= raw;
    return raw & ~*blocked & 31;
}

#include <stdbool.h>
typedef struct {
    bool held[256], sent[256], blocked[256];
    bool launcherF4;
} SofaKeys;
enum { SofaControl = 1, SofaShift = 2, SofaAlt = 4, SofaMeta = 8 };
static inline unsigned SofaKeyModifiers(const SofaKeys *keys) {
    unsigned flags = 0;
    for (unsigned i = 0; i < 4; i++)
        if (keys->sent[0xE0 + i] || keys->sent[0xE4 + i]) flags |= 1u << i;
    return flags;
}
// Return 1 for a new down, -1 for its matching up, 0 for navigation/repeats/held-across-transition keys.
static inline int SofaKeyTransition(SofaKeys *keys, unsigned code, bool pressed, bool streaming) {
    if (code >= 256) return 0;
    keys->held[code] = pressed;
    if (!pressed) {
        keys->blocked[code] = false;
        bool wasSent = keys->sent[code];
        keys->sent[code] = false;
        return wasSent ? -1 : 0;
    }
    if (!streaming || keys->blocked[code] || keys->sent[code]) return 0;
    keys->sent[code] = true;
    return 1;
}
static inline void SofaResetKeys(SofaKeys *keys) {
    keys->launcherF4 = false;
    for (unsigned i = 0; i < 256; i++) {
        keys->sent[i] = false;
        keys->blocked[i] = keys->held[i];
    }
}

// Only explicit Search/Spotlight usages; remote Select and Escape are not launchers.
static inline bool SofaIsLauncherHIDUsage(unsigned page, unsigned usage) {
    return (page == 0x0C && usage == 0x0221) ||
        (page == 0xFF01 && usage == 1);
}

// Consume bare F4 (HID 61) through release, even if modifiers change while held.
static inline bool SofaConsumeLauncherF4(SofaKeys *keys, unsigned code, int transition) {
    if (code != 61) return false;
    if (transition > 0) keys->launcherF4 = SofaKeyModifiers(keys) == 0;
    bool consumed = keys->launcherF4;
    if (transition < 0) keys->launcherF4 = false;
    return consumed;
}

// tvOS may deliver Escape as a keyless Menu press before/after GCKeyboard's callback.
static inline bool SofaEscapeSuppressesNavigation(bool held, double lastEscape, double now) {
    return held || (lastEscape > 0 && now - lastEscape < 0.4);
}
