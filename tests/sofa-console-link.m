// Run on macOS: clang -fobjc-arc -framework Foundation tests/sofa-console-link.m -o /tmp/sofa-console-link && /tmp/sofa-console-link
#import "../Moonlight TV/SofaConsoleLink.h"
#include <assert.h>
int main(void) {
    @autoreleasepool {
        assert([SofaConsoleIdentifier([NSURL URLWithString:@"sofa-consoles://console/ps5"]) isEqual:@"ps5"]);
        assert([SofaConsoleIdentifier([NSURL URLWithString:@"sofa-consoles://console/switch2"]) isEqual:@"switch2"]);
        for (NSString *invalid in @[@"https://console/ps5", @"sofa-consoles://other/ps5", @"sofa-consoles://console/switch", @"sofa-consoles://console/ps5?host=evil", @"sofa-consoles://console/ps5#evil", @"sofa-consoles://evil@console/ps5", @"sofa-consoles://console:1926/ps5", @"sofa-consoles://console/", @"sofa-consoles://console/ps5/extra"])
            assert(SofaConsoleIdentifier([NSURL URLWithString:invalid]) == nil);
        assert(SofaConsoleIdentifier(nil) == nil);
        puts("Console links: valid consoles accepted; malformed and foreign URLs rejected.");
    }
}
