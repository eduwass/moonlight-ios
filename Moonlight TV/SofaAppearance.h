#import <UIKit/UIKit.h>
@class TemporaryHost;

@interface SofaBackdrop : UIView
@property(nonatomic) BOOL consoles;
@end
@implementation SofaBackdrop
- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    [[UIColor colorWithRed:0.025 green:0.03 blue:0.045 alpha:1] setFill]; UIRectFill(rect);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    NSArray *accents = self.consoles ?
        @[[UIColor colorWithRed:0.18 green:0.24 blue:0.65 alpha:0.40], [UIColor colorWithRed:0.65 green:0.10 blue:0.20 alpha:0.34]] :
        @[[UIColor colorWithRed:0.08 green:0.30 blue:0.65 alpha:0.38], [UIColor colorWithRed:0.04 green:0.40 blue:0.50 alpha:0.18]];
    for (NSUInteger i = 0; i < accents.count; i++) {
        UIColor *color = accents[i];
        NSArray *colors = @[(__bridge id)color.CGColor, (__bridge id)[color colorWithAlphaComponent:0].CGColor];
        CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, NULL);
        CGPoint center = CGPointMake(self.bounds.size.width * (i ? 0.95 : 0.05), self.bounds.size.height * 0.45);
        CGContextDrawRadialGradient(context, gradient, center, 0, center, self.bounds.size.width * 0.62, 0);
        CGGradientRelease(gradient);
    }
    CGColorSpaceRelease(space);
}
@end

@interface SofaTile : UIControl
@property(nonatomic, strong) TemporaryHost *host;
@property(nonatomic, copy) NSString *consoleID;
@property(nonatomic, strong) UIImageView *preview;
@property(nonatomic, strong) UILabel *nameLabel, *statusLabel, *previewLabel;
@end
@implementation SofaTile
- (instancetype)init {
    if ((self = [super init])) {
        self.backgroundColor = [UIColor colorWithWhite:0.11 alpha:1];
        self.layer.cornerRadius = 22;
        self.layer.borderWidth = 3;
        self.clipsToBounds = YES;
        _preview = [UIImageView new];
        _preview.contentMode = UIViewContentModeScaleAspectFill;
        _preview.clipsToBounds = YES;
        _preview.backgroundColor = [UIColor colorWithRed:0.10 green:0.15 blue:0.22 alpha:1];
        [self addSubview:_preview];
        _nameLabel = [UILabel new]; _nameLabel.font = [UIFont systemFontOfSize:29 weight:UIFontWeightSemibold];
        _statusLabel = [UILabel new]; _statusLabel.font = [UIFont monospacedDigitSystemFontOfSize:20 weight:UIFontWeightRegular];
        _previewLabel = [UILabel new]; _previewLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
        _previewLabel.textColor = [UIColor colorWithWhite:0.8 alpha:1];
        _previewLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
        _previewLabel.textAlignment = NSTextAlignmentCenter;
        for (UILabel *label in @[_nameLabel, _statusLabel, _previewLabel]) [self addSubview:label];
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return self;
}
- (BOOL)canBecomeFocused { return YES; }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, pictureHeight = w * 9 / 16;
    _preview.frame = CGRectMake(0, 0, w, pictureHeight);
    _previewLabel.frame = CGRectMake(16, pictureHeight - 40, w - 32, 28);
    _nameLabel.frame = CGRectMake(24, pictureHeight + 18, w - 48, 38);
    _statusLabel.frame = CGRectMake(24, pictureHeight + 60, w - 48, 30);
}
- (void)didUpdateFocusInContext:(UIFocusUpdateContext *)context withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator {
    [super didUpdateFocusInContext:context withAnimationCoordinator:coordinator];
    [coordinator addCoordinatedAnimations:^{
        self.transform = self.focused ? CGAffineTransformMakeScale(1.04, 1.04) : CGAffineTransformIdentity;
        UIColor *accent = !self.consoleID ? UIColor.whiteColor : [self.consoleID isEqual:@"ps5"] ?
            [UIColor colorWithRed:0.34 green:0.55 blue:1 alpha:1] : [UIColor colorWithRed:1 green:0.32 blue:0.36 alpha:1];
        self.layer.borderColor = (self.focused ? accent : UIColor.clearColor).CGColor;
        if (self.consoleID) self.preview.alpha = self.focused ? 1 : 0.92;
    } completion:nil];
}
- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    for (UIPress *press in presses) {
        if (press.type == UIPressTypeSelect || press.key.keyCode == UIKeyboardHIDUsageKeyboardReturnOrEnter) {
            [self sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
            return;
        }
    }
    [super pressesEnded:presses withEvent:event];
}
@end
