#import "MainFrameViewController.h"
#import "DataManager.h"
#import "HttpManager.h"
#import "ServerInfoResponse.h"
#import "SofaInput.h"
#import "SofaAppearance.h"
#import "SofaShelfStore.h"
#import "SofaStreamController.h"
#import <GameController/GameController.h>

// Small tvOS-only hooks into upstream's host discovery, pairing and launch flow.
@interface MainFrameViewController (SofaHooks)
- (void)retrieveSavedHosts;
- (void)updateHosts;
- (void)showHostSelectionView;
- (void)updateAppsForHost:(TemporaryHost *)host;
- (void)hideLoadingFrame:(void (^)(void))completion;
- (void)openTvSettings:(id)sender;
- (void)prepareToStreamApp:(TemporaryApp *)app;
- (TemporaryApp *)findRunningApp:(TemporaryHost *)host;
@end

@interface SofaHomeController : MainFrameViewController
@end
@implementation SofaHomeController {
    UIView *_home;
    UIScrollView *_tilesView;
    UILabel *_heading, *_subtitle, *_keyboardStatus, *_mouseStatus, *_hint;
    UIButton *_add, *_settings;
    NSMutableDictionary<NSString *, SofaTile *> *_tiles;
    NSMutableDictionary<NSString *, NSNumber *> *_latencies;
    NSMutableSet<NSString *> *_probing;
    NSArray<TemporaryHost *> *_hosts;
    TemporaryHost *_openingHost;
    TemporaryApp *_pendingDesktop;
    NSTimer *_statusTimer, *_probeTimer;
    BOOL _ready, _connecting, _returningFromStream;
}
- (UILabel *)label:(CGFloat)size weight:(UIFontWeight)weight {
    UILabel *label = [UILabel new];
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.textColor = UIColor.whiteColor;
    [_home addSubview:label];
    return label;
}
- (void)retrieveSavedHosts {
    // Deployment may import addresses without embedding a personal fleet or credentials in the app.
    NSURL *cache = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].lastObject;
    NSURL *source = [cache URLByAppendingPathComponent:@"sofa-hosts.plist"];
    NSArray *seeds = [NSArray arrayWithContentsOfURL:source];
    DataManager *database = [DataManager new];
    NSArray<TemporaryHost *> *existing = [database getHosts];
    for (id item in seeds) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        BOOL valid = YES;
        for (NSString *key in @[@"name", @"uuid", @"address"])
            valid &= [item[key] isKindOfClass:NSString.class] && [item[key] length] > 0 && [item[key] length] < 256;
        if (!valid) continue;
        TemporaryHost *host = [TemporaryHost new];
        for (TemporaryHost *saved in existing) if ([saved.uuid isEqual:item[@"uuid"]]) { host = saved; break; }
        host.name = item[@"name"]; host.uuid = item[@"uuid"]; host.address = item[@"address"];
        NSData *certificate = item[@"serverCert"];
        if ([certificate isKindOfClass:NSData.class]) {
            SecCertificateRef parsed = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificate);
            if (parsed) { host.serverCert = certificate; host.pairState = PairStatePaired; CFRelease(parsed); }
        }
        [database updateHost:host];
    }
    if (seeds) [NSFileManager.defaultManager removeItemAtURL:source error:nil];
    [super retrieveSavedHosts];
    _hosts = [database getHosts];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    _tiles = [NSMutableDictionary new]; _latencies = [NSMutableDictionary new]; _probing = [NSMutableSet new];
    _home = [SofaBackdrop new];
    _home.contentMode = UIViewContentModeRedraw;
    _home.backgroundColor = [UIColor colorWithRed:0.025 green:0.035 blue:0.055 alpha:1];
    [self.view addSubview:_home];
    _heading = [self label:58 weight:UIFontWeightBold]; _heading.text = @"Computers";
    _subtitle = [self label:25 weight:UIFontWeightRegular]; _subtitle.text = @"Your desktops, from the sofa.";
    _subtitle.textColor = [UIColor colorWithWhite:0.6 alpha:1];
    _keyboardStatus = [self label:21 weight:UIFontWeightMedium]; _keyboardStatus.textAlignment = NSTextAlignmentRight;
    _mouseStatus = [self label:21 weight:UIFontWeightMedium]; _mouseStatus.textAlignment = NSTextAlignmentRight;
    _tilesView = [UIScrollView new]; _tilesView.clipsToBounds = NO;
    [_home addSubview:_tilesView];
    _hint = [self label:21 weight:UIFontWeightRegular];
    _hint.text = @"Click or press Enter to connect  ·  Hold Select for computer options";
    _hint.textColor = [UIColor colorWithWhite:0.5 alpha:1];
    _add = [UIButton buttonWithType:UIButtonTypeSystem]; [_add setTitle:@"＋  Add computer" forState:UIControlStateNormal];
    _add.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightMedium];
    [_add addTarget:self action:@selector(addHostClicked) forControlEvents:UIControlEventPrimaryActionTriggered];
    [_home addSubview:_add];
    _settings = [UIButton buttonWithType:UIButtonTypeSystem]; [_settings setTitle:@"Settings" forState:UIControlStateNormal];
    _settings.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightMedium];
    [_settings addTarget:self action:@selector(openTvSettings:) forControlEvents:UIControlEventPrimaryActionTriggered];
    [_home addSubview:_settings];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(openPendingComputer) name:@"SofaOpenComputer" object:nil];
    _ready = YES;
    [self showHostSelectionView];
    [self updateHosts];
}
- (void)viewWillAppear:(BOOL)animated {
    if (_returningFromStream) { _returningFromStream = NO; [self showHostSelectionView]; }
    [super viewWillAppear:animated];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.navigationController setNavigationBarHidden:!_home.hidden animated:NO];
    __weak SofaHomeController *weakSelf = self;
    SofaInput.shared.activateFocusedControl = ^{
        SofaHomeController *self = weakSelf;
        if (!self || self->_home.hidden || self.presentedViewController) return;
        id focused = [UIFocusSystem focusSystemForEnvironment:self.view].focusedItem;
        if ([focused isKindOfClass:UIControl.class]) [(UIControl *)focused sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
    };
    [_statusTimer invalidate]; [_probeTimer invalidate];
    _statusTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) { [weakSelf refreshStatus]; }];
    _probeTimer = [NSTimer scheduledTimerWithTimeInterval:10 repeats:YES block:^(NSTimer *timer) { [weakSelf probeHosts]; }];
    [self refreshStatus]; [self probeHosts]; [self updateHosts];
    [self openPendingComputer];
#if DEBUG
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--sofa-screenshot"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            UIWindow *window = self.view.window;
            if (!window) return;
            UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:window.bounds.size];
            UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
                [window.layer renderInContext:context.CGContext];
            }];
            NSURL *cache = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].lastObject;
            [UIImagePNGRepresentation(image) writeToURL:[cache URLByAppendingPathComponent:@"sofa-home.png"] atomically:YES];
            NSMutableArray *status = [NSMutableArray new];
            for (TemporaryHost *host in self->_hosts) [status addObject:@{
                @"name":host.name, @"online":@(host.state == StateOnline),
                @"paired":@(host.pairState == PairStatePaired), @"hasCertificate":@(host.serverCert.length > 0)}];
            [[NSJSONSerialization dataWithJSONObject:status options:0 error:nil]
                writeToURL:[cache URLByAppendingPathComponent:@"sofa-status.json"] atomically:YES];
        });
    }
#endif
}
- (void)viewDidDisappear:(BOOL)animated {
    [_statusTimer invalidate]; [_probeTimer invalidate];
    SofaInput.shared.activateFocusedControl = nil;
    [super viewDidDisappear:animated];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _home.frame = self.view.bounds;
    CGFloat w = _home.bounds.size.width, h = _home.bounds.size.height, margin = MAX(60, w * 0.055);
    _heading.frame = CGRectMake(margin, 70, w * 0.6, 80);
    _heading.adjustsFontSizeToFitWidth = YES;
    _subtitle.frame = CGRectMake(margin, 157, w * 0.65, 40);
    _keyboardStatus.frame = CGRectMake(w * 0.64, 85, w * 0.36 - margin, 32);
    _mouseStatus.frame = CGRectMake(w * 0.64, 125, w * 0.36 - margin, 32);
    _tilesView.frame = CGRectMake(margin, 280, w - margin * 2, MAX(220, h - 440));
    CGFloat tileWidth = MIN(560, (w - margin * 2 - 90) / 3), x = 0;
    for (TemporaryHost *host in [_hosts sortedArrayUsingSelector:@selector(compareName:)]) {
        SofaTile *tile = _tiles[host.uuid];
        tile.bounds = CGRectMake(0, 0, tileWidth, tileWidth * 9 / 16 + 114);
        tile.center = CGPointMake(x + tileWidth / 2, tile.bounds.size.height / 2);
        x += tileWidth + 45;
    }
    _tilesView.contentSize = CGSizeMake(MAX(_tilesView.bounds.size.width, x - 45), _tilesView.bounds.size.height);
    _hint.frame = CGRectMake(margin, h - 110, w - 2 * margin - 550, 45);
    _add.frame = CGRectMake(w - margin - 520, h - 115, 300, 55);
    _settings.frame = CGRectMake(w - margin - 195, h - 115, 195, 55);
}
- (void)showHostSelectionView {
    _connecting = NO; _openingHost = nil; _pendingDesktop = nil;
    [super showHostSelectionView];
    _home.hidden = NO;
    [self.view bringSubviewToFront:_home];
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    [self setNeedsFocusUpdate];
}
- (void)updateAllHosts:(NSArray *)hosts {
    NSArray *snapshot = [hosts copy];
    dispatch_async(dispatch_get_main_queue(), ^{ self->_hosts = snapshot; [self updateHosts]; });
    [super updateAllHosts:hosts];
}
- (void)updateHosts {
    if (!_ready) return;
    NSMutableSet *current = [NSMutableSet new];
    for (TemporaryHost *host in _hosts) {
        [current addObject:host.uuid];
        SofaTile *tile = _tiles[host.uuid];
        if (!tile) {
            tile = [SofaTile new];
            [tile addTarget:self action:@selector(openTile:) forControlEvents:UIControlEventPrimaryActionTriggered];
            UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(tileOptions:)];
            hold.allowedPressTypes = @[@(UIPressTypeSelect)];
            [tile addGestureRecognizer:hold];
            _tiles[host.uuid] = tile;
            [_tilesView addSubview:tile];
        }
        tile.host = host; tile.nameLabel.text = host.name;
        NSNumber *latency = _latencies[host.uuid];
        NSString *state = host.state == StateOnline ? (host.pairState == PairStatePaired ? @"Ready" : @"Pair to connect") :
                          host.state == StateOffline ? @"Offline" : @"Finding computer…";
        tile.statusLabel.text = latency && host.state == StateOnline ?
            [NSString stringWithFormat:@"●  %@   ·   %.0f ms response", state, latency.doubleValue] : [@"●  " stringByAppendingString:state];
        tile.statusLabel.textColor = host.state == StateOnline ? UIColor.systemMintColor : UIColor.secondaryLabelColor;
        NSURL *preview = SofaPreviewURL(host.uuid);
        tile.preview.image = [UIImage imageWithContentsOfFile:preview.path];
        NSDate *date;
        [preview getResourceValue:&date forKey:NSURLContentModificationDateKey error:nil];
        tile.previewLabel.text = tile.preview.image ? [@"Last seen " stringByAppendingString:
            [NSDateFormatter localizedStringFromDate:date ?: NSDate.date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle]] :
            @"No preview yet · connect to capture";
        tile.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", host.name, tile.statusLabel.text];
    }
    for (NSString *key in [_tiles.allKeys copy]) if (![current containsObject:key]) { [_tiles[key] removeFromSuperview]; [_tiles removeObjectForKey:key]; }
    NSMutableArray *shelfHosts = [NSMutableArray new];
    for (TemporaryHost *host in _hosts) {
        [shelfHosts addObject:@{@"id":host.uuid, @"name":host.name}];
        NSURL *source = SofaPreviewURL(host.uuid), *destination = SofaShelfPreview(host.uuid);
        NSDate *sourceDate = nil, *destinationDate = nil;
        [source getResourceValue:&sourceDate forKey:NSURLContentModificationDateKey error:nil];
        [destination getResourceValue:&destinationDate forKey:NSURLContentModificationDateKey error:nil];
        if (destination && sourceDate && (!destinationDate || [sourceDate compare:destinationDate] == NSOrderedDescending)) {
            [[NSData dataWithContentsOfURL:source] writeToURL:destination atomically:YES];
            [NSFileManager.defaultManager setAttributes:@{NSFileModificationDate:sourceDate} ofItemAtPath:destination.path error:nil];
        }
    }
    NSURL *index = [SofaShelfDirectory() URLByAppendingPathComponent:@"hosts.plist"];
    if (index && ![[NSArray arrayWithContentsOfURL:index] isEqual:shelfHosts]) {
        [shelfHosts writeToURL:index atomically:YES];
        [TVTopShelfContentProvider topShelfContentDidChange];
    }
    [self openPendingComputer];
    _subtitle.text = _hosts.count ? @"Your desktops, from the sofa." : @"Looking for your computers on the network…";
    [self.view setNeedsLayout];
}
- (void)refreshStatus {
    GCKeyboard *keyboard = GCKeyboard.coalescedKeyboard;
    NSString *name = keyboard.vendorName.length ? keyboard.vendorName : @"Keyboard";
    if ([name isEqualToString:@"Generic Keyboard"])
        name = [NSUserDefaults.standardUserDefaults stringForKey:@"SofaKeyboardName"] ?: @"Keyboard";
    _keyboardStatus.text = [NSString stringWithFormat:@"●  %@ · %@", name, keyboard ?
        (SofaInput.shared.keyboardConfirmed ? @"input ready" : @"connected") : @"not connected"];
    _keyboardStatus.textColor = keyboard ? UIColor.systemMintColor : UIColor.secondaryLabelColor;
    BOOL mouse = NSDate.timeIntervalSinceReferenceDate - SofaInput.shared.lastMouseEvent < 60;
    _mouseStatus.text = mouse ? @"●  Mouse · input ready" : SofaInput.shared.available ? @"●  Mouse · move to verify" : @"●  Mouse · unavailable";
    _mouseStatus.textColor = mouse ? UIColor.systemMintColor : UIColor.systemOrangeColor;
}
- (void)probeHosts {
    if (_connecting || _home.hidden || self.presentedViewController) return;
    for (TemporaryHost *host in _hosts) {
        if (host.state != StateOnline || [_probing containsObject:host.uuid]) continue;
        [_probing addObject:host.uuid];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            HttpManager *manager = [[HttpManager alloc] initWithHost:host];
            ServerInfoResponse *response = [ServerInfoResponse new];
            CFTimeInterval start = CACurrentMediaTime();
            [manager executeRequestSynchronously:[HttpRequest requestForResponse:response withUrlRequest:[manager newHttpServerInfoRequest:true]]];
            double milliseconds = (CACurrentMediaTime() - start) * 1000;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self->_probing removeObject:host.uuid];
                if (response.isStatusOk) self->_latencies[host.uuid] = @(milliseconds);
                else [self->_latencies removeObjectForKey:host.uuid];
                [self updateHosts];
            });
        });
    }
}
- (void)openPendingComputer {
    NSString *identifier = [NSUserDefaults.standardUserDefaults stringForKey:@"SofaPendingComputer"];
    if (!identifier || !self.view.window || _connecting || self.presentedViewController || self.navigationController.topViewController != self) return;
    SofaTile *tile = _tiles[identifier];
    if (!tile) return;
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"SofaPendingComputer"];
    [self openTile:tile];
}
- (void)openTile:(SofaTile *)tile {
    if (_connecting || self.presentedViewController || self.navigationController.topViewController != self) return;
    if (tile.host.state != StateOnline) { [self hostLongClicked:tile.host view:tile]; return; }
    _connecting = YES; _openingHost = tile.host;
    [super hostClicked:tile.host view:tile];
}
- (void)appClicked:(TemporaryApp *)app view:(UIView *)view {
    TemporaryApp *running = [self findRunningApp:app.host];
    if (running && [running.id isEqual:app.id]) {
        [self prepareToStreamApp:app];
        [self performSegueWithIdentifier:@"createStreamFrame" sender:nil];
    } else {
        [super appClicked:app view:view];
    }
}
- (void)tileOptions:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        SofaTile *tile = (SofaTile *)gesture.view;
        [self hostLongClicked:tile.host view:tile];
    }
}
- (void)hostClicked:(TemporaryHost *)host view:(UIView *)view {
    // Always open on the computer tiles, even with one saved host or after a stream.
    if (!view) return;
    [super hostClicked:host view:view];
}
- (void)updateAppsForHost:(TemporaryHost *)host {
    [super updateAppsForHost:host];
    if (!_connecting || ![host.uuid isEqual:_openingHost.uuid]) return;
    for (TemporaryApp *app in host.appList) {
        if ([app.name caseInsensitiveCompare:@"Desktop"] == NSOrderedSame) { _pendingDesktop = app; break; }
    }
    if (!_pendingDesktop) {
        _home.hidden = YES;
        [self.navigationController setNavigationBarHidden:NO animated:NO];
        _connecting = NO;
    }
}
- (void)hideLoadingFrame:(void (^)(void))completion {
    [super hideLoadingFrame:^{
        if (completion) completion();
        TemporaryApp *desktop = self->_pendingDesktop;
        if (desktop && self->_connecting && !self.presentedViewController) {
            self->_pendingDesktop = nil; self->_connecting = NO;
            [self appClicked:desktop view:self->_tiles[desktop.host.uuid]];
        }
    }];
}
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    [super prepareForSegue:segue sender:sender];
    if ([segue.destinationViewController isKindOfClass:SofaStreamController.class]) {
        ((SofaStreamController *)segue.destinationViewController).previewID = _openingHost.uuid;
        _returningFromStream = YES;
    }
}
- (NSArray<id<UIFocusEnvironment>> *)preferredFocusEnvironments {
    if (!_home.hidden && _tiles.count) {
        TemporaryHost *first = [_hosts sortedArrayUsingSelector:@selector(compareName:)].firstObject;
        return @[_tiles[first.uuid]];
    }
    return [super preferredFocusEnvironments];
}
@end
