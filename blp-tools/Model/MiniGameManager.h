#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const MiniGameStartNotification;
extern NSString * const MiniGameStatusChangedNotification;

@interface MiniGameManager : NSObject

// Basic game settings (from your MiniGameSettings)
@property (nonatomic, copy)   NSString *gameType;    // @"Distance", @"Putting", @"Accuracy"
@property (nonatomic, assign) NSInteger minDistance;
@property (nonatomic, assign) NSInteger maxDistance;
@property (nonatomic, copy)   NSString *format;      // e.g. @"Incremental" or @"Random"
@property (nonatomic, assign) NSInteger totalShots;
@property (nonatomic, copy)   NSString *skillLevel;  // New: "Tour", "Scratch", "5 HCP", etc.

// Designated initializer
- (instancetype)initWithGameType:(NSString *)type
                     minDistance:(NSInteger)minDist
                     maxDistance:(NSInteger)maxDist
                          format:(NSString *)format
                     numberOfShots:(NSInteger)shots
                        skillLevel:(nullable NSString *)skill; // New init param

// Accessors
- (NSInteger)getShotsRemaining;
- (NSInteger)getTargetDistanceForCurrentShot;
- (NSInteger)getTotalScore;
- (NSInteger)getTotalToPar;
- (NSInteger)getMostRecentShotScore;
- (NSInteger)getMostRecentShotToPar;
- (float)getMostRecentShotDistanceDiff;

// Main method to register a shot
- (NSDictionary*)addShot:(NSDictionary*)shotDict;

@end

NS_ASSUME_NONNULL_END
