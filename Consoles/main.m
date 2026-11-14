#import <UIKit/UIKit.h>
#import <TVServices/TVServices.h>
#import "../Moonlight TV/SofaAppearance.h"
#import "../Moonlight TV/SofaConsoleArt.h"
#import "../Moonlight TV/SofaConsoleLink.h"
#import "../Moonlight TV/SofaTVControl.h"

@interface ConsolesController : UIViewController
@property(nonatomic, strong) NSArray<SofaTile *> *tiles;
@property(nonatomic, strong) UILabel *heading, *subtitle, *hint;
@property(nonatomic, copy) NSString *pendingInput;
- (void)openPendingInput;
@end
@implementation ConsolesController
- (void)loadView {
    SofaBackdrop *background = [SofaBackdrop new];
    background.consoles = YES;
    background.contentMode = UIViewContentModeRedraw;
    self.view = background;
}
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight {
    UILabel *label = [UILabel new];
    label.text = text; label.font = [UIFont systemFontOfSize:size weight:weight];
    label.textColor = UIColor.whiteColor;
    [self.view addSubview:label];
    return label;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.heading = [self label:@"Consoles" size:58 weight:UIFontWeightBold];
    self.subtitle = [self label:@"Pick your next adventure." size:25 weight:UIFontWeightRegular];
    self.subtitle.textColor = [UIColor colorWithWhite:0.65 alpha:1];
    self.hint = [self label:@"Choose a console. Wake it with its controller." size:21 weight:UIFontWeightRegular];
    self.hint.textColor = [UIColor colorWithWhite:0.5 alpha:1];
    NSMutableArray *tiles = [NSMutableArray new];
    for (NSArray *console in @[@[@"ps5", @"PS5 Pro"], @[@"switch2", @"Switch 2"]]) {
        SofaTile *tile = [SofaTile new];
        tile.consoleID = console[0]; tile.nameLabel.text = console[1];
        tile.preview.image = SofaConsoleArt(console[0], console[1]);
        tile.previewLabel.hidden = YES;
        tile.statusLabel.text = @"Play on your TV";
        tile.statusLabel.textColor = UIColor.secondaryLabelColor;
        tile.accessibilityLabel = [@"Play on " stringByAppendingString:console[1]];
        [tile addTarget:self action:@selector(openConsole:) forControlEvents:UIControlEventPrimaryActionTriggered];
        [self.view addSubview:tile]; [tiles addObject:tile];
    }
    self.tiles = tiles;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width, h = self.view.bounds.size.height;
    CGFloat margin = MAX(60, w * 0.055), gap = 55;
    self.heading.frame = CGRectMake(margin, 70, w - 2 * margin, 80);
    self.subtitle.frame = CGRectMake(margin, 157, w - 2 * margin, 40);
    CGFloat width = MIN(730, (w - 2 * margin - gap) / 2);
    CGFloat height = width * 9 / 16 + 114;
    CGFloat x = (w - 2 * width - gap) / 2;
    for (SofaTile *tile in self.tiles) {
        tile.bounds = CGRectMake(0, 0, width, height);
        tile.center = CGPointMake(x + width / 2, (h + 120) / 2);
        x += width + gap;
    }
    self.hint.frame = CGRectMake(margin, h - 110, w - 2 * margin, 45);
}
- (NSArray<id<UIFocusEnvironment>> *)preferredFocusEnvironments { return self.tiles.count ? @[self.tiles[0]] : @[]; }
- (void)openConsole:(SofaTile *)tile { [SofaTVControl.shared openInput:tile.consoleID fromController:self]; }
- (void)openPendingInput {
    if (!self.pendingInput || !self.view.window || self.presentedViewController) return;
    NSString *identifier = self.pendingInput; self.pendingInput = nil;
    [SofaTVControl.shared openInput:identifier fromController:self];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self openPendingInput];
#if DEBUG
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--sofa-screenshot"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:self.view.bounds.size];
            UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
                [self.view.layer renderInContext:context.CGContext];
            }];
            NSURL *cache = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].lastObject;
            [UIImagePNGRepresentation(image) writeToURL:[cache URLByAppendingPathComponent:@"sofa-home.png"] atomically:YES];
            [@{ @"paired": @(SofaTVControl.shared.inputs.count == 2) } writeToURL:[cache URLByAppendingPathComponent:@"sofa-setup.plist"] atomically:YES];
        });
    }
#endif
}
@end

@interface ConsolesDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation ConsolesDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    [SofaTVControl.shared importConfiguration];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [ConsolesController new];
    [self.window makeKeyAndVisible];
    [TVTopShelfContentProvider topShelfContentDidChange];
    return YES;
}
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url options:(NSDictionary *)options {
    if ([url.absoluteString isEqual:@"sofa-consoles://home"]) return YES;
    NSString *identifier = SofaConsoleIdentifier(url);
    if (!identifier) return NO;
    ConsolesController *controller = (ConsolesController *)self.window.rootViewController;
    controller.pendingInput = identifier;
    dispatch_async(dispatch_get_main_queue(), ^{ [controller openPendingInput]; });
    return YES;
}
@end
int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(ConsolesDelegate.class)); }
}
