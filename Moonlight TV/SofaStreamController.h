#import "StreamFrameViewController.h"
@interface SofaStreamController : StreamFrameViewController
@property(nonatomic, copy) NSString *previewID;
@end
static inline NSURL *SofaPreviewURL(NSString *identifier) {
    NSString *safe = [[identifier componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet]
                     componentsJoinedByString:@""];
    NSURL *directory = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].lastObject;
    directory = [directory URLByAppendingPathComponent:@"SofaPreviews" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return [directory URLByAppendingPathComponent:[safe stringByAppendingPathExtension:@"jpg"]];
}
