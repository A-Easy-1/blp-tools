#import "GSProConnector.h"
#import "DataModel.h"            // <--- Added
#import "ScreenDataProcessor.h"  // <--- Added for Notification Names

NSString * const GSProConnectionStateNotification = @"GSProConnectionStateNotification";

@interface GSProConnector ()
@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) NSOutputStream *outputStream;
@property (nonatomic, copy) NSString *serverIP;
@property (nonatomic, assign) NSInteger serverPort;
@property (nonatomic, strong) NSTimer *reconnectTimer;
@property (nonatomic, assign) BOOL isConnected;

@property (nonatomic, assign) NSTimeInterval lastBallTimestamp;
@property (nonatomic, assign) NSTimeInterval lastClubTimestamp;

@property (nonatomic, strong) NSString *connectionState;
@end

@implementation GSProConnector

+ (instancetype)shared {
    static GSProConnector *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[GSProConnector alloc] init];
    });
    return instance;
}

#pragma mark - Public Methods

- (void)connectToServerWithIP:(NSString *)ip port:(NSInteger)port {
    if (!ip || ip.length == 0) {
        [self postConnectionNotification:@""];
        return;
    }
    
    NSString *ipPattern = @"^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\\."
                           "(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\\."
                           "(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\\."
                           "(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:ipPattern options:0 error:nil];
    NSUInteger matches = [regex numberOfMatchesInString:ip options:0 range:NSMakeRange(0, ip.length)];
    if (matches == 0) {
        [self postConnectionNotification:@"Invalid IP"];
        return;
    }

    self.serverIP = ip;
    self.serverPort = port;
    
    [self postConnectionNotification:@"Connecting"];
    [self openConnection];
}

- (BOOL)isConnected {
    if (!self.outputStream) return NO;
    NSStreamStatus status = [self.outputStream streamStatus];
    return (status == NSStreamStatusOpen || status == NSStreamStatusWriting || status == NSStreamStatusReading);
}

- (void)disconnect {
    self.isConnected = NO;
    [self closeStreams];
    [self postConnectionNotification:@"Disconnected"];
    NSLog(@"Disconnected from server.");
}

- (NSString *)createShotJsonWithBallData:(NSDictionary *)ballData
                                clubData:(NSDictionary *)clubData
                              shotNumber:(int)shotNumber
                                   error:(NSError **)error {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"DeviceID"] = @"BLP Tools";
    dict[@"Units"] = @"Yards";
    dict[@"ShotNumber"] = @(shotNumber);
    dict[@"APIversion"] = @"1";
    if (ballData) dict[@"BallData"] = ballData;
    if (clubData) dict[@"ClubData"] = clubData;
    dict[@"ShotDataOptions"] = @{
        @"ContainsBallData": @(ballData != nil),
        @"ContainsClubData": @(clubData != nil),
        @"LaunchMonitorIsReady": @YES,
        @"LaunchMonitorBallDetected": @YES,
        @"IsHeartBeat": @NO
    };
    
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:(error ? error : NULL)];
    if (!jsonData) return nil;
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (void)sendShotWithBallData:(NSDictionary *)ballData clubData:(NSDictionary *)clubData shotNumber:(int)shotNumber {
    if (!self.isConnected || !self.outputStream) {
        NSLog(@"Not connected to server. Unable to send data.");
        return;
    }
    
    NSTimeInterval now = [NSDate.date timeIntervalSince1970];
    if (ballData) {
        if ((now - self.lastBallTimestamp) < 2.0) return;
        self.lastBallTimestamp = now;
    } else if (clubData) {
        if ((now - self.lastClubTimestamp) < 2.0) return;
        self.lastClubTimestamp = now;
    }
    
    NSError *jsonError = nil;
    NSString *jsonString = [self createShotJsonWithBallData:ballData clubData:clubData shotNumber:0 error:&jsonError];
    if (!jsonString) {
        NSLog(@"Error generating JSON for GSPro: %@", jsonError);
        return;
    }
    
    NSData *data = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    if ([self.outputStream hasSpaceAvailable]) {
        NSInteger bytesWritten = [self.outputStream write:data.bytes maxLength:data.length];
        if (bytesWritten == -1) {
            NSLog(@"Error writing to stream: %@", self.outputStream.streamError);
            [self disconnect];
            [self scheduleReconnect];
        } else {
            NSLog(@"Sent %ld bytes to server.", (long)bytesWritten);
        }
    } else {
        NSLog(@"Output stream has no space available.");
    }
}

- (void)openConnection {
    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)self.serverIP, (UInt32)self.serverPort, &readStream, &writeStream);
    
    if (!readStream || !writeStream) {
        NSLog(@"Error: Could not create stream pair.");
        [self disconnect];
        [self scheduleReconnect];
        return;
    }
    
    self.inputStream = (__bridge_transfer NSInputStream *)readStream;
    self.outputStream = (__bridge_transfer NSOutputStream *)writeStream;
    self.inputStream.delegate = self;
    self.outputStream.delegate = self;
    [self.inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.inputStream open];
    [self.outputStream open];
    NSLog(@"Attempting to connect to %@:%ld", self.serverIP, (long)self.serverPort);
}

- (void)closeStreams {
    if (self.inputStream) {
        [self.inputStream close];
        [self.inputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        self.inputStream.delegate = nil;
        self.inputStream = nil;
    }
    if (self.outputStream) {
        [self.outputStream close];
        [self.outputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        self.outputStream.delegate = nil;
        self.outputStream = nil;
    }
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    switch (eventCode) {
        case NSStreamEventOpenCompleted:
            if (aStream == self.outputStream) {
                self.isConnected = YES;
                [self invalidateReconnectTimer];
                [self postConnectionNotification:@"Connected"];
            }
            break;
        case NSStreamEventErrorOccurred:
            NSLog(@"Stream error: %@", aStream.streamError);
            [self disconnect];
            [self scheduleReconnect];
            break;
        case NSStreamEventEndEncountered:
            NSLog(@"Stream end encountered.");
            [self disconnect];
            [self scheduleReconnect];
            break;
        default: break;
    }
}

- (void)scheduleReconnect {
    if (self.reconnectTimer) return;
    NSLog(@"Scheduling reconnect in 10 seconds...");
    self.reconnectTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(reconnectTimerFired:) userInfo:nil repeats:NO];
}

- (void)reconnectTimerFired:(NSTimer *)timer {
    [self invalidateReconnectTimer];
    [self openConnection];
}

- (void)invalidateReconnectTimer {
    if (self.reconnectTimer) {
        [self.reconnectTimer invalidate];
        self.reconnectTimer = nil;
    }
}

- (void)postConnectionNotification:(NSString *)stateString {
    self.connectionState = [stateString copy];
    NSDictionary *userInfo = @{ @"connectionState": stateString };
    [[NSNotificationCenter defaultCenter] postNotificationName:GSProConnectionStateNotification object:nil userInfo:userInfo];
}

- (NSString *)getConnectionState {
    return self.connectionState;
}

@end
