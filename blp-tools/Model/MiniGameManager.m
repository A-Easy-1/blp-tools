#import "MiniGameManager.h"

NSString * const MiniGameStartNotification = @"MiniGameStartNotification";
NSString * const MiniGameStatusChangedNotification = @"MiniGameStatusChangedNotification";

@interface MiniGameManager ()
@property (nonatomic, assign) NSInteger shotsRemaining;
@property (nonatomic, assign) NSInteger targetDistanceForCurrentShot;
@property (nonatomic, assign) NSInteger totalScore;
@property (nonatomic, assign) NSInteger totalToPar;
@property (nonatomic, assign) NSInteger mostRecentShotScore;
@property (nonatomic, assign) NSInteger mostRecentShotToPar;
@property (nonatomic, assign) float mostRecentShotDistanceDiff;
@end

@implementation MiniGameManager

- (instancetype)initWithGameType:(NSString *)type
                     minDistance:(NSInteger)minDist
                     maxDistance:(NSInteger)maxDist
                          format:(NSString *)format
                   numberOfShots:(NSInteger)shots
                      skillLevel:(NSString *)skill
{
    self = [super init];
    if (self) {
        _gameType = [type copy];
        _minDistance = minDist;
        _maxDistance = maxDist;
        _format = [format copy];
        _totalShots = shots;
        _skillLevel = skill ? [skill copy] : @"10 HCP";
        
        _shotsRemaining = shots;
        _targetDistanceForCurrentShot = 0;
        _totalScore = 0;
        _totalToPar = 0;
        _mostRecentShotScore = 0;
        _mostRecentShotToPar = 0;
        
        [self updateTargetDistance];
        [self broadcastUpdate];
    }
    return self;
}

- (NSDictionary *)addShot:(NSDictionary*)shotDict {
    if (self.shotsRemaining <= 0) return @{};
    
    float target = (float)self.targetDistanceForCurrentShot;
    float distError = 0.0f;
    float allowedErrorRadius = 0.0f;
    
    // --- ACCURACY LOGIC ---
    if ([self.gameType isEqualToString:@"Accuracy"]) {
        // Use Calculated Physics data
        float shotDist = [shotDict[@"TotalDistance"] floatValue];
        float shotOffline = [shotDict[@"CalcOffline"] floatValue];
        
        // 2D Pythagorean Distance from Target Point (0, Target)
        float dx = shotOffline;
        float dy = shotDist - target;
        distError = sqrtf(dx*dx + dy*dy);
        
        // Get Dispersion Radius
        float dispersionFactor = [self getDispersionFactorForSkill:self.skillLevel];
        allowedErrorRadius = target * dispersionFactor;
        
    } else {
        // Legacy Distance/Putting Logic (1D Error)
        float distance = 0.0f;
        float offline = 0.0f;
        
        if ([self.gameType isEqualToString:@"Putting"]) {
            distance = [shotDict[@"TotalDistance"] floatValue];
            offline = [shotDict[@"TotalOffline"] floatValue];
        } else {
            distance = [shotDict[@"CarryDistance"] floatValue];
            offline = [shotDict[@"CarryOffline"] floatValue];
        }
        
        distError = sqrtf(powf(target - distance, 2) + powf(offline, 2));
        allowedErrorRadius = target * 0.10f; // Default 10%
    }
    
    // --- SCORING ---
    if (distError <= (allowedErrorRadius * 0.5)) {
        self.mostRecentShotToPar = -1; // Birdie
        self.mostRecentShotScore = 100 - (int)((distError / (allowedErrorRadius * 0.5)) * 10.0);
    } else if (distError <= allowedErrorRadius) {
        self.mostRecentShotToPar = 0;  // Par
        self.mostRecentShotScore = 80 + (int)((1.0 - (distError / allowedErrorRadius)) * 10.0);
    } else {
        self.mostRecentShotToPar = 1;  // Bogey
        self.mostRecentShotScore = MAX(0, 80 - (int)((distError - allowedErrorRadius) * 2.0));
    }
    
    self.mostRecentShotDistanceDiff = distError;
    
    // Averaging
    float shotsTaken = (float)(self.totalShots - self.shotsRemaining);
    float newAvg = ((float)self.totalScore * shotsTaken + self.mostRecentShotScore) / (shotsTaken + 1);
    self.totalScore = (NSInteger)roundf(newAvg);
    self.totalToPar += self.mostRecentShotToPar;
    
    self.shotsRemaining -= 1;
    if (self.shotsRemaining > 0) [self updateTargetDistance];
    
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"MGScore"] = @(self.mostRecentShotScore);
    result[@"MGToPar"] = @(self.mostRecentShotToPar);
    [self broadcastUpdate];
    return result;
}

- (float)getDispersionFactorForSkill:(NSString *)skill {
    // Returns radius as % of distance
    if ([skill isEqualToString:@"Tour"]) return 0.04f;
    if ([skill isEqualToString:@"Scratch"]) return 0.06f;
    if ([skill isEqualToString:@"5 HCP"]) return 0.08f;
    if ([skill isEqualToString:@"10 HCP"]) return 0.10f;
    if ([skill isEqualToString:@"15 HCP"]) return 0.12f;
    if ([skill isEqualToString:@"20 HCP"]) return 0.15f;
    return 0.10f;
}

- (void)updateTargetDistance {
    if ([self.format isEqualToString:@"Random"]) {
        NSInteger range = self.maxDistance - self.minDistance;
        self.targetDistanceForCurrentShot = self.minDistance + arc4random_uniform((u_int32_t)range + 1);
    } else {
        if (self.totalShots <= 1) self.targetDistanceForCurrentShot = self.minDistance;
        else {
            NSInteger idx = self.totalShots - self.shotsRemaining;
            self.targetDistanceForCurrentShot = self.minDistance + ((idx * (self.maxDistance - self.minDistance)) / (self.totalShots - 1));
        }
    }
}

- (void)broadcastUpdate {
    [[NSNotificationCenter defaultCenter] postNotificationName:MiniGameStatusChangedNotification object:nil userInfo:@{@"miniGameManager": self}];
}

// Accessors
- (NSInteger)getShotsRemaining { return self.shotsRemaining; }
- (NSInteger)getTargetDistanceForCurrentShot { return self.targetDistanceForCurrentShot; }
- (NSInteger)getTotalScore { return self.totalScore; }
- (NSInteger)getTotalToPar { return self.totalToPar; }
- (NSInteger)getMostRecentShotScore { return self.mostRecentShotScore; }
- (NSInteger)getMostRecentShotToPar { return self.mostRecentShotToPar; }
- (float)getMostRecentShotDistanceDiff { return self.mostRecentShotDistanceDiff; }

@end
