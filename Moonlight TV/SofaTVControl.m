#import "SofaTVControl.h"
#import <Security/Security.h>

@interface SofaTVControl () <NSURLSessionDelegate, NSURLSessionTaskDelegate>
@property(nonatomic, copy) NSDictionary *configuration;
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic) BOOL switching;
@end

@implementation SofaTVControl
+ (instancetype)shared {
    static SofaTVControl *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [SofaTVControl new]; });
    return instance;
}
- (NSDictionary *)keychainQuery {
    return @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService:@"MoonlightNext.PhilipsTV", (__bridge id)kSecAttrAccount:@"paired-tv"};
}
- (BOOL)validConfiguration:(NSDictionary *)config {
    if (![config isKindOfClass:NSDictionary.class]) return NO;
    for (NSString *key in @[@"host", @"username", @"password"])
        if (![config[key] isKindOfClass:NSString.class] || [config[key] length] == 0 || [config[key] length] > 256) return NO;
    NSString *host = config[@"host"];
    if ([host rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"] invertedSet]].location != NSNotFound) return NO;
    if (![config[@"certificate"] isKindOfClass:NSData.class]) return NO;
    SecCertificateRef certificate = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)config[@"certificate"]);
    if (!certificate) return NO;
    CFRelease(certificate);
    if (![config[@"inputs"] isKindOfClass:NSArray.class] || [config[@"inputs"] count] != 2) return NO;
    NSMutableSet *ids = [NSMutableSet new];
    for (id input in config[@"inputs"]) {
        if (![input isKindOfClass:NSDictionary.class]) return NO;
        NSString *identifier = input[@"id"], *name = input[@"name"], *uri = input[@"uri"];
        if (![@[@"ps5", @"switch2"] containsObject:identifier] || [ids containsObject:identifier]) return NO;
        if (![name isKindOfClass:NSString.class] || name.length == 0 || name.length > 80) return NO;
        if (![uri isKindOfClass:NSString.class] || ![uri hasPrefix:@"content://android.media.tv/passthrough/"] || uri.length > 512) return NO;
        if (![input[@"port"] isKindOfClass:NSNumber.class] || [input[@"port"] integerValue] < 1 || [input[@"port"] integerValue] > 4) return NO;
        [ids addObject:identifier];
    }
    return YES;
}
- (void)importConfiguration {
    NSURL *cache = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].lastObject;
    NSURL *source = [cache URLByAppendingPathComponent:@"sofa-tv.plist"];
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfURL:source];
    if ([self validConfiguration:config]) {
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:config format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
        NSDictionary *attributes = @{(__bridge id)kSecValueData:data,
            (__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};
        OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)self.keychainQuery, (__bridge CFDictionaryRef)attributes);
        if (status == errSecItemNotFound) {
            NSMutableDictionary *item = [self.keychainQuery mutableCopy]; [item addEntriesFromDictionary:attributes];
            status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
        }
        if (status == errSecSuccess) [NSFileManager.defaultManager removeItemAtURL:source error:nil];
    }
    NSMutableDictionary *query = [self.keychainQuery mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) == errSecSuccess) {
        NSData *data = CFBridgingRelease(result);
        NSDictionary *saved = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:nil];
        if ([self validConfiguration:saved]) self.configuration = saved;
    }
    if (!self.session) {
        NSURLSessionConfiguration *sessionConfig = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        sessionConfig.timeoutIntervalForRequest = 8;
        sessionConfig.timeoutIntervalForResource = 12;
        self.session = [NSURLSession sessionWithConfiguration:sessionConfig delegate:self delegateQueue:NSOperationQueue.mainQueue];
    }
}
- (NSArray<NSDictionary *> *)inputs { return self.configuration[@"inputs"] ?: @[]; }
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
    completionHandler(nil); // Pairing credentials never follow a redirect.
}
- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    NSURLProtectionSpace *space = challenge.protectionSpace;
    if (![space.host isEqualToString:self.configuration[@"host"]] || space.port != 1926 || challenge.previousFailureCount > 0) {
        completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil); return;
    }
    if ([space.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        SecTrustRef trust = space.serverTrust;
        CFArrayRef chain = trust ? SecTrustCopyCertificateChain(trust) : NULL;
        SecCertificateRef leaf = chain && CFArrayGetCount(chain) ? (SecCertificateRef)CFArrayGetValueAtIndex(chain, 0) : NULL;
        NSData *der = leaf ? CFBridgingRelease(SecCertificateCopyData(leaf)) : nil;
        BOOL pinned = [der isEqual:self.configuration[@"certificate"]];
        if (chain) CFRelease(chain);
        completionHandler(pinned ? NSURLSessionAuthChallengeUseCredential : NSURLSessionAuthChallengeCancelAuthenticationChallenge,
                          pinned ? [NSURLCredential credentialForTrust:trust] : nil);
    } else if ([space.authenticationMethod isEqualToString:NSURLAuthenticationMethodHTTPDigest]) {
        completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialWithUser:self.configuration[@"username"] password:self.configuration[@"password"] persistence:NSURLCredentialPersistenceNone]);
    } else completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    [self URLSession:session didReceiveChallenge:challenge completionHandler:completionHandler];
}
- (void)sendRequest:(NSURLRequest *)request retry:(BOOL)retry completion:(void (^)(NSData *, NSURLResponse *, NSError *))completion {
    // Philips closes idle keep-alive connections without warning. Never reuse one across input changes.
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.timeoutIntervalForRequest = 8; config.timeoutIntervalForResource = 12;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:NSOperationQueue.mainQueue];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [session finishTasksAndInvalidate];
        if (retry && [error.domain isEqual:NSURLErrorDomain] && error.code == NSURLErrorNetworkConnectionLost) {
            [self sendRequest:request retry:NO completion:completion];
        } else completion(data, response, error);
    }] resume];
}
- (void)openInput:(NSString *)identifier fromController:(UIViewController *)controller {
    if (self.switching || !controller || controller.presentedViewController) return;
    NSDictionary *input = nil;
    for (NSDictionary *candidate in self.inputs) if ([candidate[@"id"] isEqual:identifier]) { input = candidate; break; }
    if (!input) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"TV pairing needed" message:@"Pair your Philips TV before using console shortcuts." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [controller presentViewController:alert animated:YES completion:nil]; return;
    }
    self.switching = YES;
    UIAlertController *progress = [UIAlertController alertControllerWithTitle:[@"Switching to " stringByAppendingString:input[@"name"]] message:@"Wake the console with its controller if needed." preferredStyle:UIAlertControllerStyleAlert];
    [controller presentViewController:progress animated:YES completion:nil];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@:1926/6/activities/launch", self.configuration[@"host"]]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"close" forHTTPHeaderField:@"Connection"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"intent":@{
        @"extras":@{@"uri":input[@"uri"]}, @"action":@"org.droidtv.playtv.SELECTURI",
        @"component":@{@"packageName":@"org.droidtv.playtv", @"className":@"org.droidtv.playtv.PlayTvActivity"}}} options:0 error:nil];
    [self sendRequest:request retry:YES completion:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        id body = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        BOOL failed = error || status < 200 || status >= 300;
        if ([body isKindOfClass:NSDictionary.class] && body[@"error_id"] && ![body[@"error_id"] isEqual:@"SUCCESS"]) failed = YES;
#if DEBUG
        NSURL *cache = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].lastObject;
        [[NSJSONSerialization dataWithJSONObject:@{@"input":identifier, @"httpStatus":@(status), @"errorCode":@(error.code), @"accepted":@(!failed)} options:0 error:nil]
            writeToURL:[cache URLByAppendingPathComponent:@"sofa-tv-result.json"] atomically:YES];
#endif
        dispatch_async(dispatch_get_main_queue(), ^{
            self.switching = NO;
            [progress dismissViewControllerAnimated:YES completion:^{
                if (!failed) return;
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Couldn’t switch the TV" message:@"Check that your Philips TV is on and reachable on the same network, then try again." preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [controller presentViewController:alert animated:YES completion:nil];
            }];
        });
    }];
}
@end
