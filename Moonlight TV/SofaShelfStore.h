#import <Foundation/Foundation.h>
#import <TVServices/TVServices.h>

static inline NSURL *SofaShelfDirectory(void) {
    NSURL *root = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:@"group.com.eduwass.moonlightnext"];
    if (!root) return nil;
    NSURL *directory = [root URLByAppendingPathComponent:@"Library/Caches/Computers" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return directory;
}
static inline NSURL *SofaShelfPreview(NSString *identifier) {
    NSString *safe = [[identifier componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@""];
    return [SofaShelfDirectory() URLByAppendingPathComponent:[safe stringByAppendingPathExtension:@"jpg"]];
}
