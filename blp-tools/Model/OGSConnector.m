#import "OGSConnector.h"
#import <UIKit/UIKit.h>
#import "DataModel.h"
#import "ScreenDataProcessor.h"

@interface OGSConnector () <NSStreamDelegate>
@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) NSOutputStream *outputStream;
@property (nonatomic, assign) BOOL isConnected;
@end

@implementation OGSConnector

+ (instancetype)shared {
    static OGSConnector *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[OGSConnector alloc] init];
    });
    return instance;
}

- (void)connectToIP:(NSString *)ip port:(NSInteger)port {
    if (self.isConnected) {
        [self disconnect];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self performConnectToIP:ip port:port];
        });
    } else {
        [self performConnectToIP:ip port:port];
    }
}

- (void)performConnectToIP:(NSString *)ip port:(NSInteger)port {
    NSLog(@"[OGS] Attempting connection to %@:%ld...", ip, (long)port);
    CFReadStreamRef readStream;
    CFWriteStreamRef writeStream;
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)ip, (UInt32)port, &readStream, &writeStream);
    self.inputStream = (__bridge_transfer NSInputStream *)readStream;
    self.outputStream = (__bridge_transfer NSOutputStream *)writeStream;
    [self.inputStream setDelegate:self];
    [self.outputStream setDelegate:self];
    [self.inputStream scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    [self.inputStream open];
    [self.outputStream open];
}

- (void)disconnect {
    if (self.inputStream) {
        [self.inputStream close];
        [self.inputStream removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
        self.inputStream = nil;
    }
    if (self.outputStream) {
        [self.outputStream close];
        [self.outputStream removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
        self.outputStream = nil;
    }
    self.isConnected = NO;
    NSLog(@"[OGS] Disconnected");
}

- (BOOL)isConnected {
    if (!self.outputStream) return NO;
    NSStreamStatus status = [self.outputStream streamStatus];
    return (status == NSStreamStatusOpen || status == NSStreamStatusWriting || status == NSStreamStatusReading);
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    switch (eventCode) {
        case NSStreamEventOpenCompleted:
            if (aStream == self.outputStream) NSLog(@"[OGS] Output Stream Opened!");
            break;
        case NSStreamEventHasSpaceAvailable:
            if (aStream == self.outputStream && !self.isConnected) {
                self.isConnected = YES;
                NSLog(@"[OGS] Connected! Sending handshake...");
                [self sendDeviceStatusReady];
            }
            break;
        case NSStreamEventErrorOccurred:
            NSLog(@"[OGS] Stream Error: %@", aStream.streamError.localizedDescription);
            [self disconnect];
            break;
        case NSStreamEventEndEncountered:
            NSLog(@"[OGS] Stream End Encountered");
            [self disconnect];
            break;
        default: break;
    }
}

- (void)sendJSON:(NSDictionary *)jsonDict {
    if (!self.outputStream) return;
    NSError *error;
    NSData *data = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:&error];
    if (error) {
        NSLog(@"[OGS] JSON Generation Error: %@", error);
        return;
    }
    NSMutableData *payload = [data mutableCopy];
    [payload appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
    if ([self.outputStream hasSpaceAvailable]) {
        [self.outputStream write:payload.bytes maxLength:payload.length];
    } else {
        NSLog(@"[OGS] Cannot write (Stream full or closed)");
    }
}

- (void)sendDeviceStatusReady {
    [self sendJSON:@{ @"type": @"device", @"status": @"ready" }];
}

// UPDATED: Now accepts shotNumber
- (void)sendShotWithBallData:(NSDictionary *)ballData
                    clubData:(NSDictionary *)clubData
                  shotNumber:(int)shotNumber {
    
    NSDictionary *shotPayload = @{
        @"ballSpeed": ballData[@"Speed"] ?: @0,
        @"verticalLaunchAngle": ballData[@"VLA"] ?: @0,
        @"horizontalLaunchAngle": ballData[@"HLA"] ?: @0,
        @"spinSpeed": ballData[@"TotalSpin"] ?: @0,
        @"spinAxis": ballData[@"SpinAxis"] ?: @0
    };
    
    NSMutableDictionary *finalShot = [shotPayload mutableCopy];
    if (clubData) {
        [finalShot addEntriesFromDictionary:@{
            @"clubSpeed": clubData[@"Speed"] ?: @0,
            @"attackAngle": clubData[@"AngleOfAttack"] ?: @0,
            @"clubPath": clubData[@"Path"] ?: @0,
        }];
    }
    
    // Add shot number if useful for debugging or tracking
    finalShot[@"shotNumber"] = @(shotNumber);
    
    NSDictionary *message = @{
        @"type": @"shot",
        @"unit": @"imperial",
        @"shot": finalShot
    };
    [self sendJSON:message];
}

@end
