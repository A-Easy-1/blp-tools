#import "DataModel.h"
#import "CameraManager.h"
#import "GSProConnector.h"
#import "OGSConnector.h"
#import "SettingsManager.h"
#import "ModelManager.h"
#import "ShotManager.h"
#import "ImageUtilities.h"
#import "Constants.h"

static NSString * const SettingsTestShotNotification = @"SettingsTestShotNotification";

@interface DataModel ()
    @property (nonatomic, strong) ScreenDataProcessor *screenDataProcessor;
    @property (nonatomic, assign) int shotNumber;
    @property (nonatomic, assign) int gsProPort;
    @property (nonatomic, assign) int ogsPort;
    @property (nonatomic, strong) ShotManager *shotManager;
    @property (atomic, assign) BOOL isProcessingPaused;
@end

@implementation DataModel

+ (instancetype)shared {
    static DataModel *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[DataModel alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(processFrame:) name:CameraManagerNewFrameNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateCorners:) name:ScreenDataProcessorNewCornersNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewBallData:) name:ScreenDataProcessorNewBallDataNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewClubData:) name:ScreenDataProcessorNewClubDataNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleIpChanged:) name:GSProIPChangedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(startMiniGame:) name:MiniGameStartNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleTestShot:) name:SettingsTestShotNotification object:nil];
        
        [UIApplication sharedApplication].idleTimerDisabled = YES;
        self.isProcessingPaused = NO;
        
        self.currentShotBallData = nil;
        self.currentShotClubData = nil;
        self.shotNumber = -1;
        self.gsProPort = 921;
        self.ogsPort = 3111;
        
        self.screenDataProcessor = [[ScreenDataProcessor alloc] init];
        [SettingsManager shared];
        [[CameraManager shared] startCamera];
        
        self.shotManager = [[ShotManager alloc] init];
        
        // Robust IP Fetch
        NSString *ip = [SettingsManager shared].gsProIP;
        if (ip.length == 0) ip = @"192.168.1.100";
        
        BOOL useOGS = [[NSUserDefaults standardUserDefaults] boolForKey:@"use_ogs"];
        
        if (useOGS) {
            NSLog(@"[DataModel] Startup: Connecting to OpenGolf (OGS) at %@:%d", ip, self.ogsPort);
            [[OGSConnector shared] connectToIP:ip port:self.ogsPort];
        } else {
            NSLog(@"[DataModel] Startup: Connecting to GSPro at %@:%d", ip, self.gsProPort);
            [[GSProConnector shared] connectToServerWithIP:ip port:self.gsProPort];
        }
        
        NSArray *models = @[@"hla-direction", @"spin-axis-direction", @"ball-speed-units", @"carry-units", @"club-speed-units", @"path-direction", @"aoa-direction"];
        for (NSString *model in models) {
            [[ModelManager shared] loadModelWithName:model error:nil];
        }
    }
    return self;
}

- (void)setProcessingPaused:(BOOL)paused {
    self.isProcessingPaused = paused;
    NSLog(@"[DataModel] Processing Paused: %@", paused ? @"YES" : @"NO");
}

- (NSDictionary *)calculateShotCoordinates:(NSDictionary *)shotData {
    if (!shotData) return @{};

    // Carry Only Logic
    double distance = [shotData[@"CarryDistance"] doubleValue];
    if (distance < 0.1) return @{};

    double hla = [shotData[@"HLA"] doubleValue];
    double spinAxis = [shotData[@"SpinAxis"] doubleValue];

    double hlaRad = hla * (M_PI / 180.0);
    double launchOffline = distance * sin(hlaRad);

    double curveFactor = 0.006;
    double curveOffline = distance * spinAxis * curveFactor;

    double totalOffline = launchOffline + curveOffline;

    return @{
        @"CalcOffline": @(totalOffline),
        @"CalcOfflineAbs": @(fabs(totalOffline))
    };
}

- (BOOL)isDuplicateBallData:(NSDictionary *)newData {
    if (!self.currentShotBallData) return NO;
    
    NSArray *keysToCheck = @[@"Speed", @"VLA", @"HLA", @"TotalSpin", @"SpinAxis", @"CarryDistance"];
    
    for (NSString *key in keysToCheck) {
        NSNumber *oldVal = self.currentShotBallData[key];
        NSNumber *newVal = newData[key];
        
        if (!oldVal || !newVal || ![oldVal isEqualToNumber:newVal]) {
            return NO; // Difference found, is new shot
        }
    }
    
    return YES; // All keys matched exactly
}

- (void)processFrame:(NSNotification *)notification {
    if (self.isProcessingPaused) return;

    UIImage *frame = notification.userInfo[@"frame"];
    if (!frame) return;
    
    static NSTimeInterval lastCallTime = 0;
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    if (currentTime - lastCallTime < OCR_RATE_SECONDS) return;
    lastCallTime = currentTime;

    [self.screenDataProcessor processScreenDataFromImage:frame error:nil];
}

- (void)handleNewBallData:(NSNotification *)notification {
    UIImage *image = notification.userInfo[@"image"];
    if (image) self.currentShotBallImage = image;
    
    NSDictionary *data = notification.userInfo[@"data"];
    if (!data) return;
    
    // --- DUPLICATE CHECK ---
    if ([self isDuplicateBallData:data]) {
        NSLog(@"[DataModel] Duplicate shot detected (Ignoring).");
        return;
    }
    
    NSMutableDictionary *enhancedData = [data mutableCopy];
    NSDictionary *physics = [self calculateShotCoordinates:enhancedData];
    [enhancedData addEntriesFromDictionary:physics];
    
    self.currentShotBallData = [enhancedData copy];
    self.currentShotClubData = nil;
    self.shotNumber++;
    
    NSLog(@"[DataModel] Shot #%d VALID. Sending to Connector... (Carry: %@)", self.shotNumber, enhancedData[@"CarryDistance"]);
    
    [self.shotManager addShot:self.currentShotBallData];
    
    BOOL useOGS = [[NSUserDefaults standardUserDefaults] boolForKey:@"use_ogs"];
    if (useOGS) {
        [[OGSConnector shared] sendShotWithBallData:self.currentShotBallData clubData:nil shotNumber:self.shotNumber];
    } else {
        [[GSProConnector shared] sendShotWithBallData:self.currentShotBallData clubData:nil shotNumber:self.shotNumber];
    }
    
    [self DEBUG_saveShotImage:image withData:self.currentShotBallData andShotNumber:self.shotNumber];
}

- (void)handleNewClubData:(NSNotification *)notification {
    if(!self.currentShotBallData) return;
    
    UIImage *image = notification.userInfo[@"image"];
    if (image) self.currentShotClubImage = image;
    
    NSDictionary *data = notification.userInfo[@"data"];
    if (!data) return;
    
    self.currentShotClubData = [data copy];
    [self.shotManager updateShotClubData:self.currentShotClubData];
    
    NSLog(@"[DataModel] Club Data Received. Sending update...");
    
    BOOL useOGS = [[NSUserDefaults standardUserDefaults] boolForKey:@"use_ogs"];
    if (useOGS) {
        [[OGSConnector shared] sendShotWithBallData:nil clubData:self.currentShotClubData shotNumber:self.shotNumber];
    } else {
        [[GSProConnector shared] sendShotWithBallData:nil clubData:self.currentShotClubData shotNumber:self.shotNumber];
    }
    
    [self DEBUG_saveShotImage:image withData:data andShotNumber:self.shotNumber];
}

// --- FIX: RANDOMIZED TEST SHOT ---
- (void)handleTestShot:(NSNotification *)n {
    NSLog(@"[DataModel] Generating Test Shot...");
    
    // Add randomness so it's never caught as a duplicate
    float randomVar = (arc4random_uniform(10) / 10.0f);
    
    NSMutableDictionary *ball = [NSMutableDictionary dictionary];
    ball[@"Speed"] = @(160.0 + randomVar);
    ball[@"VLA"] = @(12.5);
    ball[@"HLA"] = @(1.2);
    ball[@"TotalSpin"] = @(2400 + (int)(randomVar * 100));
    ball[@"SpinAxis"] = @(-2.5);
    ball[@"CarryDistance"] = @(275.0 + randomVar);
    
    // Don't calculate here, let handleNewBallData do it
    
    NSDictionary *club = @{
        @"Speed": @(108.0),
        @"Path": @(2.1),
        @"AngleOfAttack": @(3.5)
    };
    
    // IMPORTANT: Do NOT set self.currentShotBallData here.
    // Do NOT send to connector here.
    // Just post the notification. This simulates a REAL shot entering the system.
    // handleNewBallData will catch it, pass duplicate check (due to randomness), and send it.
    
    [[NSNotificationCenter defaultCenter] postNotificationName:ScreenDataProcessorNewBallDataNotification
                                                        object:nil
                                                      userInfo:@{@"data": ball}];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:ScreenDataProcessorNewClubDataNotification
                                                            object:nil
                                                          userInfo:@{@"data": club}];
    });
}

- (void)handleIpChanged:(NSNotification *)n {
    NSString *ip = n.userInfo[@"gsProIP"];
    if (!ip) return;
    
    BOOL useOGS = [[NSUserDefaults standardUserDefaults] boolForKey:@"use_ogs"];
    
    [[GSProConnector shared] disconnect];
    [[OGSConnector shared] disconnect];
    
    if (useOGS) {
        NSLog(@"[DataModel] IP Changed: Connecting to OpenGolf (OGS) at %@:%d", ip, self.ogsPort);
        [[OGSConnector shared] connectToIP:ip port:self.ogsPort];
    } else {
        NSLog(@"[DataModel] IP Changed: Connecting to GSPro at %@:%d", ip, self.gsProPort);
        [[GSProConnector shared] connectToServerWithIP:ip port:self.gsProPort];
    }
}

- (void)startMiniGame:(NSNotification *)notification {
    NSString *gameType = notification.userInfo[@"gameType"];
    NSNumber *min = notification.userInfo[@"minDistance"];
    NSNumber *max = notification.userInfo[@"maxDistance"];
    NSString *fmt = notification.userInfo[@"format"];
    NSNumber *shots = notification.userInfo[@"numberOfShots"];
    NSString *skill = notification.userInfo[@"skillLevel"];
    
    if (gameType && min && max && fmt && shots) {
        self.shotManager.miniGameManager = [[MiniGameManager alloc] initWithGameType:gameType
                                                                         minDistance:min.intValue
                                                                         maxDistance:max.intValue
                                                                              format:fmt
                                                                       numberOfShots:shots.intValue
                                                                          skillLevel:skill];
    }
}

- (void)updateCorners:(NSNotification *)n { self.screenCorners = n.userInfo[@"corners"]; }
- (MiniGameManager*)getMiniGameManager { return self.shotManager.miniGameManager; }
- (void)endMiniGameEarly { self.shotManager.miniGameManager = nil; }

- (void)exportShots {
    NSString *shotCsv = [self.shotManager exportShotsAsCSV];
    if (!shotCsv) return;

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd-HH-mm"];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];

    NSString *fileName = [NSString stringWithFormat:@"shots_%@.csv", timestamp];
    NSURL *temporaryDirectory = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    NSURL *fileURL = [temporaryDirectory URLByAppendingPathComponent:fileName];

    [shotCsv writeToURL:fileURL atomically:YES encoding:NSUTF8StringEncoding error:nil];

    UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
    activityVC.excludedActivityTypes = @[UIActivityTypeAssignToContact, UIActivityTypePostToFacebook];

    UIWindow *keyWindow = nil;
    for (UIWindowScene *windowScene in [UIApplication sharedApplication].connectedScenes) {
        if (windowScene.activationState == UISceneActivationStateForegroundActive) {
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) { keyWindow = window; break; }
            }
        }
    }
    [keyWindow.rootViewController presentViewController:activityVC animated:YES completion:nil];
}

- (void)DEBUG_saveShotImage:(UIImage *)img withData:(NSDictionary *)data andShotNumber:(int)num {
    if(!img) return;
    NSString *name = [NSString stringWithFormat:@"shot_%04d.png", num];
    [ImageUtilities saveImageToDocuments:img fileName:name];
}

@end
