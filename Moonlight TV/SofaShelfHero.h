#import <TVServices/TVServices.h>

static inline TVTopShelfCarouselItem *SofaShelfHero(NSString *name, NSString *identifier, NSString *scheme) {
    TVTopShelfCarouselItem *hero = [[TVTopShelfCarouselItem alloc] initWithIdentifier:[identifier stringByAppendingString:@"-hero"]];
    hero.title = name;
    hero.contextTitle = @"Make yourself comfortable";
    hero.summary = [identifier isEqual:@"computers"] ? @"Your desktops, from the sofa." : @"Pick your next adventure.";
    NSURL *image = [NSBundle.mainBundle URLForResource:[identifier stringByAppendingString:[identifier isEqual:@"computers"] ? @"-hero-v5" : @"-hero-v3"] withExtension:[identifier isEqual:@"computers"] ? @"png" : @"jpg" subdirectory:@"SofaArtwork"];
    [hero setImageURL:image forTraits:TVTopShelfItemImageTraitScreenScale1x];
    [hero setImageURL:image forTraits:TVTopShelfItemImageTraitScreenScale2x];
    hero.displayAction = [[TVTopShelfAction alloc] initWithURL:[NSURL URLWithString:[scheme stringByAppendingString:@"://home"]]];
    return hero;
}
