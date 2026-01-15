#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OGSConnector : NSObject

+ (instancetype)shared;

// Connect/Disconnect (Persistent TCP)
- (void)connectToIP:(NSString *)ip port:(NSInteger)port;
- (void)disconnect;
- (BOOL)isConnected;

// Send Data old
//- (void)sendShotWithBallData:(NSDictionary *)ballData clubData:(NSDictionary *)clubData;

- (void)sendShotWithBallData:(nullable NSDictionary *)ballData
                    clubData:(nullable NSDictionary *)clubData
                  shotNumber:(int)shotNumber;

@end

NS_ASSUME_NONNULL_END
