#import "SofaCursorChannel.h"
#import "SofaCursorProtocol.h"
#import "Utils.h"
#import <ImageIO/ImageIO.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <unistd.h>

@implementation SofaCursorChannel {
    dispatch_source_t _listener;
    NSInputStream *_input;
    NSMutableData *_buffer;
    NSMutableSet<NSData *> *_addresses;
    unsigned long _length;
    int _width, _height, _hotX, _hotY;
}
- (void)disconnect {
    [_input close];
    [_input removeFromRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    _input.delegate = nil; _input = nil;
    _buffer = nil; _length = 0;
    if (self.changed) self.changed(nil, CGSizeZero, CGPointZero, NO);
}
- (void)stop {
    [self disconnect];
    if (_listener) dispatch_source_cancel(_listener);
    _listener = nil;
}
- (void)startForHost:(NSString *)host {
    [self stop];
    _addresses = [NSMutableSet new];
    struct addrinfo hints = {.ai_family = AF_INET, .ai_socktype = SOCK_STREAM}, *result = NULL;
    NSString *address = [Utils addressPortStringToAddress:host];
    if (getaddrinfo(address.UTF8String, NULL, &hints, &result) != 0) return;
    for (struct addrinfo *p = result; p; p = p->ai_next) {
        struct in_addr ip = ((struct sockaddr_in *)p->ai_addr)->sin_addr;
        [_addresses addObject:[NSData dataWithBytes:&ip length:sizeof(ip)]];
    }
    freeaddrinfo(result);
    int fd = socket(AF_INET, SOCK_STREAM, 0), yes = 1;
    if (fd < 0) return;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    fcntl(fd, F_SETFL, O_NONBLOCK);
    struct sockaddr_in local = {.sin_len = sizeof(local), .sin_family = AF_INET, .sin_port = htons(47995)};
    if (bind(fd, (struct sockaddr *)&local, sizeof(local)) || listen(fd, 2)) { close(fd); return; }
    _listener = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, dispatch_get_main_queue());
    __weak SofaCursorChannel *weakSelf = self;
    dispatch_source_set_event_handler(_listener, ^{ [weakSelf acceptFrom:fd]; });
    dispatch_source_set_cancel_handler(_listener, ^{ close(fd); });
    dispatch_resume(_listener);
    NSLog(@"Sofa local cursor: listening for %@", address);
}
- (void)acceptFrom:(int)listener {
    struct sockaddr_in peer; socklen_t size = sizeof(peer);
    int fd = accept(listener, (struct sockaddr *)&peer, &size);
    if (fd < 0) return;
    NSData *address = [NSData dataWithBytes:&peer.sin_addr length:sizeof(peer.sin_addr)];
    if (![_addresses containsObject:address]) { close(fd); return; }
    [self disconnect];
    int yes = 1, idle = 10, interval = 3, count = 3;
    setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &yes, sizeof(yes));
    setsockopt(fd, IPPROTO_TCP, TCP_KEEPALIVE, &idle, sizeof(idle));
    setsockopt(fd, IPPROTO_TCP, TCP_KEEPINTVL, &interval, sizeof(interval));
    setsockopt(fd, IPPROTO_TCP, TCP_KEEPCNT, &count, sizeof(count));
    CFReadStreamRef read = NULL;
    CFStreamCreatePairWithSocket(NULL, fd, &read, NULL);
    if (!read) { close(fd); return; }
    CFReadStreamSetProperty(read, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
    _input = CFBridgingRelease(read); _input.delegate = self;
    _buffer = [NSMutableData new];
    [_input scheduleInRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    [_input open];
    if (self.changed) self.changed(nil, CGSizeZero, CGPointZero, YES);
    NSLog(@"Sofa local cursor: helper connected");
}
- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)event {
    if (stream != _input) return;
    if (event & (NSStreamEventErrorOccurred | NSStreamEventEndEncountered)) { [self disconnect]; return; }
    if (!(event & NSStreamEventHasBytesAvailable)) return;
    uint8_t chunk[16384];
    NSInteger received = [_input read:chunk maxLength:sizeof(chunk)];
    if (received <= 0) { [self disconnect]; return; }
    [_buffer appendBytes:chunk length:received];
    while (_buffer.length) {
        if (!_length) {
            const char *newline = memchr(_buffer.bytes, '\n', MIN(_buffer.length, 64));
            if (!newline) { if (_buffer.length >= 64) [self disconnect]; return; }
            size_t size = newline - (const char *)_buffer.bytes + 1;
            char line[65] = {0}; memcpy(line, _buffer.bytes, size);
            if (!SofaCursorHeader(line, &_width, &_height, &_hotX, &_hotY, &_length)) { [self disconnect]; return; }
            [_buffer replaceBytesInRange:NSMakeRange(0,size) withBytes:NULL length:0];
        }
        if (_buffer.length < _length) return;
        NSData *png = [_buffer subdataWithRange:NSMakeRange(0,_length)];
        CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)png, NULL);
        NSDictionary *properties = source ? CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL)) : nil;
        NSInteger w = [properties[(__bridge NSString *)kCGImagePropertyPixelWidth] integerValue];
        NSInteger h = [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] integerValue];
        CGImageRef pixels = w > 0 && h > 0 && w <= 1024 && h <= 1024 ? CGImageSourceCreateImageAtIndex(source,0,NULL) : NULL;
        if (source) CFRelease(source);
        if (!pixels) { [self disconnect]; return; }
        UIImage *image = [UIImage imageWithCGImage:pixels]; CGImageRelease(pixels);
        if (self.changed) self.changed(image, CGSizeMake(_width,_height), CGPointMake(_hotX,_hotY), YES);
        [_buffer replaceBytesInRange:NSMakeRange(0,_length) withBytes:NULL length:0];
        _length = 0;
    }
}
- (void)dealloc { [self stop]; }
@end
