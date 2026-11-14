#import <Foundation/Foundation.h>

static inline NSString *SofaConsoleIdentifier(NSURL *url) {
    if (![url.scheme isEqualToString:@"sofa-consoles"] || ![url.host isEqualToString:@"console"] ||
        ![@[@"/ps5", @"/switch2"] containsObject:url.path] || url.query || url.fragment || url.user || url.password || url.port) return nil;
    return [url.path substringFromIndex:1];
}
