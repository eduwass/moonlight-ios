#import <TVServices/TVServices.h>
#import "../Moonlight TV/SofaConsoleArt.h"
#import "../Moonlight TV/SofaShelfHero.h"

@interface ConsolesTopShelfProvider : TVTopShelfContentProvider
@end
@implementation ConsolesTopShelfProvider
- (void)loadTopShelfContentWithCompletionHandler:(void (^)(id<TVTopShelfContent>))completionHandler {
    NSMutableArray *items = [NSMutableArray arrayWithObject:SofaShelfHero(@"Consoles", @"consoles", @"sofa-consoles")];
    for (NSArray *console in @[@[@"ps5", @"PS5 Pro"], @[@"switch2", @"Switch 2"]]) {
        TVTopShelfCarouselItem *item = [[TVTopShelfCarouselItem alloc] initWithIdentifier:console[0]];
        item.title = console[1]; item.contextTitle = @"Your consoles";
        NSURL *image = SofaConsoleArtURL(console[0]);
        [item setImageURL:image forTraits:TVTopShelfItemImageTraitScreenScale1x];
        [item setImageURL:image forTraits:TVTopShelfItemImageTraitScreenScale2x];
        TVTopShelfAction *action = [[TVTopShelfAction alloc] initWithURL:[NSURL URLWithString:[@"sofa-consoles://console/" stringByAppendingString:console[0]]]];
        item.displayAction = action; item.playAction = action;
        [items addObject:item];
    }
    completionHandler([[TVTopShelfCarouselContent alloc] initWithStyle:TVTopShelfCarouselContentStyleDetails items:items]);
}
@end
