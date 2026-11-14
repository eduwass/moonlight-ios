#import <UIKit/UIKit.h>

@interface SofaInput : NSObject
@property(nonatomic) BOOL streaming;
@property(nonatomic, readonly) BOOL available;
@property(nonatomic, readonly) BOOL escapeSuppressesNavigation;
@property(nonatomic, readonly) BOOL keyboardConfirmed;
@property(nonatomic, readonly) NSTimeInterval lastMouseEvent;
@property(nonatomic, copy) void (^activateFocusedControl)(void);
+ (instancetype)shared;
- (void)prepareCursorForHost:(NSString *)host videoSize:(CGSize)size;
- (void)start;
- (void)stop;
- (void)logDiagnostics;
- (void)sendEscapeTap;
- (void)sendShortcutUsage:(UIKeyboardHIDUsage)usage modifiers:(UIKeyModifierFlags)modifiers;
@end
