#import <TVServices/TVServices.h>
#import "../Moonlight TV/SofaShelfStore.h"
#import "../Moonlight TV/SofaShelfHero.h"

@interface SofaTopShelfProvider : TVTopShelfContentProvider
@end
@implementation SofaTopShelfProvider
- (void)loadTopShelfContentWithCompletionHandler:(void (^)(id<TVTopShelfContent>))completionHandler {
    NSArray *hosts = [NSArray arrayWithContentsOfURL:[SofaShelfDirectory() URLByAppendingPathComponent:@"hosts.plist"]] ?: @[];
    hosts = [hosts sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSDate *ad = nil, *bd = nil;
        [SofaShelfPreview(a[@"id"]) getResourceValue:&ad forKey:NSURLContentModificationDateKey error:nil];
        [SofaShelfPreview(b[@"id"]) getResourceValue:&bd forKey:NSURLContentModificationDateKey error:nil];
        NSComparisonResult order = [(bd ?: NSDate.distantPast) compare:(ad ?: NSDate.distantPast)];
        return order == NSOrderedSame ? [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]] : order;
    }];
    NSMutableArray *computers = [NSMutableArray arrayWithObject:SofaShelfHero(@"Computers", @"computers", @"moonlight-next")];
    for (NSDictionary *host in hosts) {
        if (![[NSUUID alloc] initWithUUIDString:host[@"id"]]) continue;
        TVTopShelfCarouselItem *item = [[TVTopShelfCarouselItem alloc] initWithIdentifier:host[@"id"]];
        item.title = host[@"name"]; item.contextTitle = @"Recently used computers";
        NSURL *preview = SofaShelfPreview(host[@"id"]);
        if ([NSFileManager.defaultManager fileExistsAtPath:preview.path]) {
            [item setImageURL:preview forTraits:TVTopShelfItemImageTraitScreenScale1x];
            [item setImageURL:preview forTraits:TVTopShelfItemImageTraitScreenScale2x];
        }
        TVTopShelfAction *action = [[TVTopShelfAction alloc] initWithURL:[NSURL URLWithString:[@"moonlight-next://computer/" stringByAppendingString:host[@"id"]]]];
        item.displayAction = action; item.playAction = action; [computers addObject:item];
    }
    completionHandler([[TVTopShelfCarouselContent alloc] initWithStyle:TVTopShelfCarouselContentStyleDetails items:computers]);
}
@end
