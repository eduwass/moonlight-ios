#import "SofaStreamController.h"
#import "SofaInput.h"
#import "SofaDictation.h"
#import "SofaShelfStore.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <GameController/GameController.h>

@interface StreamFrameViewController (SofaNavigation)
- (void)returnToMainFrame;
@end

@implementation SofaStreamController {
    SofaDictation *_dictation;
    NSTimer *_previewTimer;
    NSTimer *_inputTimer;
    BOOL _connected;
    BOOL _leaving;
    NSMutableSet<GCController *> *_remotes;
    NSArray<UIKeyCommand *> *_shortcuts;
}
- (NSArray<UIKeyCommand *> *)keyCommands {
    if (!_shortcuts) {
        NSMutableDictionary<NSString *, NSNumber *> *keys = [@{@" ":@44, @"\t":@43, @"\r":@40,
            UIKeyInputLeftArrow:@80, UIKeyInputRightArrow:@79,
            UIKeyInputUpArrow:@82, UIKeyInputDownArrow:@81} mutableCopy];
        NSString *letters = @"abcdefghijklmnopqrstuvwxyz";
        for (NSUInteger i = 0; i < letters.length; i++) keys[[letters substringWithRange:NSMakeRange(i, 1)]] = @(4 + i);
        NSMutableArray *commands = [NSMutableArray array];
        for (NSString *input in keys) {
            for (unsigned mask = 0; mask < 8; mask++) {
                UIKeyModifierFlags flags = UIKeyModifierCommand;
                if (mask & 1) flags |= UIKeyModifierShift;
                if (mask & 2) flags |= UIKeyModifierAlternate;
                if (mask & 4) flags |= UIKeyModifierControl;
                UIKeyCommand *command = [UIKeyCommand commandWithTitle:@"" image:nil action:@selector(forwardShortcut:)
                    input:input modifierFlags:flags propertyList:keys[input]];
                if (@available(tvOS 15.0, *)) command.wantsPriorityOverSystemBehavior = YES;
                [commands addObject:command];
            }
        }
        _shortcuts = commands;
    }
    return _shortcuts;
}
- (void)forwardShortcut:(UIKeyCommand *)command {
    if (!_connected || _leaving) return;
    [SofaInput.shared sendShortcutUsage:[command.propertyList unsignedIntegerValue] modifiers:command.modifierFlags];
}
- (void)viewDidLoad {
    // Listen before launch/resume: the host's prep helper connects during startup.
    [SofaInput.shared prepareCursorForHost:self.streamConfig.host
                                videoSize:CGSizeMake(self.streamConfig.width, self.streamConfig.height)];
    [super viewDidLoad];
    // Raw keyboard input owns normal presses; key commands recover consumed shortcuts.
    self.controllerUserInteractionEnabled = NO;
    // Consume ambiguous UIKit Menu events. Only the physical controller callback
    // may disconnect; a keyboard Escape can never select that path.
    for (UIGestureRecognizer *gesture in self.view.gestureRecognizers.copy) {
        if ([gesture.allowedPressTypes containsObject:@(UIPressTypeMenu)])
            [self.view removeGestureRecognizer:gesture];
    }
    UITapGestureRecognizer *menu = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                        action:@selector(menuPressed:)];
    menu.allowedPressTypes = @[@(UIPressTypeMenu)];
    [self.view addGestureRecognizer:menu];
    _remotes = [NSMutableSet set];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(installRemoteHandlers)
                                              name:GCControllerDidConnectNotification object:nil];
    [self installRemoteHandlers];
}
- (void)installRemoteHandlers {
    if (_leaving) return;
    __weak SofaStreamController *weakSelf = self;
    for (GCController *controller in GCController.controllers) {
        GCMicroGamepad *remote = controller.microGamepad;
        if (!remote || [_remotes containsObject:controller]) continue;
        [_remotes addObject:controller];
        controller.handlerQueue = dispatch_get_main_queue();
        remote.buttonMenu.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
            if (pressed) [weakSelf physicalRemoteExit];
        };
        remote.buttonX.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
            if (pressed) [weakSelf physicalRemoteExit];
        };
        NSLog(@"Sofa physical remote registered: %@ (%@)", controller.vendorName, controller.productCategory);
    }
}
- (void)removeRemoteHandlers {
    [NSNotificationCenter.defaultCenter removeObserver:self name:GCControllerDidConnectNotification object:nil];
    for (GCController *controller in _remotes) {
        controller.microGamepad.buttonMenu.pressedChangedHandler = nil;
        controller.microGamepad.buttonX.pressedChangedHandler = nil;
    }
    [_remotes removeAllObjects];
}
- (void)physicalRemoteExit {
    if (_leaving || self.navigationController.topViewController != self) return;
    _leaving = YES;
    NSLog(@"Sofa physical remote: disconnect");
    [self returnToMainFrame];
}
- (void)menuPressed:(id)sender {
    // Let the physical controller callback run first if UIKit also delivered its
    // Menu event. Otherwise this is Escape, even when tvOS supplies no UIKey.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (self->_leaving || !self->_connected || self.navigationController.topViewController != self) return;
        [SofaInput.shared sendEscapeTap];
    });
}
- (void)controllerPlayPauseButtonPressed:(id)sender {
    [self physicalRemoteExit];
}
- (void)controllerPauseButtonDoublePressed:(id)sender {
    // The upstream double-Menu action must never disconnect on double-Escape.
}
- (StreamView *)streamViewIn:(UIView *)view {
    if ([view isKindOfClass:StreamView.class]) return (StreamView *)view;
    for (UIView *child in view.subviews) {
        StreamView *stream = [self streamViewIn:child];
        if (stream) return stream;
    }
    return nil;
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_dictation) return;
    StreamView *stream = [self streamViewIn:self.view];
    BOOL focused = [stream becomeFirstResponder];
    NSLog(@"Sofa stream: keyboardResponder=%d UIKitInput=%d", focused, self.controllerUserInteractionEnabled);
}
- (void)connectionStarted {
    [super connectionStarted];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.parentViewController) return;
        self->_connected = YES;
        SofaInput.shared.streaming = YES;
        [SofaInput.shared logDiagnostics];
        self->_inputTimer = [NSTimer timerWithTimeInterval:5 repeats:YES block:^(NSTimer *timer) {
            [SofaInput.shared logDiagnostics];
            NSLog(@"Sofa run loop: mode=%@ pendingVideo=%d", NSRunLoop.currentRunLoop.currentMode, LiGetPendingVideoFrames());
        }];
        [NSRunLoop.mainRunLoop addTimer:self->_inputTimer forMode:NSRunLoopCommonModes];
        __weak SofaStreamController *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            SofaStreamController *self = weakSelf;
            if (!self || !self->_connected || self->_leaving) return;
            self->_dictation = [SofaDictation new];
            [self->_dictation startIn:self streamView:[self streamViewIn:self.view]];
        });
        self->_previewTimer = [NSTimer scheduledTimerWithTimeInterval:15 repeats:YES block:^(NSTimer *timer) {
            [weakSelf capturePreview];
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [weakSelf capturePreview];
        });
    });
}
- (AVSampleBufferDisplayLayer *)videoLayer:(CALayer *)layer {
    if ([layer isKindOfClass:AVSampleBufferDisplayLayer.class]) return (AVSampleBufferDisplayLayer *)layer;
    for (CALayer *child in layer.sublayers) {
        AVSampleBufferDisplayLayer *found = [self videoLayer:child];
        if (found) return found;
    }
    return nil;
}
- (void)capturePreview {
    if (!_connected || !self.previewID.length) return;
    if (@available(tvOS 17.4, *)) {
        AVSampleBufferDisplayLayer *layer = [self videoLayer:[self streamViewIn:self.view].layer];
        CVPixelBufferRef buffer = [layer.sampleBufferRenderer copyDisplayedPixelBuffer];
        if (!buffer) return;
        CIImage *frame = [CIImage imageWithCVPixelBuffer:buffer];
        CVPixelBufferRelease(buffer);
        NSURL *destination = SofaPreviewURL(self.previewID);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            static CIContext *context;
            static dispatch_once_t once;
            dispatch_once(&once, ^{ context = [CIContext contextWithOptions:@{kCIContextCacheIntermediates:@NO}]; });
            CIImage *small = [frame imageByApplyingTransform:CGAffineTransformMakeScale(720 / frame.extent.size.width,
                                                                                      720 / frame.extent.size.width)];
            CGImageRef image = [context createCGImage:small fromRect:small.extent];
            if (image) {
                NSData *jpeg = UIImageJPEGRepresentation([UIImage imageWithCGImage:image], 0.8);
                [jpeg writeToURL:destination atomically:YES];
                NSURL *sharedPreview = SofaShelfPreview(self.previewID);
                if (sharedPreview && [jpeg writeToURL:sharedPreview atomically:YES]) [TVTopShelfContentProvider topShelfContentDidChange];
                CGImageRelease(image);
            }
        });
    }
}
- (void)returnToMainFrame {
    [_dictation stop]; _dictation = nil;
    [super returnToMainFrame];
}
- (void)willMoveToParentViewController:(UIViewController *)parent {
    if (!parent) {
        _leaving = YES;
        [_dictation stop]; _dictation = nil;
        [self removeRemoteHandlers];
        [self capturePreview];
        _connected = NO;
        [_previewTimer invalidate];
        _previewTimer = nil;
        [_inputTimer invalidate];
        _inputTimer = nil;
        SofaInput.shared.streaming = NO;
    }
    [super willMoveToParentViewController:parent];
}
- (void)connectionTerminated:(int)errorCode {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_dictation stop]; self->_dictation = nil;
        SofaInput.shared.streaming = NO;
    });
    [super connectionTerminated:errorCode];
}
@end
