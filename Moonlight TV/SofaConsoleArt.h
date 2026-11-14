#import <UIKit/UIKit.h>

// Both bundles carry the same artwork, so Top Shelf never needs a network fetch.
static inline NSURL *SofaConsoleArtURL(NSString *identifier) {
    if (![@[@"ps5", @"switch2"] containsObject:identifier]) return nil;
    return [NSBundle.mainBundle URLForResource:[identifier stringByAppendingString:@"-v1"] withExtension:@"png" subdirectory:@"SofaArtwork"];
}
static inline UIImage *SofaConsoleArt(NSString *identifier, NSString *title) {
    NSURL *url = SofaConsoleArtURL(identifier);
    return url ? [UIImage imageWithContentsOfFile:url.path] : [UIImage systemImageNamed:@"gamecontroller.fill"];
}
