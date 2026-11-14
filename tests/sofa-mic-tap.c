// cc -Wall -Wextra -Werror tests/sofa-mic-tap.c -o /tmp/sofa-mic-tap && /tmp/sofa-mic-tap
#include "../Moonlight TV/SofaMicTap.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    SofaMicTapState s={0};
    // Replay the real device trace: double-tap, hold, duplicated release, double-tap.
    assert(!SofaMicTap(&s,false,false,3.206));
    assert(SofaMicTap(&s,false,false,3.448));
    assert(!SofaMicTap(&s,true,false,7.185));
    assert(!SofaMicTap(&s,false,true,11.366));
    assert(!SofaMicTap(&s,false,true,11.371));
    assert(!SofaMicTap(&s,false,false,15.164));
    assert(SofaMicTap(&s,false,false,15.401));
    s=(SofaMicTapState){0};
    assert(!SofaMicTap(&s,false,false,1));
    assert(!SofaMicTap(&s,false,false,1.005)); // Duplicate is not a double-tap.
    assert(!SofaMicTap(&s,false,false,2)); // Isolated taps never combine.
    assert(!SofaMicTap(&s,true,false,2.1)); // Tap followed by a hold cancels candidate.
    assert(!SofaMicTap(&s,false,false,4));
    assert(!SofaMicTap(&s,false,false,4.005));
    assert(!SofaMicTap(&s,false,true,5)); // Recognition still pending.
    assert(!SofaMicTap(&s,false,true,5.2));
    s=(SofaMicTapState){0}; // Disconnect/reconnect cannot carry a first tap.
    assert(!SofaMicTap(&s,false,false,5.3));
    assert(SofaMicTap(&s,false,false,5.55));
    assert(!SofaMicTap(&s,false,false,5.56));
    assert(!SofaMicTap(&s,false,false,5.8)); // Triple tap sends only one Enter.
    puts("Mic taps: trace replay, holds, duplicates, isolated taps and resets passed.");
}
