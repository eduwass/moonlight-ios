#import <UIKit/UIKit.h>
@interface SofaCursorChannel : NSObject <NSStreamDelegate>
@property(nonatomic, copy) void (^changed)(UIImage *image, CGSize size, CGPoint hotspot, BOOL connected);
- (void)startForHost:(NSString *)host;
- (void)stop;
@end
