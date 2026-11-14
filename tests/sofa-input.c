// cc -Wall -Wextra -Werror tests/sofa-input.c -lm -o /tmp/sofa-input-check && /tmp/sofa-input-check
#include "../Moonlight TV/SofaInputMath.h"
#include <assert.h>
#include "../Moonlight TV/SofaCursorProtocol.h"
int main(void) {
    int w,h,x,y; unsigned long bytes;
    assert(SofaCursorHeader("24 24 2 3 123\n", &w,&h,&x,&y,&bytes));
    assert(w==24 && h==24 && x==2 && y==3 && bytes==123);
    assert(!SofaCursorHeader("24 24 24 0 123\n", &w,&h,&x,&y,&bytes));
    assert(!SofaCursorHeader("24 24 0 0 99999999\n", &w,&h,&x,&y,&bytes));
    assert(!SofaCursorHeader("24 24 -1 0 123\n", &w,&h,&x,&y,&bytes));
    assert(!SofaCursorHeader("24 24 0 0 123 junk\n", &w,&h,&x,&y,&bytes));
    assert(SofaBound(10, NAN, 100) == 10);
    assert(SofaBound(10, -20, 100) == 0);
    assert(SofaBound(10, 200, 100) == 100);
    double remainder = 0;
    assert(SofaTakeDelta(&remainder, 0.75) == 0);
    assert(SofaTakeDelta(&remainder, 0.75) == 1);
    assert(remainder == 0.5);
    assert(SofaTakeDelta(&remainder, INFINITY) == 0);
    assert(SofaTakeDelta(&remainder, 1e9) == SHRT_MAX);
    assert(SofaTakeDelta(&remainder, -1e9) == SHRT_MIN);
    uint32_t blocked = 1;
    assert(SofaButtons(1, &blocked) == 0);
    assert(SofaButtons(3, &blocked) == 2);
    assert(SofaButtons(0, &blocked) == 0);
    assert(SofaButtons(1, &blocked) == 1);
    assert(SofaButtons(0xFFFFFFFF, &blocked) == 31);
    assert(!SofaEscapeSuppressesNavigation(false, 0, 1)); // Physical Back
    assert(SofaEscapeSuppressesNavigation(true, 1, 10)); // Long-held Escape
    assert(SofaEscapeSuppressesNavigation(false, 10, 10.15)); // Menu arrives after Escape release
    assert(SofaEscapeSuppressesNavigation(false, 10.15, 10.3)); // Double Escape
    assert(!SofaEscapeSuppressesNavigation(false, 10, 11)); // Back works again
    assert(!SofaIsLauncherHIDUsage(0x0C, 0x80)); // Apple TV remote centre/Select.
    assert(SofaIsLauncherHIDUsage(0x0C, 0x0221));
    assert(SofaIsLauncherHIDUsage(0xFF01, 1));
    assert(!SofaIsLauncherHIDUsage(1, 0x86)); // Escape/System App Menu must never launch.
    assert(!SofaIsLauncherHIDUsage(7, 41));
    assert(!SofaIsLauncherHIDUsage(0x0C, 0xCD)); // Play/pause is unrelated.
    SofaKeys keys = {0};
    assert(SofaKeyTransition(&keys, 40, true, false) == 0); // Enter on a home tile
    SofaResetKeys(&keys);
    assert(SofaKeyTransition(&keys, 40, true, true) == 0); // Held Enter must not leak into desktop
    assert(SofaKeyTransition(&keys, 40, false, true) == 0);
    assert(SofaKeyTransition(&keys, 40, true, true) == 1);
    assert(SofaKeyTransition(&keys, 40, true, true) == 0); // No duplicate down
    assert(SofaKeyTransition(&keys, 40, false, true) == -1);
    assert(SofaKeyTransition(&keys, 41, true, true) == 1); // Escape is forwarded
    assert(SofaKeyTransition(&keys, 41, true, true) == 0); // A second GCKeyboard report cannot duplicate it
    assert(SofaKeyTransition(&keys, 41, false, true) == -1);
    assert(SofaKeyTransition(&keys, 0xE1, true, true) == 1);
    assert(SofaKeyTransition(&keys, 0xE4, true, true) == 1);
    assert(SofaKeyModifiers(&keys) == (SofaShift | SofaControl));
    assert(SofaKeyTransition(&keys, 0xE1, false, true) == -1);
    assert(SofaKeyModifiers(&keys) == SofaControl);
    SofaResetKeys(&keys);
    assert(SofaKeyModifiers(&keys) == 0);
    assert(SofaKeyTransition(&keys, 0xE4, false, true) == 0);
    assert(SofaKeyTransition(&keys, 0xE3, true, true) == 1); // Raw Command down
    assert(SofaKeyTransition(&keys, 0xE3, true, true) == 0); // Duplicate GC callback
    assert(SofaKeyModifiers(&keys) == SofaMeta);
    assert(SofaKeyTransition(&keys, 6, true, true) == 1); // C retains Command
    assert(SofaKeyModifiers(&keys) == SofaMeta);
    assert(SofaKeyTransition(&keys, 6, false, true) == -1);
    assert(SofaKeyTransition(&keys, 0xE3, false, true) == -1);
    assert(SofaKeyTransition(&keys, 0xE3, false, true) == 0);
    assert(SofaKeyModifiers(&keys) == 0);
    assert(SofaKeyTransition(&keys, 9999, true, true) == 0);
    keys = (SofaKeys){0};
    assert(SofaConsumeLauncherF4(&keys, 61, SofaKeyTransition(&keys, 61, true, true)));
    assert(SofaKeyTransition(&keys, 61, true, true) == 0); // Holding F4 cannot toggle twice.
    assert(SofaConsumeLauncherF4(&keys, 61, 0));
    assert(SofaKeyTransition(&keys, 0xE2, true, true) == 1);
    assert(SofaConsumeLauncherF4(&keys, 61, SofaKeyTransition(&keys, 61, false, true)));
    assert(!keys.launcherF4); // Release stays consumed even after Alt is pressed.
    assert(!SofaConsumeLauncherF4(&keys, 61, SofaKeyTransition(&keys, 61, true, true))); // Alt+F4 passes through.
    assert(!SofaConsumeLauncherF4(&keys, 61, SofaKeyTransition(&keys, 61, false, true)));
    assert(SofaKeyTransition(&keys, 0xE2, false, true) == -1);
    assert(SofaConsumeLauncherF4(&keys, 61, SofaKeyTransition(&keys, 61, true, true)));
    SofaResetKeys(&keys);
    assert(!keys.launcherF4);
    assert(SofaKeyTransition(&keys, 61, true, true) == 0); // Held across host switch: no launch.
    assert(!SofaConsumeLauncherF4(&keys, 61, 0));
    assert(SofaKeyTransition(&keys, 61, false, true) == 0);
    assert(SofaConsumeLauncherF4(&keys, 61, SofaKeyTransition(&keys, 61, true, true)));
}
