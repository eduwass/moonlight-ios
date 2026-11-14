#import "SofaInput.h"
#import "SofaInputMath.h"
#import "SofaCursorChannel.h"
#import <AVFoundation/AVFoundation.h>
#import "KeyboardSupport.h"
#import <GameController/GameController.h>
#import <objc/message.h>
#import <dlfcn.h>
#include <Limelight.h>

typedef CFTypeRef SofaHIDEvent;
static uint32_t (*eventType)(SofaHIDEvent);
static double (*eventFloat)(SofaHIDEvent, uint32_t);
static CFIndex (*eventInteger)(SofaHIDEvent, uint32_t);
static CFArrayRef (*eventChildren)(SofaHIDEvent);
static const int buttons[] = {BUTTON_LEFT, BUTTON_RIGHT, BUTTON_MIDDLE, BUTTON_X1, BUTTON_X2};

@implementation SofaInput {
    UIImageView *_cursor;
    SofaCursorChannel *_cursorChannel;
    BOOL _localCursor;
    CGSize _videoSize, _cursorSize;
    CGPoint _pointer, _hotspot;
    uint32_t _rawButtons, _sentButtons, _blockedButtons;
    double _dx, _dy, _sx, _sy;
    BOOL _started;
    __weak UIControl *_pressedControl;
    __weak UIControl *_hoveredControl;
    NSUInteger _pointerEvents, _sentMoves, _keyEvents, _sentKeyEvents;
    SofaKeys _keys;
    NSTimeInterval _lastKeyDown[256];
    int _lastSendResult;
    NSTimeInterval _lastEscapeEvent;
    NSMutableString *_keyTrace;
}
+ (instancetype)shared {
    static SofaInput *input;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ input = [SofaInput new]; });
    return input;
}
- (instancetype)init {
    if ((self = [super init])) {
        for (NSString *name in @[GCKeyboardDidConnectNotification, GCKeyboardDidDisconnectNotification,
                                GCMouseDidConnectNotification, GCMouseDidDisconnectNotification]) {
            [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(devicesChanged:)
                                                      name:name object:nil];
        }
    }
    return self;
}
- (void)devicesChanged:(NSNotification *)notification {
    if ([notification.name isEqual:GCKeyboardDidDisconnectNotification]) {
        _keyboardConfirmed = NO;
        _lastMouseEvent = 0;
        [self releaseButtons];
        memset(&_keys, 0, sizeof(_keys));
    }
    if ([notification.name isEqual:GCMouseDidDisconnectNotification]) {
        _lastMouseEvent = 0;
        [self releaseButtons];
    }
    GCKeyboard *keyboard = GCKeyboard.coalescedKeyboard;
    keyboard.handlerQueue = dispatch_get_main_queue();
    __weak SofaInput *weakSelf = self;
    keyboard.keyboardInput.keyChangedHandler = ^(GCKeyboardInput *input, GCControllerButtonInput *button,
                                                 GCKeyCode code, BOOL pressed) {
        SofaInput *self = weakSelf;
        if (self && self->_keyTrace && code == GCKeyCodeF4)
            [self recordKeyTrace:[NSString stringWithFormat:@"GC F4 down=%d", pressed]];
        if (self.streaming && code == GCKeyCodeSpacebar)
            NSLog(@"Sofa Space GC: down=%d modifiers=%u", pressed, SofaKeyModifiers(&self->_keys));
        if (!self || !self->_started || (self.streaming && self.available)) return;
        [self keyboardCode:code pressed:pressed];
    };
    // Run after upstream's device-connect observer so it cannot reinstall duplicate handlers.
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf takeMouseInput]; });
}
- (void)keyboardCode:(GCKeyCode)code pressed:(BOOL)pressed {
    _keyboardConfirmed = YES;
    _keyEvents++;
    if (code >= 0xE0 && code <= 0xE7)
        NSLog(@"Sofa modifier: HID=%02lx pressed=%d", (unsigned long)code, pressed);
    if (code == GCKeyCodeEscape) {
        _lastEscapeEvent = NSProcessInfo.processInfo.systemUptime;
        NSLog(@"Sofa Escape: pressed=%d", pressed);
    }
    int transition = SofaKeyTransition(&_keys, (unsigned)code, pressed, self.streaming);
    if (SofaConsumeLauncherF4(&_keys, (unsigned)code, transition)) {
        if (transition > 0)
            [self sendShortcutUsage:UIKeyboardHIDUsageKeyboardSpacebar modifiers:UIKeyModifierCommand];
        return;
    }
    if (self.streaming && (code == GCKeyCodeSpacebar || (code >= 0xE0 && code <= 0xE7)))
        NSLog(@"Sofa chord: HID=%02lx down=%d transition=%d modifiers=%u", (unsigned long)code,
              pressed, transition, SofaKeyModifiers(&_keys));
    if (transition) {
        if (transition > 0) _lastKeyDown[code] = NSProcessInfo.processInfo.systemUptime;
        unsigned modifiers = SofaKeyModifiers(&_keys);
        UIKeyModifierFlags flags = 0;
        if (modifiers & SofaControl) flags |= UIKeyModifierControl;
        if (modifiers & SofaShift) flags |= UIKeyModifierShift;
        if (modifiers & SofaAlt) flags |= UIKeyModifierAlternate;
        if (modifiers & SofaMeta) flags |= UIKeyModifierCommand;
        if ([KeyboardSupport sendKeyCode:(UIKeyboardHIDUsage)code modifiers:flags down:transition > 0])
            _sentKeyEvents++;
    }
    if (!self.streaming && pressed && code == GCKeyCodeReturnOrEnter && self.activateFocusedControl)
        self.activateFocusedControl();
}
- (BOOL)escapeSuppressesNavigation {
    BOOL held = _keys.held[GCKeyCodeEscape] ||
        [GCKeyboard.coalescedKeyboard.keyboardInput buttonForKeyCode:GCKeyCodeEscape].pressed;
    return SofaEscapeSuppressesNavigation(held, _lastEscapeEvent, NSProcessInfo.processInfo.systemUptime);
}
- (void)sendShortcutUsage:(UIKeyboardHIDUsage)usage modifiers:(UIKeyModifierFlags)modifiers {
    if (!_started || !_streaming || usage >= 256) return;
    // Raw delivery precedes UIKit. Do not replay a chord already forwarded there.
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (_keys.sent[usage] || (_lastKeyDown[usage] > 0 && now - _lastKeyDown[usage] < 0.1)) return;
    NSLog(@"Sofa shortcut fallback: HID=%02lx modifiers=%lu", (unsigned long)usage, (unsigned long)modifiers);
    UIKeyModifierFlags flags[] = {UIKeyModifierControl, UIKeyModifierShift, UIKeyModifierAlternate, UIKeyModifierCommand};
    unsigned added = 0, held = SofaKeyModifiers(&_keys);
    for (unsigned i = 0; i < 4; i++) {
        if ((modifiers & flags[i]) && !(held & (1u << i))) {
            [self keyboardCode:(GCKeyCode)(0xE0 + i) pressed:YES];
            added |= 1u << i;
        }
    }
    [self keyboardCode:(GCKeyCode)usage pressed:YES];
    [self keyboardCode:(GCKeyCode)usage pressed:NO];
    for (unsigned i = 0; i < 4; i++)
        if (added & (1u << i)) [self keyboardCode:(GCKeyCode)(0xE0 + i) pressed:NO];
}
- (void)sendEscapeTap {
    if (!_started || !_streaming || self.escapeSuppressesNavigation) return;
    // The UIKit Menu fallback is a complete key tap, not another observed
    // physical Escape. Do not debounce successive taps from a double press.
    if ([KeyboardSupport sendKeyCode:UIKeyboardHIDUsageKeyboardEscape modifiers:0 down:YES]) _sentKeyEvents++;
    if ([KeyboardSupport sendKeyCode:UIKeyboardHIDUsageKeyboardEscape modifiers:0 down:NO]) _sentKeyEvents++;
    NSLog(@"Sofa keyboard Menu: forwarded Escape");
}
- (void)takeMouseInput {
    if (!_streaming || !_available) return;
    for (GCMouse *mouse in GCMouse.mice) {
        GCMouseInput *input = mouse.mouseInput;
        input.mouseMovedHandler = nil;
        input.leftButton.pressedChangedHandler = nil;
        input.middleButton.pressedChangedHandler = nil;
        input.rightButton.pressedChangedHandler = nil;
        for (GCControllerButtonInput *button in input.auxiliaryButtons) button.pressedChangedHandler = nil;
        input.scroll.xAxis.valueChangedHandler = nil;
        input.scroll.yAxis.valueChangedHandler = nil;
    }
}
- (void)releaseButtons {
    for (unsigned code = 0; code < 256; code++) {
        if (_keys.sent[code] && !(code == GCKeyCodeF4 && _keys.launcherF4))
            [KeyboardSupport sendKeyCode:(UIKeyboardHIDUsage)code modifiers:0 down:NO];
    }
    SofaResetKeys(&_keys);
    memset(_lastKeyDown, 0, sizeof(_lastKeyDown));
    for (unsigned i = 0; i < 5; i++) {
        if (_sentButtons & (1u << i)) LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, buttons[i]);
    }
    _sentButtons = 0;
    _blockedButtons = _rawButtons;
    _pressedControl = nil;
    _dx = _dy = _sx = _sy = 0;
}
- (CGRect)videoRect {
    CGRect bounds = UIApplication.sharedApplication.keyWindow.bounds;
    return _videoSize.width > 0 && _videoSize.height > 0 ? AVMakeRectWithAspectRatioInsideRect(_videoSize, bounds) : bounds;
}
- (void)drawLocalCursor {
    _cursor.frame = (CGRect){CGPointMake(_pointer.x - _hotspot.x, _pointer.y - _hotspot.y), _cursorSize};
    _cursor.hidden = !_started || (_streaming && !_localCursor);
    [_cursor.superview bringSubviewToFront:_cursor];
}
- (void)sendAbsolutePointer {
    CGRect video = [self videoRect];
    if (video.size.width < 1 || video.size.height < 1) return;
    _lastSendResult = LiSendMousePositionEvent((short)(_pointer.x - video.origin.x),
        (short)(_pointer.y - video.origin.y), (short)video.size.width, (short)video.size.height);
}
- (void)prepareCursorForHost:(NSString *)host videoSize:(CGSize)size {
    [_cursorChannel stop];
    _videoSize = size;
    _cursorChannel = [SofaCursorChannel new];
    __weak SofaInput *weakSelf = self;
    _cursorChannel.changed = ^(UIImage *image, CGSize size, CGPoint hotspot, BOOL connected) {
        SofaInput *self = weakSelf;
        if (!self) return;
        BOOL becameLocal = connected && !self->_localCursor;
        self->_localCursor = connected;
        if (image) {
            self->_cursor.image = image;
            self->_cursorSize = CGSizeMake(size.width * 2, size.height * 2);
            self->_hotspot = CGPointMake(hotspot.x * 2, hotspot.y * 2);
        } else {
            self->_cursor.image = [UIImage systemImageNamed:@"cursorarrow"];
            self->_cursorSize = CGSizeMake(28,36); self->_hotspot = CGPointZero;
        }
        if (becameLocal) {
            CGRect video = [self videoRect];
            self->_pointer = CGPointMake(CGRectGetMidX(video), CGRectGetMidY(video));
            if (self.streaming) [self sendAbsolutePointer];
        }
        [self drawLocalCursor];
    };
    [_cursorChannel startForHost:host];
}
- (void)setStreaming:(BOOL)streaming {
    if (_streaming == streaming) {
        if (!streaming) { [_cursorChannel stop]; _cursorChannel = nil; }
        return;
    }
    [self releaseButtons];
    _streaming = streaming;
    if (streaming && [NSUserDefaults.standardUserDefaults boolForKey:@"keyTrace"]) {
        _keyTrace = [NSMutableString new];
        [self recordKeyTrace:@"stream begin"];
    } else {
        _keyTrace = nil;
    }
    [self takeMouseInput];
    if (!streaming) {
        [_cursorChannel stop]; _cursorChannel = nil;
        _localCursor = NO;
        _cursor.image = [UIImage systemImageNamed:@"cursorarrow"];
        _cursor.frame = (CGRect){_pointer, CGSizeMake(28,36)};
    } else if (_localCursor) {
        [self sendAbsolutePointer];
    }
    _cursor.hidden = (streaming && !_localCursor) || !_started;
}
- (void)start {
    _started = YES;
    [self devicesChanged:nil];
    GCKeyboardInput *keyboard = GCKeyboard.coalescedKeyboard.keyboardInput;
    for (unsigned code = 0; code < 256; code++)
        _keys.held[code] = [keyboard buttonForKeyCode:(GCKeyCode)code].pressed;
    SofaResetKeys(&_keys);
    if (!_available) {
        // Personal sideload only: tvOS does not deliver public GCMouse events on this device.
        // Resolve everything dynamically so an OS change leaves remote/keyboard navigation usable.
        static void *library;
        if (!library) library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        eventType = dlsym(library, "IOHIDEventGetType");
        eventFloat = dlsym(library, "IOHIDEventGetFloatValue");
        eventInteger = dlsym(library, "IOHIDEventGetIntegerValue");
        eventChildren = dlsym(library, "IOHIDEventGetChildren");
        SEL hook = NSSelectorFromString(@"_setHIDEventObserver:onQueue:");
        if (eventType && eventFloat && eventInteger && eventChildren &&
            [UIApplication.sharedApplication respondsToSelector:hook]) {
            __weak SofaInput *weakSelf = self;
            void (^observer)(SofaHIDEvent) = ^(SofaHIDEvent event) { [weakSelf consume:event depth:0]; };
            ((void (*)(id, SEL, id, dispatch_queue_t))objc_msgSend)(UIApplication.sharedApplication,
                hook, observer, dispatch_get_main_queue());
            _available = YES;
        }
    }
    UIWindow *window = UIApplication.sharedApplication.keyWindow;
    if (!_cursor) {
        _cursor = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"cursorarrow"]];
        _cursor.frame = CGRectMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds), 28, 36);
        _cursor.tintColor = UIColor.whiteColor;
        _cursor.layer.shadowColor = UIColor.blackColor.CGColor;
        _cursor.layer.shadowOpacity = 0.8;
        _cursor.layer.shadowRadius = 3;
        _cursor.layer.shadowOffset = CGSizeMake(1, 2);
        _cursor.userInteractionEnabled = NO;
        _cursor.accessibilityElementsHidden = YES;
    }
    [window addSubview:_cursor];
    _cursor.hidden = (_streaming && !_localCursor) || !_available;
}
- (void)stop {
    // UIKit can still have observer callbacks queued when the app resigns active.
    // Clearing the private observer then makes UIEventFetcher invoke a nil block.
    // Keep one observer for the process lifetime and gate delivery in consume:.
    _started = NO;
    [self releaseButtons];
    _lastMouseEvent = 0;
    [_cursorChannel stop]; _cursorChannel = nil;
    _cursor.hidden = YES;
}
- (void)logDiagnostics {
    NSLog(@"Sofa input: active=%d streaming=%d hook=%d publicMice=%lu pointers=%lu moves=%lu keys=%lu sentKeys=%lu sendResult=%d",
          _started, _streaming, _available, (unsigned long)GCMouse.mice.count,
          (unsigned long)_pointerEvents, (unsigned long)_sentMoves, (unsigned long)_keyEvents,
          (unsigned long)_sentKeyEvents, _lastSendResult);
}
- (void)recordKeyTrace:(NSString *)message {
    if (!_keyTrace || _keyTrace.length > 20000) return;
    [_keyTrace appendFormat:@"%.3f %@\n", NSProcessInfo.processInfo.systemUptime, message];
    NSString *path = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject
        stringByAppendingPathComponent:@"sofa-special-key-trace.log"];
    NSError *error;
    if (![_keyTrace writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        NSLog(@"Sofa key trace failed: %@", error);
        _keyTrace = nil;
    }
}
- (void)consume:(SofaHIDEvent)event depth:(unsigned)depth {
    if (!event || depth > 8 || !_started) return;
    uint32_t type = eventType(event), base = type << 16;
    if (type == 17) {
        _pointerEvents++;
        double x = eventFloat(event, base), y = eventFloat(event, base + 1);
        uint32_t raw = (uint32_t)eventInteger(event, base + 3);
        if ((isfinite(x) && x != 0) || (isfinite(y) && y != 0) || raw != _rawButtons)
            _lastMouseEvent = NSDate.timeIntervalSinceReferenceDate;
        uint32_t previous = _rawButtons;
        _rawButtons = raw;
        uint32_t mask = SofaButtons(raw, &_blockedButtons);
        if (_streaming) {
            // tvOS advertises GCMouse even when its callbacks deliver no events.
            // takeMouseInput disables that path; raw input owns the stream.
            if (_localCursor) {
                CGRect video = [self videoRect];
                _pointer.x = video.origin.x + SofaBound(_pointer.x - video.origin.x, x, video.size.width - 1);
                _pointer.y = video.origin.y + SofaBound(_pointer.y - video.origin.y, y, video.size.height - 1);
                [self drawLocalCursor];
                // Position precedes button events, including clicks without movement.
                [self sendAbsolutePointer]; _sentMoves++;
            } else {
                short dx = SofaTakeDelta(&_dx, x), dy = SofaTakeDelta(&_dy, y);
                if (dx || dy) { _lastSendResult = LiSendMouseMoveEvent(dx, dy); _sentMoves++; }
            }
            for (unsigned i = 0; i < 5; i++) {
                if ((mask ^ _sentButtons) & (1u << i))
                    LiSendMouseButtonEvent(mask & (1u << i) ? BUTTON_ACTION_PRESS : BUTTON_ACTION_RELEASE, buttons[i]);
            }
            _sentButtons = mask;
        } else {
            UIWindow *window = UIApplication.sharedApplication.keyWindow;
            CGRect frame = _cursor.frame;
            frame.origin.x = SofaBound(frame.origin.x, x, window.bounds.size.width - 2);
            frame.origin.y = SofaBound(frame.origin.y, y, window.bounds.size.height - 2);
            _cursor.frame = frame;
            [window bringSubviewToFront:_cursor];
            UIView *hit = [window hitTest:frame.origin withEvent:nil];
            UIView *target = hit;
            while (target && ![target isKindOfClass:UIControl.class]) target = target.superview;
            UIControl *control = (UIControl *)target;
            if (control && control != _hoveredControl && control.canBecomeFocused) {
                UIFocusSystem *focus = [UIFocusSystem focusSystemForEnvironment:control];
                [focus requestFocusUpdateToEnvironment:control];
                [focus updateFocusIfNeeded];
            }
            _hoveredControl = control;
            if (!(previous & 1) && (mask & 1)) _pressedControl = control;
            if ((previous & 1) && !(raw & 1)) {
                if (control && control == _pressedControl && control.enabled)
                    [control sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
                _pressedControl = nil;
            }
        }
    } else if (type == 3) {
        // Raw input owns the entire chord during streaming: tvOS can deliver
        // Command to GCKeyboard but consume Space as a system shortcut.
        CFIndex page = eventInteger(event, base), usage = eventInteger(event, base + 1);
        if (_streaming && page != 7)
            [NSNotificationCenter.defaultCenter postNotificationName:@"SofaRemoteHID" object:nil userInfo:
                @{@"page":@(page), @"usage":@(usage), @"down":@(eventInteger(event, base + 2))}];
        if (_keyTrace && (page != 7 || usage == GCKeyCodeF4))
            [self recordKeyTrace:[NSString stringWithFormat:@"HID page=%lx usage=%lx down=%ld",
                (long)page, (long)usage, (long)eventInteger(event, base + 2)]];
        if (_streaming && page != 7)
            NSLog(@"Sofa special key: page=%lx usage=%lx down=%ld modifiers=%u", (long)page, (long)usage,
                  (long)eventInteger(event, base + 2), SofaKeyModifiers(&_keys));
        // System App Menu is ambiguous with Escape; never treat it as a launcher key.
        if (_streaming && SofaIsLauncherHIDUsage((unsigned)page, (unsigned)usage))
            [self keyboardCode:GCKeyCodeF4 pressed:eventInteger(event, base + 2) != 0];
        if (_streaming && page == 7 && usage >= 4 && usage < 256) {
            BOOL down = eventInteger(event, base + 2) != 0;
            if (usage == 44)
                NSLog(@"Sofa Space raw: down=%d modifiers=%u", down, SofaKeyModifiers(&_keys));
            [self keyboardCode:(GCKeyCode)usage pressed:down];
        }
    } else if (type == 6) {
        double x = eventFloat(event, base), y = eventFloat(event, base + 1);
        if ((isfinite(x) && x) || (isfinite(y) && y)) _lastMouseEvent = NSDate.timeIntervalSinceReferenceDate;
        if (_streaming) {
            short sx = SofaTakeDelta(&_sx, x * -120), sy = SofaTakeDelta(&_sy, y * -120);
            if (sx) LiSendHighResHScrollEvent(sx);
            if (sy) LiSendHighResScrollEvent(sy);
        }
    }
    CFArrayRef children = eventChildren(event);
    for (CFIndex i = 0; children && i < CFArrayGetCount(children); i++)
        [self consume:CFArrayGetValueAtIndex(children, i) depth:depth + 1];
}
@end
