#import "SofaAppDelegate.h"
#import "SofaInput.h"
#import <Security/Security.h>
@implementation SofaAppDelegate
+ (void)importPairing {
    NSURL *cache = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].lastObject;
    NSURL *source = [cache URLByAppendingPathComponent:@"sofa-identity.plist"];
    NSDictionary *identity = [NSDictionary dictionaryWithContentsOfURL:source];
    if (!identity) return;
    BOOL valid = YES;
    for (NSString *key in @[@"client.crt", @"client.key", @"client.p12"]) {
        id data = identity[key];
        valid &= [data isKindOfClass:NSData.class] && [data length] > 0 && [data length] < 65536;
    }
    CFArrayRef items = NULL;
    if (valid) valid = SecPKCS12Import((__bridge CFDataRef)identity[@"client.p12"],
        (__bridge CFDictionaryRef)@{(__bridge NSString *)kSecImportExportPassphrase:@"limelight"}, &items) == errSecSuccess;
    if (items) CFRelease(items);
    if (valid) {
        for (NSString *key in @[@"client.crt", @"client.key", @"client.p12"])
            [NSUserDefaults.standardUserDefaults setObject:identity[key] forKey:key];
        NSString *name = identity[@"SofaKeyboardName"];
        if ([name isKindOfClass:NSString.class] && name.length < 80)
            [NSUserDefaults.standardUserDefaults setObject:name forKey:@"SofaKeyboardName"];
    }
    // The imported identity remains in the app's protected preferences, never in its bundle.
    [NSFileManager.defaultManager removeItemAtURL:source error:nil];
}
- (void)applicationDidBecomeActive:(UIApplication *)application {
    [super applicationDidBecomeActive:application];
    [SofaInput.shared start];
}
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
    if ([url.absoluteString isEqual:@"moonlight-next://home"]) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"SofaPendingComputer"];
        if ([self.window.rootViewController isKindOfClass:UINavigationController.class])
            [(UINavigationController *)self.window.rootViewController popToRootViewControllerAnimated:NO];
        return YES;
    }
    if ([url.scheme isEqual:@"moonlight-next"] && [url.host isEqual:@"computer"] && !url.query && !url.fragment && !url.user && !url.password && !url.port) {
        NSString *hostID = url.lastPathComponent;
        if (![[NSUUID alloc] initWithUUIDString:hostID] || ![url.path isEqual:[@"/" stringByAppendingString:hostID]]) return NO;
        [NSUserDefaults.standardUserDefaults setObject:hostID forKey:@"SofaPendingComputer"];
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.window.rootViewController isKindOfClass:UINavigationController.class])
                [(UINavigationController *)self.window.rootViewController popToRootViewControllerAnimated:NO];
            [NSNotificationCenter.defaultCenter postNotificationName:@"SofaOpenComputer" object:nil];
        });
        return YES;
    }
    return NO;
}
- (void)applicationWillResignActive:(UIApplication *)application {
    [SofaInput.shared stop];
    [super applicationWillResignActive:application];
}
@end
