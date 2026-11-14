#import <UIKit/UIKit.h>

@interface SofaTVControl : NSObject
+ (instancetype)shared;
- (void)importConfiguration;
- (NSArray<NSDictionary *> *)inputs;
- (void)openInput:(NSString *)identifier fromController:(UIViewController *)controller;
@end
