//#import "DataModel.h"
//#import "CameraManager.h"
//#import "GSProConnector.h"
//#import "OGSConnector.h" // <--- NEW: Import OGS
//#import "SettingsManager.h"
//#import "ModelManager.h"
//#import "ShotManager.h"
//#import "ImageUtilities.h"
//#import "Constants.h"
//
//@interface DataModel ()
//    @property (nonatomic, strong) ScreenDataProcessor *screenDataProcessor;
//    @property (nonatomic, assign) int shotNumber;
//    @property (nonatomic, assign) int gsProPort;
//    @property (nonatomic, assign) int ogsPort; // <--- NEW
//    @property (nonatomic, strong) ShotManager *shotManager;
//    @property (atomic, assign) BOOL isProcessingPaused;
//@end
//
//@implementation DataModel
//
//+ (instancetype)shared {
//    static DataModel *instance;
//    static dispatch_once_t onceToken;
//    dispatch_once(&onceToken, ^{
//        instance = [[DataModel alloc] init];
//    });
//    return instance;
//}
//
//- (instancetype)init {
//    self = [super init];
//    if (self) {
//        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(processFrame:) name:CameraManagerNewFrameNotification object:nil];
//        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateCorners:) name:ScreenDataProcessorNewCornersNotification object:nil];
//        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewBallData:) name:ScreenDataProcessorNewBallDataNotification object:nil];
//        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewClubData:) name:ScreenDataProcessorNewClubDataNotification object:nil];
//        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleIpChanged:) name:GSProIPChangedNotification object:nil];
//        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(startMiniGame:) name:MiniGameStartNotification object:nil];
//        
//        [UIApplication sharedApplication].idleTimerDisabled = YES;
//        self.isProcessingPaused = NO;
//        
//        self.currentShotBallData = nil;
//        self.currentShotClubData = nil;
//        self.shotNumber = -1;
//        self.gsProPort = 921;
//        self.ogsPort = 3111; // Standard OGS Port
//        
//        self.screenDataProcessor = [[ScreenDataProcessor alloc] init];
//        [SettingsManager shared];
//        [[CameraManager shared] startCamera];
//        
//        self.shotManager = [[ShotManager alloc] init];
//        
//        // --- ROUTING LOGIC ON STARTUP ---
//        NSString *ip = [SettingsManager shared].gsProIP;
//        BOOL useOGS = [[NSUserDefaults standardUserDefaults] boolForKey:@"use_ogs"];
//        
//        if (useOGS) {
//            NSLog(@"[DataModel] Startup: Connecting to OpenGolf (OGS) at %@:%d", ip, self.ogsPort);
//            [[OGSConnector shared] connectToIP:ip port:self.ogsPort];
//        } else {
//            NSLog(@"[DataModel] Startup: Connecting to GSPro at %@:%d", ip, self.gsProPort);
//            [[GSProConnector shared] connectToServerWithIP:ip port:self.gsProPort];
//        }
//        
//        NSArray *models = @[@"hla-direction", @"spin-axis-direction", @"ball-speed-units", @"carry-units", @"club-speed-units", @"path-direction", @"aoa-direction"];
//        for (NSString *model in models) {
//            [[ModelManager shared] loadModelWithName:model error:nil];
//        }
//    }
//    return self;
//}
//
//- (void)setProcessingPaused:(BOOL)paused {
//    self.isProcessingPaused = paused;
//    NSLog(@"[DataModel] Processing Paused: %@", paused ? @"YES" : @"NO");
//}
//
//// Standard Dispersion Logic (Unchanged from your file)
//- (NSDictionary *)calculateShotCoordinates:(NSDictionary *)shotData {
//    if (!shotData) return @{};
//
//    double totalDistance = [shotData[@"TotalDistance"] doubleValue];
//    double hla = [shotData[@"HLA"] doubleValue];
//    double spinAxis = [shotData[@"SpinAxis"] doubleValue];
//
//    double hlaRad = hla * (M_PI / 180.0);
//    double launchOffline = totalDistance * sin(hlaRad);
//
//    double curveFactor = 0.006;
//    double curveOffline = totalDistance * spinAxis * curveFactor;
//
//    double totalOffline = launchOffline + curveOffline;
//
//    return @{
//        @"CalcOffline": @(totalOffline),
//        @"CalcOfflineAbs": @(fabs(totalOffline))
//    };
//}
//
//- (void)processFrame:(NSNotification *)notification {
//    if (self.isProcessingPaused) return;
//
//    UIImage *frame = notification.userInfo[@"frame"];
//    if (!frame) return;
//    
//    static NSTimeInterval lastCallTime = 0;
//    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
//    if (currentTime - lastCallTime < OCR_RATE_SECONDS) return;
//    lastCallTime = currentTime;
//
//    NSError *error = nil;
//    [self.screenDataProcessor processScreenDataFromImage:frame error:&error];
//    if (error) {
//        NSLog(@"Error processing screen data: %@", error.localizedDescription);
//    }
//}
//
//- (void)handleNewBallData:(NSNotification *)notification {
//    UIImage *image = notification.userInfo[@"image"];
//    if (image) self.currentShotBallImage = image;
//    
//    NSDictionary *data = notification.userInfo[@"data"];
//    if (!data) return;
//    
//    NSMutableDictionary *enhancedData = [data mutableCopy];
//    
//    NSDictionary *physics = [self calculateShotCoordinates:enhancedData];
//    [enhancedData addEntriesFromDictionary:physics];
//    
//    self.currentShotBallData = [enhancedData copy];
//    self.currentShotClubData = nil;
//    self.shotNumber++;
//    
//    NSLog(@"Got new BALL data (shot #%d): %@", self.shotNumber, self.currentShotBallData);
//    
//    [self.shotManager addShot:self.currentShotBallData];
//    
//    // --- ROUTING LOGIC ---
//    // Check where to send data based on settings
//    BOOL useOGS = [[NSUserDefaults standardUserDefaults] boolForKey:@"use_ogs"];
//    if (useOGS) {
//        [[OGSConnector shared] sendShotWithBallData:self.currentShotBallData clubData:nil shotNumber:self.shotNumber];
//    } else {
//        [[GSProConnector shared] sendShotWithBallData:self.currentShotBallData clubData:nil shotNumber:self.shotNumber];
//    }
//    
//    [self DEBUG_saveShotImage:image withData:self.currentShotBallData andShotNumber:self.shotNumber];
//}
//
//- (void)handleNewClubData:(NSNotification *)notification {
//    if(!self.currentShotBallData) return;
//    
//    UIImage *image = notification.userInfo[@"image"];
//    if (image) self.currentShotClubImage = image;
//    
//    NSDictionary *data = notification.userInfo[@"data"];
//    if (!data) return;
//    
//    self.currentShotClubData = [data copy];
//    [self.shotManager updateShotClubData:self.currentShotClubData];
//    
//    NSLog(@"Got new CLUB data (shot #%d): %@", self.shotNumber, data);
//    
//    // --- ROUTING LOGIC ---
//    BOOL useOGS = [[NSUserDefaults standardUserDefaults] boolForKey:@"use_ogs"];
//    if (useOGS) {
//        [[OGSConnector shared] sendShotWithBallData:nil clubData:self.currentShotClubData shotNumber:self.shotNumber];
//    } else {
//        [[GSProConnector shared] sendShotWithBallData:nil clubData:self.currentShotClubData shotNumber:self.shotNumber];
//    }
//    
//    [self DEBUG_saveShotImage:image withData:data andShotNumber:self.shotNumber];
//}
//
//- (void)handleIpChanged:(NSNotification *)n {
//    NSString *ip = n.userInfo[@"gsProIP"];
//    if (!ip) return;
//    
//    BOOL useOGS = [[NSUserDefaults standardUserDefaults] boolForKey:@"use_ogs"];
//    
//    // Disconnect both to be safe
//    [[GSProConnector shared] disconnect];
//    [[OGSConnector shared] disconnect];
//    
//    if (useOGS) {
//        NSLog(@"[DataModel] IP Changed: Connecting to OpenGolf (OGS) at %@:%d", ip, self.ogsPort);
//        [[OGSConnector shared] connectToIP:ip port:self.ogsPort];
//    } else {
//        NSLog(@"[DataModel] IP Changed: Connecting to GSPro at %@:%d", ip, self.gsProPort);
//        [[GSProConnector shared] connectToServerWithIP:ip port:self.gsProPort];
//    }
//}
//
//- (void)startMiniGame:(NSNotification *)notification {
//    NSString *gameType = notification.userInfo[@"gameType"];
//    NSNumber *min = notification.userInfo[@"minDistance"];
//    NSNumber *max = notification.userInfo[@"maxDistance"];
//    NSString *fmt = notification.userInfo[@"format"];
//    NSNumber *shots = notification.userInfo[@"numberOfShots"];
//    NSString *skill = notification.userInfo[@"skillLevel"];
//    
//    if (gameType && min && max && fmt && shots) {
//        self.shotManager.miniGameManager = [[MiniGameManager alloc] initWithGameType:gameType minDistance:min.intValue maxDistance:max.intValue format:fmt numberOfShots:shots.intValue skillLevel:skill];
//    }
//}
//
//- (void)updateCorners:(NSNotification *)n { self.screenCorners = n.userInfo[@"corners"]; }
//- (MiniGameManager*)getMiniGameManager { return self.shotManager.miniGameManager; }
//- (void)endMiniGameEarly { self.shotManager.miniGameManager = nil; }
//- (void)exportShots { [self.shotManager exportShotsAsCSV]; }
//
//- (void)DEBUG_saveShotImage:(UIImage *)img withData:(NSDictionary *)data andShotNumber:(int)num {
//    if(!img) return;
//    NSString *name = [NSString stringWithFormat:@"shot_%04d.png", num];
//    [ImageUtilities saveImageToDocuments:img fileName:name];
//}
//
//@end

#import "DataModel.h"
#import "CameraManager.h"
#import "GSProConnector.h"
#import "OGSConnector.h"
#import "SettingsManager.h"
#import "ModelManager.h"
#import "ShotManager.h"
#import "ImageUtilities.h"
#import "Constants.h"

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
        
        // --- ROUTING LOGIC ON STARTUP ---
        NSString *ip = [SettingsManager shared].gsProIP;
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

    double totalDistance = [shotData[@"TotalDistance"] doubleValue];
    double hla = [shotData[@"HLA"] doubleValue];
    double spinAxis = [shotData[@"SpinAxis"] doubleValue];

    double hlaRad = hla * (M_PI / 180.0);
    double launchOffline = totalDistance * sin(hlaRad);

    double curveFactor = 0.006;
    double curveOffline = totalDistance * spinAxis * curveFactor;

    double totalOffline = launchOffline + curveOffline;

    return @{
        @"CalcOffline": @(totalOffline),
        @"CalcOfflineAbs": @(fabs(totalOffline))
    };
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
    
    NSMutableDictionary *enhancedData = [data mutableCopy];
    
    NSDictionary *physics = [self calculateShotCoordinates:enhancedData];
    [enhancedData addEntriesFromDictionary:physics];
    
    self.currentShotBallData = [enhancedData copy];
    self.currentShotClubData = nil;
    self.shotNumber++;
    
    NSLog(@"[DataModel] Shot #%d. Total: %@ (Calc: %@)", self.shotNumber, self.currentShotBallData[@"TotalDistance"], self.currentShotBallData[@"CalcOffline"]);
    
    [self.shotManager addShot:self.currentShotBallData];
    
    // --- ROUTING LOGIC ---
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
    
    // --- ROUTING LOGIC ---
    BOOL useOGS = [[NSUserDefaults standardUserDefaults] boolForKey:@"use_ogs"];
    if (useOGS) {
        [[OGSConnector shared] sendShotWithBallData:nil clubData:self.currentShotClubData shotNumber:self.shotNumber];
    } else {
        [[GSProConnector shared] sendShotWithBallData:nil clubData:self.currentShotClubData shotNumber:self.shotNumber];
    }
    
    [self DEBUG_saveShotImage:image withData:data andShotNumber:self.shotNumber];
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

// --- MINI GAME & EXPORT LOGIC (Restored) ---

- (void)startMiniGame:(NSNotification *)notification {
    NSString *gameType = notification.userInfo[@"gameType"];
    NSNumber *min = notification.userInfo[@"minDistance"];
    NSNumber *max = notification.userInfo[@"maxDistance"];
    NSString *fmt = notification.userInfo[@"format"];
    NSNumber *shots = notification.userInfo[@"numberOfShots"];
    NSString *skill = notification.userInfo[@"skillLevel"];
    
    if (gameType && min && max && fmt && shots) {
        NSLog(@"[DataModel] Starting Mini Game: %@ (%@)", gameType, fmt);
        self.shotManager.miniGameManager = [[MiniGameManager alloc] initWithGameType:gameType
                                                                         minDistance:min.intValue
                                                                         maxDistance:max.intValue
                                                                              format:fmt
                                                                       numberOfShots:shots.intValue
                                                                          skillLevel:skill];
    }
}

- (void)updateCorners:(NSNotification *)n {
    self.screenCorners = n.userInfo[@"corners"];
}

- (MiniGameManager*)getMiniGameManager {
    return self.shotManager.miniGameManager;
}

- (void)endMiniGameEarly {
    self.shotManager.miniGameManager = nil;
}

// RESTORED: Full Export Logic
- (void)exportShots {
    NSString *shotCsv = [self.shotManager exportShotsAsCSV];
    if (!shotCsv) {
        NSLog(@"[DataModel] No shots to export.");
        return;
    }

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd-HH-mm"];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];

    NSString *fileName = [NSString stringWithFormat:@"shots_%@.csv", timestamp];
    
    NSURL *temporaryDirectory = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    NSURL *fileURL = [temporaryDirectory URLByAppendingPathComponent:fileName];

    NSError *error;
    BOOL success = [shotCsv writeToURL:fileURL atomically:YES encoding:NSUTF8StringEncoding error:&error];

    if (!success) {
        NSLog(@"Error writing CSV file: %@", error.localizedDescription);
        return;
    }

    UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
    activityVC.excludedActivityTypes = @[UIActivityTypeAssignToContact, UIActivityTypePostToFacebook];

    // Hacky way to find top VC from DataModel (Model layer), but required since DataModel isn't a View Controller
    UIWindow *keyWindow = nil;
    for (UIWindowScene *windowScene in [UIApplication sharedApplication].connectedScenes) {
        if (windowScene.activationState == UISceneActivationStateForegroundActive) {
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) {
                    keyWindow = window;
                    break;
                }
            }
        }
        if (keyWindow) break;
    }

    [keyWindow.rootViewController presentViewController:activityVC animated:YES completion:nil];
}

- (void)DEBUG_saveShotImage:(UIImage *)img withData:(NSDictionary *)data andShotNumber:(int)num {
    if(!img) return;
    NSString *name = [NSString stringWithFormat:@"shot_%04d.png", num];
    [ImageUtilities saveImageToDocuments:img fileName:name];
}

@end
