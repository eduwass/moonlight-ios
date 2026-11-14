#import "SofaDictation.h"
#import "SofaInput.h"
#import "SofaMicTap.h"
#import "KeyboardSupport.h"
#import "RelativeTouchHandler.h"

@interface RelativeTouchHandler (SofaRemoteClick)
- (void)remoteButtonLongPressed:(id)sender;
@end
#import <objc/message.h>
#import <objc/runtime.h>
#import <Limelight.h>

@interface SofaDictation () <UITextFieldDelegate>
@property(nonatomic, weak) UIViewController *owner, *editor;
@property(nonatomic, strong) UIView *streamView;
@property(nonatomic, strong) RelativeTouchHandler *remotePointer;
@property(nonatomic) NSUInteger remoteMoves;
@property(nonatomic, strong) UITextField *field;
@property(nonatomic, strong) CALayer *cover, *originalParent;
@property(nonatomic) CGRect originalFrame;
@property(nonatomic) NSUInteger originalIndex, attempts;
@property(nonatomic, strong) NSTimer *discovery, *typingTimer;
@property(nonatomic, strong) NSMutableString *typingBuffer;
@property(nonatomic) NSUInteger typedOffset;
@property(nonatomic) BOOL running, pending;
@property(nonatomic, strong) id speechController;
@property(nonatomic, copy) NSString *phrase;
@property(nonatomic, copy) void (^sendPhrase)(NSString *);
@property(nonatomic, strong) NSMutableArray *events;
- (void)record:(NSString *)event;
- (void)speechStarted:(id)source;
- (void)recognized:(id)text source:(id)source;
- (void)speechFinished:(id)source;
@end
static __weak SofaDictation *activeDictation;

static BOOL SofaCanTypePhrase(NSString *text) {
    if (!text.length || text.length>65536) return NO;
    for (NSUInteger i=0;i<text.length;i++) {
        unichar c=[text characterAtIndex:i];
        // Do not turn spoken formatting into Enter/Tab, or fall back to Linux's
        // Ctrl+Shift+U sequence (which can trigger shortcuts and submit forms).
        if (c<32 || c>126 || ![KeyboardSupport translateKeyEvent:c withModifierFlags:0].keycode) return NO;
    }
    return YES;
}

// The device probe verified all three callbacks. Keep Apple's implementation intact.
static BOOL SofaObserveDictation(NSString *name, void (^callback)(id,id)) {
    Class cls=NSClassFromString(@"UIDictationController");
    SEL selector=NSSelectorFromString(name);
    Method method=class_getInstanceMethod(cls,selector);
    if (!method || method_getNumberOfArguments(method)!=3) return NO;
    char type[32]; method_getReturnType(method,type,sizeof(type));
    if (strcmp(type,"v")) return NO;
    method_getArgumentType(method,2,type,sizeof(type));
    if (strcmp(type,"@")) return NO;
    IMP original=method_getImplementation(method);
    IMP replacement=imp_implementationWithBlock(^(id receiver,id argument){
        // Observed callbacks run on main. Ignore an unexpected queue rather than
        // replaying a late phrase into a different stream after a disconnect.
        if (NSThread.isMainThread) callback(receiver,argument);
        ((void (*)(id,SEL,id))original)(receiver,selector,argument);
    });
    if (!class_addMethod(cls,selector,replacement,method_getTypeEncoding(method)))
        method_setImplementation(method,replacement);
    return YES;
}
static BOOL SofaInstallDictation(void) {
    static BOOL ready; static dispatch_once_t once;
    dispatch_once(&once, ^{
        BOOL begin=SofaObserveDictation(@"dictationConnectionWillStartRecording:",^(id source,id argument){
            [activeDictation speechStarted:source];
        });
        BOOL text=SofaObserveDictation(@"setLastRecognitionText:",^(id source,id argument){
            [activeDictation recognized:argument source:source];
        });
        BOOL finish=SofaObserveDictation(@"dictationConnectionDidFinish:",^(id source,id argument){
            [activeDictation speechFinished:source];
        });
#if DEBUG
        for (NSString *name in @[@"dictationConnectionDidEndRecording:", @"dictationConnectionDidCancelRecording:", @"dictationConnectionDidCancel:"])
            SofaObserveDictation(name,^(id source,id argument){ [activeDictation record:name]; });
#endif
        ready=begin && text && finish;
    });
    return ready;
}

@implementation SofaDictation {
    SofaMicTapState _micTap;
    BOOL _enterQueued;
}
- (void)record:(NSString *)event {
    if (!self.events) return;
    if (self.events.count==80) [self.events removeObjectAtIndex:0];
    [self.events addObject:@{@"event":event,@"time":@(NSDate.date.timeIntervalSince1970)}];
    NSString *path=[NSSearchPathForDirectoriesInDomains(NSCachesDirectory,NSUserDomainMask,YES).firstObject
        stringByAppendingPathComponent:@"sofa-dictation.json"];
    [[NSJSONSerialization dataWithJSONObject:self.events options:0 error:nil] writeToFile:path atomically:YES];
}
- (void)speechStarted:(id)source {
    if (!self.running) return;
    self.speechController=source; self.pending=YES; self.phrase=nil;
    _micTap.waiting=false; _micTap.held=true;
    [self record:@"speech started"];
}
- (void)recognized:(id)text source:(id)source {
    if (!self.pending || source!=self.speechController) return;
    self.phrase=nil;
    if ([text isKindOfClass:NSString.class] && [text length] &&
        [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding]<=65536)
        self.phrase=text;
}
- (void)speechFinished:(id)source {
    if (!self.running || !self.pending || source!=self.speechController) return;
    NSString *text=self.phrase;
    self.pending=NO; self.phrase=nil; self.speechController=nil;
    if (text.length && self.sendPhrase) self.sendPhrase(text);
    else [self record:@"speech finished without text"];
}
+ (void)runSelfCheck {
#if DEBUG
    NSCAssert(SofaCanTypePhrase(@"Hello from the sofa! It's 42, @home."),@"plain text and punctuation");
    NSCAssert(!SofaCanTypePhrase(@"hello\n") && !SofaCanTypePhrase(@"hello\t"),@"no Enter or Tab injection");
    NSCAssert(!SofaCanTypePhrase(@"café") && !SofaCanTypePhrase(@"🛋️"),@"no broken Unicode fallback");
    // Runnable in every Debug build; covers duplicate callbacks, repeated identical
    // utterances, wrong-controller callbacks, empty results and disconnects.
    SofaDictation *probe=[SofaDictation new]; probe.running=YES;
    NSObject *source=[NSObject new], *other=[NSObject new];
    NSMutableArray *sent=[NSMutableArray new];
    probe.sendPhrase=^(NSString *text){ [sent addObject:text]; };
    [probe recognized:@"typing" source:source]; [probe speechFinished:source];
    NSCAssert(sent.count==0,@"ordinary typing must not send a phrase");
    for (int i=0;i<2;i++) {
        [probe speechStarted:source];
        [probe recognized:@"partial" source:source];
        [probe recognized:@"hello 🛋️" source:source];
        [probe speechFinished:other];
        [probe speechFinished:source]; [probe speechFinished:source];
    }
    NSCAssert(sent.count==2 && [sent[0] isEqual:@"hello 🛋️"] && [sent[1] isEqual:sent[0]],@"one final phrase per utterance");
    [probe speechStarted:source]; [probe speechFinished:source];
    [probe speechStarted:source];
    [probe recognized:[@"x" stringByPaddingToLength:65537 withString:@"x" startingAtIndex:0] source:source];
    [probe speechFinished:source];
    [probe speechStarted:source]; [probe recognized:@"late" source:source];
    [probe stop]; [probe speechFinished:source];
    NSCAssert(sent.count==2,@"empty, oversized and disconnected results must not send");
    NSString *path=[NSSearchPathForDirectoriesInDomains(NSCachesDirectory,NSUserDomainMask,YES).firstObject
        stringByAppendingPathComponent:@"sofa-dictation-check.json"];
    [@"{\"passed\":true,\"version\":2}" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
#endif
}
- (void)startIn:(UIViewController *)owner streamView:(UIView *)streamView {
    if (self.running || !streamView || !SofaInput.shared.available) return;
    self.events=[NSMutableArray new];
    if (!SofaInstallDictation()) { [self record:@"dictation callbacks unavailable"]; return; }
    [self record:@"stream dictation starting"];
    self.owner=owner; self.streamView=streamView; self.running=YES;
    activeDictation=self;
    __weak SofaDictation *weakSelf=self;
    self.sendPhrase=^(NSString *text){
        SofaDictation *self=weakSelf;
        if (!self.running || !SofaInput.shared.streaming || !self.owner.parentViewController ||
            UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return;
        if (!SofaCanTypePhrase(text)) {
            [self record:@"phrase rejected: this test supports printable ASCII only"];
            CATextLayer *notice=[CATextLayer layer];
            notice.frame=CGRectMake(80,80,1300,65); notice.fontSize=26;
            notice.backgroundColor=UIColor.blackColor.CGColor; notice.foregroundColor=UIColor.whiteColor.CGColor;
            notice.contentsScale=UIScreen.mainScreen.scale;
            notice.string=@"Dictation test: accents, emoji and line breaks aren't supported yet.";
            [self.cover addSublayer:notice];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,4*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [notice removeFromSuperlayer]; });
            return;
        }
        if (!self.typingBuffer) self.typingBuffer=[NSMutableString new];
        [self.typingBuffer appendString:text];
        [self record:[NSString stringWithFormat:@"phrase queued as keys: characters=%lu",(unsigned long)text.length]];
        if (!self.typingTimer) {
            self.typingTimer=[NSTimer timerWithTimeInterval:0.008 repeats:YES block:^(NSTimer *timer){ [weakSelf typeNextCharacter]; }];
            [NSRunLoop.mainRunLoop addTimer:self.typingTimer forMode:NSRunLoopCommonModes];
        }
    };
    self.field=[[UITextField alloc] initWithFrame:CGRectMake(0,0,1,1)];
    self.field.textColor=UIColor.clearColor; self.field.backgroundColor=UIColor.clearColor;
    self.field.delegate=self;
    [owner.view addSubview:self.field];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(backgrounded:)
        name:UIApplicationDidEnterBackgroundNotification object:nil];
    for (NSString *name in @[@"SofaRemoteHID",UIApplicationWillResignActiveNotification,UIApplicationDidBecomeActiveNotification])
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(remoteEvent:) name:name object:nil];
    [self record:@"double mic tap -> Enter enabled"];
    BOOL accepted=[self.field becomeFirstResponder];
    [self record:[NSString stringWithFormat:@"native field accepted=%d",accepted]];
    [self startDiscovery];
}
- (void)typeNextCharacter {
    if (!self.running || !SofaInput.shared.streaming || !self.owner.parentViewController ||
        UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) {
        [self.typingTimer invalidate]; self.typingTimer=nil; self.typingBuffer=nil; self.typedOffset=0;
        return;
    }
    struct KeyEvent event=[KeyboardSupport translateKeyEvent:[self.typingBuffer characterAtIndex:self.typedOffset] withModifierFlags:0];
    // Same mapping and event flags as Moonlight's on-screen typing. Each tick
    // completes its key and modifier releases, so disconnect cannot leave Shift held.
    int result=0;
    if (event.modifier) result=LiSendKeyboardEvent(event.modifierKeycode,KEY_ACTION_DOWN,event.modifier);
    int down=LiSendKeyboardEvent2(event.keycode,KEY_ACTION_DOWN,event.modifier,SS_KBE_FLAG_NON_NORMALIZED);
    int up=LiSendKeyboardEvent2(event.keycode,KEY_ACTION_UP,event.modifier,SS_KBE_FLAG_NON_NORMALIZED);
    int modifierUp=event.modifier ? LiSendKeyboardEvent(event.modifierKeycode,KEY_ACTION_UP,event.modifier) : 0;
    self.typedOffset++;
    if (result || down || up || modifierUp || self.typedOffset==self.typingBuffer.length) {
        [self record:[NSString stringWithFormat:@"key text finished: characters=%lu result=%d",(unsigned long)self.typedOffset,result ?: down ?: up ?: modifierUp]];
        [self.typingTimer invalidate]; self.typingTimer=nil; self.typingBuffer=nil; self.typedOffset=0;
        BOOL sendEnter=_enterQueued && !result && !down && !up && !modifierUp;
        _enterQueued=NO;
        if (sendEnter) [self sendRemoteEnter];
    }
}
- (UIViewController *)findEditor:(UIViewController *)vc {
    if (!vc) return nil;
    if ([NSStringFromClass(vc.class) containsString:@"SystemInputViewController"]) return vc;
    UIViewController *match=[self findEditor:vc.presentedViewController];
    if (match) return match;
    for (UIViewController *child in vc.childViewControllers) {
        match=[self findEditor:child]; if (match) return match;
    }
    return nil;
}
- (void)startDiscovery {
    [self.discovery invalidate]; self.attempts=0;
    __weak SofaDictation *weakSelf=self;
    self.discovery=[NSTimer timerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *timer){ [weakSelf discover]; }];
    [NSRunLoop.mainRunLoop addTimer:self.discovery forMode:NSRunLoopCommonModes];
}
- (void)discover {
    if (!self.running) return;
    UIViewController *editor=[self findEditor:UIApplication.sharedApplication.delegate.window.rootViewController];
    if (!editor || !editor.view.window) {
        if (++self.attempts>=50) { [self record:@"native editor not found"]; [self stop]; }
        return;
    }
    self.editor=editor;
    // UIKit touches now belong to the native editor's window. Use that view for
    // coordinates, while retaining Moonlight's existing move/tap/drag/scroll logic.
    NSArray *existingGestures=editor.view.gestureRecognizers.copy;
    self.remotePointer=[[RelativeTouchHandler alloc] initWithView:editor.view];
    // We route Select explicitly below; don't let either the native keyboard or
    // a second gesture recognizer also consume that physical click.
    for (UIGestureRecognizer *gesture in editor.view.gestureRecognizers.copy)
        if (![existingGestures containsObject:gesture]) [editor.view removeGestureRecognizer:gesture];
    CALayer *video=self.streamView.layer;
    self.originalParent=video.superlayer; self.originalFrame=video.frame;
    self.originalIndex=[video.superlayer.sublayers indexOfObjectIdenticalTo:video];
    // ponytail: private sideload experiment; tvOS may change keyboard presentation.
    // Move the existing live layer, preserving its UIView and the native focus tree.
    // No video copies. Restore the original layer tree before dismissing the editor.
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    self.cover=[CALayer layer]; self.cover.frame=editor.view.bounds;
    self.cover.backgroundColor=UIColor.blackColor.CGColor; self.cover.zPosition=10000;
    [editor.view.layer addSublayer:self.cover];
    [self.cover addSublayer:video]; video.frame=self.cover.bounds;
    [CATransaction commit];
    [self.discovery invalidate]; self.discovery=nil;
    [self record:@"dictation armed; live stream covers native editor"];
}
- (void)restoreVideo {
    if (self.cover) {
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        CALayer *video=self.streamView.layer;
        [self.originalParent insertSublayer:video atIndex:(unsigned)MIN(self.originalIndex,self.originalParent.sublayers.count)];
        video.frame=self.originalFrame;
        [self.cover removeFromSuperlayer];
        [CATransaction commit];
    }
    self.cover=nil; self.originalParent=nil;
}
- (void)textFieldDidEndEditing:(UITextField *)textField {
    if (!self.running) return;
    // A native dismissal must always uncover the stream, even if no remote callback arrived.
    [self record:@"native editor dismissed; dictation stopped"];
    [self stop];
}
- (BOOL)routeRemotePointer:(UIEvent *)event {
    if (!self.cover || !self.remotePointer || !SofaInput.shared.streaming) return NO;
    if (event.type==UIEventTypeTouches) {
        NSSet<UITouch *> *touches=event.allTouches;
        if (!touches.count) return NO;
        for (UITouch *touch in touches) if (touch.type!=UITouchTypeIndirect) return NO;
        NSMutableSet *began=[NSMutableSet new], *moved=[NSMutableSet new], *ended=[NSMutableSet new], *cancelled=[NSMutableSet new];
        for (UITouch *touch in touches) {
            switch (touch.phase) {
                case UITouchPhaseBegan: [began addObject:touch]; break;
                case UITouchPhaseMoved: [moved addObject:touch]; break;
                case UITouchPhaseEnded: [ended addObject:touch]; break;
                case UITouchPhaseCancelled: [cancelled addObject:touch]; break;
                default: break;
            }
        }
        if (began.count) {
            self.remoteMoves=0;
            [self.remotePointer touchesBegan:began withEvent:event];
            [self record:@"remote trackpad began"];
        }
        if (moved.count) { self.remoteMoves++; [self.remotePointer touchesMoved:moved withEvent:event]; }
        if (ended.count) {
            [self.remotePointer touchesEnded:ended withEvent:event];
            [self record:[NSString stringWithFormat:@"remote trackpad ended: moves=%lu",(unsigned long)self.remoteMoves]];
        }
        if (cancelled.count) [self.remotePointer touchesCancelled:cancelled withEvent:event];
        return YES;
    }
    if (event.type==UIEventTypePresses) {
        NSSet<UIPress *> *presses=((UIPressesEvent *)event).allPresses;
        if (!presses.count) return NO;
        for (UIPress *press in presses) if (press.key || press.type!=UIPressTypeSelect) return NO;
        for (UIPress *press in presses) {
            if (press.phase==UIPressPhaseBegan) {
                [self.remotePointer remoteButtonLongPressed:nil];
                [self record:@"remote pointer button down"];
            } else if (press.phase==UIPressPhaseEnded || press.phase==UIPressPhaseCancelled) {
                [self.remotePointer touchesCancelled:[NSSet set] withEvent:nil];
                [self record:@"remote pointer button up"];
            }
        }
        return YES;
    }
    return NO;
}
- (void)sendRemoteEnter {
    if (!self.running || !self.cover || !SofaInput.shared.streaming ||
        UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return;
    if (self.typingTimer) { _enterQueued=YES; [self record:@"Enter queued after dictation text"]; return; }
    [SofaInput.shared sendShortcutUsage:UIKeyboardHIDUsageKeyboardReturnOrEnter modifiers:0];
    [self record:@"double mic tap: Enter sent"];
}
- (void)remoteEvent:(NSNotification *)notification {
    if ([notification.name isEqual:@"SofaRemoteHID"]) {
        NSDictionary *v=notification.userInfo;
        if (self.cover && [v[@"page"] integerValue]==12 && [v[@"usage"] integerValue]==4 &&
            SofaMicTap(&_micTap,[v[@"down"] boolValue],self.pending,NSProcessInfo.processInfo.systemUptime))
            [self sendRemoteEnter];
        [self record:[NSString stringWithFormat:@"remote HID page=%@ usage=%@ down=%@",v[@"page"],v[@"usage"],v[@"down"]]];
    } else {
        if ([notification.name isEqual:UIApplicationWillResignActiveNotification]) {
            _micTap=(SofaMicTapState){0}; _enterQueued=NO;
        }
        [self record:notification.name];
    }
}
- (void)backgrounded:(NSNotification *)notification { [self stop]; }
- (void)stop {
    [self.remotePointer touchesCancelled:[NSSet set] withEvent:nil]; self.remotePointer=nil;
    _micTap=(SofaMicTapState){0}; _enterQueued=NO;
    [self.typingTimer invalidate]; self.typingTimer=nil; self.typingBuffer=nil; self.typedOffset=0;
    self.running=NO; self.pending=NO; self.phrase=nil; self.speechController=nil;
    if (activeDictation==self) activeDictation=nil;
    [self.discovery invalidate]; self.discovery=nil;
    [self restoreVideo];
    UIViewController *editor=self.editor; self.editor=nil;
    self.field.delegate=nil;
    [self.field resignFirstResponder]; [self.field removeFromSuperview]; self.field=nil;
    if (editor.presentingViewController) [editor dismissViewControllerAnimated:NO completion:nil];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    self.streamView=nil; self.owner=nil; self.sendPhrase=nil;
}
- (void)dealloc { [self.typingTimer invalidate]; [self.discovery invalidate]; [NSNotificationCenter.defaultCenter removeObserver:self]; }
@end

@implementation SofaApplication
- (void)sendEvent:(UIEvent *)event {
    SofaDictation *dictation=activeDictation;
    if ([dictation routeRemotePointer:event]) return;
#if DEBUG
    if (dictation.running && event.type==UIEventTypePresses) {
        for (UIPress *press in ((UIPressesEvent *)event).allPresses) if (!press.key)
            [dictation record:[NSString stringWithFormat:@"remote UIKit type=%ld phase=%ld timestamp=%.3f",(long)press.type,(long)press.phase,press.timestamp]];
    }
#endif
    if (dictation.cover && SofaInput.shared.streaming && SofaInput.shared.available && event.type==UIEventTypePresses) {
        NSSet<UIPress *> *presses=((UIPressesEvent *)event).allPresses;
        // Device trace on tvOS 27.2: a quick mic tap arrives as private type 202,
        // whose default action dismisses the native editor. Keep this separate
        // from the raw microphone reports used to recognize double-taps.
        BOOL micTap=presses.count>0;
        for (UIPress *press in presses) if ((NSInteger)press.type!=202 || press.key) micTap=NO;
        if (micTap) { [dictation record:@"mic event intercepted; keeping native editor active"]; return; }
        BOOL hardware=presses.count>0;
        for (UIPress *press in presses) if (!press.key) hardware=NO;
        if (hardware) {
            // Raw HID already forwards the physical keys. Prevent Return/arrows from
            // editing or dismissing the hidden native editor. Recover consumed chords.
            for (UIPress *press in presses) if (press.phase==UIPressPhaseBegan)
                [SofaInput.shared sendShortcutUsage:press.key.keyCode modifiers:press.key.modifierFlags];
            return;
        }
    }
    [super sendEvent:event];
}
@end
