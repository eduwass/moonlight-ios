#import <UIKit/UIKit.h>

// Personal tvOS experiment: a native editor covered by the live stream layer.
@interface SofaDictation : NSObject
+ (void)runSelfCheck;
- (void)startIn:(UIViewController *)owner streamView:(UIView *)streamView;
- (void)stop;
@end

@interface SofaApplication : UIApplication
@end
