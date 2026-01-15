#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TrajectoryEstimator : NSObject

+ (instancetype)shared;

- (void)processBallData:(NSMutableDictionary *)ballData;
+ (NSDictionary *)estimateTrajectoryWithSpeed:(double)speedMPH vla:(double)vlaDeg spin:(double)spinRPM;

@end

NS_ASSUME_NONNULL_END
